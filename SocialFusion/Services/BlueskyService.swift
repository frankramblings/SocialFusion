import Combine
import Foundation
import SwiftUI
import UIKit
import os.log

// Import NetworkError explicitly
@_exported import struct Foundation.URL
@_exported import class Foundation.URLSession

/// Using TokenError from TokenManager
enum BlueskyTokenError: Error, Equatable {
    case noAccessToken
    case noRefreshToken
    case invalidRefreshToken
    case noClientCredentials
    case invalidServerURL
    case networkError(Error)
    case refreshFailed

    static func == (lhs: BlueskyTokenError, rhs: BlueskyTokenError) -> Bool {
        switch (lhs, rhs) {
        case (.noAccessToken, .noAccessToken),
            (.noRefreshToken, .noRefreshToken),
            (.invalidRefreshToken, .invalidRefreshToken),
            (.noClientCredentials, .noClientCredentials),
            (.invalidServerURL, .invalidServerURL),
            (.refreshFailed, .refreshFailed):
            return true
        case (.networkError(let lhsError), .networkError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

/// Set up local NetworkError temporarily
enum NetworkError: Error {
    case requestFailed(Error)
    case httpError(Int, String?)
    case noData
    case decodingError
    case invalidURL
    case cancelled
    case duplicateRequest
    case timeout
    case rateLimitExceeded(retryAfter: TimeInterval?)
    case unauthorized
    case serverError
    case accessDenied
    case resourceNotFound
    case blockedDomain(String)
    case unsupportedResponse
    case networkUnavailable
    case apiError(String)

    static func from(error: Error?, response: URLResponse?) -> NetworkError {
        // First handle NSError types
        if let nsError = error as NSError? {
            switch nsError.domain {
            case NSURLErrorDomain:
                switch nsError.code {
                case NSURLErrorTimedOut:
                    return .timeout
                case NSURLErrorCancelled:
                    return .cancelled
                case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                    return .networkUnavailable
                default:
                    return .requestFailed(nsError)
                }
            default:
                return .requestFailed(nsError)
            }
        }

        // Then handle HTTP response codes
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200...299:  // Success range, should not be an error
                return .noData  // Default if no specific error but in success range
            case 401:
                return .unauthorized
            case 403:
                return .accessDenied
            case 404:
                return .resourceNotFound
            case 429:
                // Check for Retry-After header
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                let retryTime = retryAfter.flatMap(TimeInterval.init) ?? 60
                return .rateLimitExceeded(retryAfter: retryTime)
            case 400...499:
                return .httpError(httpResponse.statusCode, nil)
            case 500...599:
                return .serverError
            default:
                return .httpError(httpResponse.statusCode, nil)
            }
        }

        // Default case if we can't categorize
        return .requestFailed(error ?? NSError(domain: "Unknown", code: -1, userInfo: nil))
    }
}

/// Represents a service for interacting with the Bluesky social platform
class BlueskyService {

    // MARK: - Singleton
    static let shared = BlueskyService()
    public init() {}

    // MARK: - Properties
    private let baseURL = "https://bsky.social/xrpc"
    private let logger = Logger(subsystem: "com.socialfusion", category: "BlueskyService")

    // Configure a custom URLSession with more robust settings
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 5
        return URLSession(configuration: config)
    }()

    // MARK: - Authentication

    /// Authenticate with Bluesky
    func authenticate(username: String, password: String) async throws -> SocialAccount {
        return try await authenticate(
            server: URL(string: "bsky.social"), username: username, password: password)
    }

    /// Authenticate a user and get auth tokens
    func authenticate(server: URL?, username: String, password: String) async throws
        -> SocialAccount
    {
        // 1. Create the API endpoint URL
        let serverURLString = server?.absoluteString ?? "bsky.social"
        let apiURL =
            serverURLString.hasPrefix("https://")
            ? "\(serverURLString)/xrpc/com.atproto.server.createSession"
            : "https://\(serverURLString)/xrpc/com.atproto.server.createSession"

        guard let url = URL(string: apiURL) else {
            throw NetworkError.invalidURL
        }

        // 2. Prepare the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 3. Create request body
        let body: [String: Any] = [
            "identifier": username,
            "password": password,
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw NetworkError.requestFailed(error)
        }

        do {
            // 4. Send request using session data method
            let (data, _) = try await session.data(for: request)

            // 5. Parse the response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let accessJwt = json["accessJwt"] as? String,
                let refreshJwt = json["refreshJwt"] as? String,
                let did = json["did"] as? String,
                let handle = json["handle"] as? String
            else {
                // Try to see if we have an error message
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let errorMsg = errorJson["error"] as? String,
                    let message = errorJson["message"] as? String
                {
                    throw NSError(
                        domain: "BlueskyAPI",
                        code: 401,
                        userInfo: [NSLocalizedDescriptionKey: "\(errorMsg): \(message)"]
                    )
                }

                throw NetworkError.decodingError
            }

            // 6. Create and return account with proper parameters
            let account = SocialAccount(
                id: did,
                username: handle,
                displayName: handle,
                serverURL: server?.absoluteString ?? "bsky.social",
                platform: .bluesky
            )

            // Save tokens
            account.saveAccessToken(accessJwt)
            account.saveRefreshToken(refreshJwt)
            account.saveTokenExpirationDate(Date().addingTimeInterval(2 * 60 * 60))  // 2 hours

            return account
        } catch {
            // Check for HTTP error
            if let httpResponse = error as? URLError {
                logger.error("HTTP error: \(httpResponse.localizedDescription)")
            }

            // Rethrow network errors
            throw NetworkError.requestFailed(error)
        }
    }

    /// Refresh session for an account to get new tokens
    func refreshSession(for account: SocialAccount) async throws -> (String, String) {
        // Check for refresh token
        guard let refreshToken = account.refreshToken else {
            throw BlueskyTokenError.noRefreshToken
        }

        // Create URL
        var serverURLString = account.serverURL?.absoluteString ?? "bsky.social"
        if serverURLString.hasPrefix("https://") {
            serverURLString = String(serverURLString.dropFirst(8))
        }

        let apiURL = "https://\(serverURLString)/xrpc/com.atproto.server.refreshSession"
        guard let url = URL(string: apiURL) else {
            throw NetworkError.invalidURL
        }

        // Prepare request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(refreshToken)", forHTTPHeaderField: "Authorization")

        do {
            // Send request using session data method
            let (data, _) = try await session.data(for: request)

            // Parse the response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let accessJwt = json["accessJwt"] as? String,
                let refreshJwt = json["refreshJwt"] as? String
            else {
                throw NetworkError.decodingError
            }

            // Update account tokens
            account.saveAccessToken(accessJwt)
            account.saveRefreshToken(refreshJwt)
            account.saveTokenExpirationDate(Date().addingTimeInterval(2 * 60 * 60))  // 2 hours

            return (accessJwt, refreshJwt)
        } catch {
            if error is NetworkError {
                throw BlueskyTokenError.invalidRefreshToken
            }
            throw BlueskyTokenError.networkError(error)
        }
    }

    /// Simplified method to refresh access token for an account
    /// Returns only the new access token and handles all the internal details
    public func refreshAccessToken(for account: SocialAccount) async throws -> String {
        do {
            let (accessToken, _) = try await refreshSession(for: account)
            return accessToken
        } catch {
            logger.error("Failed to refresh access token: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Profile Management

    /// Update profile information for account
    func updateProfileInfo(for account: SocialAccount) async throws {
        // Check for access token
        guard let accessToken = account.accessToken else {
            throw BlueskyTokenError.noAccessToken
        }

        var serverURLString = account.serverURL?.absoluteString ?? "bsky.social"
        if serverURLString.hasPrefix("https://") {
            serverURLString = String(serverURLString.dropFirst(8))
        }

        // Create URL for profile endpoint
        let apiURL =
            "https://\(serverURLString)/xrpc/app.bsky.actor.getProfile?actor=\(account.username)"
        guard let url = URL(string: apiURL) else {
            throw NetworkError.invalidURL
        }

        // Prepare request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            // First check if token is expired and needs refresh
            if let expirationDate = account.tokenExpirationDate, expirationDate <= Date() {
                let (newToken, _) = try await refreshSession(for: account)
                request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            }

            // Send request using session data method
            let (data, _) = try await session.data(for: request)

            // Parse the profile data
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NetworkError.decodingError
            }

            // Update account information
            if let displayName = json["displayName"] as? String {
                account.displayName = displayName
            }

            if let avatar = json["avatar"] as? String, let avatarURL = URL(string: avatar) {
                account.profileImageURL = avatarURL
            }
        } catch {
            throw error
        }
    }

    // MARK: - Timeline

    /// Fetch the timeline for a Bluesky account
    func fetchTimeline(for account: SocialAccount) async throws -> [Post] {
        // Call the actual API implementation instead of using sample data
        return try await fetchHomeTimeline(for: account)
    }

    /// Fetch home timeline for a Bluesky account
    public func fetchHomeTimeline(for account: SocialAccount, limit: Int = 20) async throws
        -> [Post]
    {
        guard account.platform == .bluesky else {
            throw ServiceError.invalidAccount(reason: "Account is not a Bluesky account")
        }

        guard let token = account.getAccessToken() else {
            logger.error("No access token available for Bluesky account: \(account.username)")
            throw ServiceError.unauthorized("No access token available")
        }

        var serverURLString = account.serverURL?.absoluteString ?? "bsky.social"
        if serverURLString.hasPrefix("https://") {
            serverURLString = String(serverURLString.dropFirst(8))
        }

        logger.info("Using Bluesky server: \(serverURLString)")

        // Create API endpoint URL
        let apiURL = "https://\(serverURLString)/xrpc/app.bsky.feed.getTimeline"
        guard let url = URL(string: apiURL) else {
            logger.error("Invalid Bluesky API URL: \(apiURL)")
            throw ServiceError.invalidInput(reason: "Invalid server URL")
        }

        logger.info("Fetching Bluesky timeline from: \(apiURL)")

        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30.0  // Set a longer timeout to handle slow connections

        // Add query parameters
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        if let finalURL = components?.url {
            request.url = finalURL
            logger.info("Final Bluesky API URL with params: \(finalURL.absoluteString)")
        }

        do {
            // Check if token is expired and needs refresh
            if account.isTokenExpired, let refreshToken = account.refreshToken {
                // Try to refresh token
                logger.info("Refreshing expired Bluesky token for: \(account.username)")
                do {
                    let newToken = try await refreshAccessToken(for: account)
                    request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    logger.info("Successfully refreshed Bluesky token")
                } catch {
                    logger.error("Failed to refresh Bluesky token: \(error.localizedDescription)")
                    // Continue with existing token as fallback
                }
            }

            // Make the API request
            logger.info("Making Bluesky API request...")
            let (data, response) = try await session.data(for: request)

            // Check response status
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid HTTP response from Bluesky API")
                throw ServiceError.networkError(
                    underlying: NSError(domain: "HTTP", code: 0, userInfo: nil))
            }

            logger.info("Bluesky API response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                logger.error("Authentication failed or expired for Bluesky API")
                throw ServiceError.unauthorized("Authentication failed or expired")
            }

            if httpResponse.statusCode != 200 {
                logger.error(
                    "Bluesky API returned non-success status code: \(httpResponse.statusCode)")
                // Log the response body to help diagnose issues
                if let responseBody = String(data: data, encoding: .utf8) {
                    logger.error("Response body: \(responseBody)")
                }
                throw ServiceError.apiError(
                    "Server returned status code \(httpResponse.statusCode)")
            }

            // Process the timeline data
            logger.info("Processing Bluesky timeline data...")
            let posts = try processFeedData(data, account: account)
            logger.info("Successfully processed \(posts.count) Bluesky posts")
            return posts
        } catch {
            logger.error("Error fetching Bluesky timeline: \(error.localizedDescription)")
            if let urlError = error as? URLError {
                logger.error(
                    "URLError code: \(urlError.code.rawValue), description: \(urlError.localizedDescription)"
                )
            }
            throw ServiceError.timelineError(underlying: error)
        }
    }

    /// Process feed data from timeline response
    private func processFeedData(_ data: Data, account: SocialAccount) throws -> [Post] {
        do {
            // First try to decode as raw JSON to inspect the structure
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.error("Failed to decode timeline response as JSON")
                // Log the raw data for debugging
                if let rawString = String(data: data, encoding: .utf8) {
                    logger.debug("Raw data: \(rawString.prefix(200))...")
                }
                throw NetworkError.decodingError
            }

            // Log the JSON structure for debugging
            logger.debug("Timeline JSON structure: \(json.keys)")

            // Check for feed items in the response
            guard let feed = json["feed"] as? [[String: Any]] else {
                // Check if there's an error message
                if let error = json["error"] as? String,
                    let message = json["message"] as? String
                {
                    logger.error("API error: \(error) - \(message)")
                    throw NetworkError.apiError(message)
                }

                // See if there might be a different structure in the response
                let allKeys = json.keys.joined(separator: ", ")
                logger.error("Missing feed items in timeline response. Available keys: \(allKeys)")

                // If the response is empty but valid JSON, return empty array instead of error
                if json.isEmpty {
                    logger.warning("Empty JSON response, returning empty post array")
                    return []
                }

                throw NetworkError.decodingError
            }

            logger.info("Found \(feed.count) items in Bluesky feed")

            // Process the feed items
            let posts = try processTimelineResponse(feed, account: account)
            logger.info("Successfully processed \(posts.count) Bluesky posts")
            return posts
        } catch {
            logger.error("Timeline processing error: \(error.localizedDescription)")
            if let data = String(data: data, encoding: .utf8) {
                logger.debug("Raw response data: \(data.prefix(500))...")
            }
            throw error
        }
    }

    /// Fetch a specific post by ID
    func fetchPostByID(_ postId: String, account: SocialAccount) async throws -> Post? {
        guard account.platform == .bluesky else {
            throw ServiceError.invalidAccount(reason: "Account is not a Bluesky account")
        }

        guard let token = account.getAccessToken() else {
            logger.error("No access token available for Bluesky account: \(account.username)")
            throw ServiceError.unauthorized("No access token available")
        }

        var serverURLString = account.serverURL?.absoluteString ?? "bsky.social"
        if serverURLString.hasPrefix("https://") {
            serverURLString = String(serverURLString.dropFirst(8))
        }

        // Changed endpoint from getPost to getPostThread which is implemented
        let apiURL = "https://\(serverURLString)/xrpc/app.bsky.feed.getPostThread"

        // Create URL components to add query parameters
        var components = URLComponents(string: apiURL)
        components?.queryItems = [
            URLQueryItem(name: "uri", value: postId)
        ]

        guard let url = components?.url else {
            throw ServiceError.invalidInput(reason: "Invalid server URL or post ID")
        }

        logger.info("Fetching Bluesky post from: \(url.absoluteString)")

        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30.0  // Set a longer timeout to handle slow connections

        do {
            // Check if token is expired and needs refresh
            if account.isTokenExpired, let refreshToken = account.refreshToken {
                // Try to refresh token
                logger.info("Refreshing expired Bluesky token for fetching post")
                do {
                    let newToken = try await refreshAccessToken(for: account)
                    request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                } catch {
                    logger.error("Failed to refresh Bluesky token: \(error.localizedDescription)")
                    // Continue with existing token as fallback
                }
            }

            // Make the API request
            let (data, response) = try await session.data(for: request)

            // Check response status
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ServiceError.networkError(
                    underlying: NSError(domain: "HTTP", code: 0, userInfo: nil))
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ServiceError.unauthorized("Authentication failed or expired")
            }

            if httpResponse.statusCode != 200 {
                // Log the response body to help diagnose issues
                if let responseBody = String(data: data, encoding: .utf8) {
                    logger.error("Response body: \(responseBody)")
                }
                throw ServiceError.apiError(
                    "Server returned status code \(httpResponse.statusCode)")
            }

            // Parse the post data
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NetworkError.decodingError
            }

            // The response format from getPostThread contains a thread object with the post
            guard let thread = json["thread"] as? [String: Any],
                let post = thread["post"] as? [String: Any]
            else {
                logger.error("Missing thread or post in response")
                return nil
            }

            // Create a wrapper we can process with our existing code
            let feedItems = [["post": post]]

            // Use our existing processing method to convert the data
            let posts = try processTimelineResponse(feedItems, account: account)

            if let post = posts.first {
                return post
            } else {
                logger.warning("No post returned from processing")
                return nil
            }
        } catch {
            logger.error("Error fetching Bluesky post: \(error.localizedDescription)")
            throw ServiceError.timelineError(underlying: error)
        }
    }

    // MARK: - Private Helpers

    /// Process timeline response into Post objects
    private func processTimelineResponse(_ feedItems: [[String: Any]], account: SocialAccount)
        throws -> [Post]
    {
        var posts: [Post] = []

        for item in feedItems {
            do {
                // First check for the post field
                guard let post = item["post"] as? [String: Any] else {
                    logger.warning("Missing post field in timeline item")
                    continue
                }

                // Extract basic post data
                guard let uri = post["uri"] as? String,
                    let record = post["record"] as? [String: Any],
                    let text = record["text"] as? String,
                    let createdAt = record["createdAt"] as? String,
                    let author = post["author"] as? [String: Any]
                else {
                    logger.warning("Missing required post fields in timeline item")
                    continue
                }

                // Author fields might be differently formatted depending on API version
                let authorName =
                    author["displayName"] as? String ?? author["handle"] as? String ?? "Unknown"
                let authorUsername = author["handle"] as? String ?? "unknown"
                let authorAvatarURL = author["avatar"] as? String ?? ""

                // Get metrics if available - handle different API formats
                var likeCount = 0
                var repostCount = 0

                // Try viewer metrics first (common format)
                if let metrics = post["viewer"] as? [String: Any] {
                    likeCount = metrics["likeCount"] as? Int ?? 0
                    repostCount = metrics["repostCount"] as? Int ?? 0
                }
                // Then try top-level metrics
                else if let metrics = post["likeCount"] as? Int {
                    likeCount = metrics
                    repostCount = post["repostCount"] as? Int ?? 0
                }

                // Check if this is a reply to another post
                var inReplyToID: String? = nil
                if let reply = record["reply"] as? [String: Any],
                    let parent = reply["parent"] as? [String: Any],
                    let parentUri = parent["uri"] as? String
                {
                    inReplyToID = parentUri
                    logger.info("Found reply post with parent: \(parentUri)")
                }

                // Process media attachments - handle different API embed formats
                var attachments: [Post.Attachment] = []
                if let embed = post["embed"] as? [String: Any] {
                    // First try the images array format
                    if let images = embed["images"] as? [[String: Any]] {
                        for image in images {
                            if let fullsize = image["fullsize"] as? String {
                                let alt = image["alt"] as? String ?? ""
                                attachments.append(
                                    Post.Attachment(
                                        url: fullsize,
                                        type: .image,
                                        altText: alt
                                    ))
                            }
                        }
                    }
                    // Then try the other common formats
                    else if let media = embed["media"] as? [String: Any],
                        let mediaType = media["$type"] as? String,
                        mediaType.contains("image"),
                        let imgUrl = media["image"] as? [String: Any],
                        let url = imgUrl["url"] as? String
                    {

                        attachments.append(
                            Post.Attachment(
                                url: url,
                                type: .image,
                                altText: media["alt"] as? String ?? ""
                            ))
                    }
                }

                // Extract mentions and hashtags
                var mentions: [String] = []
                var tags: [String] = []

                if let facets = record["facets"] as? [[String: Any]] {
                    for facet in facets {
                        if let features = facet["features"] as? [[String: Any]] {
                            for feature in features {
                                if let type = feature["$type"] as? String {
                                    if type == "app.bsky.richtext.facet#mention" {
                                        if let mention = feature["did"] as? String {
                                            mentions.append(mention)
                                        }
                                    } else if type == "app.bsky.richtext.facet#tag" {
                                        if let tag = feature["tag"] as? String {
                                            tags.append(tag)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Check if this is a repost
                var originalPost: Post? = nil
                var boostedBy: String? = nil

                if let reason = item["reason"] as? [String: Any],
                    let reasonType = reason["$type"] as? String,
                    reasonType == "app.bsky.feed.defs#reasonRepost"
                {
                    // This is a repost - process the original post
                    if let reasonBy = reason["by"] as? [String: Any],
                        let reposterName = reasonBy["displayName"] as? String ?? reasonBy["handle"]
                            as? String,
                        let reposterUsername = reasonBy["handle"] as? String
                    {
                        // Set the boosted by field
                        boostedBy = reposterName

                        // Create the original post
                        originalPost = Post(
                            id: uri,
                            content: text,
                            authorName: authorName,
                            authorUsername: authorUsername,
                            authorProfilePictureURL: authorAvatarURL,
                            createdAt: ISO8601DateFormatter().date(from: createdAt) ?? Date(),
                            platform: .bluesky,
                            originalURL:
                                "https://bsky.app/profile/\(authorUsername)/post/\(uri.split(separator: "/").last ?? "")",
                            attachments: attachments,
                            mentions: mentions,
                            tags: tags,
                            likeCount: likeCount,
                            repostCount: repostCount,
                            platformSpecificId: uri
                        )

                        // Create the repost as the main post
                        let repostId = "repost-\(uri)"
                        let repost = Post(
                            id: repostId,
                            content: "",  // Empty content for reposts
                            authorName: reposterName,
                            authorUsername: reposterUsername,
                            authorProfilePictureURL: reasonBy["avatar"] as? String ?? "",
                            createdAt: ISO8601DateFormatter().date(from: createdAt) ?? Date(),
                            platform: .bluesky,
                            originalURL:
                                "https://bsky.app/profile/\(reposterUsername)/post/\(uri.split(separator: "/").last ?? "")",
                            attachments: [],
                            mentions: [],
                            tags: [],
                            originalPost: originalPost,
                            isReposted: true,
                            platformSpecificId: repostId,
                            boostedBy: reposterName
                        )

                        posts.append(repost)
                        continue
                    }
                }

                // Create regular post
                let newPost = Post(
                    id: uri,
                    content: text,
                    authorName: authorName,
                    authorUsername: authorUsername,
                    authorProfilePictureURL: authorAvatarURL,
                    createdAt: ISO8601DateFormatter().date(from: createdAt) ?? Date(),
                    platform: .bluesky,
                    originalURL:
                        "https://bsky.app/profile/\(authorUsername)/post/\(uri.split(separator: "/").last ?? "")",
                    attachments: attachments,
                    mentions: mentions,
                    tags: tags,
                    likeCount: likeCount,
                    repostCount: repostCount,
                    platformSpecificId: uri,
                    boostedBy: boostedBy,
                    inReplyToID: inReplyToID
                )

                posts.append(newPost)
            } catch {
                logger.error("Error processing timeline item: \(error.localizedDescription)")
                // Continue processing other items
                continue
            }
        }

        return posts
    }

    // Other methods from original implementation...

    func sendPost(content: String, for account: SocialAccount) async throws -> Bool {
        guard let accessToken = account.accessToken else {
            throw NetworkError.unauthorized
        }

        guard let url = URL(string: "\(baseURL)/com.atproto.repo.createRecord") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let record: [String: Any] = [
            "$type": "app.bsky.feed.post",
            "text": content,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]

        let body: [String: Any] = [
            "repo": account.platformSpecificId,
            "collection": "app.bsky.feed.post",
            "record": record,
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            if account.isTokenExpired {
                _ = try await refreshSession(for: account)
            }

            let (_, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }

            return (200...299).contains(httpResponse.statusCode)
        } catch {
            logger.error("Error sending post: \(error.localizedDescription)")
            throw error
        }
    }

    func repost(post: Post, for account: SocialAccount) async throws -> Bool {
        guard let accessToken = account.accessToken else {
            throw NetworkError.unauthorized
        }

        guard let url = URL(string: "\(baseURL)/com.atproto.repo.createRecord") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let subject: [String: Any] = [
            "uri": post.platformSpecificId,
            "cid": "",  // CID isn't strictly required
        ]

        let record: [String: Any] = [
            "$type": "app.bsky.feed.repost",
            "subject": subject,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]

        let body: [String: Any] = [
            "repo": account.platformSpecificId,
            "collection": "app.bsky.feed.repost",
            "record": record,
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            if account.isTokenExpired {
                _ = try await refreshSession(for: account)
            }

            let (_, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }

            return (200...299).contains(httpResponse.statusCode)
        } catch {
            logger.error("Error reposting: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Post Actions

    /// Like a post
    func likePost(_ post: Post, account: SocialAccount) async throws -> Bool {
        // Implementation would make an API call to like the post
        return true
    }

    /// Repost a post
    func repostPost(_ post: Post, account: SocialAccount) async throws -> Bool {
        // Implementation would make an API call to repost
        return true
    }

    /// Reply to a post
    func replyToPost(_ post: Post, content: String, account: SocialAccount) async throws -> Bool {
        // Implementation would make an API call to reply
        return true
    }
}

extension URL {
    fileprivate func asURLString() -> String {
        return self.absoluteString
    }
}

import Combine
import Foundation
import SwiftUI
import UIKit
import os.log

// Import NetworkError explicitly
@_exported import struct Foundation.URL
@_exported import class Foundation.URLSession

// MARK: - Thread Safety Note
/*
 IMPORTANT: When updating any @Published properties or UI state, always use:

 await MainActor.run {
    // Update UI state here
 }

 This ensures thread safety and prevents EXC_BAD_ACCESS crashes when modifying
 state from background threads.
*/

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
    private var quotedPostsCounter = 0

    // Configure a custom URLSession with more robust settings
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 5
        return URLSession(configuration: config)
    }()

    // MARK: - JWT Token Utilities

    /// Decode JWT token to extract expiration time
    private func decodeJWTExpiration(_ jwtToken: String) -> Date? {
        let parts = jwtToken.components(separatedBy: ".")
        guard parts.count == 3 else {
            logger.warning("Invalid JWT format - expected 3 parts, got \(parts.count)")
            return nil
        }

        let payload = parts[1]

        // Add padding if needed (JWT base64 encoding might not have padding)
        var paddedPayload = payload
        let padding = 4 - (payload.count % 4)
        if padding != 4 {
            paddedPayload += String(repeating: "=", count: padding)
        }

        guard let data = Data(base64Encoded: paddedPayload) else {
            logger.warning("Failed to decode JWT payload as base64")
            return nil
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.warning("JWT payload is not valid JSON")
                return nil
            }

            // Handle different possible numeric types for the exp field
            let exp: TimeInterval
            if let expDouble = json["exp"] as? Double {
                exp = expDouble
            } else if let expInt = json["exp"] as? Int {
                exp = TimeInterval(expInt)
            } else if let expString = json["exp"] as? String, let expValue = Double(expString) {
                exp = expValue
            } else {
                logger.warning("JWT payload missing or invalid 'exp' field")
                return nil
            }

            return Date(timeIntervalSince1970: exp)
        } catch {
            logger.warning("Failed to parse JWT payload JSON: \(error.localizedDescription)")
            return nil
        }
    }

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

        print("🔍 [BlueskyAuth] Making authentication request to: \(url.absoluteString)")
        print("🔍 [BlueskyAuth] Using username: \(username)")

        do {
            // 4. Send request using session data method
            let (data, response) = try await session.data(for: request)

            print(
                "🔍 [BlueskyAuth] Response status: \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            )

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
                    print("❌ [BlueskyAuth] API error: \(errorMsg): \(message)")

                    // Provide more helpful error messages
                    let userMessage: String
                    if errorMsg.contains("InvalidCredentials")
                        || errorMsg.contains("AuthenticationRequired")
                    {
                        userMessage =
                            "Invalid username or app password. Please check your credentials."
                    } else if errorMsg.contains("RateLimitExceeded") {
                        userMessage = "Too many login attempts. Please try again later."
                    } else {
                        userMessage = "\(errorMsg): \(message)"
                    }

                    throw NSError(
                        domain: "BlueskyAPI",
                        code: 401,
                        userInfo: [NSLocalizedDescriptionKey: userMessage]
                    )
                }

                // Print raw response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    print("❌ [BlueskyAuth] Raw response: \(responseString)")
                }

                print("❌ [BlueskyAuth] Failed to decode authentication response")
                throw NetworkError.decodingError
            }

            print("✅ [BlueskyAuth] Successfully authenticated user: \(handle)")

            // 6. Create and return account with stable ID
            // Use handle + server as stable ID instead of DID which can change
            let serverString = server?.absoluteString ?? "bsky.social"
            let serverHostname: String
            if let url = URL(string: serverString), let host = url.host {
                serverHostname = host
            } else {
                // Extract hostname from string manually if URL parsing fails
                let cleanedServer = serverString.replacingOccurrences(of: "https://", with: "")
                    .replacingOccurrences(of: "http://", with: "")
                serverHostname = cleanedServer.components(separatedBy: "/").first ?? "bsky.social"
            }
            let stableId = "bluesky-\(handle)-\(serverHostname)"

            print("🔄 [BlueskyAuth] Generated stable account ID: \(stableId)")
            print("🔄 [BlueskyAuth] DID will be stored as platformSpecificId: \(did)")

            let account = SocialAccount(
                id: stableId,
                username: handle,
                displayName: handle,
                serverURL: server?.absoluteString ?? "bsky.social",
                platform: .bluesky
            )

            // Store the DID in platformSpecificId for API operations
            account.platformSpecificId = did

            // Save tokens
            account.saveAccessToken(accessJwt)
            account.saveRefreshToken(refreshJwt)

            // Decode JWT to get actual expiration time
            if let actualExpiration = decodeJWTExpiration(accessJwt) {
                logger.info("Setting Bluesky token expiration from JWT: \(actualExpiration)")
                account.saveTokenExpirationDate(actualExpiration)
            } else {
                // Fallback to conservative 2 hours if JWT decoding fails
                logger.warning("Could not decode JWT expiration, using 2-hour fallback")
                account.saveTokenExpirationDate(Date().addingTimeInterval(2 * 60 * 60))  // 2 hours
            }

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
            let (data, response) = try await session.data(for: request)

            // Check response status
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 400 {
                    // Try to parse the error response
                    if let errorJson = try? JSONSerialization.jsonObject(with: data)
                        as? [String: Any],
                        let error = errorJson["error"] as? String
                    {
                        logger.error("Bluesky refresh token error: \(error)")
                        if error == "ExpiredToken" {
                            // Refresh token has expired, user needs to re-authenticate
                            throw BlueskyTokenError.invalidRefreshToken
                        }
                    }
                    throw BlueskyTokenError.refreshFailed
                } else if httpResponse.statusCode != 200 {
                    logger.error(
                        "Bluesky refresh token failed with status: \(httpResponse.statusCode)")
                    throw BlueskyTokenError.refreshFailed
                }
            }

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

            // Decode JWT to get actual expiration time
            if let actualExpiration = decodeJWTExpiration(accessJwt) {
                logger.info(
                    "Setting refreshed Bluesky token expiration from JWT: \(actualExpiration)")
                account.saveTokenExpirationDate(actualExpiration)
            } else {
                // Fallback to conservative 2 hours if JWT decoding fails
                logger.warning("Could not decode refreshed JWT expiration, using 2-hour fallback")
                account.saveTokenExpirationDate(Date().addingTimeInterval(2 * 60 * 60))  // 2 hours
            }

            return (accessJwt, refreshJwt)
        } catch {
            if error is BlueskyTokenError {
                throw error
            }
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
                print(
                    "✅ Updated Bluesky account \(account.username) with profile image URL: \(avatarURL)"
                )

                // Post notification about the profile image update
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .profileImageUpdated,
                        object: nil,
                        userInfo: ["accountId": account.id, "profileImageURL": avatarURL]
                    )
                }
            }
        } catch {
            throw error
        }
    }

    // MARK: - Timeline

    /// Fetch the timeline for a Bluesky account
    func fetchTimeline(for account: SocialAccount) async throws -> TimelineResult {
        // Call the actual API implementation instead of using sample data
        return try await fetchHomeTimeline(for: account)
    }

    /// Fetch home timeline for a Bluesky account
    public func fetchHomeTimeline(
        for account: SocialAccount, limit: Int = 20, cursor: String? = nil
    ) async throws
        -> TimelineResult
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
        var queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]

        // Add cursor for pagination if provided
        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        components?.queryItems = queryItems

        if let finalURL = components?.url {
            request.url = finalURL
            logger.info("Final Bluesky API URL with params: \(finalURL.absoluteString)")
        }

        do {
            // Get a valid access token (automatically refreshes if needed)
            let accessToken = try await account.getValidAccessToken()
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

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

            if httpResponse.statusCode == 400 {
                // Check for expired token error and attempt auto-refresh
                if let responseBody = String(data: data, encoding: .utf8),
                    responseBody.contains("ExpiredToken")
                {
                    logger.info("Bluesky token expired, attempting automatic refresh...")

                    do {
                        // Force refresh the token
                        let refreshedToken = try await refreshAccessToken(for: account)

                        // Retry the request with the new token
                        request.setValue(
                            "Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")
                        let (retryData, retryResponse) = try await session.data(for: request)

                        if let retryHttpResponse = retryResponse as? HTTPURLResponse,
                            retryHttpResponse.statusCode == 200
                        {
                            logger.info("Successfully retried request with refreshed token")
                            return try processFeedDataWithPagination(retryData, account: account)
                        } else {
                            logger.error("Retry after token refresh still failed")
                            if let retryResponseBody = String(data: retryData, encoding: .utf8) {
                                logger.error("Retry response body: \(retryResponseBody)")
                            }
                        }
                    } catch {
                        logger.error(
                            "Failed to refresh token for retry: \(error.localizedDescription)")
                    }
                }

                // If we couldn't handle the 400 error or retry failed, fall through to generic error
                logger.error("Bluesky API returned 400 status")
                if let responseBody = String(data: data, encoding: .utf8) {
                    logger.error("Response body: \(responseBody)")
                }
                throw ServiceError.apiError("Server returned status code 400")
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
            var totalPosts = 0
            var postsWithEmbeds = 0
            var postsWithQuotes = 0

            let result = try processFeedDataWithPagination(data, account: account)

            totalPosts = result.posts.count
            postsWithEmbeds =
                result.posts.filter { post in
                    // Check if this post was created with embed data
                    return false  // We'll update this logic
                }.count

            logger.info("📊 Timeline processing summary:")
            logger.info("📊   - Total posts: \(totalPosts)")
            logger.info("📊   - Posts with embeds: \(postsWithEmbeds)")
            logger.info("📊   - Posts with quotes: \(self.quotedPostsCounter)")

            // Reset counter for next timeline fetch
            self.quotedPostsCounter = 0

            logger.info("Successfully processed \(result.posts.count) Bluesky posts")
            logger.info(
                "[Bluesky] Timeline post IDs and CIDs: \(result.posts.map { "\($0.id):\($0.cid ?? "nil")" }.joined(separator: ", "))"
            )
            return result
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

    /// Process feed data from timeline response with pagination
    private func processFeedDataWithPagination(_ data: Data, account: SocialAccount) throws
        -> TimelineResult
    {
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
                    return TimelineResult(posts: [], pagination: .empty)
                }

                throw NetworkError.decodingError
            }

            logger.info("Found \(feed.count) items in Bluesky feed")

            // Process the feed items
            let posts = try processTimelineResponse(feed, account: account)
            logger.info("Successfully processed \(posts.count) Bluesky posts")

            // Extract cursor for pagination
            let cursor = json["cursor"] as? String
            let hasNextPage = cursor != nil && !posts.isEmpty
            let pagination = PaginationInfo(hasNextPage: hasNextPage, nextPageToken: cursor)

            return TimelineResult(posts: posts, pagination: pagination)
        } catch {
            logger.error("Timeline processing error: \(error.localizedDescription)")
            if let data = String(data: data, encoding: .utf8) {
                logger.debug("Raw response data: \(data.prefix(500))...")
            }
            throw error
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
            if account.isTokenExpired, account.refreshToken != nil {
                // Try to refresh token
                logger.info("Refreshing expired Bluesky token for fetching post")
                do {
                    let (newAccessToken, newRefreshToken) = try await refreshSession(for: account)
                    account.saveAccessToken(newAccessToken)
                    account.saveRefreshToken(newRefreshToken)

                    // Update the request with the new token
                    request.setValue(
                        "Bearer \(newAccessToken)", forHTTPHeaderField: "Authorization")
                } catch BlueskyTokenError.invalidRefreshToken {
                    logger.error(
                        "Bluesky refresh token has expired for: \(account.username). User needs to re-authenticate."
                    )
                    throw ServiceError.unauthorized(
                        "Your Bluesky session has expired. Please re-add your account.")
                } catch {
                    logger.error("Failed to refresh Bluesky token: \(error.localizedDescription)")
                    // Continue with existing token as fallback but warn about potential issues
                    logger.warning("Continuing with existing token, but API calls may fail")
                }
            }

            // Get a valid access token (automatically refreshes if needed)
            let accessToken = try await account.getValidAccessToken()
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

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
        print("🔍 [QUOTE_DEBUG] Starting to process \(feedItems.count) feed items")
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

                // Extract viewer information for user interaction status
                let viewer = post["viewer"] as? [String: Any]

                // Extract interaction counts - these are crucial for user engagement metrics
                var likeCount = 0
                var repostCount = 0
                var replyCount = 0

                // DEBUG: Print entire post structure to understand API response
                print("🔍 [BlueskyService] Post structure for \(uri.suffix(20)):")
                print("🔍 [BlueskyService] Top-level keys: \(post.keys.sorted())")

                // Method 1: Direct count fields (most common in AT Protocol)
                if let likes = post["likeCount"] as? Int {
                    likeCount = likes
                }
                if let reposts = post["repostCount"] as? Int {
                    repostCount = reposts
                }
                if let replies = post["replyCount"] as? Int {
                    replyCount = replies
                }

                // Method 2: Check in metrics object
                if let metrics = post["metrics"] as? [String: Any] {
                    print("📊 [BlueskyService] Found metrics object: \(metrics)")
                    likeCount = metrics["likeCount"] as? Int ?? likeCount
                    repostCount = metrics["repostCount"] as? Int ?? repostCount
                    replyCount = metrics["replyCount"] as? Int ?? replyCount
                }

                // Method 3: Check in engagement/stats object
                if let stats = post["stats"] as? [String: Any] {
                    print("📊 [BlueskyService] Found stats object: \(stats)")
                    likeCount = stats["likeCount"] as? Int ?? likeCount
                    repostCount = stats["repostCount"] as? Int ?? repostCount
                    replyCount = stats["replyCount"] as? Int ?? replyCount
                }

                // Method 4: Check various count field names
                let countFields = [
                    "likes", "likeCount", "repost", "repostCount", "replies", "replyCount",
                ]
                for field in countFields {
                    if let value = post[field] as? Int {
                        print("📊 [BlueskyService] Found \(field): \(value)")
                        if field.contains("like") {
                            likeCount = max(likeCount, value)
                        } else if field.contains("repost") {
                            repostCount = max(repostCount, value)
                        } else if field.contains("repl") {
                            replyCount = max(replyCount, value)
                        }
                    }
                }

                print(
                    "📊 [BlueskyService] FINAL counts for \(uri.suffix(20)) - likes: \(likeCount), reposts: \(repostCount), replies: \(replyCount)"
                )

                // Check if this is a reply to another post
                var inReplyToID: String? = nil
                var inReplyToUsername: String? = nil
                var parentPost: Post? = nil

                if let reply = record["reply"] as? [String: Any],
                    let parent = reply["parent"] as? [String: Any],
                    let parentUri = parent["uri"] as? String
                {
                    inReplyToID = parentUri
                    logger.info("Found reply post with parent: \(parentUri)")

                    // Try to extract username from parent
                    if let parentAuthor = parent["author"] as? [String: Any],
                        let parentHandle = parentAuthor["handle"] as? String
                    {
                        inReplyToUsername = parentHandle
                        logger.info("[Bluesky] Setting inReplyToUsername to: \(parentHandle)")
                        // If we have sufficient information, create a simple parent post
                        if let parentDisplayName = parentAuthor["displayName"] as? String,
                            let parentAvatar = parentAuthor["avatar"] as? String
                        {
                            // Placeholder parent post: cid is nil, not actionable for like/repost
                            parentPost = Post(
                                id: parentUri,
                                content: "...",  // Placeholder until user requests full content
                                authorName: parentDisplayName,
                                authorUsername: parentHandle,
                                authorProfilePictureURL: parentAvatar,
                                createdAt: Date(),  // Placeholder
                                platform: .bluesky,
                                originalURL:
                                    "https://bsky.app/profile/\(parentHandle)/post/\(parentUri.split(separator: "/").last ?? "")",
                                attachments: [],
                                mentions: [],
                                tags: [],
                                originalPost: nil,
                                isReposted: false,
                                isLiked: false,
                                likeCount: 0,
                                repostCount: 0,
                                platformSpecificId: parentUri,
                                boostedBy: nil,
                                parent: nil,
                                inReplyToID: nil,
                                inReplyToUsername: nil,
                                quotedPostUri: nil,
                                quotedPostAuthorHandle: nil,
                                cid: nil,  // <-- Explicitly nil
                                blueskyLikeRecordURI: nil,  // Placeholder posts don't have interaction records
                                blueskyRepostRecordURI: nil
                            )
                            logger.info(
                                "[Bluesky] Created parent post with authorUsername: \(parentHandle) for parent id: \(parentUri) (placeholder, cid: nil)"
                            )
                        } else {
                            // Fallback: create a minimal parent post with just the handle
                            parentPost = Post(
                                id: parentUri,
                                content: "...",
                                authorName: parentHandle,
                                authorUsername: parentHandle,
                                authorProfilePictureURL: "",
                                createdAt: Date(),
                                platform: .bluesky,
                                originalURL:
                                    "https://bsky.app/profile/\(parentHandle)/post/\(parentUri.split(separator: "/").last ?? "")",
                                attachments: [],
                                mentions: [],
                                tags: [],
                                originalPost: nil,
                                isReposted: false,
                                isLiked: false,
                                likeCount: 0,
                                repostCount: 0,
                                platformSpecificId: parentUri,
                                boostedBy: nil,
                                parent: nil,
                                inReplyToID: nil,
                                inReplyToUsername: nil,
                                quotedPostUri: nil,
                                quotedPostAuthorHandle: nil,
                                cid: nil,  // <-- Explicitly nil
                                blueskyLikeRecordURI: nil,  // Placeholder posts don't have interaction records
                                blueskyRepostRecordURI: nil
                            )
                            logger.info(
                                "[Bluesky] Created minimal parent post with authorUsername: \(parentHandle) for parent id: \(parentUri) (placeholder, cid: nil)"
                            )
                        }
                    } else if let parentUri = parent["uri"] as? String {
                        // Fallback: try to extract handle from the URI - extract the actual DID/handle from URI pattern
                        // AT Protocol URI format: at://did:plc:xxx/app.bsky.feed.post/xxx
                        let uriComponents = parentUri.split(separator: "/")
                        let didString = uriComponents.count > 1 ? String(uriComponents[1]) : "user"

                        // For better display, try to use a readable handle if we can determine one
                        // If it's a DID, use a fallback display format
                        let displayHandle: String
                        if didString.hasPrefix("did:plc:") {
                            // For DID strings, show a truncated version
                            let shortDid = String(didString.suffix(8))  // Last 8 characters
                            displayHandle = "user-\(shortDid)"
                            inReplyToUsername = displayHandle
                        } else {
                            // It's already a handle
                            displayHandle = didString
                            inReplyToUsername = didString
                        }

                        parentPost = Post(
                            id: parentUri,
                            content: "...",
                            authorName: displayHandle,
                            authorUsername: displayHandle,
                            authorProfilePictureURL: "",
                            createdAt: Date(),
                            platform: .bluesky,
                            originalURL:
                                "https://bsky.app/profile/\(displayHandle)/post/\(parentUri.split(separator: "/").last ?? "")",
                            attachments: [],
                            mentions: [],
                            tags: [],
                            originalPost: nil,
                            isReposted: false,
                            isLiked: false,
                            likeCount: 0,
                            repostCount: 0,
                            platformSpecificId: parentUri,
                            boostedBy: nil,
                            parent: nil,
                            inReplyToID: nil,
                            inReplyToUsername: nil,
                            quotedPostUri: nil,
                            quotedPostAuthorHandle: nil,
                            cid: nil,  // <-- Explicitly nil
                            blueskyLikeRecordURI: nil,  // Placeholder posts don't have interaction records
                            blueskyRepostRecordURI: nil
                        )
                        logger.info(
                            "[Bluesky] Created fallback parent post with authorUsername: \(displayHandle) for parent id: \(parentUri) (placeholder, cid: nil)"
                        )
                    }
                }

                // Process media attachments - handle different API embed formats
                var attachments: [Post.Attachment] = []
                if let embed = post["embed"] as? [String: Any] {
                    print(
                        "[Bluesky] 🔍 Processing embed for post \(uri): \(embed.keys.joined(separator: ", "))"
                    )
                    logger.info(
                        "[Bluesky] Processing embed for post \(uri): \(embed.keys.joined(separator: ", "))"
                    )

                    // First try the images array format
                    if let images = embed["images"] as? [[String: Any]] {
                        for image in images {
                            if let fullsize = image["fullsize"] as? String, !fullsize.isEmpty,
                                URL(string: fullsize) != nil
                            {
                                let alt = image["alt"] as? String ?? "Image"
                                attachments.append(
                                    Post.Attachment(url: fullsize, type: .image, altText: alt))
                            }
                        }
                    }
                    // Then try the other common formats for images
                    else if let media = embed["media"] as? [String: Any],
                        let mediaType = media["$type"] as? String,
                        mediaType.contains("image"),
                        let imgUrl = media["image"] as? [String: Any],
                        let url = imgUrl["url"] as? String, !url.isEmpty, URL(string: url) != nil
                    {
                        let alt = media["alt"] as? String ?? "Image"
                        logger.debug("[Bluesky] Parsed image attachment: \(url) alt: \(alt)")
                        attachments.append(
                            Post.Attachment(
                                url: url,
                                type: .image,
                                altText: alt
                            ))
                    }
                    // Note: Quote posts are handled separately below, don't skip non-image embeds
                }

                // Extract mentions and hashtags
                var mentions: [String] = []
                var tags: [String] = []
                var fullTextWithLinks = text  // Start with original text

                if let facets = record["facets"] as? [[String: Any]] {
                    // Track URL replacements to avoid truncated links
                    var urlReplacements: [(range: NSRange, fullURL: String)] = []

                    for facet in facets {
                        if let features = facet["features"] as? [[String: Any]],
                            let index = facet["index"] as? [String: Any],
                            let byteStart = index["byteStart"] as? Int,
                            let byteEnd = index["byteEnd"] as? Int
                        {

                            let range = NSRange(location: byteStart, length: byteEnd - byteStart)

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
                                    } else if type == "app.bsky.richtext.facet#link" {
                                        if let fullURL = feature["uri"] as? String {
                                            // Store this URL replacement for later processing
                                            urlReplacements.append((range: range, fullURL: fullURL))
                                            logger.info(
                                                "[Bluesky] Found full URL in facet: \(fullURL) at range \(byteStart)-\(byteEnd)"
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Apply URL replacements to fix truncated links
                    // Sort by start position in reverse order to avoid range shifting
                    urlReplacements.sort { $0.range.location > $1.range.location }

                    for replacement in urlReplacements {
                        let nsText = fullTextWithLinks as NSString
                        if replacement.range.location >= 0
                            && NSMaxRange(replacement.range) <= nsText.length
                        {
                            let originalText = nsText.substring(with: replacement.range)
                            // Only replace if the original text appears truncated (contains ellipsis or is shorter)
                            if originalText.contains("...")
                                || originalText.count < replacement.fullURL.count
                            {
                                fullTextWithLinks = nsText.replacingCharacters(
                                    in: replacement.range, with: replacement.fullURL)
                                logger.info(
                                    "[Bluesky] Replaced truncated URL '\(originalText)' with full URL '\(replacement.fullURL)'"
                                )
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
                    logger.info("[Bluesky] Detected repost with reason: \(reason)")
                    // This is a repost - process the original post
                    if let reasonBy = reason["by"] as? [String: Any],
                        let reposterName = reasonBy["displayName"] as? String ?? reasonBy["handle"]
                            as? String,
                        let reposterUsername = reasonBy["handle"] as? String,
                        let repostIndexedAt = reason["indexedAt"] as? String
                    {
                        // Set the boosted by field
                        boostedBy = reposterName

                        // Create the original post with its original timestamp
                        let createdAtDate = DateParser.parse(createdAt) ?? Date.distantPast
                        let indexedAtDate = DateParser.parse(item["indexedAt"] as? String) ?? Date()
                        let now = Date()
                        let skewWindow: TimeInterval = 120  // 2 minutes
                        let displayDate: Date
                        if createdAtDate > now.addingTimeInterval(skewWindow) {
                            displayDate = indexedAtDate
                        } else {
                            displayDate = createdAtDate
                        }

                        originalPost = Post(
                            id: uri,
                            content: fullTextWithLinks,
                            authorName: authorName,
                            authorUsername: authorUsername,
                            authorProfilePictureURL: authorAvatarURL,
                            createdAt: displayDate,
                            platform: .bluesky,
                            originalURL:
                                "https://bsky.app/profile/\(authorUsername)/post/\(uri.split(separator: "/").last ?? "")",
                            attachments: attachments,
                            mentions: mentions,
                            tags: tags,
                            isReposted: viewer?["repost"] as? String != nil,  // Fixed: Use actual user repost status
                            isLiked: viewer?["like"] as? String != nil,  // Fixed: Use actual user like status
                            likeCount: likeCount,
                            repostCount: repostCount,
                            replyCount: replyCount,  // Add reply count
                            platformSpecificId: uri,
                            boostedBy: nil,  // Don't set boostedBy on the original post
                            parent: parentPost,
                            inReplyToID: inReplyToID,
                            inReplyToUsername: inReplyToUsername,
                            quotedPostUri: nil,
                            quotedPostAuthorHandle: nil,
                            cid: post["cid"] as? String,
                            blueskyLikeRecordURI: viewer?["like"] as? String,  // Fixed: Use actual like URI
                            blueskyRepostRecordURI: viewer?["repost"] as? String  // Fixed: Use actual repost URI
                        )

                        // Create the repost wrapper with repost timestamp for timeline positioning
                        let repostId = "repost-\(reposterUsername)-\(uri)"

                        // Check if the current user has reposted this content (from the original post's viewer info)
                        let userHasReposted = viewer?["repost"] as? String != nil

                        let repost = Post(
                            id: repostId,
                            content: "",  // Empty content for reposts
                            authorName: reposterName,
                            authorUsername: reposterUsername,
                            authorProfilePictureURL: reasonBy["avatar"] as? String ?? "",
                            createdAt: displayDate,  // Use repost timestamp for timeline positioning
                            platform: .bluesky,
                            originalURL:
                                "https://bsky.app/profile/\(reposterUsername)/post/\(uri.split(separator: "/").last ?? "")",
                            attachments: [],
                            mentions: [],
                            tags: [],
                            originalPost: originalPost,
                            isReposted: userHasReposted,  // Fixed: Use actual user repost status
                            platformSpecificId: repostId,
                            boostedBy: reposterName,
                            parent: nil,
                            inReplyToID: nil,
                            inReplyToUsername: nil,
                            quotedPostUri: nil,
                            quotedPostAuthorHandle: nil,
                            cid: nil,  // <-- Explicitly nil for wrapper
                            blueskyLikeRecordURI: nil,  // No like record for wrapper posts
                            blueskyRepostRecordURI: viewer?["repost"] as? String  // Use actual repost URI if user reposted
                        )

                        posts.append(repost)
                        continue
                    }
                }

                // Extract quote post info if present
                var quotedPostUri: String? = nil
                var quotedPostAuthorHandle: String? = nil
                var quotedPost: Post? = nil
                var externalEmbedURL: String? = nil

                if let embed = post["embed"] as? [String: Any] {
                    print(
                        "🔍 [QUOTE_DEBUG] Found embed for post \(uri): \(embed.keys.joined(separator: ", "))"
                    )
                    logger.info(
                        "[Bluesky] Processing embed for post \(uri): \(embed.keys.joined(separator: ", "))"
                    )

                    // Debug: Log the full embed structure
                    print("[Bluesky] 🔍 Full embed structure for post \(uri):")
                    if let embedData = try? JSONSerialization.data(withJSONObject: embed),
                        let embedString = String(data: embedData, encoding: .utf8)
                    {
                        print("[Bluesky] 🔍 Embed JSON: \(String(embedString.prefix(500)))")
                    }

                    // Extract external URLs from embeds for link preview
                    if let embedType = embed["$type"] as? String,
                        embedType == "app.bsky.embed.external#view",
                        let external = embed["external"] as? [String: Any],
                        let externalUri = external["uri"] as? String
                    {
                        externalEmbedURL = externalUri
                        logger.info("[Bluesky] Found external embed URL: \(externalUri)")
                    }

                    // Handle direct record embed (quote post) - check for app.bsky.embed.record#view
                    if let embedType = embed["$type"] as? String,
                        embedType == "app.bsky.embed.record#view",
                        let record = embed["record"] as? [String: Any],
                        let quotedUri = record["uri"] as? String,
                        let quotedAuthor = record["author"] as? [String: Any],
                        let quotedHandle = quotedAuthor["handle"] as? String
                    {
                        quotedPostUri = quotedUri
                        quotedPostAuthorHandle = quotedHandle
                        logger.info("[Bluesky] Found quote post embed: \(quotedUri)")

                        // Hydrate quotedPost if the full quoted post is embedded
                        if let quotedValue = record["value"] as? [String: Any],
                            let quotedText = quotedValue["text"] as? String,
                            let quotedCreatedAt = quotedValue["createdAt"] as? String
                        {
                            let quotedAuthorName =
                                (quotedAuthor["displayName"] as? String) ?? quotedHandle
                            let quotedAuthorAvatar = quotedAuthor["avatar"] as? String ?? ""
                            let quotedCreatedAtDate =
                                DateParser.parse(quotedCreatedAt) ?? Date.distantPast

                            // Parse quoted post attachments if present
                            var quotedAttachments: [Post.Attachment] = []
                            if let quotedEmbed = quotedValue["embed"] as? [String: Any] {
                                logger.info(
                                    "[Bluesky] Processing quoted post embed: \(quotedEmbed.keys.joined(separator: ", "))"
                                )

                                // Handle images array format in quoted post
                                if let images = quotedEmbed["images"] as? [[String: Any]] {
                                    for image in images {
                                        if let fullsize = image["fullsize"] as? String,
                                            !fullsize.isEmpty,
                                            URL(string: fullsize) != nil
                                        {
                                            let alt = image["alt"] as? String ?? "Image"
                                            quotedAttachments.append(
                                                Post.Attachment(
                                                    url: fullsize, type: .image, altText: alt))
                                            logger.debug(
                                                "[Bluesky] Parsed quoted post image: \(fullsize)")
                                        }
                                    }
                                }
                                // Handle other media formats in quoted post
                                else if let media = quotedEmbed["media"] as? [String: Any],
                                    let mediaType = media["$type"] as? String,
                                    mediaType.contains("image"),
                                    let imgUrl = media["image"] as? [String: Any],
                                    let url = imgUrl["url"] as? String, !url.isEmpty,
                                    URL(string: url) != nil
                                {
                                    let alt = media["alt"] as? String ?? "Image"
                                    quotedAttachments.append(
                                        Post.Attachment(url: url, type: .image, altText: alt))
                                    logger.debug("[Bluesky] Parsed quoted post media: \(url)")
                                }
                            }

                            quotedPost = Post(
                                id: quotedUri,
                                content: quotedText,
                                authorName: quotedAuthorName,
                                authorUsername: quotedHandle,
                                authorProfilePictureURL: quotedAuthorAvatar,
                                createdAt: quotedCreatedAtDate,
                                platform: .bluesky,
                                originalURL:
                                    "https://bsky.app/profile/\(quotedHandle)/post/\(quotedUri.split(separator: "/").last ?? "")",
                                attachments: quotedAttachments,  // Now properly parsed
                                mentions: [],
                                tags: [],
                                likeCount: 0,
                                repostCount: 0,
                                platformSpecificId: quotedUri,
                                boostedBy: nil,
                                parent: nil,
                                inReplyToID: nil,
                                inReplyToUsername: nil,
                                quotedPostUri: nil,
                                quotedPostAuthorHandle: nil,
                                cid: record["cid"] as? String,
                                blueskyLikeRecordURI: nil,  // Quoted posts don't have user interaction records
                                blueskyRepostRecordURI: nil
                            )
                            logger.info(
                                "[Bluesky] Successfully hydrated quote post with \(quotedAttachments.count) attachments: \(quotedText.prefix(40))"
                            )
                        } else {
                            logger.info(
                                "[Bluesky] Quote post found but not fully hydrated, will fetch separately"
                            )
                        }
                    }
                    // Handle recordWithMedia embed (quote post with media)
                    else if let recordWithMedia = embed["recordWithMedia"] as? [String: Any],
                        let record = recordWithMedia["record"] as? [String: Any],
                        let quotedRecord = record["record"] as? [String: Any],
                        let quotedUri = quotedRecord["uri"] as? String,
                        let quotedAuthor = quotedRecord["author"] as? [String: Any],
                        let quotedHandle = quotedAuthor["handle"] as? String
                    {
                        quotedPostUri = quotedUri
                        quotedPostAuthorHandle = quotedHandle
                        logger.info("[Bluesky] Found quote post with media embed: \(quotedUri)")

                        // Handle similar to above but also process media
                        if let quotedText = quotedRecord["text"] as? String,
                            let quotedCreatedAt = quotedRecord["createdAt"] as? String
                        {
                            let quotedAuthorName =
                                (quotedAuthor["displayName"] as? String) ?? quotedHandle
                            let quotedAuthorAvatar = quotedAuthor["avatar"] as? String ?? ""
                            let quotedCreatedAtDate =
                                DateParser.parse(quotedCreatedAt) ?? Date.distantPast

                            // Parse quoted post attachments for recordWithMedia
                            var quotedAttachments: [Post.Attachment] = []

                            // First, check if there are attachments in the quoted record itself
                            if let quotedEmbed = quotedRecord["embed"] as? [String: Any] {
                                logger.info(
                                    "[Bluesky] Processing quoted post embed in recordWithMedia: \(quotedEmbed.keys.joined(separator: ", "))"
                                )

                                if let images = quotedEmbed["images"] as? [[String: Any]] {
                                    for image in images {
                                        if let fullsize = image["fullsize"] as? String,
                                            !fullsize.isEmpty,
                                            URL(string: fullsize) != nil
                                        {
                                            let alt = image["alt"] as? String ?? "Image"
                                            quotedAttachments.append(
                                                Post.Attachment(
                                                    url: fullsize, type: .image, altText: alt))
                                            logger.debug(
                                                "[Bluesky] Parsed quoted post image in recordWithMedia: \(fullsize)"
                                            )
                                        }
                                    }
                                }
                                // Handle other media formats in quoted post
                                else if let media = quotedEmbed["media"] as? [String: Any],
                                    let mediaType = media["$type"] as? String,
                                    mediaType.contains("image"),
                                    let imgUrl = media["image"] as? [String: Any],
                                    let url = imgUrl["url"] as? String, !url.isEmpty,
                                    URL(string: url) != nil
                                {
                                    let alt = media["alt"] as? String ?? "Image"
                                    quotedAttachments.append(
                                        Post.Attachment(url: url, type: .image, altText: alt))
                                    logger.debug("[Bluesky] Parsed quoted post media: \(url)")
                                }
                            }

                            // Also check the media part of recordWithMedia for additional attachments
                            if let media = recordWithMedia["media"] as? [String: Any] {
                                logger.info(
                                    "[Bluesky] Processing media in recordWithMedia: \(media.keys.joined(separator: ", "))"
                                )

                                if let images = media["images"] as? [[String: Any]] {
                                    for image in images {
                                        if let fullsize = image["fullsize"] as? String,
                                            !fullsize.isEmpty,
                                            URL(string: fullsize) != nil
                                        {
                                            let alt = image["alt"] as? String ?? "Image"
                                            quotedAttachments.append(
                                                Post.Attachment(
                                                    url: fullsize, type: .image, altText: alt))
                                            logger.debug(
                                                "[Bluesky] Parsed media image in recordWithMedia: \(fullsize)"
                                            )
                                        }
                                    }
                                }
                            }

                            quotedPost = Post(
                                id: quotedUri,
                                content: quotedText,
                                authorName: quotedAuthorName,
                                authorUsername: quotedHandle,
                                authorProfilePictureURL: quotedAuthorAvatar,
                                createdAt: quotedCreatedAtDate,
                                platform: .bluesky,
                                originalURL:
                                    "https://bsky.app/profile/\(quotedHandle)/post/\(quotedUri.split(separator: "/").last ?? "")",
                                attachments: quotedAttachments,  // Now properly parsed
                                mentions: [],
                                tags: [],
                                likeCount: 0,
                                repostCount: 0,
                                platformSpecificId: quotedUri,
                                boostedBy: nil,
                                parent: nil,
                                inReplyToID: nil,
                                inReplyToUsername: nil,
                                quotedPostUri: nil,
                                quotedPostAuthorHandle: nil,
                                cid: quotedRecord["cid"] as? String,
                                blueskyLikeRecordURI: nil,  // Quoted posts don't have user interaction records
                                blueskyRepostRecordURI: nil
                            )
                            logger.info(
                                "[Bluesky] Successfully hydrated quote post with media and \(quotedAttachments.count) attachments: \(quotedText.prefix(40))"
                            )
                        }
                    }
                }

                let cid = post["cid"] as? String

                // Calculate displayDate for all posts
                let createdAtDate = DateParser.parse(createdAt) ?? Date.distantPast
                let indexedAtDate = DateParser.parse(item["indexedAt"] as? String) ?? Date()
                let now = Date()
                let skewWindow: TimeInterval = 120  // 2 minutes
                let displayDate: Date
                if createdAtDate > now.addingTimeInterval(skewWindow) {
                    displayDate = indexedAtDate
                } else {
                    displayDate = createdAtDate
                }

                // Add external embed URL to content for link detection
                var finalContent = fullTextWithLinks
                if let externalURL = externalEmbedURL {
                    // If the post has no text content, add the URL
                    // If it has text, append the URL with a space
                    if finalContent.isEmpty {
                        finalContent = externalURL
                    } else if !finalContent.contains(externalURL) {
                        finalContent += " \(externalURL)"
                    }
                    logger.info("[Bluesky] Added external URL to post content: \(externalURL)")
                }

                // Create regular post
                let newPost = Post(
                    id: uri,
                    content: finalContent,
                    authorName: authorName,
                    authorUsername: authorUsername,
                    authorProfilePictureURL: authorAvatarURL,
                    createdAt: displayDate,
                    platform: .bluesky,
                    originalURL:
                        "https://bsky.app/profile/\(authorUsername)/post/\(uri.split(separator: "/").last ?? "")",
                    attachments: attachments,
                    mentions: mentions,
                    tags: tags,
                    isReposted: viewer?["repost"] as? String != nil,  // Fixed: Use actual user repost status
                    isLiked: viewer?["like"] as? String != nil,  // Fixed: Use actual user like status
                    likeCount: likeCount,
                    repostCount: repostCount,
                    replyCount: replyCount,  // Add reply count
                    platformSpecificId: uri,
                    boostedBy: boostedBy,
                    parent: parentPost,
                    inReplyToID: inReplyToID,
                    inReplyToUsername: inReplyToUsername,
                    quotedPostUri: quotedPostUri,
                    quotedPostAuthorHandle: quotedPostAuthorHandle,
                    cid: cid,
                    blueskyLikeRecordURI: viewer?["like"] as? String,  // Fixed: Use actual like URI
                    blueskyRepostRecordURI: viewer?["repost"] as? String  // Fixed: Use actual repost URI
                )
                newPost.quotedPost = quotedPost

                // Count quote posts for statistics
                if quotedPostUri != nil || quotedPostAuthorHandle != nil || quotedPost != nil {
                    self.quotedPostsCounter += 1
                    logger.debug(
                        "🔗 Created post with quote metadata: \(uri) - hydrated: \(quotedPost != nil)"
                    )
                }

                logger.info(
                    "[Bluesky] Parsed post: id=\(uri), cid=\(cid ?? "nil"), content=\(fullTextWithLinks.prefix(40))"
                )

                // Debug logging for potentially problematic posts
                if fullTextWithLinks.isEmpty && originalPost == nil {
                    logger.warning(
                        "[Bluesky] Found post with empty content and no originalPost: id=\(uri), author=\(authorUsername)"
                    )
                    logger.warning(
                        "[Bluesky] - Post structure: cid=\(cid ?? "nil"), hasEmbed=\(post["embed"] != nil), quotedPostUri=\(quotedPostUri ?? "nil")"
                    )
                    if let reason = item["reason"] as? [String: Any] {
                        logger.warning("[Bluesky] - Has reason: \(reason)")
                    } else {
                        logger.warning("[Bluesky] - No reason found")
                    }
                    if let embed = post["embed"] as? [String: Any] {
                        logger.warning("[Bluesky] - Embed structure: \(embed)")
                    }
                }

                posts.append(newPost)
            } catch {
                logger.error("Error processing timeline item: \(error.localizedDescription)")
                // Continue processing other items
                continue
            }
        }

        return posts
    }

    private func convertBlueskyPostToOriginalPost(_ post: BlueskyPost) -> Post {
        let quotedPostUri = post.embed?.record?.record.uri
        let quotedPostAuthorHandle: String? = nil  // Not available from Bluesky API
        let authorName = post.author.displayName ?? post.author.handle
        let authorUsername = post.author.handle
        let authorProfilePictureURL = post.author.avatar ?? ""
        let createdAt = ISO8601DateFormatter().date(from: post.record.createdAt) ?? Date()
        let content = post.record.text
        let originalURL =
            "https://\(authorUsername)/post/\(post.uri.split(separator: "/").last ?? "")"
        var attachments: [Post.Attachment] = []
        let mentions: [String] = []  // TODO: Extract mentions from Bluesky post if available
        let tags: [String] = []  // TODO: Extract tags from Bluesky post if available
        let cid = post.cid  // Use the real cid from BlueskyPost
        return Post(
            id: UUID().uuidString,
            content: content,
            authorName: authorName,
            authorUsername: authorUsername,
            authorProfilePictureURL: authorProfilePictureURL,
            createdAt: createdAt,
            platform: .bluesky,
            originalURL: originalURL,
            attachments: attachments,
            mentions: mentions,
            tags: tags,
            originalPost: nil,
            isReposted: post.viewer?.repostUri != nil,
            isLiked: post.viewer?.likeUri != nil,
            likeCount: post.likeCount,
            repostCount: post.repostCount,
            platformSpecificId: post.uri,
            boostedBy: nil,
            parent: nil,
            inReplyToID: nil,
            inReplyToUsername: nil,
            quotedPostUri: quotedPostUri,
            quotedPostAuthorHandle: quotedPostAuthorHandle,
            cid: cid,
            blueskyLikeRecordURI: post.viewer?.likeUri,  // Use existing like URI if available
            blueskyRepostRecordURI: post.viewer?.repostUri  // Use existing repost URI if available
        )
    }

    // MARK: - Post Actions

    /// Get a specific post by URI
    func getPost(uri: String, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        let encodedUri = uri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? uri
        let serverString = account.serverURL?.absoluteString ?? "bsky.social"
        let url = URL(
            string:
                "https://\(serverString)/xrpc/app.bsky.feed.getPostThread?uri=\(encodedUri)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get post"])
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let thread = json["thread"] as? [String: Any],
            let post = thread["post"] as? [String: Any]
        else {
            throw NSError(
                domain: "BlueskyService", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse post thread"])
        }
        let postData = try JSONSerialization.data(withJSONObject: post)
        let blueskyPost = try JSONDecoder().decode(BlueskyPost.self, from: postData)
        return convertBlueskyPostToOriginalPost(blueskyPost)
    }

    /// Like a post on Bluesky
    func likePost(_ post: Post, account: SocialAccount) async throws -> Post {
        // Check if the post is present in the timeline (for debugging)
        let timelinePosts = SocialFusionTimelineDebug.shared.blueskyPosts
        let found = timelinePosts.contains(where: { $0.id == post.id })
        if !found {
            logger.warning(
                "[Bluesky] Attempting to like a post not present in timeline array: id=\(post.id)"
            )
        }
        logger.info(
            "[Bluesky] Attempting to like post: id=\(post.id), cid=\(post.cid ?? "nil"), platformSpecificId=\(post.platformSpecificId)"
        )
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        // Check if token needs refresh
        if account.isTokenExpired, account.refreshToken != nil {
            let (newAccessToken, newRefreshToken) = try await refreshSession(for: account)
            account.saveAccessToken(newAccessToken)
            account.saveRefreshToken(newRefreshToken)
        }
        // Safely unwrap and sanitize serverURL
        let rawServerURL = account.serverURL?.absoluteString ?? "bsky.social"
        let sanitizedServerURL = rawServerURL.replacingOccurrences(of: "https://", with: "")
        let urlString = "https://\(sanitizedServerURL)/xrpc/com.atproto.repo.createRecord"
        guard let url = URL(string: urlString) else {
            logger.error("Malformed Bluesky likePost URL: \(urlString)")
            throw NSError(
                domain: "BlueskyService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Malformed Bluesky likePost URL"])
        }
        logger.info("[Bluesky] likePost URL: \(urlString)")

        // For boost posts, we need to like the original post, not the wrapper
        let targetPost = post.originalPost ?? post
        let targetCid = targetPost.cid
        let targetUri = targetPost.platformSpecificId

        guard let cid = targetCid, !cid.isEmpty else {
            logger.error(
                "[Bluesky] Cannot like post: missing CID for post \(targetUri)")
            throw NSError(
                domain: "BlueskyService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Cannot like post: missing CID for post"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let parameters: [String: Any] = [
            "repo": account.platformSpecificId,  // Use DID instead of stable ID
            "collection": "app.bsky.feed.like",
            "record": [
                "$type": "app.bsky.feed.like",
                "subject": [
                    "uri": targetUri,  // Use target URI for boost posts
                    "cid": cid,
                ],
                "createdAt": ISO8601DateFormatter().string(from: Date()),
            ],
        ]
        logger.info("[Bluesky] likePost parameters: \(parameters)")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            logger.info("[Bluesky] likePost response status: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                if let responseBody = String(data: data, encoding: .utf8) {
                    logger.error("[Bluesky] likePost error response: \(responseBody)")
                }
            }
        }
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to like post"])
        }

        // Parse the response to get the like record URI
        var likeRecordURI: String? = nil
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let uri = json["uri"] as? String
        {
            likeRecordURI = uri
            logger.info("[Bluesky] Stored like record URI: \(uri)")
        } else {
            logger.warning("[Bluesky] Could not parse like record URI from response")
        }

        // Create a copy to avoid mutating the original Post object and causing AttributeGraph cycles
        let updatedPost = Post(
            id: post.id,
            content: post.content,
            authorName: post.authorName,
            authorUsername: post.authorUsername,
            authorProfilePictureURL: post.authorProfilePictureURL,
            createdAt: post.createdAt,
            platform: post.platform,
            originalURL: post.originalURL,
            attachments: post.attachments,
            mentions: post.mentions,
            tags: post.tags,
            originalPost: post.originalPost,
            isReposted: post.isReposted,
            isLiked: true,  // Updated
            likeCount: post.likeCount + 1,  // Updated
            repostCount: post.repostCount,
            platformSpecificId: post.platformSpecificId,
            boostedBy: post.boostedBy,
            parent: post.parent,
            inReplyToID: post.inReplyToID,
            inReplyToUsername: post.inReplyToUsername,
            quotedPostUri: post.quotedPostUri,
            quotedPostAuthorHandle: post.quotedPostAuthorHandle,
            cid: post.cid,
            blueskyLikeRecordURI: likeRecordURI,  // Store the like record URI
            blueskyRepostRecordURI: post.blueskyRepostRecordURI  // Preserve existing repost record URI
        )
        return updatedPost
    }

    /// Unlike a post on Bluesky
    func unlikePost(_ post: Post, account: SocialAccount) async throws -> Post {
        logger.info(
            "[Bluesky] Attempting to unlike post: id=\(post.id), cid=\(post.cid ?? "nil"), platformSpecificId=\(post.platformSpecificId)"
        )

        guard let likeRecordURI = post.blueskyLikeRecordURI else {
            logger.warning(
                "[Bluesky] No like record URI found for post \(post.id) - cannot unlike. This may be a legacy post or one liked before the record URI tracking was implemented."
            )
            // Still update local state optimistically for better UX
            let updatedPost = Post(
                id: post.id,
                content: post.content,
                authorName: post.authorName,
                authorUsername: post.authorUsername,
                authorProfilePictureURL: post.authorProfilePictureURL,
                createdAt: post.createdAt,
                platform: post.platform,
                originalURL: post.originalURL,
                attachments: post.attachments,
                mentions: post.mentions,
                tags: post.tags,
                originalPost: post.originalPost,
                isReposted: post.isReposted,
                isLiked: false,  // Updated
                likeCount: max(0, post.likeCount - 1),  // Updated
                repostCount: post.repostCount,
                platformSpecificId: post.platformSpecificId,
                boostedBy: post.boostedBy,
                parent: post.parent,
                inReplyToID: post.inReplyToID,
                inReplyToUsername: post.inReplyToUsername,
                quotedPostUri: post.quotedPostUri,
                quotedPostAuthorHandle: post.quotedPostAuthorHandle,
                cid: post.cid,
                blueskyLikeRecordURI: nil,  // Clear the like record URI
                blueskyRepostRecordURI: post.blueskyRepostRecordURI
            )
            return updatedPost
        }

        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        // Check if token needs refresh
        if account.isTokenExpired, account.refreshToken != nil {
            let (newAccessToken, newRefreshToken) = try await refreshSession(for: account)
            account.saveAccessToken(newAccessToken)
            account.saveRefreshToken(newRefreshToken)
        }

        // Extract the rkey from the like record URI
        let rkey = String(likeRecordURI.split(separator: "/").last ?? "")
        guard !rkey.isEmpty else {
            logger.error("[Bluesky] Could not extract rkey from like record URI: \(likeRecordURI)")
            throw NSError(
                domain: "BlueskyService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid like record URI format"])
        }

        // Safely unwrap and sanitize serverURL
        let rawServerURL = account.serverURL?.absoluteString ?? "bsky.social"
        let sanitizedServerURL = rawServerURL.replacingOccurrences(of: "https://", with: "")
        let urlString = "https://\(sanitizedServerURL)/xrpc/com.atproto.repo.deleteRecord"

        guard let url = URL(string: urlString) else {
            logger.error("Malformed Bluesky unlikePost URL: \(urlString)")
            throw NSError(
                domain: "BlueskyService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Malformed Bluesky unlikePost URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let parameters: [String: Any] = [
            "repo": account.platformSpecificId,  // Use DID instead of stable ID
            "collection": "app.bsky.feed.like",
            "rkey": rkey,
        ]

        logger.info("[Bluesky] unlikePost parameters: \(parameters)")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            logger.info("[Bluesky] unlikePost response status: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                if let responseBody = String(data: data, encoding: .utf8) {
                    logger.error("[Bluesky] unlikePost error response: \(responseBody)")
                }
            }
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to unlike post"])
        }

        logger.info("[Bluesky] Successfully unliked post with record URI: \(likeRecordURI)")

        // Create a copy to avoid mutating the original Post object and causing AttributeGraph cycles
        let updatedPost = Post(
            id: post.id,
            content: post.content,
            authorName: post.authorName,
            authorUsername: post.authorUsername,
            authorProfilePictureURL: post.authorProfilePictureURL,
            createdAt: post.createdAt,
            platform: post.platform,
            originalURL: post.originalURL,
            attachments: post.attachments,
            mentions: post.mentions,
            tags: post.tags,
            originalPost: post.originalPost,
            isReposted: post.isReposted,
            isLiked: false,  // Updated
            likeCount: max(0, post.likeCount - 1),  // Updated
            repostCount: post.repostCount,
            platformSpecificId: post.platformSpecificId,
            boostedBy: post.boostedBy,
            parent: post.parent,
            inReplyToID: post.inReplyToID,
            inReplyToUsername: post.inReplyToUsername,
            quotedPostUri: post.quotedPostUri,
            quotedPostAuthorHandle: post.quotedPostAuthorHandle,
            cid: post.cid,
            blueskyLikeRecordURI: nil,  // Clear the like record URI
            blueskyRepostRecordURI: post.blueskyRepostRecordURI  // Preserve existing repost record URI
        )
        return updatedPost
    }

    /// Repost a post on Bluesky
    func repostPost(_ post: Post, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        // Check if token needs refresh
        if account.isTokenExpired, account.refreshToken != nil {
            let (newAccessToken, newRefreshToken) = try await refreshSession(for: account)
            account.saveAccessToken(newAccessToken)
            account.saveRefreshToken(newRefreshToken)
        }
        // Safely unwrap and sanitize serverURL
        let rawServerURL = account.serverURL?.absoluteString ?? "bsky.social"
        let sanitizedServerURL = rawServerURL.replacingOccurrences(of: "https://", with: "")
        let urlString = "https://\(sanitizedServerURL)/xrpc/com.atproto.repo.createRecord"
        guard let url = URL(string: urlString) else {
            logger.error("Malformed Bluesky repostPost URL: \(urlString)")
            throw NSError(
                domain: "BlueskyService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Malformed Bluesky repostPost URL"])
        }
        logger.info("[Bluesky] repostPost URL: \(urlString)")

        // For boost posts, we need to repost the original post, not the wrapper
        let targetPost = post.originalPost ?? post
        let targetCid = targetPost.cid
        let targetUri = targetPost.platformSpecificId

        guard let cid = targetCid, !cid.isEmpty else {
            logger.error("[Bluesky] Cannot repost: missing CID for post \(targetUri)")
            throw NSError(
                domain: "BlueskyService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Cannot repost: missing CID for post"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let parameters: [String: Any] = [
            "repo": account.platformSpecificId,  // Use DID instead of stable ID
            "collection": "app.bsky.feed.repost",
            "record": [
                "$type": "app.bsky.feed.repost",
                "subject": [
                    "uri": targetUri,
                    "cid": cid,
                ],
                "createdAt": ISO8601DateFormatter().string(from: Date()),
            ],
        ]
        logger.info("[Bluesky] repostPost parameters: \(parameters)")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            logger.info("[Bluesky] repostPost response status: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                if let responseBody = String(data: data, encoding: .utf8) {
                    logger.error("[Bluesky] repostPost error response: \(responseBody)")
                }
            }
        }
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to repost"])
        }

        // Parse the response to get the repost record URI
        var repostRecordURI: String? = nil
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let uri = json["uri"] as? String
        {
            repostRecordURI = uri
            logger.info("[Bluesky] Stored repost record URI: \(uri)")
        } else {
            logger.warning("[Bluesky] Could not parse repost record URI from response")
        }

        // Create a copy to avoid mutating the original Post object and causing AttributeGraph cycles
        let updatedPost = Post(
            id: post.id,
            content: post.content,
            authorName: post.authorName,
            authorUsername: post.authorUsername,
            authorProfilePictureURL: post.authorProfilePictureURL,
            createdAt: post.createdAt,
            platform: post.platform,
            originalURL: post.originalURL,
            attachments: post.attachments,
            mentions: post.mentions,
            tags: post.tags,
            originalPost: post.originalPost,
            isReposted: true,  // Updated
            isLiked: post.isLiked,
            likeCount: post.likeCount,
            repostCount: post.repostCount + 1,  // Updated
            platformSpecificId: post.platformSpecificId,
            boostedBy: post.boostedBy,
            parent: post.parent,
            inReplyToID: post.inReplyToID,
            inReplyToUsername: post.inReplyToUsername,
            quotedPostUri: post.quotedPostUri,
            quotedPostAuthorHandle: post.quotedPostAuthorHandle,
            cid: post.cid,
            blueskyLikeRecordURI: post.blueskyLikeRecordURI,  // Preserve existing like record URI
            blueskyRepostRecordURI: repostRecordURI  // Store the repost record URI
        )
        return updatedPost
    }

    /// Unrepost a post on Bluesky
    func unrepostPost(_ post: Post, account: SocialAccount) async throws -> Post {
        // For boost posts, we need to unrepost the original post, not the wrapper
        let targetPost = post.originalPost ?? post
        let targetUri = targetPost.platformSpecificId

        logger.info("[Bluesky] Attempting to unrepost post: id=\(post.id), targetUri=\(targetUri)")

        guard let repostRecordURI = post.blueskyRepostRecordURI else {
            logger.warning(
                "[Bluesky] No repost record URI found for post \(post.id) - cannot unrepost. This may be a legacy post or one reposted before the record URI tracking was implemented."
            )
            // Still update local state optimistically for better UX
            let updatedPost = Post(
                id: post.id,
                content: post.content,
                authorName: post.authorName,
                authorUsername: post.authorUsername,
                authorProfilePictureURL: post.authorProfilePictureURL,
                createdAt: post.createdAt,
                platform: post.platform,
                originalURL: post.originalURL,
                attachments: post.attachments,
                mentions: post.mentions,
                tags: post.tags,
                originalPost: post.originalPost,
                isReposted: false,  // Updated
                isLiked: post.isLiked,
                likeCount: post.likeCount,
                repostCount: max(0, post.repostCount - 1),  // Updated
                platformSpecificId: post.platformSpecificId,
                boostedBy: post.boostedBy,
                parent: post.parent,
                inReplyToID: post.inReplyToID,
                inReplyToUsername: post.inReplyToUsername,
                quotedPostUri: post.quotedPostUri,
                quotedPostAuthorHandle: post.quotedPostAuthorHandle,
                cid: post.cid,
                blueskyLikeRecordURI: post.blueskyLikeRecordURI,
                blueskyRepostRecordURI: nil  // Clear the repost record URI
            )
            return updatedPost
        }

        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        // Check if token needs refresh
        if account.isTokenExpired, account.refreshToken != nil {
            let (newAccessToken, newRefreshToken) = try await refreshSession(for: account)
            account.saveAccessToken(newAccessToken)
            account.saveRefreshToken(newRefreshToken)
        }

        // Extract the rkey from the repost record URI
        let rkey = String(repostRecordURI.split(separator: "/").last ?? "")
        guard !rkey.isEmpty else {
            logger.error(
                "[Bluesky] Could not extract rkey from repost record URI: \(repostRecordURI)")
            throw NSError(
                domain: "BlueskyService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid repost record URI format"])
        }

        // Safely unwrap and sanitize serverURL
        let rawServerURL = account.serverURL?.absoluteString ?? "bsky.social"
        let sanitizedServerURL = rawServerURL.replacingOccurrences(of: "https://", with: "")
        let urlString = "https://\(sanitizedServerURL)/xrpc/com.atproto.repo.deleteRecord"

        guard let url = URL(string: urlString) else {
            logger.error("Malformed Bluesky unrepostPost URL: \(urlString)")
            throw NSError(
                domain: "BlueskyService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Malformed Bluesky unrepostPost URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let parameters: [String: Any] = [
            "repo": account.platformSpecificId,  // Use DID instead of stable ID
            "collection": "app.bsky.feed.repost",
            "rkey": rkey,
        ]

        logger.info("[Bluesky] unrepostPost parameters: \(parameters)")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            logger.info("[Bluesky] unrepostPost response status: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                if let responseBody = String(data: data, encoding: .utf8) {
                    logger.error("[Bluesky] unrepostPost error response: \(responseBody)")
                }
            }
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to unrepost"])
        }

        logger.info("[Bluesky] Successfully unreposted post with record URI: \(repostRecordURI)")

        // Create a copy to avoid mutating the original Post object and causing AttributeGraph cycles
        let updatedPost = Post(
            id: post.id,
            content: post.content,
            authorName: post.authorName,
            authorUsername: post.authorUsername,
            authorProfilePictureURL: post.authorProfilePictureURL,
            createdAt: post.createdAt,
            platform: post.platform,
            originalURL: post.originalURL,
            attachments: post.attachments,
            mentions: post.mentions,
            tags: post.tags,
            originalPost: post.originalPost,
            isReposted: false,  // Updated
            isLiked: post.isLiked,
            likeCount: post.likeCount,
            repostCount: max(0, post.repostCount - 1),  // Updated
            platformSpecificId: post.platformSpecificId,
            boostedBy: post.boostedBy,
            parent: post.parent,
            inReplyToID: post.inReplyToID,
            inReplyToUsername: post.inReplyToUsername,
            quotedPostUri: post.quotedPostUri,
            quotedPostAuthorHandle: post.quotedPostAuthorHandle,
            cid: post.cid,
            blueskyLikeRecordURI: post.blueskyLikeRecordURI,  // Preserve existing like record URI
            blueskyRepostRecordURI: nil  // Clear the repost record URI
        )
        return updatedPost
    }

    /// Reply to a post on Bluesky
    func replyToPost(_ post: Post, content: String, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        // Check if token needs refresh
        if account.isTokenExpired {
            _ = try await refreshSession(for: account)
        }
        let url = URL(
            string:
                "https://\(account.serverURL?.absoluteString ?? "bsky.social")/xrpc/com.atproto.repo.createRecord"
        )!
        let record: [String: Any] = [
            "$type": "app.bsky.feed.post",
            "text": content,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "reply": [
                "root": [
                    "uri": post.platformSpecificId,
                    "cid": post.cid ?? post.platformSpecificId.components(separatedBy: "/").last
                        ?? "",
                ],
                "parent": [
                    "uri": post.platformSpecificId,
                    "cid": post.cid ?? post.platformSpecificId.components(separatedBy: "/").last
                        ?? "",
                ],
            ],
        ]
        let parameters: [String: Any] = [
            "repo": account.platformSpecificId,  // Use DID instead of stable ID
            "collection": "app.bsky.feed.post",
            "record": record,
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to reply to post"])
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let uri = json["uri"] as? String
        else {
            throw NSError(
                domain: "BlueskyService", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse post URI"])
        }
        // Fetch the created reply to return it
        return try await getPost(uri: uri, account: account)
    }
}

extension URL {
    fileprivate func asURLString() -> String {
        return self.absoluteString
    }
}

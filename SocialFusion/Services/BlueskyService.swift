import Foundation
import SwiftUI
import os.log

// Import TokenError for token management

/// Using TokenError from TokenManager
enum TokenError: Error, Equatable {
    case noAccessToken
    case noRefreshToken
    case invalidRefreshToken
    case noClientCredentials
    case invalidServerURL
    case networkError(Error)
    case refreshFailed

    static func == (lhs: TokenError, rhs: TokenError) -> Bool {
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

/// Represents a service for interacting with the Bluesky social platform
public class BlueskyService {
    private let session = URLSession.shared

    // MARK: - Authentication

    /// Authenticate with Bluesky using app password
    public func authenticate(server: URL?, username: String, password: String) async throws
        -> SocialAccount
    {
        // Get server URL string, removing https:// if already present
        var serverURLString = server?.absoluteString ?? "bsky.social"
        if serverURLString.hasPrefix("https://") {
            serverURLString = String(serverURLString.dropFirst(8))
        }

        let serverURL = URL(
            string: "https://\(serverURLString)/xrpc/com.atproto.server.createSession")!

        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let parameters: [String: Any] = [
            "identifier": username,
            "password": password,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await session.data(for: request)
        // data is needed for error handling if the response status code isn't 200

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // Handle error response
            if let errorJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let error = errorJSON["error"] as? String,
                let message = errorJSON["message"] as? String
            {
                throw NSError(
                    domain: "BlueskyService",
                    code: (response as? HTTPURLResponse)?.statusCode ?? 400,
                    userInfo: [NSLocalizedDescriptionKey: "\(error): \(message)"])
            }
            throw NSError(
                domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 400,
                userInfo: [NSLocalizedDescriptionKey: "Failed to authenticate with Bluesky"])
        }

        // Decode the authentication response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessJwt = json["accessJwt"] as? String,
            let refreshJwt = json["refreshJwt"] as? String,
            let did = json["did"] as? String,
            let handle = json["handle"] as? String
        else {
            throw NSError(
                domain: "BlueskyService", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid authentication response format"])
        }

        // Extract display name from handle
        let displayName = handle.components(separatedBy: ".").first ?? handle

        print("✅ Successfully authenticated Bluesky account: \(handle)")
        print("✅ Access token: \(accessJwt.prefix(10))...")
        print("✅ Refresh token: \(refreshJwt.prefix(10))...")

        // Create the account
        let account = SocialAccount(
            id: did,
            username: handle,
            displayName: displayName,
            serverURL: serverURLString,
            platform: .bluesky,
            accessToken: accessJwt,
            refreshToken: refreshJwt,
            expirationDate: Date().addingTimeInterval(2 * 60 * 60),  // 2 hours
            clientId: nil,
            clientSecret: nil,
            accountDetails: nil,
            profileImageURL: nil,
            platformSpecificId: did
        )

        // Verify tokens were set properly
        if let storedAccessToken = account.getAccessToken() {
            print("✅ Verified access token was stored: \(storedAccessToken.prefix(10))...")
        } else {
            print("❌ Failed to store access token!")
        }

        if let storedRefreshToken = account.getRefreshToken() {
            print("✅ Verified refresh token was stored: \(storedRefreshToken.prefix(10))...")
        } else {
            print("❌ Failed to store refresh token!")
        }

        // Update profile information
        await updateProfileInfo(for: account)

        return account
    }

    /// Refresh an expired access token
    public func refreshSession(for account: SocialAccount) async throws -> (
        accessToken: String, refreshToken: String
    ) {
        guard let refreshToken = account.getRefreshToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No refresh token available"])
        }

        var serverURLString = account.serverURL?.absoluteString ?? "bsky.social"
        if serverURLString.hasPrefix("https://") {
            serverURLString = String(serverURLString.dropFirst(8))
        }

        let refreshURL = URL(
            string: "https://\(serverURLString)/xrpc/com.atproto.server.refreshSession")!

        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(refreshToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        // data is needed for error handling if the response status code isn't 200

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // Log the raw error response body
            var responseBodyString: String? = nil
            if let responseBody = String(data: data, encoding: .utf8) {
                responseBodyString = responseBody
                print("❌ Bluesky refresh failed. Response Body: \(responseBody)")
            } else {
                print("❌ Bluesky refresh failed. Unable to decode response body.")
            }

            // If the response body is empty or doesn't contain a specific error message,
            // assume the refresh token is invalid.
            if responseBodyString?.isEmpty ?? true {
                if let errorJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    errorJSON["error"] as? String != nil,
                    errorJSON["message"] as? String != nil
                {
                    // Fallthrough to handle specific error below if parsing succeeds
                } else {
                    print(
                        "❌ Bluesky refresh failed with empty/unparsable body, assuming invalid refresh token."
                    )
                    throw TokenError.invalidRefreshToken
                }
            }

            // Handle specific error response if parsable
            if let errorJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let error = errorJSON["error"] as? String,
                let message = errorJSON["message"] as? String
            {
                throw NSError(
                    domain: "BlueskyService",
                    code: (response as? HTTPURLResponse)?.statusCode ?? 400,
                    userInfo: [NSLocalizedDescriptionKey: "\(error): \(message)"])
            }
            throw NSError(
                domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 400,
                userInfo: [NSLocalizedDescriptionKey: "Failed to refresh Bluesky session"])
        }

        // Decode the refresh response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessJwt = json["accessJwt"] as? String,
            let refreshJwt = json["refreshJwt"] as? String
        else {
            throw NSError(
                domain: "BlueskyService", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid refresh response format"])
        }

        // Update account tokens
        account.saveAccessToken(accessJwt)
        account.saveRefreshToken(refreshJwt)
        account.saveTokenExpirationDate(Date().addingTimeInterval(2 * 60 * 60))  // 2 hours

        return (accessJwt, refreshJwt)
    }

    /// Update the profile information for a Bluesky account
    private func updateProfileInfo(for account: SocialAccount) async {
        do {
            var serverURL = account.serverURL?.absoluteString ?? "bsky.social"
            if serverURL.hasPrefix("https://") {
                serverURL = String(serverURL.dropFirst(8))
            }

            let profileURL = URL(
                string:
                    "https://\(serverURL)/xrpc/app.bsky.actor.getProfile?actor=\(account.username)"
            )!

            var request = URLRequest(url: profileURL)
            guard let accessToken = account.getAccessToken() else {
                print("No access token available for profile update")
                return
            }

            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            // data is needed for error handling if the response status code isn't 200

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200
            else {
                print(
                    "Failed to fetch profile, status code: \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                )
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("Failed to parse profile JSON")
                return
            }

            // Update display name if available
            if let displayName = json["displayName"] as? String {
                DispatchQueue.main.async {
                    account.displayName = displayName
                }
            }

            // Update profile image if available
            if let avatar = json["avatar"] as? String, let avatarURL = URL(string: avatar) {
                DispatchQueue.main.async {
                    account.profileImageURL = avatarURL

                    // Notify observers of profile image update
                    NotificationCenter.default.post(
                        name: .profileImageUpdated,
                        object: nil,
                        userInfo: ["accountId": account.id, "profileImageURL": avatarURL]
                    )
                }
            }
        } catch {
            print("Error updating profile: \(error)")
        }
    }

    // MARK: - Timeline Methods

    /// Fetch the home timeline for a Bluesky account
    func fetchHomeTimeline(for account: SocialAccount) async throws -> [Post] {
        // Validate input account and get access token
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available for this account"])
        }

        // Check if token needs refresh before proceeding
        if let expirationDate = account.tokenExpirationDate, expirationDate <= Date() {
            print("🔄 Bluesky token expired, attempting to refresh...")
            do {
                let (newAccessToken, _) = try await refreshSession(for: account)
                print("✅ Bluesky token refreshed successfully")
                print("✅ New access token: \(newAccessToken.prefix(10))...")
            } catch {
                print("❌ Failed to refresh Bluesky token: \(error.localizedDescription)")
                throw NSError(
                    domain: "BlueskyService", code: 401,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Failed to refresh token: \(error.localizedDescription)"
                    ])
            }
        }

        var serverURL = account.serverURL?.absoluteString ?? "bsky.social"
        if serverURL.hasPrefix("https://") {
            serverURL = String(serverURL.dropFirst(8))
        }

        let timelineURL = URL(
            string: "https://\(serverURL)/xrpc/app.bsky.feed.getTimeline?limit=50")!

        print("🔍 Fetching Bluesky timeline from URL: \(timelineURL.absoluteString)")
        print("🔍 Using access token: \(accessToken.prefix(5))...")

        var request = URLRequest(url: timelineURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        // Make the request with no automatic retries to better handle rate limits
        do {
            let (data, response) = try await session.data(for: request)

            // Get HTTP response for status code checking
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(
                    domain: "BlueskyService", code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
            }

            // Check for rate limiting
            if httpResponse.statusCode == 429 {
                // Extract headers and rate limit information
                var headerDict: [String: Any] = [:]

                // Extract all header fields
                if let headerFields = httpResponse.allHeaderFields as? [String: Any] {
                    headerDict = headerFields
                }

                // Try to get the retry-after header
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60"
                print("⛔️ Rate limit hit! Retry-After: \(retryAfter) seconds")

                // Create a detailed error with header information
                throw NSError(
                    domain: "BlueskyService", code: 429,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Rate limit exceeded, please try again later",
                        "Response-Headers": headerDict,
                        "Retry-After": retryAfter,
                    ])
            }

            // Check for other error status codes
            guard httpResponse.statusCode == 200 else {
                print("📊 Bluesky timeline failed with status code: \(httpResponse.statusCode)")

                // Try to parse the error response
                if let errorJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let error = errorJSON["error"] as? String,
                    let message = errorJSON["message"] as? String
                {
                    throw NSError(
                        domain: "BlueskyService", code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "\(error): \(message)"])
                }

                // Generic error if we can't parse the specific error
                throw NSError(
                    domain: "BlueskyService", code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to fetch timeline"])
            }

            // Parse successful response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let feed = json["feed"] as? [[String: Any]]
            else {
                throw NSError(
                    domain: "BlueskyService", code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid timeline response format"])
            }

            // Convert feed items to Post model
            var posts: [Post] = []

            for (index, item) in feed.enumerated() {
                do {
                    let post = try convertFeedItemToPost(item)
                    posts.append(post)
                } catch {
                    print(
                        "⚠️ Failed to convert Bluesky feed item #\(index): \(error.localizedDescription)"
                    )
                }
            }

            print("✅ Successfully converted \(posts.count) Bluesky posts")
            return posts
        } catch let error as NSError
            where error.domain == "NSURLErrorDomain" && error.code == NSURLErrorCancelled
        {
            print("❌ Request was cancelled")
            throw error
        } catch {
            // Pass through the error with additional context
            print("❌ Error fetching Bluesky timeline: \(error.localizedDescription)")

            // If it's already our custom error with headers, pass it through
            if (error as NSError).domain == "BlueskyService" {
                throw error
            }

            // Otherwise, wrap it in a more descriptive error
            throw NSError(
                domain: "BlueskyService", code: (error as NSError).code,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to fetch timeline: \(error.localizedDescription)",
                    NSUnderlyingErrorKey: error,
                ])
        }
    }

    /// Creates a post using the provided content and account
    /// - Parameters:
    ///   - content: The text content of the post
    ///   - account: The account from which to post
    ///   - image: Optional image to attach to the post
    /// - Returns: The created Post object
    func createPost(content: String, account: SocialAccount, image: UIImage? = nil) async throws
        -> Post
    {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        let serverURL = account.serverURL?.absoluteString ?? "bsky.social"
        let createPostURL = URL(
            string: "https://\(serverURL)/xrpc/com.atproto.repo.createRecord")!

        var request = URLRequest(url: createPostURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Prepare post data
        var record: [String: Any] = [
            "$type": "app.bsky.feed.post",
            "text": content,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]

        // If image is provided, upload it first
        if let image = image {
            if let imageRef = try? await uploadImage(image, account: account) {
                record["embed"] = [
                    "$type": "app.bsky.embed.images",
                    "images": [
                        [
                            "alt": "Attached image",
                            "image": imageRef,
                        ]
                    ],
                ]
            }
        }

        let parameters: [String: Any] = [
            "repo": account.id,
            "collection": "app.bsky.feed.post",
            "record": record,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await session.data(for: request)
        // data is needed for error handling if the response status code isn't 200

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(
                domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create post"])
        }

        // Parse the response to get post URI and CID
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let uri = json["uri"] as? String
        else {
            throw NSError(
                domain: "BlueskyService", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid post creation response"])
        }

        // Create a Post object with the created post data
        let authorName = account.displayName ?? account.username
        let profilePictureURL = account.profileImageURL?.absoluteString ?? ""

        let post = Post(
            id: UUID().uuidString,
            content: content,
            authorName: authorName,
            authorUsername: account.username,
            authorProfilePictureURL: profilePictureURL,
            createdAt: Date(),
            platform: .bluesky,
            originalURL:
                "https://bsky.app/profile/\(account.username)/post/\(uri.components(separatedBy: "/").last ?? "")",
            attachments: image != nil
                ? [Post.Attachment(url: "image_url", type: .image, altText: "Attached image")] : [],
            mentions: [],
            tags: [],
            isReposted: false,
            isLiked: false
        )

        return post
    }

    /// Uploads an image to Bluesky
    private func uploadImage(_ image: UIImage, account: SocialAccount) async throws -> [String: Any]
    {
        guard let accessToken = account.getAccessToken(),
            let imageData = image.jpegData(compressionQuality: 0.8)
        else {
            throw NSError(
                domain: "BlueskyService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Failed to prepare image for upload"])
        }

        let serverURL = account.serverURL?.absoluteString ?? "bsky.social"
        let uploadURL = URL(string: "https://\(serverURL)/xrpc/com.atproto.repo.uploadBlob")!

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData

        let (data, response) = try await session.data(for: request)
        // data is needed for error handling if the response status code isn't 200

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(
                domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to upload image"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let blob = json["blob"] as? [String: Any]
        else {
            throw NSError(
                domain: "BlueskyService", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid blob upload response"])
        }

        return [
            "$type": "blob",
            "ref": blob["ref"] ?? [:],
            "mimeType": blob["mimeType"] as? String ?? "image/jpeg",
            "size": blob["size"] as? Int ?? 0,
        ]
    }

    /// Likes a post
    /// - Parameters:
    ///   - post: The post to like
    ///   - account: The account performing the like action
    /// - Returns: The liked post with updated state
    func likePost(_ post: Post, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        let serverURL = account.serverURL?.absoluteString ?? "bsky.social"
        let likeURL = URL(string: "https://\(serverURL)/xrpc/com.atproto.repo.createRecord")!

        var request = URLRequest(url: likeURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Extract the post URI and CID from original URL
        let postPath = post.originalURL.components(separatedBy: "post/").last ?? ""
        let postUri = "at://\(account.id)/app.bsky.feed.post/\(postPath)"

        let parameters: [String: Any] = [
            "repo": account.id,
            "collection": "app.bsky.feed.like",
            "record": [
                "$type": "app.bsky.feed.like",
                "subject": [
                    "uri": postUri,
                    "cid": postPath,
                ],
                "createdAt": ISO8601DateFormatter().string(from: Date()),
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await session.data(for: request)
        // data is needed for error handling if the response status code isn't 200

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(
                domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to like post"])
        }

        // Return updated post (in real implementation, would fetch the updated post)
        return post
    }

    /// Reposts a post
    /// - Parameters:
    ///   - post: The post to repost
    ///   - account: The account performing the repost action
    /// - Returns: The reposted post with updated state
    func repostPost(_ post: Post, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        let serverURL = account.serverURL?.absoluteString ?? "bsky.social"
        let repostURL = URL(string: "https://\(serverURL)/xrpc/com.atproto.repo.createRecord")!

        var request = URLRequest(url: repostURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Extract the post URI and CID from original URL
        let postPath = post.originalURL.components(separatedBy: "post/").last ?? ""
        let postUri = "at://\(account.id)/app.bsky.feed.post/\(postPath)"

        let parameters: [String: Any] = [
            "repo": account.id,
            "collection": "app.bsky.feed.repost",
            "record": [
                "$type": "app.bsky.feed.repost",
                "subject": [
                    "uri": postUri,
                    "cid": postPath,
                ],
                "createdAt": ISO8601DateFormatter().string(from: Date()),
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await session.data(for: request)
        // data is needed for error handling if the response status code isn't 200

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(
                domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to repost"])
        }

        // Return updated post (in real implementation, would fetch the updated post)
        return post
    }

    /// Replies to a post
    /// - Parameters:
    ///   - post: The post to reply to
    ///   - content: The content of the reply
    ///   - account: The account creating the reply
    /// - Returns: The created reply Post
    func replyToPost(_ post: Post, content: String, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        var serverURL = account.serverURL?.absoluteString ?? "bsky.social"
        if serverURL.hasPrefix("https://") {
            serverURL = String(serverURL.dropFirst(8))
        }

        let replyURL = URL(string: "https://\(serverURL)/xrpc/com.atproto.repo.createRecord")!

        var request = URLRequest(url: replyURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Extract the post URI and CID from original URL
        let postPath = post.originalURL.components(separatedBy: "post/").last ?? ""
        let postUri = "at://\(account.id)/app.bsky.feed.post/\(postPath)"

        let parameters: [String: Any] = [
            "repo": account.id,
            "collection": "app.bsky.feed.post",
            "record": [
                "$type": "app.bsky.feed.post",
                "text": content,
                "reply": [
                    "root": [
                        "uri": postUri,
                        "cid": postPath,
                    ],
                    "parent": [
                        "uri": postUri,
                        "cid": postPath,
                    ],
                ],
                "createdAt": ISO8601DateFormatter().string(from: Date()),
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await session.data(for: request)
        // data is needed for error handling if the response status code isn't 200

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(
                domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to reply to post"])
        }

        // Create a Post object with the reply data
        let authorName = account.displayName ?? account.username
        let profilePictureURL = account.profileImageURL?.absoluteString ?? ""

        let replyPost = Post(
            id: UUID().uuidString,
            content: content,
            authorName: authorName,
            authorUsername: account.username,
            authorProfilePictureURL: profilePictureURL,
            createdAt: Date(),
            platform: .bluesky,
            originalURL:
                "https://bsky.app/profile/\(account.username)/post/\(UUID().uuidString.prefix(8))",
            attachments: [],
            mentions: [post.authorUsername],
            tags: [],
            isReposted: false,
            isLiked: false
        )

        return replyPost
    }

    /// Fetches trending posts
    /// - Returns: An array of trending posts
    func fetchTrendingPosts() async throws -> [Post] {
        // For Bluesky, fetch popular feed if no specific account is provided
        let popularURL = URL(string: "https://bsky.social/xrpc/app.bsky.feed.getPopular")!

        let request = URLRequest(url: popularURL)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print(
                "❌ Failed to fetch trending posts, status code: \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            )
            if let responseText = String(data: data, encoding: .utf8) {
                print("Error response: \(responseText)")
            }
            throw NSError(
                domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch trending posts"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let feedItems = json["feed"] as? [[String: Any]]
        else {
            throw NSError(
                domain: "BlueskyService", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid trending feed response format"])
        }

        // Convert feed items to posts
        var posts: [Post] = []

        for item in feedItems {
            if let post = try? convertFeedItemToPost(item) {
                posts.append(post)
            }
        }

        return posts
    }

    /// Fetches trending posts with a specific account
    /// - Parameter account: The account to use for fetching
    /// - Returns: An array of trending posts
    func fetchTrendingPosts(account: SocialAccount) async throws -> [Post] {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        var serverURL = account.serverURL?.absoluteString ?? "bsky.social"
        if serverURL.hasPrefix("https://") {
            serverURL = String(serverURL.dropFirst(8))
        }

        let popularURL = URL(string: "https://\(serverURL)/xrpc/app.bsky.feed.getPopular")!

        var request = URLRequest(url: popularURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(
                domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch trending posts"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let feedItems = json["feed"] as? [[String: Any]]
        else {
            throw NSError(
                domain: "BlueskyService", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid trending feed response format"])
        }

        // Convert feed items to posts
        var posts: [Post] = []

        for item in feedItems {
            if let post = try? convertFeedItemToPost(item) {
                posts.append(post)
            }
        }

        return posts
    }

    // MARK: - Helper methods

    /// Convert a Bluesky feed item to a Post
    private func convertFeedItemToPost(_ feedItem: [String: Any]) throws -> Post {
        guard let post = feedItem["post"] as? [String: Any],
            let uri = post["uri"] as? String,
            let author = post["author"] as? [String: Any],
            let record = post["record"] as? [String: Any],
            let text = record["text"] as? String,
            let createdAt = record["createdAt"] as? String,
            let handle = author["handle"] as? String
        else {
            throw NSError(
                domain: "BlueskyService", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid post format in feed"])
        }

        let displayName = author["displayName"] as? String ?? handle
        let avatarURL = author["avatar"] as? String ?? ""

        // Process attachments if present
        var attachments: [Post.Attachment] = []
        if let embed = post["embed"] as? [String: Any] {
            if let embedImages = embed["images"] as? [[String: Any]] {
                for (_, image) in embedImages.enumerated() {
                    if let imageRef = image["image"] as? [String: Any],
                        let refLink = (imageRef["ref"] as? [String: Any])?["$link"] as? String
                    {
                        let attachment = Post.Attachment(
                            url: "https://cdn.bsky.app/img/feed_fullsize/\(refLink)",
                            type: .image,
                            altText: image["alt"] as? String
                        )
                        attachments.append(attachment)
                    }
                }
            }

            if let external = embed["external"] as? [String: Any],
                external["uri"] as? String != nil,
                let thumb = external["thumb"] as? [String: Any],
                let thumbRefLink = (thumb["ref"] as? [String: Any])?["$link"] as? String
            {
                let attachment = Post.Attachment(
                    url: "https://cdn.bsky.app/img/feed_thumbnail/\(thumbRefLink)",
                    type: .image,
                    altText: external["title"] as? String ?? "External link"
                )
                attachments.append(attachment)
            }
        }

        // Extract counts
        let likeCount = post["likeCount"] as? Int ?? 0
        let repostCount = post["repostCount"] as? Int ?? 0
        let _ = post["replyCount"] as? Int ?? 0

        // Check if this is a repost
        let isReposted = (post["viewer"] as? [String: Any])?["repostUri"] != nil

        // Check if this post is a repost/boost
        if let reason = feedItem["reason"] as? [String: Any],
            let reasonType = reason["$type"] as? String,
            reasonType == "app.bsky.feed.defs#reasonRepost"
        {

            // This is a repost - create an originalPost and a wrapper post
            // Extract the reposter's information
            guard let by = reason["by"] as? [String: Any],
                let repostHandle = by["handle"] as? String,
                let indexedAt = reason["indexedAt"] as? String
            else {
                throw NSError(
                    domain: "BlueskyService", code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid repost data in feed"])
            }

            let repostDisplayName = by["displayName"] as? String ?? repostHandle
            let repostAvatarURL = by["avatar"] as? String ?? ""

            // Create the original post (the one that was boosted)
            let originalPost = Post(
                id: UUID().uuidString,
                content: text,
                authorName: displayName,
                authorUsername: handle,
                authorProfilePictureURL: avatarURL,
                createdAt: ISO8601DateFormatter().date(from: createdAt) ?? Date(),
                platform: .bluesky,
                originalURL:
                    "https://bsky.app/profile/\(handle)/post/\(uri.components(separatedBy: "/").last ?? "")",
                attachments: attachments,
                mentions: [],
                tags: [],
                isReposted: true,
                isLiked: (post["viewer"] as? [String: Any])?["likeUri"] != nil,
                likeCount: likeCount,
                repostCount: repostCount
            )

            // Create the wrapper repost
            return Post(
                id: UUID().uuidString,
                content: "",  // Repost doesn't have its own content
                authorName: repostDisplayName,
                authorUsername: repostHandle,
                authorProfilePictureURL: repostAvatarURL,
                createdAt: ISO8601DateFormatter().date(from: indexedAt) ?? Date(),
                platform: .bluesky,
                originalURL:
                    "https://bsky.app/profile/\(repostHandle)/post/repost/\(uri.components(separatedBy: "/").last ?? "")",
                attachments: [],
                mentions: [],
                tags: [],
                originalPost: originalPost,
                isReposted: true,
                isLiked: (post["viewer"] as? [String: Any])?["likeUri"] != nil,
                likeCount: likeCount,
                repostCount: repostCount
            )
        }

        // Create the post object (regular, non-reposted post)
        return Post(
            id: UUID().uuidString,
            content: text,
            authorName: displayName,
            authorUsername: handle,
            authorProfilePictureURL: avatarURL,
            createdAt: ISO8601DateFormatter().date(from: createdAt) ?? Date(),
            platform: .bluesky,
            originalURL:
                "https://bsky.app/profile/\(handle)/post/\(uri.components(separatedBy: "/").last ?? "")",
            attachments: attachments,
            mentions: [],  // Would need further processing to extract mentions
            tags: [],  // Would need further processing to extract tags
            isReposted: isReposted,
            isLiked: (post["viewer"] as? [String: Any])?["likeUri"] != nil,
            likeCount: likeCount,
            repostCount: repostCount
        )
    }
}

extension URL {
    fileprivate func asURLString() -> String {
        return self.absoluteString
    }
}

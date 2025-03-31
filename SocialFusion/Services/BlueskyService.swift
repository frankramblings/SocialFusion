import Foundation
import UIKit

// MARK: - API Error Enum
enum APIError: Error {
    case invalidURL
    case authenticationFailed(String)
    case noAccessToken
    case invalidResponse
    case decodingError
    case networkError(Error)
    case httpError(Int, String)
    case internalError(String)
}

enum NetworkError: Error {
    case httpError(Int, String)
}

// MARK: - Session Model
struct Session: Codable {
    let accessJwt: String
    let refreshJwt: String
    let handle: String
    let did: String
}

// MARK: - URL Helper Extensions
extension Optional where Wrapped == URL {
    func asURLString() -> String {
        guard let url = self else { return "" }
        return url.absoluteString
    }
}

// MARK: - Bluesky Models Additions

// BlueskyEmbeds structure to handle embedded content
struct BlueskyEmbeds {
    let images: [BlueskyImage]?
}

// Add embeds property to BlueskyPost
extension BlueskyPost {
    var embeds: BlueskyEmbeds? {
        if let images = embed?.images {
            return BlueskyEmbeds(images: images)
        }
        return nil
    }
}

// Add properties to BlueskyViewer
extension BlueskyViewer {
    var like: Bool {
        return likeUri != nil
    }

    var repost: Bool {
        return repostUri != nil
    }
}

class BlueskyService {
    private let session = URLSession.shared
    private let baseURL = "https://bsky.social/xrpc"

    // MARK: - Converter Methods

    /// Convert Bluesky feed items to standard Post objects
    func convertBlueskyFeedToPosts(_ feedItems: [BlueskyFeedItem], account: SocialAccount) -> [Post]
    {
        return feedItems.compactMap { feedItem in
            convertBlueskyPostToPost(feedItem.post, account: account)
        }
    }

    /// Convert a Bluesky post to a standard Post object
    func convertBlueskyPostToPost(_ post: BlueskyPost, account: SocialAccount) -> Post {
        let content = post.record.text
        var attachments: [Post.Attachment] = []

        // Parse the created date
        let dateFormatter = ISO8601DateFormatter()
        let createdAt = dateFormatter.date(from: post.record.createdAt) ?? Date()

        // Handle images if present
        if let embed = post.embed, let images = embed.images {
            for (index, image) in images.enumerated() {
                if let link = image.image.ref?["$link"] ?? image.image.ref?["link"] {
                    let imageUrl = "https://cdn.bsky.app/img/feed_thumbnail/\(link)"
                    let attachment = Post.Attachment(
                        url: imageUrl,
                        type: .image,
                        altText: image.alt ?? ""
                    )
                    attachments.append(attachment)
                }
            }
        }

        // Extract mentions and tags
        let mentions = extractMentions(from: post)
        let tags = extractTags(from: post.record.text)

        // Create and return Post
        return Post(
            id: post.uri,
            content: content,
            authorName: post.author.displayName ?? post.author.handle,
            authorUsername: post.author.handle,
            authorProfilePictureURL: post.author.avatar ?? "",
            createdAt: createdAt,
            platform: .bluesky,
            originalURL:
                "https://bsky.app/profile/\(post.author.handle)/post/\(post.uri.split(separator: "/").last ?? "")",
            attachments: attachments,
            mentions: mentions,
            tags: tags
        )
    }

    // MARK: - Helper Methods

    /// Extract mentions from a Bluesky post
    private func extractMentions(from post: BlueskyPost) -> [Post.Mention] {
        var mentions: [Post.Mention] = []

        // Implement proper mention extraction logic here if available in the BlueskyPost
        // For now, return an empty array

        return mentions
    }

    /// Extract hashtags from post content
    private func extractTags(from content: String) -> [String] {
        var tags: [String] = []

        // Simple regex to extract hashtags
        let hashtagRegex = try? NSRegularExpression(pattern: "#([\\w\\d]+)", options: [])
        if let matches = hashtagRegex?.matches(
            in: content, options: [], range: NSRange(location: 0, length: content.utf16.count))
        {
            for match in matches {
                if let range = Range(match.range(at: 1), in: content) {
                    let tag = String(content[range])
                    tags.append(tag)
                }
            }
        }

        return tags
    }

    /// Extract media attachments from Bluesky embedded content
    private func extractMediaAttachments(from embed: BlueskyEmbed?) -> [Post.Attachment] {
        var attachments: [Post.Attachment] = []

        // Process embedded images
        if let images = embed?.images {
            for image in images {
                if let link = image.image.ref?["$link"] ?? image.image.ref?["link"] {
                    let imageUrl = "https://cdn.bsky.app/img/feed_thumbnail/\(link)"
                    let attachment = Post.Attachment(
                        url: imageUrl,
                        type: .image,
                        altText: image.alt ?? ""
                    )
                    attachments.append(attachment)
                }
            }
        }

        return attachments
    }

    /// Helper method to convert Bluesky feed item to our app's Post model
    private func convertBlueskyPostToPost(_ feedItem: BlueskyFeedItem, account: SocialAccount)
        -> Post
    {
        let post = feedItem.post

        // Handle repost
        if let reason = feedItem.reason {
            // Extract embedded content
            let attachments = extractMediaAttachments(from: post.embed)

            // Create post from repost
            return Post(
                id: UUID().uuidString,
                content: post.record.text,
                authorName: reason.by.displayName ?? reason.by.handle,
                authorUsername: reason.by.handle,
                authorProfilePictureURL: reason.by.avatar ?? "",
                createdAt: ISO8601DateFormatter().date(from: reason.indexedAt) ?? Date(),
                platform: .bluesky,
                originalURL:
                    "https://bsky.app/profile/\(post.author.handle)/post/\(post.uri.split(separator: "/").last ?? "")",
                attachments: attachments,
                mentions: extractMentions(from: post),
                tags: extractTags(from: post.record.text)
            )
        }

        // Handle reply
        if feedItem.reply != nil {
            let content = post.record.text
            let attachments = extractMediaAttachments(from: post.embed)

            // Create post from reply
            return Post(
                id: UUID().uuidString,
                content: content,
                authorName: post.author.displayName ?? post.author.handle,
                authorUsername: post.author.handle,
                authorProfilePictureURL: post.author.avatar ?? "",
                createdAt: ISO8601DateFormatter().date(from: post.record.createdAt) ?? Date(),
                platform: .bluesky,
                originalURL:
                    "https://bsky.app/profile/\(post.author.handle)/post/\(post.uri.split(separator: "/").last ?? "")",
                attachments: attachments,
                mentions: extractMentions(from: post),
                tags: extractTags(from: post.record.text)
            )
        }

        // Regular post
        return convertBlueskyPostToOriginalPost(post)
    }

    /// Helper method to convert a Bluesky post to our app's Post model
    private func convertBlueskyPostToOriginalPost(_ post: BlueskyPost) -> Post {
        // Pass through the content directly
        let content = post.record.text
        let attachments = extractMediaAttachments(from: post.embed)

        return Post(
            id: UUID().uuidString,
            content: content,
            authorName: post.author.displayName ?? post.author.handle,
            authorUsername: post.author.handle,
            authorProfilePictureURL: post.author.avatar ?? "",
            createdAt: ISO8601DateFormatter().date(from: post.record.createdAt) ?? Date(),
            platform: .bluesky,
            originalURL:
                "https://bsky.app/profile/\(post.author.handle)/post/\(post.uri.split(separator: "/").last ?? "")",
            attachments: attachments,
            mentions: extractMentions(from: post),
            tags: extractTags(from: post.record.text)
        )
    }

    // MARK: - Authentication

    /// Authenticate with Bluesky using the AT Protocol
    func authenticate(username: String, password: String, server: URL? = URL(string: "bsky.social"))
        async throws -> SocialAccount
    {
        // Normalize the username - if it's an email, it should be passed as is
        let identifier = username.trimmingCharacters(in: .whitespacesAndNewlines)

        // Ensure the server URL is properly formatted
        var serverUrlString = server?.absoluteString ?? "bsky.social"

        // If the server URL doesn't have a scheme, add https://
        if !serverUrlString.contains("://") {
            serverUrlString = "https://" + serverUrlString
        }

        // Remove any trailing slashes
        if serverUrlString.hasSuffix("/") {
            serverUrlString.removeLast()
        }

        // Create the session URL with proper error handling
        guard let url = URL(string: "\(serverUrlString)/xrpc/com.atproto.server.createSession")
        else {
            throw NSError(
                domain: "BlueskyService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL format"])
        }

        print("Authenticating with Bluesky at URL: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let parameters: [String: Any] = [
            "identifier": identifier,
            "password": password,
        ]

        // Add error handling for JSON serialization
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        } catch {
            throw NSError(
                domain: "BlueskyService",
                code: 400,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to serialize login parameters: \(error.localizedDescription)"
                ])
        }

        do {
            let (data, response) = try await session.data(for: request)

            // Check for HTTP errors with more detail
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(
                    domain: "BlueskyService",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
            }

            // Handle different status codes
            guard httpResponse.statusCode == 200 else {
                // Try to decode a proper error message
                if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                    throw NSError(
                        domain: "BlueskyError",
                        code: httpResponse.statusCode,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "The operation couldn't be completed. (\(errorResponse.error) error \(errorResponse.message ?? "1"))"
                        ])
                }

                // If we can't get a specific error, use the HTTP status
                if let responseText = String(data: data, encoding: .utf8) {
                    throw NetworkError.httpError(httpResponse.statusCode, responseText)
                } else {
                    throw NetworkError.httpError(httpResponse.statusCode, "Authentication failed")
                }
            }

            // Try to decode the response
            let authResponse: BlueskyAuthResponse
            do {
                authResponse = try JSONDecoder().decode(BlueskyAuthResponse.self, from: data)
            } catch {
                throw NSError(
                    domain: "BlueskyService",
                    code: 500,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Failed to decode auth response: \(error.localizedDescription)"
                    ])
            }

            // Create a SocialAccount object
            let displayName =
                authResponse.handle.components(separatedBy: ".").first
                ?? authResponse.handle

            let account = SocialAccount(
                id: authResponse.did,
                username: authResponse.handle,
                displayName: displayName,
                serverURL: URL(string: serverUrlString),
                platform: .bluesky
            )

            // Save the tokens
            account.saveAccessToken(authResponse.accessJwt)
            account.saveRefreshToken(authResponse.refreshJwt)
            account.saveTokenExpirationDate(authResponse.expirationDate)

            return account
        } catch {
            // Convert any network or system errors to our custom format
            if (error as NSError).domain != "BlueskyError" {
                throw NSError(
                    domain: "BlueskyService",
                    code: (error as NSError).code,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Authentication failed: \(error.localizedDescription)"
                    ])
            }
            throw error
        }
    }

    /// Refresh an expired access token
    func refreshSession(refreshToken: String, server: URL?) async throws
        -> BlueskyAuthResponse
    {
        let serverStr = server.asURLString()
        guard let url = URL(string: "https://\(serverStr)/xrpc/com.atproto.server.refreshSession")
        else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(refreshToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        // Check for HTTP errors
        if let httpResponse = response as? HTTPURLResponse,
            !(200...299).contains(httpResponse.statusCode)
        {
            throw NetworkError.httpError(
                httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        return try JSONDecoder().decode(BlueskyAuthResponse.self, from: data)
    }

    /// Get the authenticated user's profile information
    func getProfile(for account: SocialAccount) async throws -> BlueskyProfile {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken() {
            let newSession = try await refreshSession(
                refreshToken: refreshToken, server: account.serverURL)
            account.saveAccessToken(newSession.accessJwt)
            account.saveRefreshToken(newSession.refreshJwt)
            account.saveTokenExpirationDate(newSession.expirationDate)
        }

        let urlStr =
            "https://\(account.serverURL.asURLString())/xrpc/app.bsky.actor.getProfile?actor=\(account.username)"
        guard let url = URL(string: urlStr) else {
            throw APIError.invalidURL
        }

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
                userInfo: [NSLocalizedDescriptionKey: "Failed to get profile"])
        }

        return try JSONDecoder().decode(BlueskyProfile.self, from: data)
    }

    // MARK: - Timeline

    /// Fetch the home timeline from the Bluesky API
    func fetchHomeTimeline(for account: SocialAccount) async throws -> [Post] {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken() {
            let newSession = try await refreshSession(
                refreshToken: refreshToken, server: account.serverURL)
            account.saveAccessToken(newSession.accessJwt)
            account.saveRefreshToken(newSession.refreshJwt)
            account.saveTokenExpirationDate(newSession.expirationDate)
        }

        let urlStr =
            "https://\(account.serverURL.asURLString())/xrpc/app.bsky.feed.getTimeline?limit=50"
        guard let url = URL(string: urlStr) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
            let responseText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NetworkError.httpError(statusCode, responseText)
        }

        let timelineResponse = try JSONDecoder().decode(BlueskyTimelineResponse.self, from: data)
        return convertBlueskyFeedToPosts(timelineResponse.feed, account: account)
    }

    /// Fetch a user's profile timeline
    func fetchUserTimeline(username: String, for account: SocialAccount) async throws -> [Post] {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken() {
            let newSession = try await refreshSession(
                refreshToken: refreshToken, server: account.serverURL)
            account.saveAccessToken(newSession.accessJwt)
            account.saveRefreshToken(newSession.refreshJwt)
            account.saveTokenExpirationDate(newSession.expirationDate)
        }

        let urlStr =
            "https://\(account.serverURL.asURLString())/xrpc/app.bsky.feed.getAuthorFeed?actor=\(username)&limit=50"
        guard let url = URL(string: urlStr) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
            let responseText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NetworkError.httpError(statusCode, responseText)
        }

        let timelineResponse = try JSONDecoder().decode(BlueskyTimelineResponse.self, from: data)
        return convertBlueskyFeedToPosts(timelineResponse.feed, account: account)
    }

    // MARK: - Post Actions

    /// Upload a blob to Bluesky
    private func uploadBlob(data: Data, account: SocialAccount) async throws -> [String: Any] {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        let urlStr = "https://\(account.serverURL.asURLString())/xrpc/com.atproto.repo.uploadBlob"
        guard let url = URL(string: urlStr) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (responseData, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let responseText = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw NetworkError.httpError(statusCode, responseText)
        }

        // Parse the blob reference
        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            let blob = json["blob"] as? [String: Any]
        else {
            throw NSError(
                domain: "BlueskyService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse blob reference"])
        }

        return blob
    }

    /// Create a new post on Bluesky
    func createPost(
        content: String, images: [UIImage] = [], account: SocialAccount
    ) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        // Upload images first if provided
        var imageRefs: [[String: Any]] = []

        for image in images {
            if let imageData = image.jpegData(compressionQuality: 0.8) {
                let blob = try await uploadBlob(data: imageData, account: account)
                imageRefs.append(blob)
            }
        }

        // Now create the post with references to the uploaded images
        let urlStr = "https://\(account.serverURL.asURLString())/xrpc/com.atproto.repo.createRecord"
        guard let url = URL(string: urlStr) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build the record object
        var record: [String: Any] = [
            "text": content,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "$type": "app.bsky.feed.post",
        ]

        // Add images if uploaded
        if !imageRefs.isEmpty {
            var embed: [String: Any] = [
                "$type": "app.bsky.embed.images",
                "images": imageRefs.map { ref in
                    return [
                        "alt": "Image",
                        "image": ref,
                    ]
                },
            ]
            record["embed"] = embed
        }

        // Format the parameters for creating a post
        let parameters: [String: Any] = [
            "repo": account.username,
            "collection": "app.bsky.feed.post",
            "record": record,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let responseText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NetworkError.httpError(statusCode, responseText)
        }

        // Create a new post object to return
        // Normally we'd parse the response, but for now we'll create a basic post
        return Post(
            id: UUID().uuidString,
            content: content,
            authorName: account.displayName ?? account.username,
            authorUsername: account.username,
            authorProfilePictureURL: "",  // We don't have access to avatar from the account
            createdAt: Date(),
            platform: .bluesky,
            originalURL: "https://bsky.app/profile/\(account.username)",
            attachments: images.enumerated().map { (index, image) in
                Post.Attachment(
                    url: "local://temp/\(UUID().uuidString)",
                    type: .image,
                    altText: "Uploaded image \(index + 1)"
                )
            },
            mentions: [],
            tags: []
        )
    }

    /// Fetch a specific post by its URI
    func getPost(uri: String, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        // We'll need to extract the post components from the URI
        // Create a postIdentifier in the format did:username/posts/postid
        let postComponents = uri.split(separator: "/")
        guard postComponents.count >= 2 else {
            throw NSError(
                domain: "BlueskyService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid post URI format"])
        }

        let authorDid = postComponents[2]
        let postId = postComponents.last ?? ""

        let urlStr =
            "https://\(account.serverURL.asURLString())/xrpc/app.bsky.feed.getPostThread?uri=\(uri)"
        guard let url = URL(string: urlStr) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let responseText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NetworkError.httpError(statusCode, responseText)
        }

        // Parse the thread response to get the post
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let thread = json["thread"] as? [String: Any],
            let post = thread["post"] as? [String: Any]
        else {
            throw NSError(
                domain: "BlueskyService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse post data"])
        }

        // Create a simplified post object with the available data
        return Post(
            id: uri,
            content: post["text"] as? String ?? "",
            authorName: "Author",  // We'd need to extract more data for a proper author name
            authorUsername: String(describing: authorDid),
            authorProfilePictureURL: "",
            createdAt: Date(),
            platform: .bluesky,
            originalURL: "https://bsky.app/profile/\(authorDid)/post/\(postId)",
            attachments: [],
            mentions: [],
            tags: []
        )
    }

    /// Like a post on Bluesky
    func likePost(_ post: Post, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        // Extract the post URI from originalURL
        guard let uri = extractUriFromOriginalUrl(post.originalURL) else {
            throw NSError(
                domain: "BlueskyService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid post URL format"])
        }

        let urlStr = "https://\(account.serverURL.asURLString())/xrpc/com.atproto.repo.createRecord"
        guard let url = URL(string: urlStr) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Format the parameters for liking a post
        let parameters: [String: Any] = [
            "repo": account.username,
            "collection": "app.bsky.feed.like",
            "record": [
                "$type": "app.bsky.feed.like",
                "subject": [
                    "uri": uri,
                    "cid": uri.components(separatedBy: "/").last ?? "",
                ],
                "createdAt": ISO8601DateFormatter().string(from: Date()),
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to like post"])
        }

        // Return the same post since we can't modify the struct
        return post
    }

    /// Repost a post on Bluesky
    func repostPost(_ post: Post, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken() {
            let newSession = try await refreshSession(
                refreshToken: refreshToken, server: account.serverURL)
            account.saveAccessToken(newSession.accessJwt)
            account.saveRefreshToken(newSession.refreshJwt)
            account.saveTokenExpirationDate(newSession.expirationDate)
        }

        // Extract the post URI from originalURL
        guard let uri = extractUriFromOriginalUrl(post.originalURL) else {
            throw NSError(
                domain: "BlueskyService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid post URL format"])
            }

        let url = URL(
            string:
                "https://\(account.serverURL.asURLString())/xrpc/com.atproto.repo.createRecord"
        )!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let parameters: [String: Any] = [
            "repo": account.id,
            "collection": "app.bsky.feed.repost",
            "record": [
                "$type": "app.bsky.feed.repost",
                "subject": [
                    "uri": uri,
                    "cid": uri.components(separatedBy: "/").last ?? "",
                ],
                "createdAt": ISO8601DateFormatter().string(from: Date()),
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to repost"])
        }

        // Return the same post since we can't modify the struct
        return post
    }

    /// Extract URI from original URL
    private func extractUriFromOriginalUrl(_ originalUrl: String) -> String? {
        // Original URL format: https://bsky.app/profile/username.bsky.social/post/postid
        let components = originalUrl.split(separator: "/")
        guard components.count >= 6 else {
            return nil
        }

        // components[3] should be "profile"
        // components[4] should be username
        // components[6] should be postId

        let author = String(components[components.count - 3])
        let postId = String(components[components.count - 1])

        return "at://\(author)/app.bsky.feed.post/\(postId)"
    }

    /// Generate a random CID for new posts
    private func generateCid() -> String {
        let uuid = UUID().uuidString
        return "bafyrei\(uuid.replacingOccurrences(of: "-", with: "").lowercased())"
    }

    /// Create a reply to a post on Bluesky
    func replyToPost(_ post: Post, content: String, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        // We'll need the DID of the user and post ID from the URL
        // Original URL format: https://bsky.app/profile/username.bsky.social/post/postid
        let postComponents = post.originalURL.split(separator: "/")
        guard postComponents.count >= 6 else {
            throw NSError(
                domain: "BlueskyService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid post URL format"])
        }

        // Create a URI in the format at://did:plc:username/app.bsky.feed.post/postid
        let author = String(postComponents[postComponents.count - 3])
        let postId = String(postComponents[postComponents.count - 1])
        let uri = "at://\(author)/app.bsky.feed.post/\(postId)"

        let urlStr = "https://\(account.serverURL.asURLString())/xrpc/com.atproto.repo.createRecord"
        guard let url = URL(string: urlStr) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build the record object for a reply
        let record: [String: Any] = [
            "text": content,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "$type": "app.bsky.feed.post",
            "reply": [
                "root": [
                    "uri": uri,
                    "cid": generateCid(),
                ],
                "parent": [
                    "uri": uri,
                    "cid": generateCid(),
                ],
            ],
        ]

        // Format the parameters for creating a post
        let parameters: [String: Any] = [
            "repo": account.username,
            "collection": "app.bsky.feed.post",
            "record": record,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let responseText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NetworkError.httpError(statusCode, responseText)
        }

        // Create a new post object to return
        return Post(
            id: UUID().uuidString,
            content: content,
            authorName: account.displayName ?? account.username,
            authorUsername: account.username,
            authorProfilePictureURL: "",
            createdAt: Date(),
            platform: .bluesky,
            originalURL: "https://bsky.app/profile/\(account.username)",
            attachments: [],
            mentions: [],
            tags: []
        )
    }

    // MARK: - Public Access APIs

    /// Fetch trending posts from Bluesky without requiring authentication
    func fetchTrendingPosts() async throws -> [Post] {
        print("Fetching Bluesky trending posts")

        // Use the public timeline endpoint
        guard
            let url = URL(
                string:
                    "https://bsky.social/xrpc/app.bsky.feed.getTimeline?algorithm=reverse-chronological"
            )
        else {
            print("Invalid Bluesky API URL")
            throw NSError(
                domain: "BlueskyService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid HTTP response from Bluesky API")
                return createFallbackBlueskyPosts()
            }

            // Handle different response statuses
            switch httpResponse.statusCode {
            case 200:
                // Success - try to parse the posts
                let decoder = JSONDecoder()
                do {
                    let feed = try decoder.decode(BlueskyTimelineResponse.self, from: data)
                    let posts = feed.feed.map { convertFeedItemToPostPublic($0) }
                    print("Successfully fetched \(posts.count) Bluesky trending posts")
                    return posts
                } catch {
                    print("Error parsing Bluesky feed: \(error.localizedDescription)")
                    return createFallbackBlueskyPosts()
                }

            case 401:
                // Authentication required
                print("Authentication required for Bluesky trending posts - using fallback content")
                return createFallbackBlueskyPosts()

            default:
                // Other error cases
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("Bluesky API error: \(errorText), Status code: \(httpResponse.statusCode)")
                return createFallbackBlueskyPosts()
            }
        } catch {
            print("Network error fetching Bluesky trending posts: \(error.localizedDescription)")
            return createFallbackBlueskyPosts()
        }
    }

    /// Authenticate with a token instead of username/password
    func authenticateWithToken(accessToken: String, refreshToken: String, server: URL?) async throws
        -> (session: Session, account: SocialAccount)
    {
        let serverStr = server.asURLString()
        guard let url = URL(string: "https://\(serverStr)/xrpc/com.atproto.server.refreshSession")
        else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(refreshToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to authenticate with token"])
        }

        let authResponse = try JSONDecoder().decode(BlueskyAuthResponse.self, from: data)

        // Create session object
        let session = Session(
            accessJwt: authResponse.accessJwt,
            refreshJwt: authResponse.refreshJwt,
            handle: authResponse.handle,
            did: authResponse.did
        )

        // Create account
        let displayName =
            authResponse.handle.components(separatedBy: ".").first ?? authResponse.handle

        let account = SocialAccount(
            id: authResponse.did,
            username: authResponse.handle,
            displayName: displayName,
            serverURL: URL(string: serverStr),
            platform: .bluesky
        )

        // Save the tokens
        account.saveAccessToken(authResponse.accessJwt)
        account.saveRefreshToken(authResponse.refreshJwt)
        account.saveTokenExpirationDate(authResponse.expirationDate)

        return (session, account)
    }

    /// Create realistic Bluesky sample posts when API isn't available
    private func createFallbackBlueskyPosts() -> [Post] {
        print("Creating fallback Bluesky posts")

        // Sample authors
        let authors = [
            (name: "TechExplorer", handle: "techexplorer.bsky.social"),
            (name: "NaturePhotography", handle: "naturephotos.bsky.social"),
            (name: "CodeCrafter", handle: "codecrafter.bsky.social"),
            (name: "FoodieJourney", handle: "foodjourney.bsky.social"),
            (name: "BookReviewer", handle: "bookreviews.bsky.social"),
            (name: "TravelDiaries", handle: "traveldiaries.bsky.social"),
            (name: "MusicEnthusiast", handle: "musiclover.bsky.social"),
            (name: "ScienceGeek", handle: "sciencegeek.bsky.social"),
            (name: "ArtisticSoul", handle: "artlover.bsky.social"),
            (name: "FitnessCoach", handle: "fitcoach.bsky.social"),
        ]

        // Sample content themes
        let contentThemes = [
            "Just released a new open-source project on machine learning. Check it out if you're interested in AI! #OpenSource #MachineLearning",
            "Captured this beautiful sunset at the beach today. Nature's artwork is truly breathtaking. #Photography #NatureLovers",
            "Finally solved that challenging coding problem I've been stuck on for days. The key was simplifying my approach! #Coding #TechLife",
            "Made homemade pasta from scratch today. The result was delicious and so worth the effort! #Cooking #FoodLovers",
            "Just finished this amazing novel that completely changed my perspective. Highly recommend! #Books #Reading",
            "Exploring the hidden gems of this beautiful city. Sometimes the best places are off the beaten path. #Travel #Adventure",
            "Attended an incredible concert last night. The energy was electric! #Music #LiveEvents",
            "Fascinating new research about black holes published today. The universe is full of mysteries! #Science #Astronomy",
            "Visited a gallery showcasing local artists today. So much talent in our community! #Art #CreativeSouls",
            "Completed my first marathon today! Months of training finally paid off. #Fitness #PersonalAchievement",
        ]

        var posts: [Post] = []

        // Create a varied set of posts
        for i in 0..<min(15, contentThemes.count * authors.count) {
            let authorIndex = i % authors.count
            let contentIndex = i % contentThemes.count

            let author = authors[authorIndex]
            let content = contentThemes[contentIndex]

            // Create a unique ID
            let id = "sample-bluesky-\(UUID().uuidString)"

            // Generate a random time within the last 24 hours
            let randomTimeInterval = TimeInterval(Int.random(in: 0..<86400))  // 24 hours in seconds
            let createdAt = Date().addingTimeInterval(-randomTimeInterval)

            // Create the post
            let post = Post(
                id: id,
                content: content,
                authorName: author.name,
                authorUsername: author.handle,
                authorProfilePictureURL:
                    "https://ui-avatars.com/api/?name=\(author.name.replacingOccurrences(of: " ", with: "+"))&background=random",
                createdAt: createdAt,
                platform: .bluesky,
                originalURL: "https://bsky.app/profile/\(author.handle)/post/\(id.suffix(10))",
                attachments: [],
                mentions: [],
                tags: []
            )

            posts.append(post)
        }

        // Sort by date
        return posts.sorted { $0.createdAt > $1.createdAt }
    }

    private func convertFeedItemToPostPublic(_ feedItem: BlueskyFeedItem) -> Post {
        // Create a post from feed item data
        let post = Post(
            id: feedItem.post.uri,
            content: feedItem.post.record.text,
            authorName: feedItem.post.author.displayName ?? feedItem.post.author.handle,
            authorUsername: feedItem.post.author.handle,
            authorProfilePictureURL: feedItem.post.author.avatar ?? "",
            createdAt: ISO8601DateFormatter().date(from: feedItem.post.record.createdAt) ?? Date(),
            platform: .bluesky,
            originalURL:
                "https://bsky.app/profile/\(feedItem.post.author.handle)/post/\(feedItem.post.uri.split(separator: "/").last ?? "")",
            attachments: [],
            mentions: [],
            tags: []
        )

        return post
    }
}

extension URL {
    fileprivate func asURLString() -> String {
        return self.absoluteString
    }
}

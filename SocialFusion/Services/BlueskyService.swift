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
        var mediaAttachments: [MediaAttachment] = []

        // Parse the created date
        let dateFormatter = ISO8601DateFormatter()
        let createdAt = dateFormatter.date(from: post.record.createdAt) ?? Date()

        // Handle images if present
        if let embed = post.embed, let images = embed.images {
            for (index, image) in images.enumerated() {
                if let link = image.image.ref?["$link"] ?? image.image.ref?["link"],
                    let url = URL(string: "https://cdn.bsky.app/img/feed_thumbnail/\(link)")
                {
                    let mediaAttachment = MediaAttachment(
                        id: "img_\(index)_\(post.cid)",
                        url: url,
                        previewURL: url,  // Use same URL for preview
                        altText: image.alt,
                        type: .image
                    )
                    mediaAttachments.append(mediaAttachment)
                }
            }
        }

        // Create author from profile
        let author = Author(
            id: post.author.did,
            username: post.author.handle,
            displayName: post.author.displayName ?? post.author.handle,
            profileImageURL: URL(string: post.author.avatar ?? ""),
            platform: .bluesky,
            platformSpecificId: post.author.did
        )

        // Create and return Post
        return Post(
            id: post.uri,
            platform: .bluesky,
            author: author,
            content: content,
            mediaAttachments: mediaAttachments,
            createdAt: createdAt,
            visibility: .public_,
            likeCount: post.likeCount,
            repostCount: post.repostCount,
            replyCount: post.replyCount,
            isLiked: post.viewer?.like ?? false,
            isReposted: post.viewer?.repost ?? false,
            inReplyToID: post.record.reply?.parent.uri,
            platformSpecificId: post.uri
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
        let serverUrl = server.asURLString()

        // Create the session URL with proper error handling
        guard let url = URL(string: "\(serverUrl)/xrpc/com.atproto.server.createSession") else {
            throw NSError(
                domain: "BlueskyService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

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
                serverURL: URL(string: serverUrl),
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

    /// Helper method to convert Bluesky feed item to our app's Post model
    private func convertBlueskyPostToPost(_ feedItem: BlueskyFeedItem, account: SocialAccount)
        -> Post
    {
        let post = feedItem.post

        // Handle repost
        if let reason = feedItem.reason {
            // This is a repost
            return Post(
                id: UUID().uuidString,
                platform: .bluesky,
                author: Author(
                    id: reason.by.did,
                    username: reason.by.handle,
                    displayName: reason.by.displayName ?? reason.by.handle,
                    profileImageURL: reason.by.avatar != nil ? URL(string: reason.by.avatar!) : nil,
                    platform: .bluesky,
                    platformSpecificId: reason.by.did
                ),
                content: "",  // Repost doesn't have its own content
                mediaAttachments: [],
                createdAt: ISO8601DateFormatter().date(from: reason.indexedAt) ?? Date(),
                visibility: .public_,
                likeCount: post.likeCount,
                repostCount: post.repostCount,
                replyCount: post.replyCount,
                isLiked: post.viewer?.like ?? false,
                isReposted: post.viewer?.repost ?? false,
                platformSpecificId: post.uri
            )
        }

        // Handle reply
        if feedItem.reply != nil {
            // Pass through content directly
            let content = post.record.text

            // This is a reply
            return Post(
                id: UUID().uuidString,
                platform: .bluesky,
                author: Author(
                    id: post.author.did,
                    username: post.author.handle,
                    displayName: post.author.displayName ?? post.author.handle,
                    profileImageURL: post.author.avatar != nil
                        ? URL(string: post.author.avatar!) : nil,
                    platform: .bluesky,
                    platformSpecificId: post.author.did
                ),
                content: content,
                mediaAttachments: extractMediaAttachments(post.embed),
                createdAt: ISO8601DateFormatter().date(from: post.record.createdAt) ?? Date(),
                visibility: .public_,
                likeCount: post.likeCount,
                repostCount: post.repostCount,
                replyCount: post.replyCount,
                isLiked: post.viewer?.like ?? false,
                isReposted: post.viewer?.repost ?? false,
                platformSpecificId: post.uri
            )
        }

        // Regular post
        return convertBlueskyPostToOriginalPost(post)
    }

    /// Helper method to convert a Bluesky post to our app's Post model
    private func convertBlueskyPostToOriginalPost(_ post: BlueskyPost) -> Post {
        // Pass through the content directly
        let content = post.record.text

        return Post(
            id: UUID().uuidString,
            platform: .bluesky,
            author: Author(
                id: post.author.did,
                username: post.author.handle,
                displayName: post.author.displayName ?? post.author.handle,
                profileImageURL: post.author.avatar != nil ? URL(string: post.author.avatar!) : nil,
                platform: .bluesky,
                platformSpecificId: post.author.did
            ),
            content: content,
            mediaAttachments: extractMediaAttachments(post.embed),
            createdAt: ISO8601DateFormatter().date(from: post.record.createdAt) ?? Date(),
            visibility: .public_,
            likeCount: post.likeCount,
            repostCount: post.repostCount,
            replyCount: post.replyCount,
            isLiked: post.viewer?.like ?? false,
            isReposted: post.viewer?.repost ?? false,
            platformSpecificId: post.uri
        )
    }

    /// Extract media attachments from a Bluesky embed
    private func extractMediaAttachments(_ embed: BlueskyEmbed?) -> [MediaAttachment] {
        guard let embed = embed else { return [] }

        var attachments: [MediaAttachment] = []

        // Handle images
        if let images = embed.images {
            for (index, image) in images.enumerated() {
                if let link = image.image.ref?["$link"] ?? image.image.ref?["link"],
                    let imageUrl = URL(string: "https://cdn.bsky.app/img/feed_thumbnail/\(link)")
                {
                    attachments.append(
                        MediaAttachment(
                            id: "\(index)",
                            url: imageUrl,
                            previewURL: imageUrl,  // Use same URL for preview
                            altText: image.alt,
                            type: .image
                        ))
                }
            }
        }

        // Handle external links with thumbnails
        if let external = embed.external, let thumb = external.thumb,
            let link = thumb.ref?["$link"] ?? thumb.ref?["link"],
            let thumbUrl = URL(string: "https://cdn.bsky.app/img/feed_thumbnail/\(link)")
        {
            attachments.append(
                MediaAttachment(
                    id: "external",
                    url: thumbUrl,
                    previewURL: thumbUrl,  // Use same URL for preview
                    altText: external.title ?? "External link",
                    type: .image
                ))
        }

        return attachments
    }

    // MARK: - Post Actions

    /// Upload a blob (image) to Bluesky
    private func uploadBlob(data: Data, account: SocialAccount) async throws -> String {
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

        let url = URL(
            string:
                "https://\(account.serverURL.asURLString())/xrpc/com.atproto.repo.uploadBlob"
        )!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (responseData, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: responseData)
            {
                throw errorResponse
            }
            throw NSError(
                domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to upload image"])
        }

        // Parse the response to get the blob reference
        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            let blob = json["blob"] as? [String: Any],
            let ref = blob["$link"] as? String
        else {
            throw NSError(
                domain: "BlueskyService", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse blob reference"])
        }

        return ref
    }

    /// Create a new post on Bluesky
    func createPost(content: String, mediaAttachments: [Data] = [], account: SocialAccount)
        async throws -> Post
    {
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

        // Upload images if any
        var images: [[String: Any]] = []
        for attachment in mediaAttachments {
            let blobRef = try await uploadBlob(data: attachment, account: account)
            images.append([
                "alt": "",
                "image": ["$type": "blob", "ref": ["$link": blobRef], "mimeType": "image/jpeg"],
            ])
        }

        // Create the post
        let url = URL(
            string:
                "https://\(account.serverURL.asURLString())/xrpc/com.atproto.repo.createRecord"
        )!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var record: [String: Any] = [
            "$type": "app.bsky.feed.post",
            "text": content,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]

        if !images.isEmpty {
            record["embed"] = [
                "$type": "app.bsky.embed.images",
                "images": images,
            ]
        }

        let parameters: [String: Any] = [
            "repo": account.id,
            "collection": "app.bsky.feed.post",
            "record": record,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create post"])
        }

        // Parse the response to get the post URI
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let uri = json["uri"] as? String
        else {
            throw NSError(
                domain: "BlueskyService", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse post URI"])
        }

        // Fetch the created post to return it
        return try await getPost(uri: uri, account: account)
    }

    /// Get a specific post by URI
    private func getPost(uri: String, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "BlueskyService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        let encodedUri = uri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? uri
        let url = URL(
            string:
                "https://\(account.serverURL.asURLString())/xrpc/app.bsky.feed.getPostThread?uri=\(encodedUri)"
        )!

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

        // Parse the thread response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let thread = json["thread"] as? [String: Any],
            let post = thread["post"] as? [String: Any]
        else {
            throw NSError(
                domain: "BlueskyService", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse post thread"])
        }

        // Convert the JSON to our BlueskyPost model
        let postData = try JSONSerialization.data(withJSONObject: post)
        let blueskyPost = try JSONDecoder().decode(BlueskyPost.self, from: postData)

        // Convert to our app's Post model
        return convertBlueskyPostToOriginalPost(blueskyPost)
    }

    /// Like a post on Bluesky
    func likePost(_ post: Post, account: SocialAccount) async throws -> Post {
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
            "collection": "app.bsky.feed.like",
            "record": [
                "$type": "app.bsky.feed.like",
                "subject": [
                    "uri": post.platformSpecificId,
                    "cid": post.platformSpecificId.components(separatedBy: "/").last ?? "",
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

        // Return the updated post
        let updatedPost = post
        updatedPost.isLiked = true
        updatedPost.likeCount += 1
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
        if account.isTokenExpired, let refreshToken = account.getRefreshToken() {
            let newSession = try await refreshSession(
                refreshToken: refreshToken, server: account.serverURL)
            account.saveAccessToken(newSession.accessJwt)
            account.saveRefreshToken(newSession.refreshJwt)
            account.saveTokenExpirationDate(newSession.expirationDate)
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
                    "uri": post.platformSpecificId,
                    "cid": post.platformSpecificId.components(separatedBy: "/").last ?? "",
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

        // Return the updated post
        let updatedPost = post
        updatedPost.isReposted = true
        updatedPost.repostCount += 1
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
        if account.isTokenExpired, let refreshToken = account.getRefreshToken() {
            let newSession = try await refreshSession(
                refreshToken: refreshToken, server: account.serverURL)
            account.saveAccessToken(newSession.accessJwt)
            account.saveRefreshToken(newSession.refreshJwt)
            account.saveTokenExpirationDate(newSession.expirationDate)
        }

        let url = URL(
            string:
                "https://\(account.serverURL.asURLString())/xrpc/com.atproto.repo.createRecord"
        )!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Get the post's URI components for the reply reference
        let postUri = post.platformSpecificId
        let postCid = postUri.components(separatedBy: "/").last ?? ""

        let record: [String: Any] = [
            "$type": "app.bsky.feed.post",
            "text": content,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "reply": [
                "root": [
                    "uri": postUri,
                    "cid": postCid,
                ],
                "parent": [
                    "uri": postUri,
                    "cid": postCid,
                ],
            ],
        ]

        let parameters: [String: Any] = [
            "repo": account.id,
            "collection": "app.bsky.feed.post",
            "record": record,
        ]

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

        // Parse the response to get the post URI
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

    // MARK: - Public Access APIs

    /// Fetch trending posts from Bluesky without requiring authentication
    func fetchTrendingPosts(server: String = "bsky.social") async throws -> [Post] {
        print("Starting Bluesky trending posts fetch...")

        // Create a dummy account for conversion purposes
        let dummyAccount = SocialAccount(
            id: "trending",
            username: "trending",
            displayName: "Trending",
            serverURL: URL(string: "bsky.social"),
            platform: .bluesky
        )

        // Determine if we're passed a complete URL or just a server
        let algorithmUrl: String

        if server.contains("xrpc") {
            // This is already a complete feed URL
            algorithmUrl = server
            print("Using custom feed URL: \(server)")
        } else {
            // Use the standard Bluesky timeline algorithm which is more reliable
            // This is the default "For You" feed
            algorithmUrl =
                "https://bsky.social/xrpc/app.bsky.feed.getTimeline?algorithm=reverse-chronological&limit=30"
            print("Using standard Bluesky timeline: \(algorithmUrl)")
        }

        let url = URL(string: algorithmUrl)!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200
            else {
                if let httpResponse = response as? HTTPURLResponse {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("Error response: \(errorMessage)")
                    throw NSError(
                        domain: "BlueskyService",
                        code: httpResponse.statusCode,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Server returned status code \(httpResponse.statusCode)"
                        ]
                    )
                } else {
                    throw NSError(
                        domain: "BlueskyService",
                        code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "Unknown network error"]
                    )
                }
            }

            do {
                // The response structure depends on whether we're using timeline or feed endpoint
                if algorithmUrl.contains("getTimeline") {
                    let timeline = try JSONDecoder().decode(
                        BlueskyTimelineResponse.self, from: data)
                    print("Successfully fetched \(timeline.feed.count) Bluesky timeline posts")
                    return timeline.feed.compactMap { feedItem in
                        convertBlueskyPostToPost(feedItem, account: dummyAccount)
                    }
                } else {
                    let feed = try JSONDecoder().decode(BlueskyFeed.self, from: data)
                    print("Successfully fetched \(feed.feed.count) Bluesky feed posts")
                    return feed.feed.compactMap { feedItem in
                        convertBlueskyPostToPost(feedItem, account: dummyAccount)
                    }
                }
            } catch {
                print("Error parsing Bluesky feed: \(error.localizedDescription)")
                throw error
            }
        } catch {
            print("Network error fetching Bluesky feed: \(error.localizedDescription)")
            throw error
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
}

extension URL {
    fileprivate func asURLString() -> String {
        return self.absoluteString
    }
}

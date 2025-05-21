import Foundation

class BlueskyService {
    private let session = URLSession.shared
    private let baseURL = "https://bsky.social/xrpc"
    
    // MARK: - Authentication
    
    /// Authenticate with Bluesky using the AT Protocol
    func authenticate(username: String, password: String, server: String = "bsky.social") async throws -> SocialAccount {
        let url = URL(string: "https://\(server)/xrpc/com.atproto.server.createSession")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let parameters: [String: Any] = [
            "identifier": username,
            "password": password
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to authenticate"])
        }
        
        let authResponse = try JSONDecoder().decode(BlueskyAuthResponse.self, from: data)
        
        // Create a SocialAccount object
        let account = SocialAccount(
            id: authResponse.did,
            username: authResponse.handle,
            displayName: authResponse.handle.components(separatedBy: ".").first ?? authResponse.handle,
            serverURL: server,
            platform: .bluesky
        )
        
        // Save the tokens
        account.saveAccessToken(authResponse.accessJwt)
        account.saveRefreshToken(authResponse.refreshJwt)
        account.saveTokenExpirationDate(authResponse.expirationDate)
        
        return account
    }
    
    /// Refresh an expired access token
    func refreshSession(refreshToken: String, server: String = "bsky.social") async throws -> BlueskyAuthResponse {
        let url = URL(string: "https://\(server)/xrpc/com.atproto.server.refreshSession")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(refreshToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to refresh session"])
        }
        
        return try JSONDecoder().decode(BlueskyAuthResponse.self, from: data)
    }
    
    /// Get the authenticated user's profile information
    func getProfile(for account: SocialAccount) async throws -> BlueskyProfile {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(domain: "BlueskyService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        
        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken() {
            let newSession = try await refreshSession(refreshToken: refreshToken, server: account.serverURL)
            account.saveAccessToken(newSession.accessJwt)
            account.saveRefreshToken(newSession.refreshJwt)
            account.saveTokenExpirationDate(newSession.expirationDate)
        }
        
        let url = URL(string: "https://\(account.serverURL)/xrpc/app.bsky.actor.getProfile?actor=\(account.username)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to get profile"])
        }
        
        return try JSONDecoder().decode(BlueskyProfile.self, from: data)
    }
    
    // MARK: - Timeline
    
    /// Fetch the home timeline from the Bluesky API
    func fetchHomeTimeline(for account: SocialAccount) async throws -> [Post] {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(domain: "BlueskyService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        
        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken() {
            let newSession = try await refreshSession(refreshToken: refreshToken, server: account.serverURL)
            account.saveAccessToken(newSession.accessJwt)
            account.saveRefreshToken(newSession.refreshJwt)
            account.saveTokenExpirationDate(newSession.expirationDate)
        }
        
        let url = URL(string: "https://\(account.serverURL)/xrpc/app.bsky.feed.getTimeline?limit=50")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch timeline"])
        }
        
        let feed = try JSONDecoder().decode(BlueskyFeed.self, from: data)
        
        // Convert to our app's Post model
        return feed.feed.compactMap { feedItem in
            convertBlueskyPostToPost(feedItem, account: account)
        }
    }
    
    /// Fetch a user's profile timeline
    func fetchUserTimeline(username: String, for account: SocialAccount) async throws -> [Post] {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(domain: "BlueskyService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        
        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken() {
            let newSession = try await refreshSession(refreshToken: refreshToken, server: account.serverURL)
            account.saveAccessToken(newSession.accessJwt)
            account.saveRefreshToken(newSession.refreshJwt)
            account.saveTokenExpirationDate(newSession.expirationDate)
        }
        
        let url = URL(string: "https://\(account.serverURL)/xrpc/app.bsky.feed.getAuthorFeed?actor=\(username)&limit=50")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch user timeline"])
        }
        
        let feed = try JSONDecoder().decode(BlueskyFeed.self, from: data)
        
        // Convert to our app's Post model
        return feed.feed.compactMap { feedItem in
            convertBlueskyPostToPost(feedItem, account: account)
        }
    }
    
    /// Helper method to convert Bluesky feed item to our app's Post model
    private func convertBlueskyPostToPost(_ feedItem: BlueskyFeedItem, account: SocialAccount) -> Post {
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
                    avatarURL: reason.by.avatar != nil ? URL(string: reason.by.avatar!) : nil,
                    platform: .bluesky,
                    platformSpecificId: reason.by.did
                ),
                content: "",  // Repost doesn't have its own content
                mediaAttachments: [],
                createdAt: ISO8601DateFormatter().date(from: reason.indexedAt) ?? Date(),
                likeCount: post.likeCount,
                repostCount: post.repostCount,
                replyCount: post.replyCount,
                isLiked: post.viewer?.likeUri != nil,
                isReposted: post.viewer?.repostUri != nil,
                originalPost: convertBlueskyPostToOriginalPost(post),
                platformSpecificId: post.uri
            )
        }
        
        // Handle reply
        if feedItem.reply != nil {
            // This is a reply
            return Post(
                id: UUID().uuidString,
                platform: .bluesky,
                author: Author(
                    id: post.author.did,
                    username: post.author.handle,
                    displayName: post.author.displayName ?? post.author.handle,
                    avatarURL: post.author.avatar != nil ? URL(string: post.author.avatar!) : nil,
                    platform: .bluesky,
                    platformSpecificId: post.author.did
                ),
                content: post.record.text,
                mediaAttachments: extractMediaAttachments(post.embed),
                createdAt: ISO8601DateFormatter().date(from: post.record.createdAt) ?? Date(),
                likeCount: post.likeCount,
                repostCount: post.repostCount,
                replyCount: post.replyCount,
                isLiked: post.viewer?.likeUri != nil,
                isReposted: post.viewer?.repostUri != nil,
                originalPost: nil,  // We would need to fetch the original post separately
                platformSpecificId: post.uri
            )
        }
        
        // Regular post
        return convertBlueskyPostToOriginalPost(post)
    }
    
    /// Helper method to convert a Bluesky post to our app's Post model
    private func convertBlueskyPostToOriginalPost(_ post: BlueskyPost) -> Post {
        let quotedPostUri = post.embed?.record?.record.uri
        // The handle of the quoted post's author is not directly available in the embed, so leave nil for now
        let quotedPostAuthorHandle: String? = nil
        return Post(
            id: UUID().uuidString,
            platform: .bluesky,
            author: Author(
                id: post.author.did,
                username: post.author.handle,
                displayName: post.author.displayName ?? post.author.handle,
                avatarURL: post.author.avatar != nil ? URL(string: post.author.avatar!) : nil,
                platform: .bluesky,
                platformSpecificId: post.author.did
            ),
            content: post.record.text,
            mediaAttachments: extractMediaAttachments(post.embed),
            createdAt: ISO8601DateFormatter().date(from: post.record.createdAt) ?? Date(),
            likeCount: post.likeCount,
            repostCount: post.repostCount,
            replyCount: post.replyCount,
            isLiked: post.viewer?.likeUri != nil,
            isReposted: post.viewer?.repostUri != nil,
            originalPost: nil,
            platformSpecificId: post.uri,
            quotedPostUri: quotedPostUri,
            quotedPostAuthorHandle: quotedPostAuthorHandle
        )
    }
    
    /// Extract media attachments from a Bluesky embed
    private func extractMediaAttachments(_ embed: BlueskyEmbed?) -> [MediaAttachment] {
        guard let embed = embed else { return [] }
        
        var attachments: [MediaAttachment] = []
        
        // Handle images
        if let images = embed.images {
            for (index, image) in images.enumerated() {
                if let imageUrl = URL(string: "https://cdn.bsky.app/img/feed_thumbnail/\(image.image.ref?["$link"] ?? "")") {
                    attachments.append(MediaAttachment(
                        id: "\(index)",
                        url: imageUrl,
                        type: .image,
                        altText: image.alt
                    ))
                }
            }
        }
        
        // Handle external links with thumbnails
        if let external = embed.external, let thumb = external.thumb, let thumbUrl = URL(string: "https://cdn.bsky.app/img/feed_thumbnail/\(thumb.ref?["$link"] ?? "")") {
            attachments.append(MediaAttachment(
                id: "external",
                url: thumbUrl,
                type: .image,
                altText: external.title ?? "External link"
            ))
        }
        
        return attachments
    }
    
    // MARK: - Post Actions
    
    /// Upload a blob (image) to Bluesky
    private func uploadBlob(data: Data, account: SocialAccount) async throws -> String {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(domain: "BlueskyService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        
        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken() {
            let newSession = try await refreshSession(refreshToken: refreshToken, server: account.serverURL)
            account.saveAccessToken(newSession.accessJwt)
            account.saveRefreshToken(newSession.refreshJwt)
            account.saveTokenExpirationDate(newSession.expirationDate)
        }
        
        let url = URL(string: "https://\(account.serverURL)/xrpc/com.atproto.repo.uploadBlob")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        
        let (responseData, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: responseData) {
                throw errorResponse
            }
            throw NSError(domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to upload image"])
        }
        
        // Parse the response to get the blob reference
        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let blob = json["blob"] as? [String: Any],
              let ref = blob["$link"] as? String else {
            throw NSError(domain: "BlueskyService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to parse blob reference"])
        }
        
        return ref
    }
    
    /// Create a new post on Bluesky
    func createPost(content: String, mediaAttachments: [Data] = [], account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(domain: "BlueskyService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        
        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken() {
            let newSession = try await refreshSession(refreshToken: refreshToken, server: account.serverURL)
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
                "image": ["$type": "blob", "ref": ["$link": blobRef], "mimeType": "image/jpeg"]
            ])
        }
        
        // Create the post
        let url = URL(string: "https://\(account.serverURL)/xrpc/com.atproto.repo.createRecord")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var record: [String: Any] = [
            "$type": "app.bsky.feed.post",
            "text": content,
            "createdAt": ISO8601DateFormatter().string(from: Date())
        ]
        
        if !images.isEmpty {
            record["embed"] = [
                "$type": "app.bsky.embed.images",
                "images": images
            ]
        }
        
        let parameters: [String: Any] = [
            "repo": account.id,
            "collection": "app.bsky.feed.post",
            "record": record
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create post"])
        }
        
        // Parse the response to get the post URI
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uri = json["uri"] as? String else {
            throw NSError(domain: "BlueskyService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to parse post URI"])
        }
        
        // Fetch the created post to return it
        return try await getPost(uri: uri, account: account)
    }
    
    /// Get a specific post by URI
    private func getPost(uri: String, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(domain: "BlueskyService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        
        let encodedUri = uri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? uri
        let url = URL(string: "https://\(account.serverURL)/xrpc/app.bsky.feed.getPostThread?uri=\(encodedUri)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to get post"])
        }
        
        // Parse the thread response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let thread = json["thread"] as? [String: Any],
              let post = thread["post"] as? [String: Any] else {
            throw NSError(domain: "BlueskyService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to parse post thread"])
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
            throw NSError(domain: "BlueskyService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        
        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken() {
            let newSession = try await refreshSession(refreshToken: refreshToken, server: account.serverURL)
            account.saveAccessToken(newSession.accessJwt)
            account.saveRefreshToken(newSession.refreshJwt)
            account.saveTokenExpirationDate(newSession.expirationDate)
        }
        
        let url = URL(string: "https://\(account.serverURL)/xrpc/com.atproto.repo.createRecord")!
        
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
                    "cid": post.platformSpecificId.components(separatedBy: "/").last ?? ""
                ],
                "createdAt": ISO8601DateFormatter().string(from: Date())
                ]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to like post"])
        }
        
        // Return the updated post
        var updatedPost = post
        updatedPost.isLiked = true
        updatedPost.likeCount += 1
        return updatedPost
    }
    
    /// Repost a post on Bluesky
    func repostPost(_ post: Post, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(domain: "BlueskyService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        
        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken() {
            let newSession = try await refreshSession(refreshToken: refreshToken, server: account.serverURL)
            account.saveAccessToken(newSession.accessJwt)
            account.saveRefreshToken(newSession.refreshJwt)
            account.saveTokenExpirationDate(newSession.expirationDate)
        }
        
        let url = URL(string: "https://\(account.serverURL)/xrpc/com.atproto.repo.createRecord")!
        
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
                    "cid": post.platformSpecificId.components(separatedBy: "/").last ?? ""
                ],
                "createdAt": ISO8601DateFormatter().string(from: Date())
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to repost"])
        }
        
        // Return the updated post
        var updatedPost = post
        updatedPost.isReposted = true
        updatedPost.repostCount += 1
        return updatedPost
    }
    
    /// Reply to a post on Bluesky
    func replyToPost(_ post: Post, content: String, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(domain: "BlueskyService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        
        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken() {
            let newSession = try await refreshSession(refreshToken: refreshToken, server: account.serverURL)
            account.saveAccessToken(newSession.accessJwt)
            account.saveRefreshToken(newSession.refreshJwt)
            account.saveTokenExpirationDate(newSession.expirationDate)
        }
        
        let url = URL(string: "https://\(account.serverURL)/xrpc/com.atproto.repo.createRecord")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Get the post's URI components for the reply reference
        let postUri = post.platformSpecificId
        let postCid = postUri.components(separatedBy: "/").last ?? ""
        
        var record: [String: Any] = [
            "$type": "app.bsky.feed.post",
            "text": content,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "reply": [
                "root": [
                    "uri": postUri,
                    "cid": postCid
                ],
                "parent": [
                    "uri": postUri,
                    "cid": postCid
                ]
            ]
        ]
        
        let parameters: [String: Any] = [
            "repo": account.id,
            "collection": "app.bsky.feed.post",
            "record": record
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(BlueskyError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "BlueskyService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to reply to post"])
        }
        
        // Parse the response to get the post URI
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uri = json["uri"] as? String else {
            throw NSError(domain: "BlueskyService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to parse post URI"])
        }
        
        // Fetch the created reply to return it
        return try await getPost(uri: uri, account: account)
    }
}
import Foundation

class MastodonService {
    private let session = URLSession.shared
    
    // MARK: - Authentication
    
    /// Register a new application with the Mastodon server
    func registerApp(server: String, clientName: String = "SocialFusion", redirectURI: String = "socialfusion://oauth") async throws -> (clientId: String, clientSecret: String) {
        let url = URL(string: "https://\(server)/api/v1/apps")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let parameters: [String: Any] = [
            "client_name": clientName,
            "redirect_uris": redirectURI,
            "scopes": "read write follow push",
            "website": "https://socialfusion.app"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to register app"])
        }
        
        let app = try JSONDecoder().decode(MastodonApp.self, from: data)
        return (app.clientId, app.clientSecret)
    }
    
    /// Get the OAuth authorization URL for the user to authorize the app
    func getOAuthURL(server: String, clientId: String, redirectURI: String = "socialfusion://oauth") -> URL {
        let baseURL = "https://\(server)/oauth/authorize"
        let queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "read write follow push")
        ]
        
        var components = URLComponents(string: baseURL)!
        components.queryItems = queryItems
        
        return components.url!
    }
    
    /// Exchange authorization code for access token
    func getAccessToken(server: String, clientId: String, clientSecret: String, code: String, redirectURI: String = "socialfusion://oauth") async throws -> MastodonToken {
        let url = URL(string: "https://\(server)/oauth/token")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let parameters: [String: Any] = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "scope": "read write follow push"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to get access token"])
        }
        
        return try JSONDecoder().decode(MastodonToken.self, from: data)
    }
    
    /// Refresh an expired access token
    func refreshToken(server: String, clientId: String, clientSecret: String, refreshToken: String) async throws -> MastodonToken {
        let url = URL(string: "https://\(server)/oauth/token")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let parameters: [String: Any] = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "read write follow push"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to refresh token"])
        }
        
        return try JSONDecoder().decode(MastodonToken.self, from: data)
    }
    
    /// Get the authenticated user's account information
    func verifyCredentials(server: String, accessToken: String) async throws -> MastodonAccount {
        let url = URL(string: "https://\(server)/api/v1/accounts/verify_credentials")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to verify credentials"])
        }
        
        return try JSONDecoder().decode(MastodonAccount.self, from: data)
    }
    
    /// Complete OAuth authentication flow
    func authenticate(server: String, username: String, password: String) async throws -> SocialAccount {
        // Note: Mastodon doesn't support password-based authentication directly through the API
        // This is a placeholder for the OAuth flow which would typically involve redirecting to a web browser
        // For a real implementation, you would need to implement the OAuth flow with a web view or browser
        
        // For now, we'll simulate the OAuth flow by registering an app and getting credentials
        let (clientId, clientSecret) = try await registerApp(server: server)
        
        // In a real app, you would redirect the user to the OAuth URL and get the authorization code
        // let authURL = getOAuthURL(server: server, clientId: clientId)
        // ... redirect user to authURL and get authorization code ...
        
        // Simulate getting an authorization code (this would come from the OAuth redirect)
        let simulatedCode = "simulated_auth_code"
        
        // Exchange the code for an access token
        let token = try await getAccessToken(server: server, clientId: clientId, clientSecret: clientSecret, code: simulatedCode)
        
        // Get the user's account information
        let mastodonAccount = try await verifyCredentials(server: server, accessToken: token.accessToken)
        
        // Create a SocialAccount object
        let account = SocialAccount(
            id: UUID().uuidString,
            username: mastodonAccount.acct,
            displayName: mastodonAccount.displayName,
            serverURL: server,
            platform: .mastodon
        )
        
        // Save the tokens and client credentials
        account.saveAccessToken(token.accessToken)
        account.saveRefreshToken(token.refreshToken ?? "")
        account.saveTokenExpirationDate(token.expirationDate)
        account.saveClientCredentials(clientId: clientId, clientSecret: clientSecret)
        
        return account
    }
    
    // MARK: - Timeline
    
    /// Fetch the home timeline from the Mastodon API
    func fetchHomeTimeline(for account: SocialAccount) async throws -> [Post] {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(domain: "MastodonService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        
        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken(), let clientId = account.getClientId(), let clientSecret = account.getClientSecret() {
            let newToken = try await refreshToken(server: account.serverURL, clientId: clientId, clientSecret: clientSecret, refreshToken: refreshToken)
            account.saveAccessToken(newToken.accessToken)
            account.saveRefreshToken(newToken.refreshToken)
            account.saveTokenExpirationDate(newToken.expirationDate)
        }
        
        let url = URL(string: "https://\(account.serverURL)/api/v1/timelines/home?limit=40")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch timeline"])
        }
        
        let statuses = try JSONDecoder().decode([MastodonStatus].self, from: data)
        
        // Convert to our app's Post model
        return statuses.map { convertMastodonStatusToPost($0, account: account) }
    }
    
    /// Fetch the public timeline from the Mastodon API
    func fetchPublicTimeline(for account: SocialAccount, local: Bool = false) async throws -> [Post] {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(domain: "MastodonService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        
        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken(), let clientId = account.getClientId(), let clientSecret = account.getClientSecret() {
            let newToken = try await refreshToken(server: account.serverURL, clientId: clientId, clientSecret: clientSecret, refreshToken: refreshToken)
            account.saveAccessToken(newToken.accessToken)
            account.saveRefreshToken(newToken.refreshToken)
            account.saveTokenExpirationDate(newToken.expirationDate)
        }
        
        let endpoint = local ? "public?local=true" : "public"
        let url = URL(string: "https://\(account.serverURL)/api/v1/timelines/\(endpoint)&limit=40")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch public timeline"])
        }
        
        let statuses = try JSONDecoder().decode([MastodonStatus].self, from: data)
        
        // Convert to our app's Post model
        return statuses.map { convertMastodonStatusToPost($0, account: account) }
    }
    
    /// Fetch a user's profile timeline
    func fetchUserTimeline(userId: String, for account: SocialAccount) async throws -> [Post] {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(domain: "MastodonService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        
        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken(), let clientId = account.getClientId(), let clientSecret = account.getClientSecret() {
            let newToken = try await refreshToken(server: account.serverURL, clientId: clientId, clientSecret: clientSecret, refreshToken: refreshToken)
            account.saveAccessToken(newToken.accessToken)
            account.saveRefreshToken(newToken.refreshToken)
            account.saveTokenExpirationDate(newToken.expirationDate)
        }
        
        let url = URL(string: "https://\(account.serverURL)/api/v1/accounts/\(userId)/statuses?limit=40")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch user timeline"])
        }
        
        let statuses = try JSONDecoder().decode([MastodonStatus].self, from: data)
        
        // Convert to our app's Post model
        return statuses.map { convertMastodonStatusToPost($0, account: account) }
    }
    
    // MARK: - Post Actions
    
    /// Upload media attachment to Mastodon
    private func uploadMedia(data: Data, description: String?, server: String, accessToken: String) async throws -> String {
        let url = URL(string: "https://\(server)/api/v2/media")!
        
        let boundary = UUID().uuidString
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"media.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add description if provided
        if let description = description {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"description\"\r\n\r\n".data(using: .utf8)!)
            body.append(description.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        // Add closing boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create post"])
        }
        
        let mastodonStatus = try JSONDecoder().decode(MastodonStatus.self, from: data)
        
        // Convert to our app's Post model
        return convertMastodonStatusToPost(mastodonStatus, account: account)
    }
    
    /// Like a post on Mastodon
    func likePost(_ post: Post, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(domain: "MastodonService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        
        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken(), let clientId = account.getClientId(), let clientSecret = account.getClientSecret() {
            let newToken = try await refreshToken(server: account.serverURL, clientId: clientId, clientSecret: clientSecret, refreshToken: refreshToken)
            account.saveAccessToken(newToken.accessToken)
            account.saveRefreshToken(newToken.refreshToken)
            account.saveTokenExpirationDate(newToken.expirationDate)
        }
        
        let url = URL(string: "https://\(account.serverURL)/api/v1/statuses/\(post.platformSpecificId)/favourite")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to like post"])
        }
        
        let mastodonStatus = try JSONDecoder().decode(MastodonStatus.self, from: data)
        
        // Convert to our app's Post model
        return convertMastodonStatusToPost(mastodonStatus, account: account)
    }
    
    /// Repost (reblog) a post on Mastodon
    func repostPost(_ post: Post, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(domain: "MastodonService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        
        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken(), let clientId = account.getClientId(), let clientSecret = account.getClientSecret() {
            let newToken = try await refreshToken(server: account.serverURL, clientId: clientId, clientSecret: clientSecret, refreshToken: refreshToken)
            account.saveAccessToken(newToken.accessToken)
            account.saveRefreshToken(newToken.refreshToken)
            account.saveTokenExpirationDate(newToken.expirationDate)
        }
        
        let url = URL(string: "https://\(account.serverURL)/api/v1/statuses/\(post.platformSpecificId)/reblog")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to repost"])
        }
        
        let mastodonStatus = try JSONDecoder().decode(MastodonStatus.self, from: data)
        
        // Convert to our app's Post model
        return convertMastodonStatusToPost(mastodonStatus, account: account)
    }
    
    /// Reply to a post on Mastodon
    func replyToPost(_ post: Post, content: String, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(domain: "MastodonService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        
        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken(), let clientId = account.getClientId(), let clientSecret = account.getClientSecret() {
            let newToken = try await refreshToken(server: account.serverURL, clientId: clientId, clientSecret: clientSecret, refreshToken: refreshToken)
            account.saveAccessToken(newToken.accessToken)
            account.saveRefreshToken(newToken.refreshToken)
            account.saveTokenExpirationDate(newToken.expirationDate)
        }
        
        let url = URL(string: "https://\(account.serverURL)/api/v1/statuses")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let parameters: [String: Any] = [
            "status": content,
            "in_reply_to_id": post.platformSpecificId,
            "visibility": "public"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to reply to post"])
        }
        
        let mastodonStatus = try JSONDecoder().decode(MastodonStatus.self, from: data)
        
        // Convert to our app's Post model
        return convertMastodonStatusToPost(mastodonStatus, account: account)
    }
    
    // MARK: - Helper Methods
    
    /// Convert a Mastodon status to our app's Post model
    private func convertMastodonStatusToPost(_ status: MastodonStatus, account: SocialAccount) -> Post {
        // Handle reblog/repost if present
        if let reblog = status.reblog {
            return Post(
                id: UUID().uuidString,
                platform: .mastodon,
                author: Author(
                    id: status.account.id,
                    username: status.account.acct,
                    displayName: status.account.displayName,
                    avatarURL: URL(string: status.account.avatar),
                    platform: .mastodon,
                    platformSpecificId: status.account.id
                ),
                content: "",  // Repost doesn't have its own content
                mediaAttachments: [],
                createdAt: ISO8601DateFormatter().date(from: status.createdAt) ?? Date(),
                likeCount: reblog.favouritesCount,
                repostCount: reblog.reblogsCount,
                replyCount: reblog.repliesCount,
                isLiked: status.favourited ?? false,
                isReposted: status.reblogged ?? false,
                originalPost: convertMastodonStatusToPost(reblog, account: account),
                platformSpecificId: status.id
            )
        }
        
        // Convert media attachments
        let mediaAttachments = status.mediaAttachments.map { attachment -> MediaAttachment in
            return MediaAttachment(
                id: attachment.id,
                url: URL(string: attachment.url)!,
                type: convertMediaType(attachment.type),
                altText: attachment.description
            )
        }
        
        // Create post
        return Post(
            id: UUID().uuidString,
            platform: .mastodon,
            author: Author(
                id: status.account.id,
                username: status.account.acct,
                displayName: status.account.displayName,
                avatarURL: URL(string: status.account.avatar),
                platform: .mastodon,
                platformSpecificId: status.account.id
            ),
            content: status.content,
            mediaAttachments: mediaAttachments,
            createdAt: ISO8601DateFormatter().date(from: status.createdAt) ?? Date(),
            likeCount: status.favouritesCount,
            repostCount: status.reblogsCount,
            replyCount: status.repliesCount,
            isLiked: status.favourited ?? false,
            isReposted: status.reblogged ?? false,
            originalPost: status.inReplyToId != nil ? nil : nil,  // We would need to fetch the original post separately
            platformSpecificId: status.id
        )
    }
    
    /// Convert Mastodon media type to our app's MediaType
    private func convertMediaType(_ type: String) -> MediaAttachment.MediaType {
        switch type {
        case "image":
            return .image
        case "video":
            return .video
        case "gifv":
            return .gifv
        case "audio":
            return .audio
        default:
            return .image
        }
    } 200 || httpResponse.statusCode == 202 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to upload media"])
        }
        
        let mediaResponse = try JSONDecoder().decode([String: Any].self, from: data) as? [String: Any]
        guard let mediaId = mediaResponse?["id"] as? String else {
            throw NSError(domain: "MastodonService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to get media ID"])
        }
        
        return mediaId
    }
    
    /// Create a new post on Mastodon
    func createPost(content: String, mediaAttachments: [Data] = [], visibility: PostVisibility = .public, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(domain: "MastodonService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        
        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken(), let clientId = account.getClientId(), let clientSecret = account.getClientSecret() {
            let newToken = try await refreshToken(server: account.serverURL, clientId: clientId, clientSecret: clientSecret, refreshToken: refreshToken)
            account.saveAccessToken(newToken.accessToken)
            account.saveRefreshToken(newToken.refreshToken)
            account.saveTokenExpirationDate(newToken.expirationDate)
        }
        
        // Upload media attachments if any
        var mediaIds: [String] = []
        for attachment in mediaAttachments {
            let mediaId = try await uploadMedia(data: attachment, description: nil, server: account.serverURL, accessToken: accessToken)
            mediaIds.append(mediaId)
        }
        
        // Create the status
        let url = URL(string: "https://\(account.serverURL)/api/v1/statuses")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var parameters: [String: Any] = [
            "status": content,
            "visibility": visibility.rawValue
        ]
        
        if !mediaIds.isEmpty {
            parameters["media_ids"] = mediaIds
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create post"])
        }
        
        let mastodonStatus = try JSONDecoder().decode(MastodonStatus.self, from: data)
        
        // Convert to our app's Post model
        return convertMastodonStatusToPost(mastodonStatus, account: account)
    }
    
    /// Like a post on Mastodon
    func likePost(_ post: Post, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(domain: "MastodonService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        
        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken(), let clientId = account.getClientId(), let clientSecret = account.getClientSecret() {
            let newToken = try await refreshToken(server: account.serverURL, clientId: clientId, clientSecret: clientSecret, refreshToken: refreshToken)
            account.saveAccessToken(newToken.accessToken)
            account.saveRefreshToken(newToken.refreshToken)
            account.saveTokenExpirationDate(newToken.expirationDate)
        }
        
        let url = URL(string: "https://\(account.serverURL)/api/v1/statuses/\(post.platformSpecificId)/favourite")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to like post"])
        }
        
        let mastodonStatus = try JSONDecoder().decode(MastodonStatus.self, from: data)
        
        // Convert to our app's Post model
        return convertMastodonStatusToPost(mastodonStatus, account: account)
    }
    
    /// Repost (reblog) a post on Mastodon
    func repostPost(_ post: Post, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(domain: "MastodonService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        
        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken(), let clientId = account.getClientId(), let clientSecret = account.getClientSecret() {
            let newToken = try await refreshToken(server: account.serverURL, clientId: clientId, clientSecret: clientSecret, refreshToken: refreshToken)
            account.saveAccessToken(newToken.accessToken)
            account.saveRefreshToken(newToken.refreshToken)
            account.saveTokenExpirationDate(newToken.expirationDate)
        }
        
        let url = URL(string: "https://\(account.serverURL)/api/v1/statuses/\(post.platformSpecificId)/reblog")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to repost"])
        }
        
        let mastodonStatus = try JSONDecoder().decode(MastodonStatus.self, from: data)
        
        // Convert to our app's Post model
        return convertMastodonStatusToPost(mastodonStatus, account: account)
    }
    
    /// Reply to a post on Mastodon
    func replyToPost(_ post: Post, content: String, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(domain: "MastodonService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }
        
        // Check if token needs refresh
        if account.isTokenExpired, let refreshToken = account.getRefreshToken(), let clientId = account.getClientId(), let clientSecret = account.getClientSecret() {
            let newToken = try await refreshToken(server: account.serverURL, clientId: clientId, clientSecret: clientSecret, refreshToken: refreshToken)
            account.saveAccessToken(newToken.accessToken)
            account.saveRefreshToken(newToken.refreshToken)
            account.saveTokenExpirationDate(newToken.expirationDate)
        }
        
        let url = URL(string: "https://\(account.serverURL)/api/v1/statuses")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let parameters: [String: Any] = [
            "status": content,
            "in_reply_to_id": post.platformSpecificId,
            "visibility": "public"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Failed to reply to post"])
        }
        
        let mastodonStatus = try JSONDecoder().decode(MastodonStatus.self, from: data)
        
        // Convert to our app's Post model
        return convertMastodonStatusToPost(mastodonStatus, account: account)
    }
    
    // MARK: - Helper Methods
    
    /// Convert a Mastodon status to our app's Post model
    private func convertMastodonStatusToPost(_ status: MastodonStatus, account: SocialAccount) -> Post {
        // Handle reblog/repost if present
        if let reblog = status.reblog {
            return Post(
                id: UUID().uuidString,
                platform: .mastodon,
                author: Author(
                    id: status.account.id,
                    username: status.account.acct,
                    displayName: status.account.displayName,
                    avatarURL: URL(string: status.account.avatar),
                    platform: .mastodon,
                    platformSpecificId: status.account.id
                ),
                content: "",  // Repost doesn't have its own content
                mediaAttachments: [],
                createdAt: ISO8601DateFormatter().date(from: status.createdAt) ?? Date(),
                likeCount: reblog.favouritesCount,
                repostCount: reblog.reblogsCount,
                replyCount: reblog.repliesCount,
                isLiked: status.favourited ?? false,
                isReposted: status.reblogged ?? false,
                originalPost: convertMastodonStatusToPost(reblog, account: account),
                platformSpecificId: status.id
            )
        }
        
        // Convert media attachments
        let mediaAttachments = status.mediaAttachments.map { attachment -> MediaAttachment in
            return MediaAttachment(
                id: attachment.id,
                url: URL(string: attachment.url)!,
                type: convertMediaType(attachment.type),
                altText: attachment.description
            )
        }
        
        // Create post
        return Post(
            id: UUID().uuidString,
            platform: .mastodon,
            author: Author(
                id: status.account.id,
                username: status.account.acct,
                displayName: status.account.displayName,
                avatarURL: URL(string: status.account.avatar),
                platform: .mastodon,
                platformSpecificId: status.account.id
            ),
            content: status.content,
            mediaAttachments: mediaAttachments,
            createdAt: ISO8601DateFormatter().date(from: status.createdAt) ?? Date(),
            likeCount: status.favouritesCount,
            repostCount: status.reblogsCount,
            replyCount: status.repliesCount,
            isLiked: status.favourited ?? false,
            isReposted: status.reblogged ?? false,
            originalPost: status.inReplyToId != nil ? nil : nil,  // We would need to fetch the original post separately
            platformSpecificId: status.id
        )
    }
    
    /// Convert Mastodon media type to our app's MediaType
    private func convertMediaType(_ type: String) -> MediaAttachment.MediaType {
        switch type {
        case "image":
            return .image
        case "video":
            return .video
        case "gifv":
            return .gifv
        case "audio":
            return .audio
        default:
            return .image
        }
    }
}

enum PostVisibility: String, Codable {
    case `public` = "public"
    case unlisted = "unlisted"
    case `private` = "private"
    case direct = "direct"
}
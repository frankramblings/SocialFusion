import Foundation
import UIKit

// Add URL extension for optional URL
extension Optional where Wrapped == URL {
    func asString() -> String {
        switch self {
        case .some(let url):
            return url.absoluteString
        case .none:
            return ""
        }
    }
}

class MastodonService {
    private let session = URLSession.shared

    // MARK: - Authentication Utilities

    /// Creates an authenticated request with a valid access token
    /// - Parameters:
    ///   - url: The URL for the request
    ///   - method: The HTTP method
    ///   - account: The account to authenticate as
    /// - Returns: A URLRequest with the Authorization header set
    private func createAuthenticatedRequest(url: URL, method: String, account: SocialAccount)
        async throws -> URLRequest
    {
        var request = URLRequest(url: url)
        request.httpMethod = method

        // Ensure we have a valid token, refreshing if necessary
        let token = try await account.getValidAccessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return request
    }

    /// Creates an authenticated request for JSON-based APIs
    /// - Parameters:
    ///   - url: The URL for the request
    ///   - method: The HTTP method
    ///   - account: The account to authenticate as
    ///   - body: Optional body parameters as a dictionary
    /// - Returns: A configured URLRequest
    private func createJSONRequest(
        url: URL, method: String, account: SocialAccount, body: [String: Any]? = nil
    ) async throws -> URLRequest {
        var request = try await createAuthenticatedRequest(
            url: url, method: method, account: account)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return request
    }

    /// Ensures a server URL has the https scheme
    /// - Parameter server: The server URL string
    /// - Returns: A properly formatted server URL string
    private func formatServerURL(_ server: String) -> String {
        let lowercasedServer = server.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // If it doesn't have a scheme, add https://
        if !lowercasedServer.hasPrefix("http://") && !lowercasedServer.hasPrefix("https://") {
            return "https://" + lowercasedServer
        }

        // If it has http://, replace with https://
        if lowercasedServer.hasPrefix("http://") {
            return "https://" + lowercasedServer.dropFirst(7)
        }

        return lowercasedServer
    }

    // MARK: - Authentication

    /// Register a new application with the Mastodon server
    func registerApp(
        server: URL?, clientName: String = "SocialFusion",
        redirectURI: String = "socialfusion://oauth"
    ) async throws -> (clientId: String, clientSecret: String) {
        // Ensure the server URL has the https scheme
        let serverUrl = formatServerURL(server.asString())

        guard let url = URL(string: "\(serverUrl)/api/v1/apps") else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let parameters: [String: Any] = [
            "client_name": clientName,
            "redirect_uris": redirectURI,
            "scopes": "read write follow push",
            "website": "https://socialfusion.app",
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to register app"])
        }

        let app = try JSONDecoder().decode(MastodonApp.self, from: data)
        return (app.clientId, app.clientSecret)
    }

    /// Get the OAuth authorization URL for the user to authorize the app
    func getOAuthURL(server: URL?, clientId: String, redirectURI: String = "socialfusion://oauth")
        -> URL
    {
        // Ensure server has the scheme
        let serverUrl = formatServerURL(server.asString())
        let baseURL = "\(serverUrl)/oauth/authorize"
        let queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "read write follow push"),
        ]

        var components = URLComponents(string: baseURL)!
        components.queryItems = queryItems

        return components.url!
    }

    /// Exchange authorization code for access token
    func getAccessToken(
        server: URL?, clientId: String, clientSecret: String, code: String,
        redirectURI: String = "socialfusion://oauth"
    ) async throws -> MastodonToken {
        // Ensure server has the scheme
        let serverUrl = formatServerURL(server.asString())

        guard let url = URL(string: "\(serverUrl)/oauth/token") else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let parameters: [String: Any] = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "scope": "read write follow push",
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get access token"])
        }

        return try JSONDecoder().decode(MastodonToken.self, from: data)
    }

    /// Refresh an expired access token
    func refreshToken(server: URL?, clientId: String, clientSecret: String, refreshToken: String)
        async throws -> MastodonToken
    {
        // Ensure server has the scheme
        let serverUrl = formatServerURL(server.asString())

        guard let url = URL(string: "\(serverUrl)/oauth/token") else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let parameters: [String: Any] = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "read write follow push",
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to refresh token"])
        }

        return try JSONDecoder().decode(MastodonToken.self, from: data)
    }

    /// Get the authenticated user's account information
    func verifyCredentials(server: URL?, accessToken: String) async throws -> MastodonAccount {
        // Ensure server has the scheme
        let serverUrl = formatServerURL(server.asString())

        guard let url = URL(string: "\(serverUrl)/api/v1/accounts/verify_credentials") else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to verify credentials"])
        }

        return try JSONDecoder().decode(MastodonAccount.self, from: data)
    }

    /// Verify credentials using a SocialAccount (automatically handles token refreshing)
    func verifyCredentials(account: SocialAccount) async throws -> MastodonAccount {
        let serverUrl = formatServerURL(account.serverURL.asString())

        guard let url = URL(string: "\(serverUrl)/api/v1/accounts/verify_credentials") else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "GET", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to verify credentials"])
        }

        return try JSONDecoder().decode(MastodonAccount.self, from: data)
    }

    /// Complete OAuth authentication flow (not needed anymore, handled by OAuthManager)
    func authenticate(server: URL?) async throws -> SocialAccount {
        // This is a placeholder implementation for OAuth authentication
        throw NSError(
            domain: "MastodonService",
            code: 501,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "OAuth authentication using separate method not implemented - use OAuthManager instead"
            ]
        )
    }

    /// Legacy authenticate method for backward compatibility (will be deprecated)
    func authenticate(server: URL?, username: String, password: String) async throws
        -> SocialAccount
    {
        // Ensure proper URL format with scheme
        let serverUrl: String
        if let url = server {
            serverUrl = url.absoluteString
        } else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Server URL is required"])
        }

        // Validate the URL is properly formatted
        guard let url = URL(string: serverUrl) else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL format"])
        }

        // Extract the host part for storage
        guard let host = url.host else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Could not parse server hostname"])
        }

        // Step 1: Register the application
        let (clientId, clientSecret) = try await registerApp(server: url)

        // Instead of using password grant which is unsupported by many servers,
        // we'll use client credentials flow for testing purposes

        // Endpoint for token
        guard let tokenUrl = URL(string: "\(serverUrl)/oauth/token") else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid token URL"])
        }

        // Create request for client credentials grant
        var request = URLRequest(url: tokenUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let parameters: [String: Any] = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "client_credentials",
            "scope": "read",
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let error = errorJson["error"] as? String
            {
                throw NSError(
                    domain: "MastodonService",
                    code: (response as? HTTPURLResponse)?.statusCode ?? 400,
                    userInfo: [NSLocalizedDescriptionKey: "Authentication failed: \(error)"])
            }
            throw NSError(
                domain: "MastodonService",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to authenticate"])
        }

        // Parse token response
        let token = try JSONDecoder().decode(MastodonToken.self, from: data)

        // Create a unique ID based on server and username
        let accountId = "\(host)_\(username.hashValue)"

        // Extract a display name from the username
        let displayName: String
        if username.contains("@") {
            // If it contains @, it might be an email or a full Mastodon handle
            displayName = username.components(separatedBy: "@").first ?? username
        } else {
            // Use the username as is
            displayName = username
        }

        // Create the account with the token we received
        let account = SocialAccount(
            id: accountId,
            username: username,
            displayName: displayName,
            serverURL: host,  // Store without protocol
            platform: .mastodon
        )

        // Save authentication details
        account.saveAccessToken(token.accessToken)
        if let refreshToken = token.refreshToken {
            account.saveRefreshToken(refreshToken)
        }
        account.saveTokenExpirationDate(token.expirationDate)
        account.saveClientCredentials(clientId: clientId, clientSecret: clientSecret)

        return account
    }

    // MARK: - Timeline

    /// Fetches the home timeline for a Mastodon account
    func fetchHomeTimeline(for account: SocialAccount) async throws -> [Post] {
        let serverUrl = account.serverURL?.absoluteString ?? ""

        guard let url = URL(string: "\(serverUrl)/api/v1/timelines/home?limit=40") else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "GET", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch timeline"])
        }

        let statuses = try JSONDecoder().decode([MastodonStatus].self, from: data)
        return convertToGenericPosts(statuses: statuses)
    }

    /// Fetch the public timeline from the Mastodon API
    func fetchPublicTimeline(for account: SocialAccount, local: Bool = false) async throws -> [Post]
    {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "MastodonService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        // Check if token needs refresh
        if account.isTokenExpired, let refreshTokenStr = account.getRefreshToken(),
            let clientId = account.getClientId(), let clientSecret = account.getClientSecret()
        {
            let newToken = try await self.refreshToken(
                server: account.serverURL, clientId: clientId, clientSecret: clientSecret,
                refreshToken: refreshTokenStr)
            account.saveAccessToken(newToken.accessToken)
            account.saveRefreshToken(newToken.refreshToken ?? "")
            account.saveTokenExpirationDate(newToken.expirationDate)
        }

        // Ensure server has the scheme
        let serverUrlString = account.serverURL?.absoluteString ?? ""
        let serverUrl =
            serverUrlString.contains("://")
            ? serverUrlString : "https://\(serverUrlString)"
        let endpoint = local ? "public?local=true" : "public"
        // Fix: Changed '&limit=40' to '?limit=40' for the non-local case or append with &
        let urlString =
            local
            ? "\(serverUrl)/api/v1/timelines/\(endpoint)&limit=40"
            : "\(serverUrl)/api/v1/timelines/\(endpoint)?limit=40"

        guard let url = URL(string: urlString) else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch public timeline"])
        }

        let statuses = try JSONDecoder().decode([MastodonStatus].self, from: data)

        // Convert to our app's Post model
        return statuses.map { convertMastodonStatusToPost($0, account: account) }
    }

    /// Fetch a user's profile timeline
    func fetchUserTimeline(userId: String, for account: SocialAccount) async throws -> [Post] {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "MastodonService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        // Check if token needs refresh
        if account.isTokenExpired, let refreshTokenStr = account.getRefreshToken(),
            let clientId = account.getClientId(), let clientSecret = account.getClientSecret()
        {
            let newToken = try await self.refreshToken(
                server: account.serverURL, clientId: clientId, clientSecret: clientSecret,
                refreshToken: refreshTokenStr)
            account.saveAccessToken(newToken.accessToken)
            account.saveRefreshToken(newToken.refreshToken ?? "")
            account.saveTokenExpirationDate(newToken.expirationDate)
        }

        // Ensure server has the scheme
        let serverUrl =
            account.serverURL.asString().contains("://")
            ? account.serverURL.asString() : "https://\(account.serverURL.asString())"
        guard let url = URL(string: "\(serverUrl)/api/v1/accounts/\(userId)/statuses?limit=40")
        else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch user timeline"])
        }

        let statuses = try JSONDecoder().decode([MastodonStatus].self, from: data)

        // Convert to our app's Post model
        return statuses.map { convertMastodonStatusToPost($0, account: account) }
    }

    // MARK: - Post Actions

    /// Upload media to Mastodon
    private func uploadMedia(data: Data, account: SocialAccount) async throws -> String {
        let serverUrl = formatServerURL(account.serverURL.asString())

        guard let url = URL(string: "\(serverUrl)/api/v2/media") else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

        // Get a valid token
        let token = try await account.getValidAccessToken()

        // Create multipart form data request manually
        let boundary = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Detect image type
        let imageType = detectMediaType(data)

        // Create multipart form body
        var body = Data()

        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"upload.\(imageType.fileExtension)\"\r\n"
                .data(using: .utf8)!)
        body.append("Content-Type: \(imageType.mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)

        // End of form
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (responseData, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200 || httpResponse.statusCode == 202
        else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: responseData)
            {
                throw errorResponse
            }
            throw NSError(
                domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to upload media"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            let mediaId = json["id"] as? String
        else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse media upload response"])
        }

        return mediaId
    }

    /// Detect the type of media from its data
    private func detectMediaType(_ data: Data) -> (mimeType: String, fileExtension: String) {
        // Check for image signatures
        if data.count >= 2 {
            let header = [UInt8](data.prefix(2))

            // JPEG signature
            if header[0] == 0xFF && header[1] == 0xD8 {
                return ("image/jpeg", "jpg")
            }

            // PNG signature
            if data.count >= 8 {
                let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
                if [UInt8](data.prefix(8)) == pngSignature {
                    return ("image/png", "png")
                }
            }

            // GIF signature
            if data.count >= 6 {
                let header6 = [UInt8](data.prefix(6))
                if header6[0] == 0x47 && header6[1] == 0x49 && header6[2] == 0x46
                    && header6[3] == 0x38 && (header6[4] == 0x37 || header6[4] == 0x39)
                    && header6[5] == 0x61
                {
                    return ("image/gif", "gif")
                }
            }
        }

        // Default to JPEG if we can't determine the type
        return ("image/jpeg", "jpg")
    }

    /// Like a post
    func likePost(_ post: Post, account: SocialAccount) async throws -> Post {
        let serverUrl = formatServerURL(account.serverURL.asString())
        let statusId = post.platformSpecificId.components(separatedBy: "/").last ?? post.id

        guard let url = URL(string: "\(serverUrl)/api/v1/statuses/\(statusId)/favourite") else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL or post ID"])
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "POST", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to like post"])
        }

        let status = try JSONDecoder().decode(MastodonStatus.self, from: data)
        return convertMastodonStatusToPost(status, account: account)
    }

    /// Repost (reblog) a post on Mastodon
    func repostPost(_ post: Post, account: SocialAccount) async throws -> Post {
        let serverUrl = formatServerURL(account.serverURL.asString())
        let statusId = post.platformSpecificId.components(separatedBy: "/").last ?? post.id

        guard let url = URL(string: "\(serverUrl)/api/v1/statuses/\(statusId)/reblog") else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL or post ID"])
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "POST", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to repost"])
        }

        let status = try JSONDecoder().decode(MastodonStatus.self, from: data)
        return convertMastodonStatusToPost(status, account: account)
    }

    /// Reply to a post on Mastodon
    func replyToPost(_ post: Post, content: String, account: SocialAccount) async throws -> Post {
        let serverUrl = formatServerURL(account.serverURL.asString())
        let statusId = post.platformSpecificId.components(separatedBy: "/").last ?? post.id

        guard let url = URL(string: "\(serverUrl)/api/v1/statuses") else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

        let parameters: [String: Any] = [
            "status": content,
            "in_reply_to_id": statusId,
            "visibility": "public",
        ]

        let request = try await createJSONRequest(
            url: url, method: "POST", account: account, body: parameters)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to post reply"])
        }

        let status = try JSONDecoder().decode(MastodonStatus.self, from: data)
        return convertMastodonStatusToPost(status, account: account)
    }

    // MARK: - Helper Methods

    /// Converts Mastodon statuses to generic Post objects
    private func convertToGenericPosts(statuses: [MastodonStatus]) -> [Post] {
        return statuses.map { convertMastodonStatusToPost($0) }
    }

    /// Converts a Mastodon status to a generic Post
    private func convertMastodonStatusToPost(
        _ status: MastodonStatus, account: SocialAccount? = nil
    ) -> Post {
        // Handle reblogs (reposts)
        let originalStatus = status.reblog ?? status

        // Create author
        let author = Author(
            id: originalStatus.account.id,
            username: originalStatus.account.username,
            displayName: originalStatus.account.displayName,
            profileImageURL: URL(string: originalStatus.account.avatar),
            platform: .mastodon,
            platformSpecificId: originalStatus.account.id
        )

        // Handle media attachments
        let mediaAttachments = originalStatus.mediaAttachments.compactMap {
            attachment -> MediaAttachment? in
            guard let url = URL(string: attachment.url) else { return nil }
            return MediaAttachment(
                id: attachment.id,
                url: url,
                previewURL: URL(string: attachment.previewUrl),
                altText: attachment.description,
                type: mapMediaType(attachment.type)
            )
        }

        // Create the post
        let post = Post(
            id: originalStatus.id,
            platform: .mastodon,
            author: author,
            content: originalStatus.content,
            mediaAttachments: mediaAttachments,
            createdAt: formatDate(originalStatus.createdAt),
            likeCount: originalStatus.favouritesCount,
            repostCount: originalStatus.reblogsCount,
            replyCount: originalStatus.repliesCount,
            isLiked: originalStatus.favourited ?? false,
            isReposted: originalStatus.reblogged ?? false,
            inReplyToID: originalStatus.inReplyToId,
            platformSpecificId: originalStatus.id
        )

        return post
    }

    /// Maps Mastodon media types to our app's MediaType
    private func mapMediaType(_ mastodonType: String) -> MediaType {
        switch mastodonType {
        case "image":
            return .image
        case "video":
            return .video
        case "gifv":
            return .animatedGIF
        case "audio":
            return .audio
        default:
            return .unknown
        }
    }

    /// Format the date string from Mastodon API
    private func formatDate(_ dateString: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: dateString) {
            return date
        }

        // Try without fractional seconds if the first attempt failed
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString) ?? Date()
    }

    /// Create a new post on Mastodon
    func createPost(
        content: String, mediaAttachments: [Data] = [], visibility: PostVisibilityType = .public_,
        account: SocialAccount
    ) async throws -> Post {
        let serverUrl = formatServerURL(account.serverURL.asString())

        // First upload any media attachments
        var mediaIds: [String] = []

        for attachmentData in mediaAttachments {
            let mediaId = try await uploadMedia(
                data: attachmentData, account: account)
            mediaIds.append(mediaId)
        }

        // Then create the post with references to the media
        guard let url = URL(string: "\(serverUrl)/api/v1/statuses") else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

        // Convert app-wide visibility to Mastodon-specific visibility
        let mastodonVisibility: MastodonVisibility
        switch visibility {
        case .public_:
            mastodonVisibility = .public
        case .unlisted:
            mastodonVisibility = .unlisted
        case .private_:
            mastodonVisibility = .private
        case .direct:
            mastodonVisibility = .direct
        }

        var parameters: [String: Any] = [
            "status": content,
            "visibility": mastodonVisibility.rawValue,
        ]

        if !mediaIds.isEmpty {
            parameters["media_ids"] = mediaIds
        }

        let request = try await createJSONRequest(
            url: url, method: "POST", account: account, body: parameters)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create post"])
        }

        let status = try JSONDecoder().decode(MastodonStatus.self, from: data)
        return convertMastodonStatusToPost(status, account: account)
    }

    // MARK: - Public Access APIs

    /// Fetch trending posts from Mastodon
    func fetchTrendingPosts() async throws -> [Post] {
        // Use a major instance for trending posts
        let server = "mastodon.social"
        let serverUrl = formatServerURL(server)

        guard let url = URL(string: "\(serverUrl)/api/v1/trends/statuses") else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch trending posts"])
        }

        let statuses = try JSONDecoder().decode([MastodonStatus].self, from: data)
        return convertToGenericPosts(statuses: statuses)
    }
}

enum MastodonVisibility: String, Codable {
    case `public` = "public"
    case unlisted = "unlisted"
    case `private` = "private"
    case direct = "direct"
}

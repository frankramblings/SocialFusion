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

    /// Create an application on the Mastodon server
    private func createApplication(server: String) async throws -> (String, String) {
        return try await registerApp(server: URL(string: server))
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

    /// Get access token using username/password (for direct authentication)
    func getAccessToken(
        server: String,
        username: String,
        password: String,
        clientId: String,
        clientSecret: String
    ) async throws -> String {
        // Ensure server has the scheme
        let serverUrl = formatServerURL(server)

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
            "grant_type": "password",
            "username": username,
            "password": password,
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

        let token = try JSONDecoder().decode(MastodonToken.self, from: data)
        return token.accessToken
    }

    /// Get user information from the Mastodon API
    private func getUserInfo(server: String, accessToken: String) async throws -> MastodonAccount {
        return try await verifyCredentials(server: URL(string: server), accessToken: accessToken)
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

        let mastodonAccount = try JSONDecoder().decode(MastodonAccount.self, from: data)

        // Create and return a new SocialAccount with the verified information
        let verifiedAccount = SocialAccount(
            id: mastodonAccount.id,
            username: mastodonAccount.username,
            displayName: mastodonAccount.displayName ?? mastodonAccount.username,
            serverURL: serverUrl,
            platform: .mastodon,
            profileImageURL: URL(string: mastodonAccount.avatar),
            platformSpecificId: mastodonAccount.id
        )

        // Make sure to explicitly set the access token on the verified account
        verifiedAccount.accessToken = accessToken

        // Post notification about the profile image update if we have an avatar URL
        if let avatarURL = URL(string: mastodonAccount.avatar) {
            print("Found Mastodon avatar URL: \(avatarURL)")
            NotificationCenter.default.post(
                name: Notification.Name("ProfileImageUpdated"),
                object: nil,
                userInfo: ["accountId": verifiedAccount.id, "profileImageURL": avatarURL]
            )
        }

        return mastodonAccount
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

    /// Authenticate with Mastodon and return a SocialAccount
    func authenticate(server: URL?, username: String, password: String) async throws
        -> SocialAccount
    {
        // Ensure server URL has proper scheme
        let serverStr = formatServerURL(server?.absoluteString ?? "mastodon.social")

        // Create application if needed
        let (clientId, clientSecret) = try await createApplication(server: serverStr)

        // Get access token
        let accessToken = try await getAccessToken(
            server: serverStr,
            username: username,
            password: password,
            clientId: clientId,
            clientSecret: clientSecret
        )

        // Get user info
        let userInfo = try await getUserInfo(server: serverStr, accessToken: accessToken)

        // Create account with default avatar
        let account = createAccount(
            from: userInfo,
            serverStr: serverStr,
            accessToken: accessToken,
            clientId: clientId,
            clientSecret: clientSecret
        )

        // Post notification about the profile image update if we have an avatar URL
        if let avatarURL = account.profileImageURL {
            print("Found Mastodon avatar URL during authentication: \(avatarURL)")
            NotificationCenter.default.post(
                name: Notification.Name("ProfileImageUpdated"),
                object: nil,
                userInfo: ["accountId": account.id, "profileImageURL": avatarURL]
            )
        }

        return account
    }

    /// Verify access token and get account information
    func verifyAndCreateAccount(account: SocialAccount) async throws -> SocialAccount {
        guard let accessToken = account.getAccessToken(), !accessToken.isEmpty else {
            throw NSError(
                domain: "MastodonService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No valid access token provided"])
        }

        // Ensure server URL has proper scheme
        let serverUrlString =
            account.serverURL.asString().contains("://")
            ? account.serverURL.asString()
            : "https://" + account.serverURL.asString()

        guard let serverUrl = URL(string: serverUrlString) else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [
                    NSLocalizedDescriptionKey: "Invalid server URL: \(account.serverURL.asString())"
                ])
        }

        let verifyUrl = serverUrl.appendingPathComponent("api/v1/accounts/verify_credentials")

        var request = URLRequest(url: verifyUrl)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            print("Verifying Mastodon credentials at: \(verifyUrl)")
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(
                    domain: "MastodonService",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
            }

            guard httpResponse.statusCode == 200 else {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                print(
                    "Mastodon verification failed: \(errorText), Status code: \(httpResponse.statusCode)"
                )
                throw NSError(
                    domain: "MastodonService",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Verification failed: \(errorText)"])
            }

            let mastodonAccount = try JSONDecoder().decode(MastodonAccount.self, from: data)
            print("Successfully verified Mastodon account: \(mastodonAccount.username)")

            // Create a new account with the verified information
            let verifiedAccount = SocialAccount(
                id: mastodonAccount.id,
                username: mastodonAccount.username,
                displayName: mastodonAccount.displayName ?? mastodonAccount.username,
                serverURL: serverUrl.absoluteString,
                platform: .mastodon,
                profileImageURL: URL(string: mastodonAccount.avatar),
                platformSpecificId: mastodonAccount.id
            )

            // Set the access token
            verifiedAccount.accessToken = accessToken

            // Post notification about the profile image update if we have an avatar URL
            if let avatarURL = URL(string: mastodonAccount.avatar) {
                print("Found Mastodon avatar URL during verification: \(avatarURL)")
                NotificationCenter.default.post(
                    name: Notification.Name("ProfileImageUpdated"),
                    object: nil,
                    userInfo: ["accountId": verifiedAccount.id, "profileImageURL": avatarURL]
                )
            }

            return verifiedAccount
        } catch {
            print("Error verifying Mastodon credentials: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Timeline

    /// Fetches the home timeline for a Mastodon account
    func fetchHomeTimeline(for account: SocialAccount) async throws -> [Post] {
        // Check if we have a valid access token
        guard let accessToken = account.getAccessToken(), !accessToken.isEmpty else {
            print("No valid token available for Mastodon account: \(account.username)")
            throw NSError(
                domain: "MastodonService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No valid token available"])
        }

        // Ensure server URL has proper scheme
        let serverUrl =
            account.serverURL.asString().contains("://")
            ? account.serverURL.asString()
            : "https://" + account.serverURL.asString()

        // Construct the URL for the home timeline endpoint
        guard let url = URL(string: "\(serverUrl)/api/v1/timelines/home?limit=40") else {
            print("Invalid server URL for Mastodon timeline: \(serverUrl)")
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

        // Check if token needs refresh
        if account.isTokenExpired,
            let refreshToken = account.getRefreshToken(),
            let clientId = account.getClientId(),
            let clientSecret = account.getClientSecret()
        {
            do {
                let newToken = try await self.refreshToken(
                    server: account.serverURL,
                    clientId: clientId,
                    clientSecret: clientSecret,
                    refreshToken: refreshToken)

                account.saveAccessToken(newToken.accessToken)
                account.saveRefreshToken(newToken.refreshToken ?? "")
                account.saveTokenExpirationDate(newToken.expirationDate)
                print("Successfully refreshed token for \(account.username)")
            } catch {
                print("Failed to refresh token: \(error.localizedDescription)")
                // Continue with the existing token
            }
        }

        print("Fetching Mastodon timeline from: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(
                    domain: "MastodonService",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
            }

            if httpResponse.statusCode != 200 {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("Mastodon API error: \(errorText), Status code: \(httpResponse.statusCode)")

                if httpResponse.statusCode == 401 {
                    throw NSError(
                        domain: "MastodonService",
                        code: 401,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Authentication failed: Invalid or expired token"
                        ])
                }

                throw NSError(
                    domain: "MastodonService",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to fetch timeline: \(errorText)"])
            }

            // Parse the timeline data
            let statuses = try JSONDecoder().decode([MastodonStatus].self, from: data)

            // Convert to our app's Post model
            let posts = statuses.map { convertMastodonStatusToPost($0, account: account) }
            print("Successfully fetched \(posts.count) Mastodon posts for \(account.username)")
            return posts
        } catch {
            print("Error fetching Mastodon timeline: \(error.localizedDescription)")
            throw error
        }
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

        // Extract status ID from the post's originalURL if available
        var statusId = post.id
        if let lastPathComponent = URL(string: post.originalURL)?.lastPathComponent {
            statusId = lastPathComponent
        }

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

        // Extract status ID from the post's originalURL if available
        var statusId = post.id
        if let lastPathComponent = URL(string: post.originalURL)?.lastPathComponent {
            statusId = lastPathComponent
        }

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

        // Extract status ID from the post's originalURL if available
        var statusId = post.id
        if let lastPathComponent = URL(string: post.originalURL)?.lastPathComponent {
            statusId = lastPathComponent
        }

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
        let attachments = status.mediaAttachments.compactMap { media -> Post.Attachment? in
            return Post.Attachment(
                url: media.url,
                type: media.type == "image" ? .image : .video,
                altText: media.description ?? ""
            )
        }

        let mentions = status.mentions.compactMap { mention -> String in
            return mention.username
        }

        let tags = status.tags.compactMap { tag -> String in
            return tag.name
        }

        let authorName = status.account.displayName
        let authorUsername = status.account.username
        let authorProfilePictureURL = status.account.avatar

        return Post(
            id: status.id,
            content: status.content,
            authorName: authorName,
            authorUsername: authorUsername,
            authorProfilePictureURL: authorProfilePictureURL,
            createdAt: ISO8601DateFormatter().date(from: status.createdAt) ?? Date(),
            platform: .mastodon,
            originalURL: status.url ?? "",
            attachments: attachments,
            mentions: mentions,
            tags: tags
        )
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
        content: String, mediaAttachments: [Data] = [], visibility: String = "public",
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

        var parameters: [String: Any] = [
            "status": content,
            "visibility": visibility,
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

    // Try to fetch the profile image data
    private func updateProfileImage(for account: SocialAccount) async {
        do {
            guard let serverStr = account.serverURL?.absoluteString else {
                print("No server URL found for account")
                return
            }

            let endpoint = "https://\(serverStr)/api/v1/accounts/verify_credentials"
            var request = URLRequest(url: URL(string: endpoint)!)

            if let accessToken = account.getAccessToken() {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }

            let (data, _) = try await URLSession.shared.data(for: request)
            let mastodonAccount = try JSONDecoder().decode(MastodonAccount.self, from: data)

            if let avatarURL = URL(string: mastodonAccount.avatar) {
                print("Found Mastodon avatar URL: \(avatarURL)")
                account.profileImageURL = avatarURL
                print("Updated Mastodon account with new profile image URL")
            }
        } catch {
            print("Error fetching Mastodon profile: \(error)")
        }
    }

    private func createAccount(
        from userInfo: MastodonAccount,
        serverStr: String,
        accessToken: String,
        clientId: String,
        clientSecret: String
    ) -> SocialAccount {
        // Generate a default avatar URL using the displayName
        let displayName = userInfo.displayName.isEmpty ? userInfo.username : userInfo.displayName
        let defaultAvatarURL = URL(
            string:
                "https://ui-avatars.com/api/?name=\(displayName.replacingOccurrences(of: " ", with: "+"))&background=random"
        )
        print("Setting default Mastodon avatar URL: \(String(describing: defaultAvatarURL))")

        // Create account with default avatar
        let account = SocialAccount(
            id: userInfo.id,
            username: userInfo.username,
            displayName: displayName,
            serverURL: URL(string: serverStr),
            platform: .mastodon,
            profileImageURL: defaultAvatarURL
        )

        // Store credentials
        account.saveAccessToken(accessToken)
        account.saveClientCredentials(clientId: clientId, clientSecret: clientSecret)
        account.saveTokenExpirationDate(Date().addingTimeInterval(2 * 60 * 60))  // 2 hours

        // Try to fetch the actual profile image
        if let avatarURL = URL(string: userInfo.avatar) {
            account.profileImageURL = avatarURL
            print("Updated Mastodon profile image URL: \(avatarURL.absoluteString)")
        }

        return account
    }
}

// Define notification names if not already defined elsewhere
/* Commenting out duplicate declarations
extension Notification.Name {
    static let profileImageUpdated = Notification.Name("AccountProfileImageUpdated")
    static let accountUpdated = Notification.Name("AccountUpdated")
}
*/

enum MastodonVisibility: String, Codable {
    case `public` = "public"
    case unlisted = "unlisted"
    case `private` = "private"
    case direct = "direct"
}

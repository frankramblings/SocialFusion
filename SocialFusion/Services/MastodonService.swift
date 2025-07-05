import Combine
import Foundation
/// A service for interacting with the Mastodon API
import SwiftUI
// Import utilities
import UIKit
import os.log

// MARK: - Thread Safety Note
/*
 IMPORTANT: When updating any @Published properties or UI state, always use:

 await MainActor.run {
    // Update UI state here
 }

 This ensures thread safety and prevents EXC_BAD_ACCESS crashes when modifying
 state from background threads.
*/

// Add URL extension for optional URL
extension Optional where Wrapped == URL {
    func asString() -> String {
        return self?.absoluteString ?? ""
    }
}

public class MastodonService {
    private let session = URLSession.shared
    private let logger = Logger(subsystem: "com.socialfusion.app", category: "MastodonService")

    // MARK: - Authentication Utilities

    /// Creates an authenticated request with automatic token refresh
    private func createAuthenticatedRequest(
        url: URL,
        method: String,
        account: SocialAccount,
        body: Data? = nil
    ) async throws -> URLRequest {
        // Get a valid access token (automatically refreshes if needed)
        let accessToken = try await account.getValidAccessToken()

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            request.httpBody = body
        }

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

        // Handle empty string case
        if lowercasedServer.isEmpty {
            return "https://mastodon.social"
        }

        // If it doesn't have a scheme, add https://
        if !lowercasedServer.hasPrefix("http://") && !lowercasedServer.hasPrefix("https://") {
            return "https://" + lowercasedServer
        }

        // If it has http://, replace with https://
        if lowercasedServer.hasPrefix("http://") {
            return "https://" + lowercasedServer.dropFirst(7)
        }

        // Handle potential URL formatting issues
        var formattedURL = lowercasedServer

        // Check for malformed URLs with extra slashes after the domain
        if formattedURL.contains("://") {
            let parts = formattedURL.components(separatedBy: "://")
            if parts.count == 2 {
                let scheme = parts[0]
                var domain = parts[1]

                // Fix domain part if it has excessive slashes
                if domain.contains("//") {
                    domain = domain.replacingOccurrences(of: "//", with: "/")
                }

                formattedURL = "\(scheme)://\(domain)"
            }
        }

        // Ensure we have the proper https:// prefix
        if formattedURL.hasPrefix("https:/") && !formattedURL.hasPrefix("https://") {
            formattedURL = "https://" + formattedURL.dropFirst(7)
        }

        return formattedURL
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

    /// Minimal token refresh method that works without client credentials
    /// Some Mastodon instances allow refresh without client credentials
    private func refreshMastodonTokenMinimal(
        server: String,
        refreshToken: String
    ) async throws -> MastodonToken {
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

        // Minimal parameters - some instances support this
        let parameters: [String: Any] = [
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
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to refresh token - may need re-authentication"
                ])
        }

        return try JSONDecoder().decode(MastodonToken.self, from: data)
    }

    /// Simplified method to refresh access token for an account
    /// Returns only the new access token and handles all the internal details
    public func refreshAccessToken(for account: SocialAccount) async throws -> String {
        guard let serverURL = account.serverURL else {
            throw TokenError.invalidServer
        }

        guard let refreshToken = account.refreshToken else {
            logger.warning(
                "No refresh token available for account \(account.username). Cannot refresh - user needs to re-authenticate."
            )
            throw TokenError.noRefreshToken
        }

        do {
            // Get client credentials for this account
            let (clientId, clientSecret) = account.getClientCredentials()

            let token: MastodonToken

            if let clientId = clientId, let clientSecret = clientSecret {
                // Use full refresh with client credentials
                logger.info(
                    "Refreshing Mastodon token with client credentials for \(account.username)")
                token = try await refreshMastodonToken(
                    server: serverURL.absoluteString,
                    clientId: clientId,
                    clientSecret: clientSecret,
                    refreshToken: refreshToken
                )
            } else {
                // Fall back to minimal refresh without client credentials
                logger.warning(
                    "No client credentials found for \(account.username), trying minimal refresh")
                token = try await refreshMastodonTokenMinimal(
                    server: serverURL.absoluteString,
                    refreshToken: refreshToken
                )
            }

            account.saveAccessToken(token.accessToken)
            if let newRefreshToken = token.refreshToken {
                account.saveRefreshToken(newRefreshToken)
            }

            // Use server-provided expiration or fallback to 30 days (more realistic than 7 days)
            // Many Mastodon instances provide tokens that last weeks or months
            let expiresIn = token.expiresIn ?? (30 * 24 * 60 * 60)
            account.saveTokenExpirationDate(Date().addingTimeInterval(TimeInterval(expiresIn)))

            return token.accessToken
        } catch {
            logger.error("Failed to refresh Mastodon token: \(error.localizedDescription)")
            throw TokenError.refreshFailed
        }
    }

    /// Refreshes a Mastodon token using the refresh token flow
    private func refreshMastodonToken(
        server: String,
        clientId: String,
        clientSecret: String,
        refreshToken: String
    ) async throws -> MastodonToken {
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
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            // Try to decode error response for better error messages
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }

            // Provide more specific error messages based on status code
            let errorMessage: String
            switch statusCode {
            case 401:
                errorMessage = "Invalid access token. Please check your credentials."
            case 403:
                errorMessage = "Access forbidden. Your token may not have the required permissions."
            case 404:
                errorMessage = "Server not found. Please check the server URL."
            case 422:
                errorMessage = "Invalid request format. Please check your server URL."
            default:
                errorMessage = "Failed to verify credentials (HTTP \(statusCode))"
            }

            throw NSError(
                domain: "MastodonService",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }

        return try JSONDecoder().decode(MastodonAccount.self, from: data)
    }

    /// Verify credentials using a SocialAccount (automatically handles token refreshing)
    func verifyCredentials(account: SocialAccount) async throws -> MastodonAccount {
        let serverUrl = formatServerURL(
            account.serverURL?.absoluteString ?? "")

        guard let url = URL(string: "\(serverUrl)/api/v1/accounts/verify_credentials") else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Invalid server URL: \(account.serverURL?.absoluteString ?? "")"
                ])
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

    /// Authenticate with the Mastodon API and get account information
    /// - Parameters:
    ///   - server: Mastodon server URL
    ///   - username: Username or email
    ///   - password: Password
    /// - Returns: A SocialAccount object
    public func authenticate(server: URL?, username: String, password: String) async throws
        -> SocialAccount
    {
        // In a real implementation, this would use OAuth to authenticate
        // and fetch the user info from the Mastodon API

        let id = UUID().uuidString
        let account = SocialAccount(
            id: id,
            username: username,
            displayName: username.components(separatedBy: "@").first ?? username,
            serverURL: server?.absoluteString ?? "mastodon.social",
            platform: .mastodon,
            accessToken: "mock_access_token"
        )

        return account
    }

    /// Authenticate with a Mastodon server using an existing access token
    /// - Parameters:
    ///   - server: The Mastodon server URL
    ///   - accessToken: The access token to use for authentication
    /// - Returns: A SocialAccount object
    public func authenticateWithToken(server: URL, accessToken: String) async throws
        -> SocialAccount
    {
        // Format the server URL properly
        let serverUrlStr = server.absoluteString
        let formattedServerURL =
            serverUrlStr.contains("://") ? serverUrlStr : "https://" + serverUrlStr

        // Verify the account's credentials with the Mastodon API
        print("Verifying Mastodon credentials with server: \(formattedServerURL)")
        let mastodonAccount = try await verifyCredentials(
            server: URL(string: formattedServerURL),
            accessToken: accessToken
        )

        // Create a SocialAccount with the verified details
        let verifiedAccount = SocialAccount(
            id: mastodonAccount.id,
            username: mastodonAccount.username,
            displayName: mastodonAccount.displayName,
            serverURL: formattedServerURL,
            platform: .mastodon,
            accessToken: accessToken,
            profileImageURL: URL(string: mastodonAccount.avatar),
            platformSpecificId: mastodonAccount.id
        )

        // Save the access token securely
        verifiedAccount.saveAccessToken(accessToken)

        // Set a more realistic default expiration time (30 days) if none provided
        // Most Mastodon instances provide tokens that last weeks or months
        if verifiedAccount.tokenExpirationDate == nil {
            verifiedAccount.saveTokenExpirationDate(Date().addingTimeInterval(30 * 24 * 60 * 60))
        }

        print("Successfully verified Mastodon account: \(mastodonAccount.username)")
        return verifiedAccount
    }

    /// Verifies credentials and creates a social account with the provided access token
    func verifyAndCreateAccount(account: SocialAccount) async throws -> SocialAccount {
        print(
            "Verifying credentials for Mastodon account with server: \(account.serverURL?.absoluteString ?? "unknown")"
        )

        // Make sure we have an access token
        guard let accessToken = account.getAccessToken(), !accessToken.isEmpty else {
            print("No access token provided")
            throw NSError(
                domain: "MastodonService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token provided"]
            )
        }

        // Make sure we have a server URL
        guard let serverURL = account.serverURL else {
            print("No server URL provided")
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "No server URL provided"]
            )
        }

        // Format the server URL properly
        let serverUrlStr = serverURL.absoluteString
        let formattedServerURL =
            serverUrlStr.contains("://") ? serverUrlStr : "https://" + serverUrlStr

        // Verify the account's credentials with the Mastodon API
        print("Verifying Mastodon credentials with server: \(formattedServerURL)")
        guard
            let mastodonAccount = try? await verifyCredentials(
                server: URL(string: formattedServerURL),
                accessToken: accessToken
            )
        else {
            print("Failed to verify Mastodon credentials")
            throw NSError(
                domain: "MastodonService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Invalid access token or server URL"]
            )
        }

        // Create a SocialAccount with the verified details
        let verifiedAccount = SocialAccount(
            id: mastodonAccount.id,
            username: mastodonAccount.username,
            displayName: mastodonAccount.displayName,
            serverURL: formattedServerURL,
            platform: .mastodon,
            accessToken: accessToken,
            profileImageURL: URL(string: mastodonAccount.avatar),
            platformSpecificId: mastodonAccount.id
        )

        // Save the access token securely
        verifiedAccount.saveAccessToken(accessToken)

        // Set a more realistic default expiration time (30 days) if none provided
        // Most Mastodon instances provide tokens that last weeks or months
        if verifiedAccount.tokenExpirationDate == nil {
            verifiedAccount.saveTokenExpirationDate(Date().addingTimeInterval(30 * 24 * 60 * 60))
        }

        print("Successfully verified Mastodon account: \(mastodonAccount.username)")
        return verifiedAccount
    }

    // MARK: - Timeline

    /// Fetch the home timeline from the Mastodon API
    public func fetchHomeTimeline(for account: SocialAccount, limit: Int = 40, maxId: String? = nil)
        async throws
        -> TimelineResult
    {
        guard account.platform == .mastodon else {
            throw ServiceError.invalidAccount(reason: "Account is not a Mastodon account")
        }

        guard let token = account.getAccessToken() else {
            logger.error("No access token available for Mastodon account: \(account.username)")
            throw ServiceError.unauthorized("No access token available")
        }

        // Ensure server has the scheme
        let serverUrlString = account.serverURL?.absoluteString ?? ""
        let serverUrl =
            serverUrlString.contains("://")
            ? serverUrlString : "https://\(serverUrlString)"

        // Create URL with pagination parameters
        var urlString = "\(serverUrl)/api/v1/timelines/home?limit=\(limit)"
        if let maxId = maxId {
            urlString += "&max_id=\(maxId)"
        }

        guard let url = URL(string: urlString) else {
            logger.error("Invalid Mastodon API URL: \(urlString)")
            throw ServiceError.invalidInput(reason: "Invalid server URL")
        }

        logger.info("Fetching Mastodon timeline from: \(urlString)")

        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            // Check if token needs refresh
            if account.isTokenExpired, account.getRefreshToken() != nil {
                logger.info("Refreshing expired Mastodon token for: \(account.username)")
                // Note: Token refresh requires client credentials which may not be available
                // For now, we'll continue with the existing token
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
                throw ServiceError.apiError(
                    "Server returned status code \(httpResponse.statusCode)")
            }

            // Decode the response
            let statuses = try JSONDecoder().decode([MastodonStatus].self, from: data)

            // Convert to post models
            let posts = statuses.map { convertMastodonStatusToPost($0, account: account) }

            // Determine pagination info - Mastodon has more pages if we get the full limit
            let hasNextPage = posts.count >= limit
            let nextPageToken = posts.last?.id

            let pagination = PaginationInfo(hasNextPage: hasNextPage, nextPageToken: nextPageToken)

            return TimelineResult(posts: posts, pagination: pagination)
        } catch {
            print("Error fetching Mastodon timeline: \(error.localizedDescription)")
            throw ServiceError.timelineError(underlying: error)
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
        if account.isTokenExpired, account.getRefreshToken() != nil {
            print("Token refresh is needed but client credentials are not available")
            // Without client credentials, refresh isn't possible
            // Continue with existing token
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

    /// Fetch the public timeline from the Mastodon API without requiring an account
    /// Useful for fetching trending posts when the user has no accounts
    /// - Parameters:
    ///   - serverURL: The Mastodon server URL to fetch from
    ///   - count: Number of posts to fetch (defaults to 20)
    ///   - local: Whether to fetch only local posts
    /// - Returns: An array of Post objects
    func fetchPublicTimeline(serverURL: URL, count: Int = 20, local: Bool = false) async throws
        -> [Post]
    {
        // Ensure server has the scheme
        let serverUrlString = serverURL.absoluteString
        let serverUrl = formatServerURL(serverUrlString)

        let endpoint = local ? "public?local=true" : "public"
        let limitParam = local ? "&limit=\(count)" : "?limit=\(count)"
        let urlString = "\(serverUrl)/api/v1/timelines/\(endpoint)\(limitParam)"

        guard let url = URL(string: urlString) else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // This is a public API so no auth required

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "MastodonService",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch public timeline"])
        }

        let statuses = try JSONDecoder().decode([MastodonStatus].self, from: data)

        // Create a fake account for the server (only used for display purposes)
        let serverAccount = SocialAccount(
            id: "mastodon-\(serverURL.host ?? "unknown")",
            username: "public",
            displayName: nil,
            serverURL: serverURL,
            platform: .mastodon)

        // Convert to our app's Post model
        return statuses.map { convertMastodonStatusToPost($0, account: serverAccount) }
    }

    /// Fetch a user's profile timeline
    func fetchUserTimeline(userId: String, for account: SocialAccount) async throws -> [Post] {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "MastodonService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        // Check if token needs refresh
        if account.isTokenExpired, account.getRefreshToken() != nil {
            print("Token refresh is needed but client credentials are not available")
            // Without client credentials, refresh isn't possible
            // Continue with existing token
        }

        // Ensure server has the scheme
        let serverUrl = account.serverURL?.absoluteString ?? ""
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
        let serverUrl = formatServerURL(
            account.serverURL?.absoluteString ?? "")

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
        let serverUrl = formatServerURL(
            account.serverURL?.absoluteString ?? "")

        // For boost posts, we need to like the original post, not the wrapper
        let targetPost = post.originalPost ?? post

        // Use platformSpecificId as the primary source for status ID
        // Only fall back to URL extraction if platformSpecificId is not a valid number
        var statusId = targetPost.platformSpecificId

        // Validate that platformSpecificId looks like a Mastodon status ID (numeric)
        if !statusId.allSatisfy({ $0.isNumber }) {
            // If platformSpecificId doesn't look like a status ID, try URL extraction
            if let lastPathComponent = URL(string: targetPost.originalURL)?.lastPathComponent {
                statusId = lastPathComponent
            }
        }

        print(
            "[Mastodon] Attempting to like post: id=\(targetPost.id), platformSpecificId=\(targetPost.platformSpecificId), originalURL=\(targetPost.originalURL)"
        )
        print("[Mastodon] Using statusId: \(statusId)")

        guard let url = URL(string: "\(serverUrl)/api/v1/statuses/\(statusId)/favourite") else {
            print(
                "[Mastodon] Failed to create URL: \(serverUrl)/api/v1/statuses/\(statusId)/favourite"
            )
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL or post ID"])
        }

        print("[Mastodon] Like URL: \(url.absoluteString)")

        let request = try await createAuthenticatedRequest(
            url: url, method: "POST", account: account)
        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            print("[Mastodon] Like response status: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                if let responseBody = String(data: data, encoding: .utf8) {
                    print("[Mastodon] Like error response: \(responseBody)")
                }
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[Mastodon] Invalid HTTP response received")
            throw NSError(
                domain: "MastodonService",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }

        guard httpResponse.statusCode == 200 else {
            print("[Mastodon] HTTP error status: \(httpResponse.statusCode)")

            // Try to decode server error response
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                print("[Mastodon] Server error: \(errorResponse.error)")
                throw NSError(
                    domain: "MastodonService",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: errorResponse.error])
            }

            // If we can't decode the error, provide a generic message
            let errorMessage = "Failed to like post (HTTP \(httpResponse.statusCode))"
            print("[Mastodon] \(errorMessage)")
            throw NSError(
                domain: "MastodonService",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }

        // Try to decode the successful response
        do {
            let status = try JSONDecoder().decode(MastodonStatus.self, from: data)
            print("[Mastodon] Successfully liked post: \(status.id)")
            return await self.convertMastodonStatusToPost(status, account: account)
        } catch {
            print("[Mastodon] Failed to decode like response: \(error)")
            if let responseBody = String(data: data, encoding: .utf8) {
                print("[Mastodon] Response body: \(responseBody)")
            }
            throw NSError(
                domain: "MastodonService",
                code: 500,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to decode like response: \(error.localizedDescription)"
                ])
        }
    }

    /// Unlike a post
    func unlikePost(_ post: Post, account: SocialAccount) async throws -> Post {
        let serverUrl = formatServerURL(
            account.serverURL?.absoluteString ?? "")

        // For boost posts, we need to unlike the original post, not the wrapper
        let targetPost = post.originalPost ?? post

        // Use platformSpecificId as the primary source for status ID
        // Only fall back to URL extraction if platformSpecificId is not a valid number
        var statusId = targetPost.platformSpecificId

        // Validate that platformSpecificId looks like a Mastodon status ID (numeric)
        if !statusId.allSatisfy({ $0.isNumber }) {
            // If platformSpecificId doesn't look like a status ID, try URL extraction
            if let lastPathComponent = URL(string: targetPost.originalURL)?.lastPathComponent {
                statusId = lastPathComponent
            }
        }

        print(
            "[Mastodon] Attempting to unlike post: id=\(targetPost.id), platformSpecificId=\(targetPost.platformSpecificId), originalURL=\(targetPost.originalURL)"
        )
        print("[Mastodon] Using statusId: \(statusId)")

        guard let url = URL(string: "\(serverUrl)/api/v1/statuses/\(statusId)/unfavourite") else {
            print(
                "[Mastodon] Failed to create URL: \(serverUrl)/api/v1/statuses/\(statusId)/unfavourite"
            )
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL or post ID"])
        }

        print("[Mastodon] Unlike URL: \(url.absoluteString)")

        let request = try await createAuthenticatedRequest(
            url: url, method: "POST", account: account)
        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            print("[Mastodon] Unlike response status: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                if let responseBody = String(data: data, encoding: .utf8) {
                    print("[Mastodon] Unlike error response: \(responseBody)")
                }
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[Mastodon] Invalid HTTP response received for unlike")
            throw NSError(
                domain: "MastodonService",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }

        guard httpResponse.statusCode == 200 else {
            print("[Mastodon] HTTP error status for unlike: \(httpResponse.statusCode)")

            // Try to decode server error response
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                print("[Mastodon] Server error for unlike: \(errorResponse.error)")
                throw NSError(
                    domain: "MastodonService",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: errorResponse.error])
            }

            // If we can't decode the error, provide a generic message
            let errorMessage = "Failed to unlike post (HTTP \(httpResponse.statusCode))"
            print("[Mastodon] \(errorMessage)")
            throw NSError(
                domain: "MastodonService",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }

        // Try to decode the successful response
        do {
            let status = try JSONDecoder().decode(MastodonStatus.self, from: data)
            print("[Mastodon] Successfully unliked post: \(status.id)")
            return await self.convertMastodonStatusToPost(status, account: account)
        } catch {
            print("[Mastodon] Failed to decode unlike response: \(error)")
            if let responseBody = String(data: data, encoding: .utf8) {
                print("[Mastodon] Response body: \(responseBody)")
            }
            throw NSError(
                domain: "MastodonService",
                code: 500,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to decode unlike response: \(error.localizedDescription)"
                ])
        }
    }

    /// Repost (reblog) a post on Mastodon
    func repostPost(_ post: Post, account: SocialAccount) async throws -> Post {
        let serverUrl = formatServerURL(
            account.serverURL?.absoluteString ?? "")

        // For boost posts, we need to repost the original post, not the wrapper
        let targetPost = post.originalPost ?? post

        // Use platformSpecificId as the primary source for status ID
        // Only fall back to URL extraction if platformSpecificId is not a valid number
        var statusId = targetPost.platformSpecificId

        // Validate that platformSpecificId looks like a Mastodon status ID (numeric)
        if !statusId.allSatisfy({ $0.isNumber }) {
            // If platformSpecificId doesn't look like a status ID, try URL extraction
            if let lastPathComponent = URL(string: targetPost.originalURL)?.lastPathComponent {
                statusId = lastPathComponent
            }
        }

        print(
            "[Mastodon] Attempting to repost post: id=\(targetPost.id), platformSpecificId=\(targetPost.platformSpecificId), originalURL=\(targetPost.originalURL)"
        )
        print("[Mastodon] Using statusId: \(statusId)")

        guard let url = URL(string: "\(serverUrl)/api/v1/statuses/\(statusId)/reblog") else {
            print(
                "[Mastodon] Failed to create reblog URL: \(serverUrl)/api/v1/statuses/\(statusId)/reblog"
            )
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL or post ID"])
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "POST", account: account)
        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            print("[Mastodon] Repost response status: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                if let responseBody = String(data: data, encoding: .utf8) {
                    print("[Mastodon] Repost error response: \(responseBody)")
                }
            }
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to repost"])
        }

        let status = try JSONDecoder().decode(MastodonStatus.self, from: data)
        return await self.convertMastodonStatusToPost(status, account: account)
    }

    /// Unrepost (unreblog) a post on Mastodon
    func unrepostPost(_ post: Post, account: SocialAccount) async throws -> Post {
        let serverUrl = formatServerURL(
            account.serverURL?.absoluteString ?? "")

        // For boost posts, we need to unrepost the original post, not the wrapper
        let targetPost = post.originalPost ?? post

        // Use platformSpecificId as the primary source for status ID
        // Only fall back to URL extraction if platformSpecificId is not a valid number
        var statusId = targetPost.platformSpecificId

        // Validate that platformSpecificId looks like a Mastodon status ID (numeric)
        if !statusId.allSatisfy({ $0.isNumber }) {
            // If platformSpecificId doesn't look like a status ID, try URL extraction
            if let lastPathComponent = URL(string: targetPost.originalURL)?.lastPathComponent {
                statusId = lastPathComponent
            }
        }

        guard let url = URL(string: "\(serverUrl)/api/v1/statuses/\(statusId)/unreblog") else {
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
                userInfo: [NSLocalizedDescriptionKey: "Failed to unrepost"])
        }

        let status = try JSONDecoder().decode(MastodonStatus.self, from: data)
        return await self.convertMastodonStatusToPost(status, account: account)
    }

    /// Reply to a post on Mastodon
    func replyToPost(_ post: Post, content: String, account: SocialAccount) async throws -> Post {
        let serverUrl = formatServerURL(
            account.serverURL?.absoluteString ?? "")

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
        return await self.convertMastodonStatusToPost(status, account: account)
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
        // Move the replyToUsername logic to the top of the function
        var replyToUsername: String? = nil
        if let replyToAccountId = status.inReplyToAccountId, let replyToId = status.inReplyToId {
            // Improved reply username extraction logic
            if let mention = status.mentions.first(where: { $0.id == replyToAccountId }) {
                replyToUsername = mention.username
            } else if let firstMention = status.mentions.first {
                replyToUsername = firstMention.username
            } else if !status.mentions.isEmpty {
                replyToUsername = status.mentions.first?.username
            }
        }

        // Check if this is a reblog/boost
        if let reblog = status.reblog {
            var originalPost = Post(
                id: reblog.id,
                content: reblog.content,
                authorName: reblog.account.displayName,
                authorUsername: reblog.account.acct,
                authorProfilePictureURL: reblog.account.avatar,
                createdAt: DateParser.parse(reblog.createdAt) ?? Date.distantPast,
                platform: .mastodon,
                originalURL: reblog.url ?? "",
                attachments: reblog.mediaAttachments.compactMap { media in
                    return Post.Attachment(
                        url: media.url,
                        type: media.type == "image"
                            ? .image
                            : media.type == "video"
                                ? .video : media.type == "gifv" ? .gifv : .audio,
                        altText: media.description
                    )
                },
                mentions: reblog.mentions.compactMap { $0.username },
                tags: reblog.tags.compactMap { $0.name },
                isReposted: reblog.reblogged ?? false,
                isLiked: reblog.favourited ?? false,
                likeCount: reblog.favouritesCount,
                repostCount: reblog.reblogsCount,
                replyCount: reblog.repliesCount,  // Add reply count
                platformSpecificId: reblog.id,
                blueskyLikeRecordURI: nil,  // Mastodon doesn't use Bluesky record URIs
                blueskyRepostRecordURI: nil
            )

            // Hydrate originalPost if content is empty (defensive, rare)
            if originalPost.content.isEmpty, let acct = account {
                Task {
                    if let hydrated = try? await self.fetchPostByID(originalPost.id, account: acct),
                        !hydrated.content.isEmpty
                    {
                        originalPost = hydrated
                    }
                }
            }

            let boostPost = Post(
                id: status.id,
                content: "",  // Reblog doesn't have its own content
                authorName: status.account.displayName,
                authorUsername: status.account.acct,
                authorProfilePictureURL: status.account.avatar,
                createdAt: DateParser.parse(status.createdAt) ?? Date.distantPast,
                platform: .mastodon,
                originalURL: status.url ?? "",
                attachments: [],
                mentions: [],
                tags: [],
                originalPost: originalPost,
                isReposted: status.reblogged ?? false,
                isLiked: status.favourited ?? false,
                likeCount: status.favouritesCount,
                repostCount: status.reblogsCount,
                replyCount: status.repliesCount,  // Add reply count
                boostedBy: status.account.displayName.isEmpty
                    ? status.account.acct : status.account.displayName,
                blueskyLikeRecordURI: nil,  // Mastodon doesn't use Bluesky record URIs
                blueskyRepostRecordURI: nil
            )

            return boostPost
        }

        // Regular non-boosted post
        let attachments = status.mediaAttachments.compactMap { media -> Post.Attachment? in
            guard media.type == "image", let url = URL(string: media.url), !media.url.isEmpty else {
                print(
                    "[Mastodon] Skipping non-image or invalid attachment: \(media.url) type: \(media.type)"
                )
                return nil
            }
            let alt = media.description ?? "Image"
            print("[Mastodon] Parsed image attachment: \(url) alt: \(alt)")
            return Post.Attachment(
                url: media.url,
                type: .image,
                altText: alt
            )
        }

        let mentions = status.mentions.compactMap { mention -> String in
            return mention.username
        }

        let tags = status.tags.compactMap { tag -> String in
            return tag.name
        }

        // Create a properly configured ISO8601DateFormatter
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let createdDate = formatter.date(from: status.createdAt) ?? Date()

        // Log reply status information
        if let replyToId = status.inReplyToId {
            logger.info(
                "Converting Mastodon reply post: id=\(status.id), in_reply_to_id=\(replyToId)")
        } else {
            logger.debug("Converting regular Mastodon post (not a reply): id=\(status.id)")
        }

        // Try to find the username being replied to from mentions
        var parentPost: Post? = nil

        if let replyToAccountId = status.inReplyToAccountId, let replyToId = status.inReplyToId,
            replyToId != status.id
        {  // Prevent self-referencing
            // Create a minimal parent post with the info we have to display immediately
            // This gives us a parent post without needing an additional API call
            // The full content will be loaded on demand when expanded
            parentPost = Post(
                id: replyToId,
                content: "...",  // Placeholder until expanded
                authorName: replyToUsername ?? "Loading...",  // Use username as display name until we have more info
                authorUsername: replyToUsername ?? "...",
                authorProfilePictureURL: "",  // We don't have the avatar URL yet
                createdAt: createdDate.addingTimeInterval(-60),  // Estimate 1 minute earlier
                platform: .mastodon,
                originalURL: "",
                parent: nil,
                inReplyToID: nil,
                inReplyToUsername: replyToUsername,  // Set the reply username in parent post too
                blueskyLikeRecordURI: nil,  // Mastodon doesn't use Bluesky record URIs
                blueskyRepostRecordURI: nil
            )

            // Log what we're using for the parent post
            logger.info(
                "Created parent post placeholder with username: \(replyToUsername ?? "nil")")
        }

        let post = Post(
            id: status.id,
            content: status.content,
            authorName: status.account.displayName,
            authorUsername: status.account.acct,
            authorProfilePictureURL: status.account.avatar,
            createdAt: createdDate,
            platform: .mastodon,
            originalURL: status.url ?? "",
            attachments: attachments,
            mentions: mentions,
            tags: tags,
            isReposted: status.reblogged ?? false,
            isLiked: status.favourited ?? false,
            likeCount: status.favouritesCount,
            repostCount: status.reblogsCount,
            replyCount: status.repliesCount,  // Add reply count
            parent: parentPost,
            inReplyToID: status.inReplyToId,
            inReplyToUsername: replyToUsername,
            blueskyLikeRecordURI: nil,  // Mastodon doesn't use Bluesky record URIs
            blueskyRepostRecordURI: nil
        )

        // DEBUG: Print interaction counts for debugging
        print(
            "📊 [MastodonService] Post \(status.id.prefix(10)) - likes: \(status.favouritesCount), reposts: \(status.reblogsCount), replies: \(status.repliesCount)"
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
        content: String, mediaAttachments: [Data] = [], visibility: String = "public",
        account: SocialAccount
    ) async throws -> Post {
        let serverUrl = formatServerURL(
            account.serverURL?.absoluteString ?? "")

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
        return await self.convertMastodonStatusToPost(status, account: account)
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
        let posts = await convertToGenericPosts(statuses: statuses)
        return posts
    }

    /// Update profile image for a Mastodon account
    public func updateProfileImage(for account: SocialAccount) async {
        do {
            guard let serverURL = account.serverURL else {
                print("❌ No server URL found for Mastodon account: \(account.username)")
                return
            }

            print("🔄 Fetching Mastodon profile for \(account.username) from server: \(serverURL)")

            // Build the endpoint URL properly
            let endpoint = serverURL.appendingPathComponent("api/v1/accounts/verify_credentials")
            var request = URLRequest(url: endpoint)

            guard let accessToken = account.getAccessToken() else {
                print("❌ No access token found for Mastodon account: \(account.username)")
                return
            }

            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            print("🔐 Using access token for \(account.username): \(accessToken.prefix(10))...")

            print("🌐 Making Mastodon API request to: \(endpoint)")
            let (data, response) = try await URLSession.shared.data(for: request)

            // Check HTTP response status
            if let httpResponse = response as? HTTPURLResponse {
                print(
                    "📡 Mastodon API response status for \(account.username): \(httpResponse.statusCode)"
                )
                if httpResponse.statusCode != 200 {
                    print(
                        "❌ Mastodon API returned error status \(httpResponse.statusCode) for \(account.username)"
                    )
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("❌ Response body: \(responseString)")
                    }
                    return
                }
            }
            let mastodonAccount = try JSONDecoder().decode(MastodonAccount.self, from: data)

            print(
                "Raw avatar field from Mastodon API for \(mastodonAccount.username): '\(mastodonAccount.avatar)'"
            )

            if mastodonAccount.avatar.isEmpty {
                print(
                    "⚠️ Empty avatar field returned from Mastodon API for \(mastodonAccount.username)"
                )
            } else if let avatarURL = URL(string: mastodonAccount.avatar) {
                print(
                    "✅ Successfully parsed Mastodon avatar URL for \(mastodonAccount.username): \(avatarURL)"
                )

                // Ensure UI updates happen on the main thread
                // Make local copies of values to avoid Sendable issues
                let accountId = account.id
                DispatchQueue.main.async { [avatarURL] in
                    account.profileImageURL = avatarURL
                    print(
                        "✅ Updated Mastodon account \(mastodonAccount.username) with profile image URL"
                    )

                    // Post notification about the profile image update
                    NotificationCenter.default.post(
                        name: .profileImageUpdated,
                        object: nil,
                        userInfo: ["accountId": accountId, "profileImageURL": avatarURL]
                    )
                }
            } else {
                print(
                    "❌ Failed to create valid URL from avatar field for \(mastodonAccount.username): '\(mastodonAccount.avatar)'"
                )
            }
        } catch {
            print("❌ Error fetching Mastodon profile for \(account.username): \(error)")

            // More detailed error logging
            if let urlError = error as? URLError {
                print(
                    "❌ URLError code: \(urlError.code.rawValue), description: \(urlError.localizedDescription)"
                )
            } else if let decodingError = error as? DecodingError {
                print("❌ JSON decoding error: \(decodingError)")
            }
        }
    }

    /// Create an account for the given OAuth credentials
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
        account.saveTokenExpirationDate(Date().addingTimeInterval(30 * 24 * 60 * 60))  // 30 days

        // Try to fetch the actual profile image
        if let avatarURL = URL(string: userInfo.avatar) {
            account.profileImageURL = avatarURL
            print("Updated Mastodon profile image URL: \(avatarURL.absoluteString)")

            // Post notification about the profile image update
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .profileImageUpdated,
                    object: nil,
                    userInfo: ["accountId": account.id, "profileImageURL": avatarURL]
                )
            }
        }

        return account
    }

    /// Fetches a single post by its ID
    /// - Parameters:
    ///   - postID: The ID of the post to fetch
    ///   - account: The account to use for API access
    /// - Returns: The post if found, nil if not found or error occurs
    public func fetchPostByID(_ postID: String, account: SocialAccount) async throws -> Post? {
        var serverURLString = account.serverURL?.absoluteString ?? "mastodon.social"
        if serverURLString.hasPrefix("https://") {
            serverURLString = String(serverURLString.dropFirst(8))
        }

        // Format the API URL
        let apiURL = URL(string: "https://\(serverURLString)/api/v1/statuses/\(postID)")!

        var request = URLRequest(url: apiURL)

        // Add authorization if available
        if let accessToken = account.getAccessToken() {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        // Make the request
        let (data, response) = try await URLSession.shared.data(for: request)

        // Check for successful response
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(
                domain: "MastodonService", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch post"]
            )
        }

        // Parse the response
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let status = try decoder.decode(MastodonStatus.self, from: data)
            return await self.convertMastodonStatusToPost(status, account: account)
        } catch {
            print("Error decoding Mastodon status: \(error)")
            return nil
        }
    }

    /// Refreshes an access token if needed
    public func refreshTokenIfNeeded(account: SocialAccount) async throws -> String {
        print("Checking if Mastodon token needs refresh")
        // If token is still valid, return it
        if !account.isTokenExpired, let accessToken = account.getAccessToken() {
            print("Mastodon token is still valid")
            return accessToken
        }

        // If we have a refresh token but no client credentials, we can't refresh
        if account.getRefreshToken() != nil {
            print("Token expired but client credentials not available for refresh")
        }

        // Try to use existing token even if expired, as a fallback
        if let accessToken = account.getAccessToken() {
            print("Using existing token despite expiration")
            return accessToken
        }

        throw TokenError.noAccessToken
    }

    // MARK: - Status methods

    /// Local cache for recently fetched status posts
    private var statusCache: [String: (post: Post, timestamp: Date)] = [:]

    /// Fetches a status by its ID
    /// - Parameter id: The ID of the status to fetch
    /// - Parameter account: The account to use for authentication
    /// - Returns: The post if found, nil otherwise
    func fetchStatus(id: String, account: SocialAccount) async throws -> Post? {
        // Check cache first - posts are valid for 5 minutes
        if let cached = statusCache[id], Date().timeIntervalSince(cached.timestamp) < 300 {
            logger.info("Using cached Mastodon status for ID: \(id)")
            return cached.post
        }

        guard let serverURLString = account.serverURL else {
            logger.error("No server URL for Mastodon account")
            throw NSError(
                domain: "MastodonService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "No server URL"])
        }

        // Ensure server has the scheme
        let serverUrl = formatServerURL(serverURLString.absoluteString)

        guard let url = URL(string: "\(serverUrl)/api/v1/statuses/\(id)") else {
            logger.error("Invalid server URL or status ID: \(serverUrl)/api/v1/statuses/\(id)")
            throw NSError(
                domain: "MastodonService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL or status ID"])
        }

        logger.info("Fetching Mastodon status \(id) from \(serverUrl)")

        let request = try await createAuthenticatedRequest(
            url: url, method: "GET", account: account)

        // Create the URLRequest before executing to minimize main-thread time
        let finalRequest = request

        do {
            // Execute the request with a high priority for better UI responsiveness
            return try await Task.detached(priority: .userInitiated) {
                // Log the actual request
                self.logger.info("Sending request to fetch Mastodon status: \(url.absoluteString)")

                let (data, response) = try await self.session.data(for: finalRequest)

                guard let httpResponse = response as? HTTPURLResponse,
                    httpResponse.statusCode == 200
                else {
                    if let errorMessage = String(data: data, encoding: .utf8) {
                        self.logger.error(
                            "Error response (\((response as? HTTPURLResponse)?.statusCode ?? 0)): \(errorMessage)"
                        )
                    }
                    throw NSError(
                        domain: "MastodonService",
                        code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to fetch status"])
                }

                // Log the response for debugging
                if let responseStr = String(data: data, encoding: .utf8) {
                    self.logger.debug(
                        "Raw response from Mastodon API: \(responseStr.prefix(200))...")
                }

                // Decode the status
                let status = try JSONDecoder().decode(MastodonStatus.self, from: data)
                self.logger.info(
                    "Successfully decoded Mastodon status: id=\(status.id), in_reply_to_id=\(status.inReplyToId ?? "nil")"
                )

                // Convert to our Post model using the existing convertMastodonStatusToPost method
                let post = await self.convertMastodonStatusToPost(status, account: account)
                self.logger.info(
                    "Converted to Post model: id=\(post.id), inReplyToID=\(post.inReplyToID ?? "nil")"
                )

                // Store in cache
                await MainActor.run {
                    self.statusCache[id] = (post: post, timestamp: Date())
                }

                return post
            }.value
        } catch {
            logger.error("Error fetching status: \(error.localizedDescription)")
            throw error
        }
    }

    /// For compatibility with existing code - fetches a status by its ID using a callback
    /// - Parameters:
    ///   - id: The ID of the status to fetch
    ///   - completion: Completion handler called with the result
    func fetchStatus(id: String, completion: @escaping (Post?) -> Void) {
        // Check cache first
        if let cached = statusCache[id], Date().timeIntervalSince(cached.timestamp) < 300 {
            logger.info("Using cached Mastodon status for callback API: \(id)")
            completion(cached.post)
            return
        }

        // Use a higher priority task for better UI responsiveness
        Task(priority: .userInitiated) {
            // Find an account to use
            guard let account = await findValidAccount() else {
                logger.error("No valid account found for fetching status")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            do {
                let post = try await fetchStatus(id: id, account: account)
                // Copy the post to a local variable to avoid Sendable capture issues
                let finalPost = post

                if let post = post {
                    // Store in cache (no need to use MainActor here since we're calling from non-UI code)
                    statusCache[id] = (post: post, timestamp: Date())
                }

                // Call completion on main thread for UI updates
                DispatchQueue.main.async {
                    completion(finalPost)
                }
            } catch {
                logger.error("Error fetching status: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }

    /// Find a valid account to use for API requests
    @MainActor
    private func findValidAccount() -> SocialAccount? {
        // This method should look for a valid account in your account storage
        // For now, we'll use this placeholder
        let accounts = SocialServiceManager.shared.mastodonAccounts
        return accounts.first
    }

    // MARK: - Thread Context Methods

    /// Fetch status context (thread ancestors and descendants) from Mastodon
    /// - Parameters:
    ///   - statusId: The ID of the status to get context for
    ///   - account: The account to use for authentication
    /// - Returns: ThreadContext containing ancestors and descendants
    func fetchStatusContext(statusId: String, account: SocialAccount) async throws -> ThreadContext
    {
        guard let serverURLString = account.serverURL else {
            logger.error("No server URL for Mastodon account")
            throw NSError(
                domain: "MastodonService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "No server URL"])
        }

        let serverUrl = formatServerURL(serverURLString.absoluteString)

        guard let url = URL(string: "\(serverUrl)/api/v1/statuses/\(statusId)/context") else {
            logger.error(
                "Invalid server URL or status ID for context: \(serverUrl)/api/v1/statuses/\(statusId)/context"
            )
            throw NSError(
                domain: "MastodonService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL or status ID"])
        }

        logger.info("Fetching Mastodon context for status \(statusId) from \(serverUrl)")

        let request = try await createAuthenticatedRequest(
            url: url, method: "GET", account: account)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200
            else {
                if let errorMessage = String(data: data, encoding: .utf8) {
                    logger.error(
                        "Context error response (\((response as? HTTPURLResponse)?.statusCode ?? 0)): \(errorMessage)"
                    )
                }
                throw NSError(
                    domain: "MastodonService",
                    code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to fetch status context"])
            }

            // Parse the context response
            let contextResponse = try JSONDecoder().decode(MastodonStatusContext.self, from: data)

            // Convert Mastodon statuses to Post objects
            let ancestors = contextResponse.ancestors.compactMap { status in
                convertMastodonStatusToPost(status, account: account)
            }

            let descendants = contextResponse.descendants.compactMap { status in
                convertMastodonStatusToPost(status, account: account)
            }

            logger.info(
                "Successfully fetched context: \(ancestors.count) ancestors, \(descendants.count) descendants"
            )

            return ThreadContext(ancestors: ancestors, descendants: descendants)
        } catch {
            logger.error("Error fetching status context: \(error.localizedDescription)")
            throw error
        }
    }
}

// MARK: - Mastodon Status Context Models

/// Mastodon API response for status context
private struct MastodonStatusContext: Codable {
    let ancestors: [MastodonStatus]
    let descendants: [MastodonStatus]
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

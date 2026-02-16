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

/// In-memory cache for Mastodon custom emoji maps keyed by account ID.
final class EmojiCache {
    static let shared = EmojiCache()

    private var cache: [String: [String: String]] = [:]
    private let lock = NSLock()

    private init() {}

    func store(accountId: String, emojiMap: [String: String]) {
        guard !accountId.isEmpty, !emojiMap.isEmpty else { return }
        lock.lock()
        cache[accountId] = emojiMap
        lock.unlock()
    }

    func get(accountId: String) -> [String: String]? {
        guard !accountId.isEmpty else { return nil }
        lock.lock()
        let emojiMap = cache[accountId]
        lock.unlock()
        return emojiMap
    }
}

public final class MastodonService: @unchecked Sendable {
    private let session = URLSession.shared
    private let logger = Logger(subsystem: "com.socialfusion.app", category: "MastodonService")

    public init() {}

    // MARK: - Rate Limit Helpers

    /// Parse Mastodon rate limit reset time from x-ratelimit-reset header
    /// Mastodon uses ISO 8601 timestamp format: 2026-01-01T01:55:00.588881Z
    private func parseRateLimitReset(_ resetHeader: String?) -> TimeInterval? {
        guard let resetHeader = resetHeader else { return nil }

        // Try ISO 8601 format first (Mastodon standard)
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let resetDate = iso8601Formatter.date(from: resetHeader) {
            let now = Date()
            let secondsUntilReset = resetDate.timeIntervalSince(now)
            return max(0, secondsUntilReset)  // Ensure non-negative
        }

        // Fallback: Try standard ISO 8601 without fractional seconds
        iso8601Formatter.formatOptions = [.withInternetDateTime]
        if let resetDate = iso8601Formatter.date(from: resetHeader) {
            let now = Date()
            let secondsUntilReset = resetDate.timeIntervalSince(now)
            return max(0, secondsUntilReset)
        }

        // Fallback: Try parsing as seconds (Retry-After format)
        if let seconds = TimeInterval(resetHeader) {
            return max(0, seconds)
        }

        return nil
    }

    // MARK: - Authentication Utilities

    /// Creates an authenticated request with automatic token refresh
    public func createAuthenticatedRequest(
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
    public func formatServerURL(_ server: String) -> String {
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

            // For accounts without refresh tokens (manual token entry), extend expiration as fallback
            logger.info(
                "Extending token expiration for account \(account.username) without refresh token")
            account.saveTokenExpirationDate(Date().addingTimeInterval(30 * 24 * 60 * 60))  // 30 more days

            // Return the current access token since we can't refresh
            return account.accessToken ?? ""
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

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "MastodonService",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }

        // Handle rate limiting (429) with specific error type
        if httpResponse.statusCode == 429 {
            let resetHeader = httpResponse.value(forHTTPHeaderField: "x-ratelimit-reset")
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")

            // Parse rate limit reset time
            let retrySeconds: TimeInterval
            if let resetTime = parseRateLimitReset(resetHeader) {
                retrySeconds = resetTime
            } else if let retryAfterValue = retryAfter, let seconds = TimeInterval(retryAfterValue)
            {
                retrySeconds = seconds
            } else {
                retrySeconds = 60  // Default to 60 seconds if we can't parse
            }

            logger.error(
                "❌ MASTODON: Rate limited during verifyCredentials - retry after: \(retrySeconds) seconds"
            )
            print(
                "❌ MASTODON: Rate limited during verifyCredentials - retry after: \(retrySeconds) seconds"
            )

            throw ServiceError.rateLimitError(
                reason: "Too many requests to Mastodon server",
                retryAfter: retrySeconds
            )
        }

        guard httpResponse.statusCode == 200 else {
            let statusCode = httpResponse.statusCode

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
    public func verifyCredentials(account: SocialAccount) async throws -> MastodonAccount {
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

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "MastodonService",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }

        // Handle rate limiting (429) with specific error type
        if httpResponse.statusCode == 429 {
            let resetHeader = httpResponse.value(forHTTPHeaderField: "x-ratelimit-reset")
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")

            // Parse rate limit reset time
            let retrySeconds: TimeInterval
            if let resetTime = parseRateLimitReset(resetHeader) {
                retrySeconds = resetTime
            } else if let retryAfterValue = retryAfter, let seconds = TimeInterval(retryAfterValue)
            {
                retrySeconds = seconds
            } else {
                retrySeconds = 60  // Default to 60 seconds if we can't parse
            }

            logger.error(
                "❌ MASTODON: Rate limited during verifyCredentials - retry after: \(retrySeconds) seconds"
            )
            print(
                "❌ MASTODON: Rate limited during verifyCredentials - retry after: \(retrySeconds) seconds"
            )

            throw ServiceError.rateLimitError(
                reason: "Too many requests to Mastodon server",
                retryAfter: retrySeconds
            )
        }

        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw errorResponse
            }
            throw NSError(
                domain: "MastodonService", code: httpResponse.statusCode,
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
            displayName: mastodonAccount.displayName ?? mastodonAccount.username,
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
            displayName: mastodonAccount.displayName ?? mastodonAccount.username,
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

        logger.info("🔄 MASTODON: Fetching timeline from: \(urlString)")
        print("🔄 MASTODON: Fetching timeline from: \(urlString)")
        print("🔄 MASTODON: Token present, proceeding with request")

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
                print("❌ MASTODON: Authentication failed - token may be expired")
                throw ServiceError.unauthorized("Authentication failed or expired")
            }

            // Handle rate limiting (429) with specific error type
            if httpResponse.statusCode == 429 {
                let resetHeader = httpResponse.value(forHTTPHeaderField: "x-ratelimit-reset")
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")

                // Parse rate limit reset time
                let retrySeconds: TimeInterval
                if let resetTime = parseRateLimitReset(resetHeader) {
                    retrySeconds = resetTime
                } else if let retryAfterValue = retryAfter,
                    let seconds = TimeInterval(retryAfterValue)
                {
                    retrySeconds = seconds
                } else {
                    retrySeconds = 60  // Default to 60 seconds if we can't parse
                }

                logger.error("❌ MASTODON: Rate limited - retry after: \(retrySeconds) seconds")

                throw ServiceError.rateLimitError(
                    reason: "Too many requests to Mastodon server",
                    retryAfter: retrySeconds
                )
            }

            if httpResponse.statusCode != 200 {
                // Log response body for debugging
                #if DEBUG
                if let responseString = String(data: data, encoding: .utf8) {
                    logger.error("❌ MASTODON: Response body: \(String(responseString.prefix(500)))")
                }
                #endif
                throw ServiceError.apiError(
                    "Server returned status code \(httpResponse.statusCode)")
            }

            // Check if we got empty data
            if data.isEmpty {
                logger.warning("⚠️ MASTODON: Received empty response data")
                return TimelineResult(posts: [], pagination: PaginationInfo.empty)
            }

            // Check if response looks like HTML instead of JSON
            if let responseString = String(data: data, encoding: .utf8) {
                if responseString.lowercased().contains("<html")
                    || responseString.lowercased().contains("<!doctype")
                {
                    logger.error(
                        "❌ MASTODON: Server returned HTML instead of JSON - possible auth redirect")
                    throw ServiceError.unauthorized(
                        "Server returned HTML page instead of JSON - token may be invalid")
                }
            }

            // Decode the response with better error handling
            let statuses: [MastodonStatus]
            do {
                statuses = try JSONDecoder().decode([MastodonStatus].self, from: data)
            } catch {
                logger.error("❌ MASTODON JSON DECODE ERROR: \(error)")

                // Try to log first 1000 characters of response to see what we got
                #if DEBUG
                if let responseString = String(data: data, encoding: .utf8) {
                    logger.error("❌ MASTODON RAW RESPONSE: \(String(responseString.prefix(1000)))")
                }
                #endif

                // Try to decode as a single status instead of array (some endpoints return single objects)
                if let singleStatus = try? JSONDecoder().decode(MastodonStatus.self, from: data) {
                    logger.info("✅ MASTODON: Successfully decoded single status instead of array")
                    statuses = [singleStatus]
                } else {
                    throw error
                }
            }

            // Convert to post models
            var posts = statuses.map { convertMastodonStatusToPost($0, account: account) }

            // Enrich posts with relationship data (following/muting/blocking status)
            posts = await enrichPostsWithRelationships(posts, account: account)

            logger.info("✅ MASTODON: Successfully fetched \(posts.count) posts")

            // Determine pagination info - Mastodon has more pages if we get the full limit
            let hasNextPage = posts.count >= limit
            let nextPageToken = posts.last?.id

            let pagination = PaginationInfo(hasNextPage: hasNextPage, nextPageToken: nextPageToken)

            return TimelineResult(posts: posts, pagination: pagination)
        } catch {
            logger.error("❌ MASTODON ERROR: \(error.localizedDescription)")
            print("❌ MASTODON ERROR: \(error.localizedDescription)")
            print("❌ MASTODON ERROR DETAILS: \(error)")
            throw ServiceError.timelineError(underlying: error)
        }
    }

    /// Fetch the public timeline from the Mastodon API
    func fetchPublicTimeline(for account: SocialAccount, local: Bool = false) async throws -> [Post]
    {
        let result = try await fetchPublicTimeline(
            for: account,
            local: local,
            limit: 40,
            maxId: nil
        )
        return result.posts
    }

    /// Fetch the public timeline from the Mastodon API with pagination
    func fetchPublicTimeline(
        for account: SocialAccount,
        local: Bool = false,
        limit: Int = 40,
        maxId: String? = nil
    ) async throws -> TimelineResult {
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
        let urlString =
            local
            ? "\(serverUrl)/api/v1/timelines/\(endpoint)&limit=\(limit)"
            : "\(serverUrl)/api/v1/timelines/\(endpoint)?limit=\(limit)"

        var components = URLComponents(string: urlString)
        var queryItems = components?.queryItems ?? []
        if let maxId = maxId {
            queryItems.append(URLQueryItem(name: "max_id", value: maxId))
        }
        
        // Fix: Assign to a temporary variable first to avoid exclusivity crash
        if var finalComponents = components {
            finalComponents.queryItems = queryItems
            components = finalComponents
        }

        guard let url = components?.url else {
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

        // Convert to our app's Post model and enrich with relationship data
        var posts = statuses.map { convertMastodonStatusToPost($0, account: account) }
        posts = await enrichPostsWithRelationships(posts, account: account)
        let hasNextPage = posts.count >= limit
        let nextPageToken = posts.last?.id
        return TimelineResult(
            posts: posts,
            pagination: PaginationInfo(hasNextPage: hasNextPage, nextPageToken: nextPageToken)
        )
    }

    /// Fetch the timeline for a Mastodon list
    func fetchListTimeline(
        for account: SocialAccount,
        listId: String,
        limit: Int = 40,
        maxId: String? = nil
    ) async throws -> TimelineResult {
        guard let accessToken = account.getAccessToken() else {
            throw NSError(
                domain: "MastodonService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token available"])
        }

        let serverUrlString = account.serverURL?.absoluteString ?? ""
        let serverUrl =
            serverUrlString.contains("://")
            ? serverUrlString : "https://\(serverUrlString)"
        var components = URLComponents(
            string: "\(serverUrl)/api/v1/timelines/list/\(listId)?limit=\(limit)")
        var queryItems = components?.queryItems ?? []
        if let maxId = maxId {
            queryItems.append(URLQueryItem(name: "max_id", value: maxId))
        }
        
        // Fix: Assign to a temporary variable first to avoid exclusivity crash
        if var finalComponents = components {
            finalComponents.queryItems = queryItems
            components = finalComponents
        }

        guard let url = components?.url else {
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
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch list timeline"])
        }

        let statuses = try JSONDecoder().decode([MastodonStatus].self, from: data)
        var posts = statuses.map { convertMastodonStatusToPost($0, account: account) }
        posts = await enrichPostsWithRelationships(posts, account: account)
        let hasNextPage = posts.count >= limit
        let nextPageToken = posts.last?.id
        return TimelineResult(
            posts: posts,
            pagination: PaginationInfo(hasNextPage: hasNextPage, nextPageToken: nextPageToken)
        )
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
        let result = try await fetchPublicTimeline(
            serverURL: serverURL,
            limit: count,
            maxId: nil,
            local: local
        )
        return result.posts
    }

    /// Fetch the public timeline from the Mastodon API without requiring an account (with pagination)
    func fetchPublicTimeline(
        serverURL: URL,
        limit: Int = 20,
        maxId: String? = nil,
        local: Bool = false
    ) async throws -> TimelineResult {
        // Ensure server has the scheme
        let serverUrlString = serverURL.absoluteString
        let serverUrl = formatServerURL(serverUrlString)

        let endpoint = local ? "public?local=true" : "public"
        let limitParam = local ? "&limit=\(limit)" : "?limit=\(limit)"
        let urlString = "\(serverUrl)/api/v1/timelines/\(endpoint)\(limitParam)"

        var components = URLComponents(string: urlString)
        var queryItems = components?.queryItems ?? []
        if let maxId = maxId {
            queryItems.append(URLQueryItem(name: "max_id", value: maxId))
        }
        
        // Fix: Assign to a temporary variable first to avoid exclusivity crash
        if var finalComponents = components {
            finalComponents.queryItems = queryItems
            components = finalComponents
        }

        guard let url = components?.url else {
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
        let posts = statuses.map { convertMastodonStatusToPost($0, account: serverAccount) }
        let hasNextPage = posts.count >= limit
        let nextPageToken = posts.last?.id
        return TimelineResult(
            posts: posts,
            pagination: PaginationInfo(hasNextPage: hasNextPage, nextPageToken: nextPageToken)
        )
    }

    /// Fetch a user's profile timeline
    public func fetchUserTimeline(
        userId: String, for account: SocialAccount, limit: Int = 40, maxId: String? = nil
    ) async throws -> [Post] {
        logger.info(
            "🔍 MASTODON: Fetching user timeline for userId: \(userId), account: \(account.username)"
        )
        print(
            "🔍 MASTODON: Fetching user timeline for userId: \(userId), account: \(account.username)"
        )

        // Validate userId is not empty
        guard !userId.isEmpty else {
            logger.error("❌ MASTODON: userId is empty")
            print("❌ MASTODON: userId is empty")
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "User ID is empty"])
        }

        let serverUrl = formatServerURL(account.serverURL?.absoluteString ?? "")
        var urlString = "\(serverUrl)/api/v1/accounts/\(userId)/statuses?limit=\(limit)"
        if let maxId = maxId {
            urlString += "&max_id=\(maxId)"
        }

        logger.info("🔍 MASTODON: Request URL: \(urlString)")

        guard let url = URL(string: urlString) else {
            logger.error("❌ MASTODON: Invalid URL: \(urlString)")
            print("❌ MASTODON: Invalid URL: \(urlString)")
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

        do {
            let request = try await createAuthenticatedRequest(
                url: url, method: "GET", account: account)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("❌ MASTODON: Invalid HTTP response")
                throw NSError(
                    domain: "MastodonService",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
            }

            logger.info("🔍 MASTODON: HTTP Status Code: \(httpResponse.statusCode)")

            if httpResponse.statusCode != 200 {
                // Try to decode error response
                if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                    logger.error("❌ MASTODON: API Error: \(errorResponse.error)")
                    print("❌ MASTODON: API Error: \(errorResponse.error)")
                    throw errorResponse
                }

                // Log response body for debugging
                #if DEBUG
                if let responseString = String(data: data, encoding: .utf8) {
                    logger.error("❌ MASTODON: Response body: \(String(responseString.prefix(500)))")
                }
                #endif

                let errorMessage = "Failed to fetch user timeline: HTTP \(httpResponse.statusCode)"
                logger.error("❌ MASTODON: \(errorMessage)")
                throw NSError(
                    domain: "MastodonService",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: errorMessage])
            }

            // Check if response is empty
            if data.isEmpty {
                logger.info("✅ MASTODON: Empty response - user has no posts")
                return []
            }

            let statuses = try JSONDecoder().decode([MastodonStatus].self, from: data)
            logger.info("✅ MASTODON: Successfully fetched \(statuses.count) statuses")

            // Convert to our app's Post model and enrich with relationship data
            var posts = statuses.map { convertMastodonStatusToPost($0, account: account) }
            posts = await enrichPostsWithRelationships(posts, account: account)
            return posts
        } catch {
            logger.error("❌ MASTODON: Error fetching user timeline: \(error.localizedDescription)")
            print("❌ MASTODON: Error fetching user timeline: \(error.localizedDescription)")
            throw error
        }
    }

    /// Search for content on Mastodon
    public func search(query: String, account: SocialAccount, type: String? = nil, limit: Int = 20)
        async throws -> MastodonSearchResult
    {
        let serverUrl = formatServerURL(account.serverURL?.absoluteString ?? "")

        var components = URLComponents(string: "\(serverUrl)/api/v2/search")!
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "resolve", value: "true"),
        ]

        if let type = type {
            queryItems.append(URLQueryItem(name: "type", value: type))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw ServiceError.invalidInput(reason: "Invalid search query")
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "GET", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.apiError("Invalid response")
        }
        
        // Debug: Log the raw response
        #if DEBUG
        if let responseString = String(data: data, encoding: .utf8) {
            print("🔍 [Search] Raw response: \(responseString.prefix(500))")
        }
        #endif
        print("🔍 [Search] Response data size: \(data.count) bytes, status: \(httpResponse.statusCode)")

        // Some instances return 500 but still include valid JSON data
        // Try to decode even on non-200 status codes if we have data
        if httpResponse.statusCode != 200 {
            // Check if the response body contains valid JSON that might be parseable
            if data.isEmpty {
                throw ServiceError.apiError(
                    "Search failed with status \(httpResponse.statusCode)")
            }
            
            // Try to decode anyway - some servers return 500 with valid data
            do {
                let decoder = JSONDecoder()
                let result = try decoder.decode(MastodonSearchResult.self, from: data)
                print("⚠️ [Search] Successfully decoded response despite status \(httpResponse.statusCode)")
                return result
            } catch {
                // If decoding fails, throw the original status error
                throw ServiceError.apiError(
                    "Search failed with status \(httpResponse.statusCode)")
            }
        }

        // Note: Do NOT use .convertFromSnakeCase here as MastodonStatus/MastodonSearchResult
        // already have explicit CodingKeys that handle snake_case conversion.
        // Using both would cause double-conversion and decoding failures.
        let decoder = JSONDecoder()
        return try decoder.decode(MastodonSearchResult.self, from: data)
    }

    /// Fetch trending tags from Mastodon
    public func fetchTrendingTags(account: SocialAccount, limit: Int = 10) async throws
        -> [MastodonTag]
    {
        let serverUrl = formatServerURL(account.serverURL?.absoluteString ?? "")
        let url = URL(string: "\(serverUrl)/api/v1/trending/tags?limit=\(limit)")!

        let request = try await createAuthenticatedRequest(
            url: url, method: "GET", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.apiError("Failed to fetch trending tags")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([MastodonTag].self, from: data)
    }

    /// Fetch notifications from Mastodon
    public func fetchNotifications(
        for account: SocialAccount, limit: Int = 40, maxId: String? = nil
    ) async throws -> [MastodonNotification] {
        let serverUrl = formatServerURL(account.serverURL?.absoluteString ?? "")

        var urlString = "\(serverUrl)/api/v1/notifications?limit=\(limit)"
        if let maxId = maxId {
            urlString += "&max_id=\(maxId)"
        }

        guard let url = URL(string: urlString) else {
            throw ServiceError.invalidInput(reason: "Invalid server URL")
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "GET", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.apiError("Failed to fetch notifications")
        }

        return try JSONDecoder().decode([MastodonNotification].self, from: data)
    }

    // MARK: - Post Actions

    /// Upload media to Mastodon
    private func uploadMedia(data: Data, description: String? = nil, account: SocialAccount)
        async throws -> String
    {
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

        // Add description (alt-text) if provided
        if let description = description {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append(
                "Content-Disposition: form-data; name=\"description\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(description)\r\n".data(using: .utf8)!)
        }

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

        guard let url = URL(string: "\(serverUrl)/api/v1/statuses/\(statusId)/favourite") else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL or post ID"])
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "POST", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "MastodonService",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }

        guard httpResponse.statusCode == 200 else {
            // Try to decode server error response
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw NSError(
                    domain: "MastodonService",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: errorResponse.error])
            }

            // If we can't decode the error, provide a generic message
            let errorMessage = "Failed to like post (HTTP \(httpResponse.statusCode))"
            throw NSError(
                domain: "MastodonService",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }

        // Try to decode the successful response
        do {
            let status = try JSONDecoder().decode(MastodonStatus.self, from: data)
            return self.convertMastodonStatusToPost(status, account: account)
        } catch {
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

        guard let url = URL(string: "\(serverUrl)/api/v1/statuses/\(statusId)/unfavourite") else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL or post ID"])
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "POST", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "MastodonService",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }

        guard httpResponse.statusCode == 200 else {
            // Try to decode server error response
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                throw NSError(
                    domain: "MastodonService",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: errorResponse.error])
            }

            // If we can't decode the error, provide a generic message
            let errorMessage = "Failed to unlike post (HTTP \(httpResponse.statusCode))"
            throw NSError(
                domain: "MastodonService",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }

        // Try to decode the successful response
        do {
            let status = try JSONDecoder().decode(MastodonStatus.self, from: data)
            return self.convertMastodonStatusToPost(status, account: account)
        } catch {
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
        return self.convertMastodonStatusToPost(status, account: account)
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
        return self.convertMastodonStatusToPost(status, account: account)
    }

    /// Reply to a post on Mastodon
    func replyToPost(
        _ post: Post,
        content: String,
        mediaAttachments: [Data] = [],
        mediaAltTexts: [String] = [],
        pollOptions: [String] = [],
        pollExpiresIn: Int? = nil,
        visibility: String = "public",
        account: SocialAccount,
        spoilerText: String? = nil,
        sensitive: Bool = false,
        composerTextModel: ComposerTextModel? = nil
    ) async throws -> Post {
        let serverUrl = formatServerURL(
            account.serverURL?.absoluteString ?? "")

        // If this is a boosted/reposted post, reply to the original post
        let targetPost = post.originalPost ?? post

        print("🔍 Reply attempt - isBoost: \(post.originalPost != nil), post.id: \(post.id), post.platformSpecificId: \(post.platformSpecificId)")
        print("   post.originalURL: \(post.originalURL)")
        if let originalPost = post.originalPost {
            print("   originalPost.id: \(originalPost.id), originalPost.platformSpecificId: \(originalPost.platformSpecificId)")
            print("   originalPost.originalURL: \(originalPost.originalURL)")
        }

        // Check if this is a cross-instance reply (post from different server)
        let postServerURL = URL(string: targetPost.originalURL)?.host
        let accountServerURL = account.serverURL?.host
        let isCrossInstance = postServerURL != nil && accountServerURL != nil && postServerURL != accountServerURL

        print("🌐 Cross-instance check: postServer=\(postServerURL ?? "nil"), accountServer=\(accountServerURL ?? "nil"), isCrossInstance=\(isCrossInstance)")

        var statusId = targetPost.platformSpecificId
        var searchSucceeded = false

        // For cross-instance replies, search for the post on the local server first
        if isCrossInstance {
            print("🔎 Cross-instance reply detected - searching for post on local server...")
            print("   Searching for URL: \(targetPost.originalURL)")
            do {
                let searchResult = try await search(
                    query: targetPost.originalURL,
                    account: account,
                    type: "statuses",
                    limit: 1
                )

                print("   Search returned \(searchResult.statuses.count) statuses")
                if let firstStatus = searchResult.statuses.first {
                    statusId = firstStatus.id
                    searchSucceeded = true
                    print("✅ Found local post ID: \(statusId) (was: \(targetPost.platformSpecificId))")
                } else {
                    print("⚠️  No search results - cross-instance reply may not be federated to local server")
                }
            } catch {
                print("⚠️  Search failed: \(error.localizedDescription)")
                print("   Error details: \(error)")
            }
        }

        // Only use fallback if we don't have a valid status ID
        // Don't override a successful search result!
        if statusId.isEmpty && !searchSucceeded {
            print("🔧 Using fallback ID extraction...")
            if let lastPathComponent = URL(string: targetPost.originalURL)?.lastPathComponent {
                statusId = lastPathComponent
                print("   Extracted ID from URL: \(statusId)")
            } else {
                statusId = targetPost.id
                print("   Using post.id as last resort: \(statusId)")
            }
        }

        print("📝 Final reply statusId: \(statusId) to server: \(serverUrl)")

        guard let url = URL(string: "\(serverUrl)/api/v1/statuses") else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

        var mediaIds: [String] = []
        for (index, attachmentData) in mediaAttachments.enumerated() {
            let altText = index < mediaAltTexts.count ? mediaAltTexts[index] : nil
            let mediaId = try await uploadMedia(
                data: attachmentData, description: altText, account: account)
            mediaIds.append(mediaId)
        }

        // Compile entities from composerTextModel if provided (for mentions/hashtags)
        var finalContent = content
        if let model = composerTextModel {
            finalContent = model.toPlainText()
            // Mastodon API accepts mentions/hashtags as plain text in status
            // Entities are parsed server-side
        }
        
        var parameters: [String: Any] = [
            "status": finalContent,
            "in_reply_to_id": statusId,
            "visibility": visibility,
        ]

        if !mediaIds.isEmpty {
            parameters["media_ids"] = mediaIds
        }
        
        // Handle content warning
        if let spoilerText = spoilerText, !spoilerText.isEmpty {
            parameters["spoiler_text"] = spoilerText
        }
        
        // Handle sensitive flag
        if sensitive {
            parameters["sensitive"] = true
        }

        if !pollOptions.isEmpty {
            parameters["poll"] = [
                "options": pollOptions,
                "expires_in": pollExpiresIn ?? 86400,
            ]
        }

        let request = try await createJSONRequest(
            url: url, method: "POST", account: account, body: parameters)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let errorResponse = try? JSONDecoder().decode(MastodonError.self, from: data) {
                print("❌ Mastodon API error (\(statusCode)): \(errorResponse.error)")
                if let description = errorResponse.errorDescription {
                    print("   Description: \(description)")
                }
                throw errorResponse
            }
            // If we can't decode the error, log the raw response
            if let rawError = String(data: data, encoding: .utf8) {
                print("❌ Mastodon reply failed (\(statusCode)): \(rawError)")
            }
            throw NSError(
                domain: "MastodonService", code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Failed to post reply (HTTP \(statusCode))"])
        }

        let status = try JSONDecoder().decode(MastodonStatus.self, from: data)
        return self.convertMastodonStatusToPost(status, account: account)
    }

    /// Fetch relationship between current user and other accounts
    func fetchRelationships(accountIds: [String], account: SocialAccount) async throws
        -> [MastodonRelationship]
    {
        let serverUrl = formatServerURL(account.serverURL?.absoluteString ?? "")
        var components = URLComponents(string: "\(serverUrl)/api/v1/accounts/relationships")!
        components.queryItems = accountIds.map { URLQueryItem(name: "id[]", value: $0) }

        guard let url = components.url else {
            throw ServiceError.invalidInput(reason: "Invalid account IDs")
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "GET", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.networkError(
                underlying: NSError(domain: "HTTP", code: 0, userInfo: nil))
        }

        if httpResponse.statusCode != 200 {
            throw ServiceError.apiError("Failed to fetch relationships")
        }

        do {
            return try JSONDecoder().decode([MastodonRelationship].self, from: data)
        } catch {
            logger.error("❌ MASTODON: Relationship decode failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Lookup a Mastodon account by acct handle and return its numeric id
    func lookupAccountId(acct: String, account: SocialAccount) async throws -> String {
        let serverUrl = formatServerURL(account.serverURL?.absoluteString ?? "")
        var components = URLComponents(string: "\(serverUrl)/api/v1/accounts/lookup")!
        components.queryItems = [URLQueryItem(name: "acct", value: acct)]

        guard let url = components.url else {
            throw ServiceError.invalidInput(reason: "Invalid acct lookup value")
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "GET", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.networkError(
                underlying: NSError(domain: "HTTP", code: 0, userInfo: nil))
        }

        if httpResponse.statusCode != 200 {
            if let responseString = String(data: data, encoding: .utf8) {
                logger.error("❌ MASTODON: Account lookup failed (\(httpResponse.statusCode)) response: \(String(responseString.prefix(500)))")
            } else {
                logger.error("❌ MASTODON: Account lookup failed (\(httpResponse.statusCode)) with empty response")
            }
            throw ServiceError.apiError("Failed to lookup account")
        }

        let account = try JSONDecoder().decode(MastodonAccount.self, from: data)
        return account.id
    }

    /// Enrich posts with relationship data (following/muting/blocking status)
    /// This fetches relationships for all unique authors in the posts array and updates the posts
    func enrichPostsWithRelationships(_ posts: [Post], account: SocialAccount) async -> [Post] {
        // Skip if no posts or no account
        guard !posts.isEmpty else { return posts }

        // Collect unique author IDs (excluding the current user)
        let currentUserId = account.platformSpecificId
        let uniqueAuthorIds = Array(Set(posts.flatMap { post -> [String] in
            var ids: [String] = []
            if !post.authorId.isEmpty, post.authorId != currentUserId {
                ids.append(post.authorId)
            }
            if let original = post.originalPost,
                !original.authorId.isEmpty,
                original.authorId != currentUserId
            {
                ids.append(original.authorId)
            }
            return ids
        }))

        // Skip if no authors to look up
        guard !uniqueAuthorIds.isEmpty else { return posts }

        // Fetch relationships in batches (Mastodon API typically limits to ~40 per request)
        let batchSize = 40
        var relationshipMap: [String: MastodonRelationship] = [:]

        for batchStart in stride(from: 0, to: uniqueAuthorIds.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, uniqueAuthorIds.count)
            let batch = Array(uniqueAuthorIds[batchStart..<batchEnd])

            do {
                let relationships = try await fetchRelationships(accountIds: batch, account: account)
                for rel in relationships {
                    relationshipMap[rel.id] = rel
                }
            } catch {
                // Log error but continue - we don't want to fail timeline loading
                logger.warning("Failed to fetch relationships for batch: \(error.localizedDescription)")
            }
        }

        // Update posts with relationship data
        for post in posts {
            if let relationship = relationshipMap[post.authorId] {
                post.isFollowingAuthor = relationship.following
                post.isMutedAuthor = relationship.muting
                post.isBlockedAuthor = relationship.blocking
            }
            if let original = post.originalPost,
                let relationship = relationshipMap[original.authorId]
            {
                original.isFollowingAuthor = relationship.following
                original.isMutedAuthor = relationship.muting
                original.isBlockedAuthor = relationship.blocking
            }
        }

        logger.debug("Enriched \(posts.count) posts with \(relationshipMap.count) author relationships")
        return posts
    }

    /// Follow a user on Mastodon
    func followAccount(userId: String, account: SocialAccount) async throws -> MastodonRelationship
    {
        let serverUrl = formatServerURL(account.serverURL?.absoluteString ?? "")
        guard let url = URL(string: "\(serverUrl)/api/v1/accounts/\(userId)/follow") else {
            throw ServiceError.invalidInput(reason: "Invalid user ID")
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "POST", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.apiError("Failed to follow user")
        }

        return try JSONDecoder().decode(MastodonRelationship.self, from: data)
    }

    /// Unfollow a user on Mastodon
    func unfollowAccount(userId: String, account: SocialAccount) async throws
        -> MastodonRelationship
    {
        let serverUrl = formatServerURL(account.serverURL?.absoluteString ?? "")
        guard let url = URL(string: "\(serverUrl)/api/v1/accounts/\(userId)/unfollow") else {
            throw ServiceError.invalidInput(reason: "Invalid user ID")
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "POST", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.apiError("Failed to unfollow user")
        }

        return try JSONDecoder().decode(MastodonRelationship.self, from: data)
    }

    /// Mute a user on Mastodon
    func muteAccount(userId: String, account: SocialAccount) async throws -> MastodonRelationship {
        let serverUrl = formatServerURL(account.serverURL?.absoluteString ?? "")
        guard let url = URL(string: "\(serverUrl)/api/v1/accounts/\(userId)/mute") else {
            throw ServiceError.invalidInput(reason: "Invalid user ID")
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "POST", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.apiError("Failed to mute user")
        }

        return try JSONDecoder().decode(MastodonRelationship.self, from: data)
    }

    /// Unmute a user on Mastodon
    func unmuteAccount(userId: String, account: SocialAccount) async throws -> MastodonRelationship
    {
        let serverUrl = formatServerURL(account.serverURL?.absoluteString ?? "")
        guard let url = URL(string: "\(serverUrl)/api/v1/accounts/\(userId)/unmute") else {
            throw ServiceError.invalidInput(reason: "Invalid user ID")
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "POST", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.apiError("Failed to unmute user")
        }

        return try JSONDecoder().decode(MastodonRelationship.self, from: data)
    }

    /// Block a user on Mastodon
    func blockAccount(userId: String, account: SocialAccount) async throws -> MastodonRelationship {
        let serverUrl = formatServerURL(account.serverURL?.absoluteString ?? "")
        guard let url = URL(string: "\(serverUrl)/api/v1/accounts/\(userId)/block") else {
            throw ServiceError.invalidInput(reason: "Invalid user ID")
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "POST", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.apiError("Failed to block user")
        }

        return try JSONDecoder().decode(MastodonRelationship.self, from: data)
    }

    /// Unblock a user on Mastodon
    func unblockAccount(userId: String, account: SocialAccount) async throws -> MastodonRelationship
    {
        let serverUrl = formatServerURL(account.serverURL?.absoluteString ?? "")
        guard let url = URL(string: "\(serverUrl)/api/v1/accounts/\(userId)/unblock") else {
            throw ServiceError.invalidInput(reason: "Invalid user ID")
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "POST", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.apiError("Failed to unblock user")
        }

        return try JSONDecoder().decode(MastodonRelationship.self, from: data)
    }

    /// Report a user/post on Mastodon
    func reportAccount(
        userId: String, statusIds: [String]? = nil, comment: String? = nil, account: SocialAccount
    ) async throws {
        let serverUrl = formatServerURL(account.serverURL?.absoluteString ?? "")
        guard let url = URL(string: "\(serverUrl)/api/v1/reports") else {
            throw ServiceError.invalidInput(reason: "Invalid report URL")
        }

        var parameters: [String: Any] = ["account_id": userId]
        if let statusIds = statusIds {
            parameters["status_ids"] = statusIds
        }
        if let comment = comment {
            parameters["comment"] = comment
        }

        let request = try await createJSONRequest(
            url: url, method: "POST", account: account, body: parameters)
        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.apiError("Failed to submit report")
        }
    }

    /// Add an account to a list on Mastodon
    func addToList(listId: String, accountId: String, account: SocialAccount) async throws {
        let serverUrl = formatServerURL(account.serverURL?.absoluteString ?? "")
        guard let url = URL(string: "\(serverUrl)/api/v1/lists/\(listId)/accounts") else {
            throw ServiceError.invalidInput(reason: "Invalid list URL")
        }

        let parameters: [String: Any] = ["account_ids": [accountId]]
        let request = try await createJSONRequest(
            url: url, method: "POST", account: account, body: parameters)
        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.apiError("Failed to add account to list")
        }
    }

    /// Fetch all lists for an account on Mastodon
    func fetchLists(account: SocialAccount) async throws -> [MastodonList] {
        let serverUrl = formatServerURL(account.serverURL?.absoluteString ?? "")
        guard let url = URL(string: "\(serverUrl)/api/v1/lists") else {
            throw ServiceError.invalidInput(reason: "Invalid lists URL")
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "GET", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.apiError("Failed to fetch lists")
        }

        return try JSONDecoder().decode([MastodonList].self, from: data)
    }

    /// Vote in a poll on Mastodon
    func voteInPoll(pollId: String, choices: [Int], account: SocialAccount) async throws {
        let serverUrl = formatServerURL(account.serverURL?.absoluteString ?? "")
        guard let url = URL(string: "\(serverUrl)/api/v1/polls/\(pollId)/votes") else {
            throw ServiceError.invalidInput(reason: "Invalid poll vote URL")
        }

        let parameters: [String: Any] = [
            "choices": choices
        ]

        let request = try await createJSONRequest(
            url: url, method: "POST", account: account, body: parameters)
        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.apiError("Failed to vote in poll on Mastodon")
        }
    }

    /// Fetch conversations (DMs) for an account on Mastodon
    func fetchConversations(account: SocialAccount) async throws -> [DMConversation] {
        let serverUrl = formatServerURL(account.serverURL?.absoluteString ?? "")
        guard let url = URL(string: "\(serverUrl)/api/v1/conversations") else {
            throw ServiceError.invalidInput(reason: "Invalid conversations URL")
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "GET", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.apiError("Failed to fetch conversations")
        }

        let mastodonConversations = try JSONDecoder().decode(
            [MastodonConversation].self, from: data)

        return mastodonConversations.map { mastodonConv in
            // Extract emoji map from conversation participant
            let participantEmojiMap: [String: String]? = {
                guard let emojis = mastodonConv.accounts[0].emojis, !emojis.isEmpty else { return nil }
                var map: [String: String] = [:]
                for emoji in emojis {
                    let url = emoji.staticUrl.isEmpty ? emoji.url : emoji.staticUrl
                    if !url.isEmpty { map[emoji.shortcode] = url }
                }
                return map.isEmpty ? nil : map
            }()

            let participant = NotificationAccount(
                id: mastodonConv.accounts[0].id,
                username: mastodonConv.accounts[0].acct,
                displayName: mastodonConv.accounts[0].displayName,
                avatarURL: mastodonConv.accounts[0].avatar,
                displayNameEmojiMap: participantEmojiMap
            )

            let lastMessage = DirectMessage(
                id: mastodonConv.lastStatus.id,
                sender: participant,  // Simplified for now
                recipient: NotificationAccount(
                    id: account.id, username: account.username, displayName: account.displayName,
                    avatarURL: account.profileImageURL?.absoluteString,
                    displayNameEmojiMap: account.displayNameEmojiMap),
                content: HTMLString(raw: mastodonConv.lastStatus.content).plainText,
                createdAt: DateParser.parse(mastodonConv.lastStatus.createdAt) ?? Date(),
                platform: .mastodon
            )

            return DMConversation(
                id: mastodonConv.id,
                participant: participant,
                lastMessage: lastMessage,
                unreadCount: mastodonConv.unread ? 1 : 0,
                platform: .mastodon
            )
        }
    }

    /// Update profile information on Mastodon
    func updateProfile(
        displayName: String?, note: String?, avatarData: Data?, account: SocialAccount
    ) async throws -> SocialAccount {
        let serverUrl = formatServerURL(account.serverURL?.absoluteString ?? "")
        guard let url = URL(string: "\(serverUrl)/api/v1/accounts/update_credentials") else {
            throw ServiceError.invalidInput(reason: "Invalid update credentials URL")
        }

        // Use multipart form data for potential image upload
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try await createAuthenticatedRequest(
            url: url, method: "PATCH", account: account)
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        if let displayName = displayName {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append(
                "Content-Disposition: form-data; name=\"display_name\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(displayName)\r\n".data(using: .utf8)!)
        }
        if let note = note {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"note\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(note)\r\n".data(using: .utf8)!)
        }
        if let avatarData = avatarData {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append(
                "Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.jpg\"\r\n".data(
                    using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(avatarData)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.apiError("Failed to update Mastodon profile")
        }

        let mastodonAccount = try JSONDecoder().decode(MastodonAccount.self, from: data)

        // Update local account object
        account.displayName = mastodonAccount.displayName
        account.bio = mastodonAccount.note
        if let url = URL(string: mastodonAccount.avatar) {
            account.profileImageURL = url
        }
        
        // Update emoji maps for display name and bio
        account.displayNameEmojiMap = extractAccountEmojiMap(from: mastodonAccount)
        // Note: bioEmojiMap would need to be extracted from note HTML if needed

        return account
    }

    // MARK: - Helper Methods

    /// Converts Mastodon statuses to generic Post objects
    private func convertToGenericPosts(statuses: [MastodonStatus]) -> [Post] {
        return statuses.map { convertMastodonStatusToPost($0) }
    }

    /// Converts a Mastodon status to a generic Post
    /// Extracts custom emoji from a MastodonStatus into a dictionary mapping shortcode to URL
    private func extractEmojiMap(from status: MastodonStatus) -> [String: String]? {
        guard !status.emojis.isEmpty else {
            if let htmlMap = extractEmojiMap(fromHTML: status.content), !htmlMap.isEmpty {
                return htmlMap
            }
            return nil
        }
        var emojiMap: [String: String] = [:]
        for emoji in status.emojis {
            // Use staticUrl if available (smaller, faster), otherwise fall back to url
            let emojiURL = emoji.staticUrl.isEmpty ? emoji.url : emoji.staticUrl
            if !emojiURL.isEmpty {
                emojiMap[emoji.shortcode] = emojiURL
            }
        }
        return emojiMap.isEmpty ? nil : emojiMap
    }

    private func extractEmojiMap(fromHTML html: String) -> [String: String]? {
        guard html.contains("emoji"),
            let regex = try? NSRegularExpression(pattern: "<img[^>]*>", options: [.caseInsensitive])
        else {
            return nil
        }

        var emojiMap: [String: String] = [:]
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        for match in matches {
            guard let matchRange = Range(match.range, in: html) else { continue }
            let tag = String(html[matchRange])
            if !tag.lowercased().contains("emoji") { continue }

            guard let alt = attributeValue("alt", in: tag) else { continue }
            let shortcode = alt.trimmingCharacters(in: CharacterSet(charactersIn: " :\t\n\r"))
            guard !shortcode.isEmpty else { continue }

            let url =
                attributeValue("data-static", in: tag)
                ?? attributeValue("src", in: tag)
                ?? attributeValue("data-url", in: tag)
            guard let url, !url.isEmpty else { continue }

            emojiMap[shortcode] = url
        }

        return emojiMap.isEmpty ? nil : emojiMap
    }

    private func attributeValue(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match = regex.firstMatch(in: tag, options: [], range: range) else { return nil }

        if let doubleQuotedRange = Range(match.range(at: 1), in: tag),
            !doubleQuotedRange.isEmpty
        {
            return String(tag[doubleQuotedRange])
        }
        if let singleQuotedRange = Range(match.range(at: 2), in: tag),
            !singleQuotedRange.isEmpty
        {
            return String(tag[singleQuotedRange])
        }
        return nil
    }

    /// Extracts custom emoji from a MastodonAccount (for display name emoji)
    private func extractAccountEmojiMap(from account: MastodonAccount) -> [String: String]? {
        guard let emojis = account.emojis, !emojis.isEmpty else {
            return nil
        }

        var emojiMap: [String: String] = [:]
        for emoji in emojis {
            // Use staticUrl if available (smaller, faster), otherwise fall back to url
            let emojiURL = emoji.staticUrl.isEmpty ? emoji.url : emoji.staticUrl
            if !emojiURL.isEmpty {
                emojiMap[emoji.shortcode] = emojiURL
            }
        }
        guard !emojiMap.isEmpty else { return nil }
        EmojiCache.shared.store(accountId: account.id, emojiMap: emojiMap)
        return emojiMap
    }

    private func resolveAuthorEmojiMap(
        extracted: [String: String]?,
        displayName: String,
        accountId: String
    ) -> [String: String]? {
        if let extracted = extracted, !extracted.isEmpty {
            return extracted
        }
        guard displayName.contains(":"), !accountId.isEmpty else {
            return nil
        }
        return EmojiCache.shared.get(accountId: accountId)
    }
    
    /// Extracts custom emoji from a MastodonReblog into a dictionary mapping shortcode to URL
    private func extractEmojiMap(from reblog: MastodonReblog) -> [String: String]? {
        guard let emojis = reblog.emojis, !emojis.isEmpty else {
            if let content = reblog.content,
                let htmlMap = extractEmojiMap(fromHTML: content),
                !htmlMap.isEmpty
            {
                return htmlMap
            }
            return nil
        }
        var emojiMap: [String: String] = [:]
        for emoji in emojis {
            // Use staticUrl if available (smaller, faster), otherwise fall back to url
            let emojiURL = emoji.staticUrl.isEmpty ? emoji.url : emoji.staticUrl
            if !emojiURL.isEmpty {
                emojiMap[emoji.shortcode] = emojiURL
            }
        }
        return emojiMap.isEmpty ? nil : emojiMap
    }

    private func convertPoll(_ poll: MastodonPoll?) -> Post.Poll? {
        guard let poll = poll else { return nil }
        let options = poll.options.map {
            Post.Poll.PollOption(title: $0.title, votesCount: $0.votesCount)
        }
        return Post.Poll(
            id: poll.id,
            expiresAt: DateParser.parse(poll.expiresAt),
            expired: poll.expired,
            multiple: poll.multiple,
            votesCount: poll.votesCount,
            votersCount: poll.votersCount,
            voted: poll.voted,
            ownVotes: poll.ownVotes,
            options: options
        )
    }

    public func convertMastodonStatusToPost(
        _ status: MastodonStatus, account: SocialAccount? = nil
    ) -> Post {
        // Move the replyToUsername logic to the top of the function
        var replyToUsername: String? = nil
        let instanceDomain: String? = {
            if let host = account?.serverURL?.host, !host.isEmpty {
                return host
            }
            if let urlString = status.url, let host = URL(string: urlString)?.host {
                return host
            }
            return nil
        }()
        func normalizeMastodonHandle(_ rawHandle: String?) -> String? {
            guard let rawHandle = rawHandle?.trimmingCharacters(in: .whitespacesAndNewlines),
                !rawHandle.isEmpty
            else { return nil }
            if rawHandle.contains("@") {
                return rawHandle
            }
            guard let domain = instanceDomain else { return rawHandle }
            return "\(rawHandle)@\(domain)"
        }
        if let replyToAccountId = status.inReplyToAccountId, status.inReplyToId != nil {
            // Improved reply username extraction logic
            // CRITICAL FIX: Check if this is a self-reply first
            if replyToAccountId == status.account.id {
                // Self-reply - use the author's own username
                replyToUsername = normalizeMastodonHandle(status.account.acct)
            } else if let mention = status.mentions.first(where: { $0.id == replyToAccountId }) {
                // Found the reply-to user in mentions
                replyToUsername = normalizeMastodonHandle(mention.acct) ?? mention.username
            } else if let firstMention = status.mentions.first {
                // Fallback to first mention if reply-to account not found
                replyToUsername = normalizeMastodonHandle(firstMention.acct) ?? firstMention.username
            } else if !status.mentions.isEmpty {
                // Last resort: use first mention's username
                replyToUsername = normalizeMastodonHandle(status.mentions.first?.acct)
                    ?? status.mentions.first?.username
            }
        }

        // Check if this is a reblog/boost
        if let reblog = status.reblog {
            // Debug: Log reblog structure
            logger.info(
                "[Mastodon] 🔍 Processing reblog: id=\(reblog.id ?? "nil"), hasMediaAttachments=\(reblog.mediaAttachments?.count ?? 0), mediaAttachments=\(reblog.mediaAttachments?.map { $0.url }.joined(separator: ", ") ?? "none")"
            )
            print(
                "[Mastodon] 🔍 Processing reblog: id=\(reblog.id ?? "nil"), hasMediaAttachments=\(reblog.mediaAttachments?.count ?? 0)"
            )

            let reblogCreatedAt: Date = {
                let createdAtString = reblog.createdAt ?? ""
                let parsedDate = DateParser.parse(createdAtString)
                if parsedDate == nil {
                    logger.error("❌ MASTODON REBLOG DATE PARSE FAILED: '\(createdAtString)'")
                    print("❌ MASTODON REBLOG DATE PARSE FAILED: '\(createdAtString)'")
                }
                return parsedDate ?? Date.distantPast
            }()
            let reblogAttachments: [Post.Attachment] = {
                // Debug: Check what we're working with
                let mediaAttachmentsArray = reblog.mediaAttachments ?? []
                logger.info(
                    "[Mastodon] 🔍 reblog.mediaAttachments is \(reblog.mediaAttachments == nil ? "nil" : "not nil"), count: \(mediaAttachmentsArray.count)"
                )
                if mediaAttachmentsArray.isEmpty && reblog.mediaAttachments != nil {
                    logger.warning(
                        "[Mastodon] ⚠️ reblog.mediaAttachments exists but is empty for reblog \(reblog.id ?? "unknown")"
                    )
                }

                let parsedAttachments = mediaAttachmentsArray.compactMap {
                    media -> Post.Attachment? in
                    let attachmentType: Post.Attachment.AttachmentType
                    switch media.type {
                    case "image":
                        // Check if image is actually a GIF file
                        if let url = URL(string: media.url), URLService.shared.isGIFURL(url) {
                            attachmentType = .animatedGIF
                        } else {
                            attachmentType = .image
                        }
                    case "video":
                        attachmentType = .video
                    case "gifv":
                        // For gifv attachments, check if remoteUrl exists and is a GIF file
                        // Mastodon stores the original GIF in remoteUrl and the video version in url
                        if let remoteUrlString = media.remoteUrl, !remoteUrlString.isEmpty,
                            let remoteURL = URL(string: remoteUrlString),
                            URLService.shared.isGIFURL(remoteURL)
                        {
                            // Use the original GIF file instead of the video
                            return Post.Attachment(
                                url: remoteUrlString,
                                type: .animatedGIF,
                                altText: media.description ?? "Animated GIF",
                                width: media.bestWidth,
                                height: media.bestHeight
                            )
                        } else {
                            // For .gifv type, always use video version (will loop automatically)
                            // Don't check if main URL is a GIF - .gifv URLs are always videos
                            attachmentType = .gifv
                        }
                    case "audio":
                        attachmentType = .audio
                    default:
                        return nil  // Skip unsupported types
                    }
                    return Post.Attachment(
                        url: media.url,
                        type: attachmentType,
                        altText: media.description,
                        width: media.bestWidth,
                        height: media.bestHeight
                    )
                }
                // Log attachments for debugging
                if !parsedAttachments.isEmpty {
                    logger.info(
                        "[Mastodon] 📎 Parsed \(parsedAttachments.count) attachments for reblog \(reblog.id ?? "unknown"): \(parsedAttachments.map { $0.url }.joined(separator: ", "))"
                    )
                    print(
                        "[Mastodon] 📎 Parsed \(parsedAttachments.count) attachments for reblog \(reblog.id ?? "unknown"): \(parsedAttachments.map { $0.url }.joined(separator: ", "))"
                    )
                }
                return parsedAttachments
            }()
            let reblogMentions = (reblog.mentions ?? []).compactMap { $0.username }
            let reblogTags = (reblog.tags ?? []).compactMap { $0.name }
            let reblogPoll = convertPoll(reblog.poll)

            // Extract author emoji map from reblog
            // Try to extract from display name HTML first, then match from reblog.emojis array
            let authorDisplayName = reblog.account?.displayName ?? reblog.account?.acct ?? ""
            let extractedAuthorEmojiMap: [String: String]? = {
                // First try extracting from display name HTML if it contains emoji tags
                if let htmlMap = extractEmojiMap(fromHTML: authorDisplayName), !htmlMap.isEmpty {
                    return htmlMap
                }
                // Otherwise, try matching shortcodes from reblog.emojis array that appear in display name
                if let reblogEmojis = reblog.emojis, !reblogEmojis.isEmpty {
                    var emojiMap: [String: String] = [:]
                    for emoji in reblogEmojis {
                        // Check if this shortcode appears in the display name
                        let shortcodePattern = ":\(emoji.shortcode):"
                        if authorDisplayName.contains(shortcodePattern) {
                            let emojiURL = emoji.staticUrl.isEmpty ? emoji.url : emoji.staticUrl
                            if !emojiURL.isEmpty {
                                emojiMap[emoji.shortcode] = emojiURL
                            }
                        }
                    }
                    return emojiMap.isEmpty ? nil : emojiMap
                }
                return nil
            }()
            if let extractedAuthorEmojiMap = extractedAuthorEmojiMap,
                let accountId = reblog.account?.id
            {
                EmojiCache.shared.store(
                    accountId: accountId,
                    emojiMap: extractedAuthorEmojiMap
                )
            }
            let authorEmojiMap = resolveAuthorEmojiMap(
                extracted: extractedAuthorEmojiMap,
                displayName: authorDisplayName,
                accountId: reblog.account?.id ?? ""
            )
            
            var originalPost = Post(
                id: reblog.id ?? "",
                content: reblog.content ?? "",
                authorName: authorDisplayName,
                authorUsername: reblog.account?.acct ?? "",
                authorId: reblog.account?.id ?? "",
                authorProfilePictureURL: reblog.account?.avatar ?? "",
                createdAt: reblogCreatedAt,
                platform: .mastodon,
                originalURL: reblog.url ?? "",
                attachments: reblogAttachments,
                mentions: reblogMentions,
                tags: reblogTags,
                isReposted: false,
                isLiked: false,
                likeCount: 0,
                repostCount: 0,
                replyCount: 0,
                platformSpecificId: reblog.id ?? "",
                poll: reblogPoll,
                cid: nil,
                primaryLinkURL: nil,
                primaryLinkTitle: nil,
                primaryLinkDescription: nil,
                primaryLinkThumbnailURL: nil,
                blueskyLikeRecordURI: nil,  // Mastodon doesn't use Bluesky record URIs
                blueskyRepostRecordURI: nil,
                customEmojiMap: extractEmojiMap(from: reblog),
                authorEmojiMap: authorEmojiMap,  // Extract emoji from display name HTML or reblog.emojis
                clientName: nil  // MastodonReblog doesn't have application field - client name comes from wrapper status
            )

            // Hydrate originalPost if content is empty (defensive, rare)
            // BUT: Don't hydrate if there are attachments - attachments are valid content
            if originalPost.content.isEmpty,
                originalPost.attachments.isEmpty,
                let acct = account
            {
                logger.info(
                    "[Mastodon] 🔄 Hydrating reblog originalPost \(originalPost.id) - content empty and no attachments"
                )
                Task {
                    if let hydrated = try? await self.fetchPostByID(originalPost.id, account: acct),
                        !hydrated.content.isEmpty
                    {
                        // Preserve attachments from original if hydrated post doesn't have them
                        if !originalPost.attachments.isEmpty && hydrated.attachments.isEmpty {
                            // Create a new Post instance with preserved attachments
                            let preservedHydrated = Post(
                                id: hydrated.id,
                                content: hydrated.content,
                                authorName: hydrated.authorName,
                                authorUsername: hydrated.authorUsername,
                                authorId: hydrated.authorId,
                                authorProfilePictureURL: hydrated.authorProfilePictureURL,
                                createdAt: hydrated.createdAt,
                                platform: hydrated.platform,
                                originalURL: hydrated.originalURL,
                                attachments: originalPost.attachments,  // Preserve original attachments
                                mentions: hydrated.mentions,
                                tags: hydrated.tags,
                                originalPost: hydrated.originalPost,
                                isReposted: hydrated.isReposted,
                                isLiked: hydrated.isLiked,
                                isReplied: hydrated.isReplied,
                                likeCount: hydrated.likeCount,
                                repostCount: hydrated.repostCount,
                                replyCount: hydrated.replyCount,
                                isFollowingAuthor: hydrated.isFollowingAuthor,
                                isMutedAuthor: hydrated.isMutedAuthor,
                                isBlockedAuthor: hydrated.isBlockedAuthor,
                                platformSpecificId: hydrated.platformSpecificId,
                                boostedBy: hydrated.boostedBy,
                                parent: hydrated.parent,
                                inReplyToID: hydrated.inReplyToID,
                                inReplyToUsername: hydrated.inReplyToUsername,
                                quotedPostUri: hydrated.quotedPostUri,
                                quotedPostAuthorHandle: hydrated.quotedPostAuthorHandle,
                                quotedPost: hydrated.quotedPost,
                                poll: hydrated.poll,
                                cid: hydrated.cid,
                                primaryLinkURL: hydrated.primaryLinkURL,
                                primaryLinkTitle: hydrated.primaryLinkTitle,
                                primaryLinkDescription: hydrated.primaryLinkDescription,
                                primaryLinkThumbnailURL: hydrated.primaryLinkThumbnailURL,
                                blueskyLikeRecordURI: hydrated.blueskyLikeRecordURI,
                                blueskyRepostRecordURI: hydrated.blueskyRepostRecordURI,
                                customEmojiMap: hydrated.customEmojiMap,
                                authorEmojiMap: hydrated.authorEmojiMap  // Preserve author emoji map
                            )
                            originalPost = preservedHydrated
                            logger.info(
                                "[Mastodon] ✅ Preserved \(originalPost.attachments.count) attachments during hydration"
                            )
                        } else {
                            originalPost = hydrated
                        }
                    }
                }
            } else if !originalPost.attachments.isEmpty {
                logger.info(
                    "[Mastodon] ⏭️ Skipping hydration for reblog \(originalPost.id) - has \(originalPost.attachments.count) attachments"
                )
            }

            // Log final attachment count before creating boost wrapper
            logger.info(
                "[Mastodon] 🔄 Creating boost wrapper for \(status.id) with originalPost having \(originalPost.attachments.count) attachments"
            )
            if !originalPost.attachments.isEmpty {
                logger.info(
                    "[Mastodon] 📎 Attachment URLs: \(originalPost.attachments.map { $0.url }.joined(separator: ", "))"
                )
            }

            let boostPost = Post(
                id: status.id,
                content: "",  // Reblog doesn't have its own content
                authorName: status.account.displayName ?? status.account.acct,
                authorUsername: status.account.acct,
                authorId: status.account.id,
                authorProfilePictureURL: status.account.avatar,
                createdAt: {
                    let parsedDate = DateParser.parse(status.createdAt)
                    if parsedDate == nil {
                        logger.error("❌ MASTODON DATE PARSE FAILED: '\(status.createdAt)'")
                        print("❌ MASTODON DATE PARSE FAILED: '\(status.createdAt)'")
                    }
                    return parsedDate ?? Date.distantPast
                }(),
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
                boostedBy: {
                    // Use displayName if available and not empty, otherwise use acct
                    let displayName = status.account.displayName
                    let acct = status.account.acct
                    let boostedByValue = (!(displayName?.isEmpty ?? true)) ? displayName! : acct
                    logger.info(
                        "[Mastodon] Setting boostedBy for boost wrapper: displayName=\(displayName ?? "nil"), acct=\(acct), final=\(boostedByValue)"
                    )
                    return boostedByValue
                }(),
                blueskyLikeRecordURI: nil,  // Mastodon doesn't use Bluesky record URIs
                blueskyRepostRecordURI: nil,
                customEmojiMap: nil,  // Boost posts don't have their own content emoji
                authorEmojiMap: nil,  // Boost wrapper doesn't show its own author
                boosterEmojiMap: extractAccountEmojiMap(from: status.account),  // Emoji for the person who boosted
                clientName: status.application?.name  // Extract client name from boost wrapper
            )

            // Log final state after creating boost wrapper
            logger.info(
                "[Mastodon] ✅ Created boost wrapper. Final originalPost attachments: \(boostPost.originalPost?.attachments.count ?? 0), boostedBy: \(boostPost.boostedBy ?? "nil")"
            )

            return boostPost
        }

        // Regular non-boosted post
        let attachments = status.mediaAttachments.compactMap { media -> Post.Attachment? in
            // Accept image, gifv, video, and audio attachments
            let supportedTypes = ["image", "gifv", "video", "audio"]
            guard supportedTypes.contains(media.type), let url = URL(string: media.url),
                !media.url.isEmpty
            else {
                print(
                    "[Mastodon] Skipping unsupported or invalid attachment: \(media.url) type: \(media.type)"
                )
                return nil
            }

            let alt = media.description ?? (media.type == "gifv" ? "Animated GIF" : "Media")
            let attachmentType: Post.Attachment.AttachmentType
            switch media.type {
            case "image":
                // Check if image is actually a GIF file
                let isGIF = URLService.shared.isGIFURL(url)
                if isGIF {
                    attachmentType = .animatedGIF
                } else {
                    attachmentType = .image
                }
            case "video":
                attachmentType = .video
            case "gifv":
                // For gifv attachments, check if remoteUrl exists and is a GIF file
                // Mastodon stores the original GIF in remoteUrl and the video version in url
                if let remoteUrlString = media.remoteUrl, !remoteUrlString.isEmpty,
                    let remoteURL = URL(string: remoteUrlString),
                    URLService.shared.isGIFURL(remoteURL)
                {
                    // Use the original GIF file instead of the video
                    return Post.Attachment(
                        url: remoteUrlString,
                        type: .animatedGIF,
                        altText: alt,
                        width: media.meta?.small?.width ?? media.meta?.original?.width,
                        height: media.meta?.small?.height ?? media.meta?.original?.height
                    )
                } else {
                    // For .gifv type, always use video version (will loop automatically at normal speed)
                    // Don't check if main URL is a GIF - .gifv URLs are always videos
                    attachmentType = .gifv
                }
            case "audio":
                attachmentType = .audio
            default:
                return nil  // Skip unsupported types
            }
            print(
                "[Mastodon] Parsed \(media.type) attachment: \(url) alt: \(alt) -> \(attachmentType)"
            )
            return Post.Attachment(
                url: media.url,
                type: attachmentType,
                altText: alt,
                width: media.meta?.small?.width ?? media.meta?.original?.width,
                height: media.meta?.small?.height ?? media.meta?.original?.height
            )
        }

        let mentions = status.mentions.compactMap { mention -> String in
            normalizeMastodonHandle(mention.acct) ?? mention.username
        }

        let tags = status.tags.compactMap { tag -> String in
            return tag.name
        }

        // Use DateParser for consistent date parsing
        let createdDate =
            DateParser.parse(status.createdAt)
            ?? {
                logger.error("❌ MASTODON MAIN DATE PARSE FAILED: '\(status.createdAt)'")
                print("❌ MASTODON MAIN DATE PARSE FAILED: '\(status.createdAt)'")
                return Date.distantPast
            }()

        // Log reply status information
        if let replyToId = status.inReplyToId {
            logger.info(
                "Converting Mastodon reply post: id=\(status.id), in_reply_to_id=\(replyToId)")
        } else {
            logger.debug("Converting regular Mastodon post (not a reply): id=\(status.id)")
        }

        // Try to find the username being replied to from mentions
        var parentPost: Post? = nil

        if status.inReplyToAccountId != nil, let replyToId = status.inReplyToId,
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

        // Extract link preview card data if present
        let cardURL: URL? = status.card.flatMap { URL(string: $0.url) }
        let cardTitle: String? = status.card?.title
        let cardDescription: String? = status.card?.description
        let cardThumbnailURL: URL? = status.card?.image.flatMap { URL(string: $0) }
        
        if let card = status.card {
            logger.debug("[Mastodon] Found card for post \(status.id): url=\(card.url), title=\(card.title)")
        }
        
        let authorDisplayName = status.account.displayName ?? status.account.acct
        let extractedAuthorEmojiMap = extractAccountEmojiMap(from: status.account)
        let resolvedAuthorEmojiMap = resolveAuthorEmojiMap(
            extracted: extractedAuthorEmojiMap,
            displayName: authorDisplayName,
            accountId: status.account.id
        )

        let post = Post(
            id: status.id,
            content: status.content,
            authorName: authorDisplayName,
            authorUsername: status.account.acct,
            authorId: status.account.id,
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
            poll: convertPoll(status.poll),
            cid: nil,
            primaryLinkURL: cardURL,
            primaryLinkTitle: cardTitle,
            primaryLinkDescription: cardDescription,
            primaryLinkThumbnailURL: cardThumbnailURL,
            blueskyLikeRecordURI: nil,  // Mastodon doesn't use Bluesky record URIs
            blueskyRepostRecordURI: nil,
            customEmojiMap: extractEmojiMap(from: status),
            authorEmojiMap: resolvedAuthorEmojiMap,  // Emoji in author's display name
            clientName: status.application?.name  // Extract client/application name
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
        content: String,
        mediaAttachments: [Data] = [],
        mediaAltTexts: [String] = [],
        pollOptions: [String] = [],
        pollExpiresIn: Int? = nil,
        visibility: String = "public",
        account: SocialAccount,
        spoilerText: String? = nil,
        sensitive: Bool = false,
        composerTextModel: ComposerTextModel? = nil
    ) async throws -> Post {
        let serverUrl = formatServerURL(
            account.serverURL?.absoluteString ?? "")

        // First upload any media attachments
        var mediaIds: [String] = []

        for (index, attachmentData) in mediaAttachments.enumerated() {
            let altText = index < mediaAltTexts.count ? mediaAltTexts[index] : nil
            let mediaId = try await uploadMedia(
                data: attachmentData, description: altText, account: account)
            mediaIds.append(mediaId)
        }

        // Then create the post with references to the media
        guard let url = URL(string: "\(serverUrl)/api/v1/statuses") else {
            throw NSError(
                domain: "MastodonService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

        // Compile entities from composerTextModel if provided (for mentions/hashtags)
        var finalContent = content
        if let model = composerTextModel {
            finalContent = model.toPlainText()
            // Mastodon API accepts mentions/hashtags as plain text in status
            // Entities are parsed server-side, but we can include them for clarity
            // Note: Mastodon doesn't require explicit entity ranges in the API
        }
        
        var parameters: [String: Any] = [
            "status": finalContent,
            "visibility": visibility,
        ]

        if !mediaIds.isEmpty {
            parameters["media_ids"] = mediaIds
        }
        
        // Handle content warning
        if let spoilerText = spoilerText, !spoilerText.isEmpty {
            parameters["spoiler_text"] = spoilerText
        }
        
        // Handle sensitive flag (CW enabled OR any attachment marked sensitive)
        if sensitive {
            parameters["sensitive"] = true
        }

        // Handle poll
        if !pollOptions.isEmpty {
            parameters["poll"] = [
                "options": pollOptions,
                "expires_in": pollExpiresIn ?? 86400,  // Default 24 hours
            ]
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
        return self.convertMastodonStatusToPost(status, account: account)
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
        let posts = convertToGenericPosts(statuses: statuses)
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
            #if DEBUG
            print("🔐 Using access token for \(account.username)")
            print("🌐 Making Mastodon API request to: \(endpoint)")
            #endif
            let (data, response) = try await URLSession.shared.data(for: request)

            // Check HTTP response status
            if let httpResponse = response as? HTTPURLResponse {
                print(
                    "📡 Mastodon API response status for \(account.username): \(httpResponse.statusCode)"
                )

                // Handle rate limiting (429) gracefully for background profile updates
                if httpResponse.statusCode == 429 {
                    let resetHeader = httpResponse.value(forHTTPHeaderField: "x-ratelimit-reset")
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")

                    // Parse rate limit reset time
                    let retrySeconds: TimeInterval
                    if let resetTime = parseRateLimitReset(resetHeader) {
                        retrySeconds = resetTime
                    } else if let retryAfterValue = retryAfter,
                        let seconds = TimeInterval(retryAfterValue)
                    {
                        retrySeconds = seconds
                    } else {
                        retrySeconds = 60  // Default to 60 seconds if we can't parse
                    }

                    print(
                        "⚠️ Rate limited while updating profile for \(account.username) - retry after: \(Int(retrySeconds)) seconds"
                    )
                    return  // Silently fail for background operations
                }

                if httpResponse.statusCode != 200 {
                    print(
                        "❌ Mastodon API returned error status \(httpResponse.statusCode) for \(account.username)"
                    )
                    #if DEBUG
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("❌ Response body: \(responseString)")
                    }
                    #endif
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
                let username = mastodonAccount.username
                DispatchQueue.main.async { [avatarURL] in
                    account.profileImageURL = avatarURL
                    print(
                        "✅ Updated Mastodon account \(username) with profile image URL"
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
        let displayName =
            (userInfo.displayName?.isEmpty ?? true)
            ? userInfo.username : (userInfo.displayName ?? userInfo.username)
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
        
        // Set emoji maps for display name and bio
        account.displayNameEmojiMap = extractAccountEmojiMap(from: userInfo)
        // Note: bioEmojiMap would need to be extracted from note HTML if needed

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
            return self.convertMastodonStatusToPost(status, account: account)
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
    private let statusCacheLock = NSLock()
    private var statusCache: [String: (post: Post, timestamp: Date)] = [:]

    private func getCachedStatus(id: String) -> Post? {
        statusCacheLock.lock()
        defer { statusCacheLock.unlock() }
        if let cached = statusCache[id], Date().timeIntervalSince(cached.timestamp) < 300 {
            return cached.post
        }
        return nil
    }

    private func updateStatusCache(id: String, post: Post) {
        statusCacheLock.lock()
        defer { statusCacheLock.unlock() }
        statusCache[id] = (post: post, timestamp: Date())
    }

    /// Fetches a status by its ID
    /// - Parameter id: The ID of the status to fetch
    /// - Parameter account: The account to use for authentication
    /// - Returns: The post if found, nil otherwise
    func fetchStatus(id: String, account: SocialAccount) async throws -> Post? {
        // Check cache first - posts are valid for 5 minutes
        if let cached = getCachedStatus(id: id) {
            logger.info("Using cached Mastodon status for ID: \(id)")
            return cached
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
            logger.info("Sending request to fetch Mastodon status: \(url.absoluteString)")

            let (data, response) = try await session.data(for: finalRequest)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                if let errorMessage = String(data: data, encoding: .utf8) {
                    logger.error(
                        "Error response (\((response as? HTTPURLResponse)?.statusCode ?? 0)): \(errorMessage)"
                    )
                }
                throw NSError(
                    domain: "MastodonService",
                    code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to fetch status"])
            }

            #if DEBUG
            if let responseStr = String(data: data, encoding: .utf8) {
                logger.debug("Raw response from Mastodon API: \(responseStr.prefix(200))...")
            }
            #endif

            let status = try JSONDecoder().decode(MastodonStatus.self, from: data)
            logger.info(
                "Successfully decoded Mastodon status: id=\(status.id), in_reply_to_id=\(status.inReplyToId ?? "nil")"
            )

            let post = self.convertMastodonStatusToPost(status, account: account)
            logger.info(
                "Converted to Post model: id=\(post.id), inReplyToID=\(post.inReplyToID ?? "nil")"
            )

            updateStatusCache(id: id, post: post)

            return post
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
        if let cached = getCachedStatus(id: id) {
            logger.info("Using cached Mastodon status for callback API: \(id)")
            completion(cached)
            return
        }

        // Use a higher priority task for better UI responsiveness
        Task(priority: .userInitiated) {
            // Find an account to use
            guard let account = await findValidAccount() else {
                logger.error("No valid account found for fetching status")
                await MainActor.run {
                    completion(nil)
                }
                return
            }

            do {
                let post = try await fetchStatus(id: id, account: account)

                if let post {
                    updateStatusCache(id: id, post: post)
                }

                await MainActor.run {
                    completion(post)
                }
            } catch {
                logger.error("Error fetching status: \(error.localizedDescription)")
                await MainActor.run {
                    completion(nil)
                }
            }
        }
    }

    /// Find a valid account to use for API requests
    @MainActor
    private func findValidAccount() -> SocialAccount? {
        // TODO: This is a legacy method that should be removed in favor of explicit account passing
        // For now, return nil to avoid dependency issues
        // All new code should use the async methods that take an explicit account parameter
        return nil
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

            // Fetch the main status itself (context endpoint doesn't include it)
            let mainPost = try? await fetchStatus(id: statusId, account: account)

            logger.info(
                "Successfully fetched context: mainPost=\(mainPost != nil ? "yes" : "no"), \(ancestors.count) ancestors, \(descendants.count) descendants"
            )

            return ThreadContext(mainPost: mainPost, ancestors: ancestors, descendants: descendants)
        } catch {
            logger.error("Error fetching status context: \(error.localizedDescription)")
            throw error
        }
    }

    /// Fetch following accounts for a Mastodon account
    public func fetchFollowing(for account: SocialAccount) async throws -> Set<UserID> {
        guard let serverURLString = account.serverURL else {
            throw ServiceError.invalidAccount(reason: "No server URL")
        }

        let serverUrl = formatServerURL(serverURLString.absoluteString)
        let accountId = account.platformSpecificId

        guard !accountId.isEmpty else {
            throw ServiceError.invalidAccount(reason: "Account ID not found")
        }

        guard let url = URL(string: "\(serverUrl)/api/v1/accounts/\(accountId)/following?limit=80")
        else {
            throw ServiceError.invalidInput(reason: "Invalid URL")
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "GET", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.apiError("Failed to fetch following")
        }

        struct MastodonAccount: Codable {
            let acct: String
        }

        let following = try JSONDecoder().decode([MastodonAccount].self, from: data)
        let instanceDomain = serverUrl.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")

        return Set(
            following.map { mastodonAccount in
                let handle =
                    mastodonAccount.acct.contains("@")
                    ? mastodonAccount.acct : "\(mastodonAccount.acct)@\(instanceDomain)"
                return UserID(value: handle, platform: .mastodon)
            })
    }

    /// Fetch accounts that reblogged (boosted) a status.
    public func fetchRebloggedBy(
        statusId: String,
        account: SocialAccount,
        limit: Int = 80
    ) async throws -> [MastodonAccount] {
        guard let serverURLString = account.serverURL else {
            throw ServiceError.invalidAccount(reason: "No server URL")
        }

        let serverUrl = formatServerURL(serverURLString.absoluteString)
        guard
            let url = URL(
                string: "\(serverUrl)/api/v1/statuses/\(statusId)/reblogged_by?limit=\(limit)")
        else {
            throw ServiceError.invalidInput(reason: "Invalid URL")
        }

        let request = try await createAuthenticatedRequest(
            url: url, method: "GET", account: account)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.apiError("Failed to fetch boosters")
        }

        return try JSONDecoder().decode([MastodonAccount].self, from: data)
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

/// Resolver for Mastodon thread participants
public final class MastodonThreadResolver: ThreadParticipantResolver {
    private let service: MastodonService
    private let accountProvider: @Sendable () async -> SocialAccount?

    public init(
        service: MastodonService, accountProvider: @escaping @Sendable () async -> SocialAccount?
    ) {
        self.service = service
        self.accountProvider = accountProvider
    }

    public func getThreadParticipants(for post: Post) async throws -> Set<UserID> {
        guard let account = await accountProvider() else { return [] }
        let context = try await service.fetchStatusContext(
            statusId: post.platformSpecificId, account: account)

        var participants = Set<UserID>()
        // Add author of current post
        participants.insert(UserID(value: post.authorUsername, platform: .mastodon))

        // Add authors of ancestors
        for ancestor in context.ancestors {
            participants.insert(UserID(value: ancestor.authorUsername, platform: .mastodon))
        }

        // Add authors of descendants
        for descendant in context.descendants {
            participants.insert(UserID(value: descendant.authorUsername, platform: .mastodon))
        }

        return participants
    }
}

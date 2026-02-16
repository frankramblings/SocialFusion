import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI
import UIKit

/// Model for storing OAuth credentials
struct OAuthCredentials {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let accountId: String
    let username: String
    let displayName: String
    let serverURL: String
    let clientId: String
    let clientSecret: String
}

/// Custom errors for OAuth process
enum OAuthError: Error, LocalizedError {
    case invalidServerURL
    case registrationFailed
    case missingAuthorizationCode
    case authenticationCancelled
    case tokenExchangeFailed
    case userInfoFailed
    case stateMismatch
    case invalidCallbackURL
    case missingCredentials
    case serverError(error: String, description: String)
    case appRegistrationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Invalid server URL"
        case .registrationFailed:
            return "Failed to register application with server"
        case .missingAuthorizationCode:
            return "Authorization code not received from server"
        case .authenticationCancelled:
            return "Authentication was cancelled"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code for token"
        case .userInfoFailed:
            return "Failed to retrieve user information"
        case .stateMismatch:
            return "State parameter mismatch (potential CSRF attack)"
        case .invalidCallbackURL:
            return "Received invalid callback URL"
        case .missingCredentials:
            return "Missing authentication credentials"
        case .serverError(let error, let description):
            // For rate limits and user-friendly errors, return description directly
            if error == "rate_limit" {
                return description
            }
            return description.isEmpty ? "Server error: \(error)" : description
        case .appRegistrationFailed(let error):
            return "Application registration failed: \(error.localizedDescription)"
        }
    }
}

class OAuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    // MARK: - Published Properties

    @Published var isAuthenticating = false
    @Published var authenticationError: Error?

    // MARK: - Private Properties

    private var authenticationSession: ASWebAuthenticationSession?
    private var completionHandler: ((Result<OAuthCredentials, Error>) -> Void)?
    private var codeVerifier: String?
    private var state: String?
    private var currentServer: String?
    private var clientId: String?
    private var clientSecret: String?

    // Store temporary credentials during the auth flow
    private var pendingCredentials = [String: Any]()

    // Cache for app registrations to avoid re-registering with the same server
    private var appRegistrationCache = [String: (clientId: String, clientSecret: String)]()

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return window
        }
        
        return ASPresentationAnchor()
    }

    // MARK: - Public Methods

    /// Begin OAuth authentication process for a Mastodon server
    func authenticateMastodon(
        server: String,
        completion: @escaping (Result<OAuthCredentials, Error>) -> Void
    ) {
        NSLog("🔐 [OAuth] authenticateMastodon called for: %@", server)
        guard !isAuthenticating else {
            NSLog("⚠️ [OAuth] Already authenticating, ignoring request for: %@", server)
            completion(.failure(OAuthError.serverError(error: "busy", description: "Authentication already in progress")))
            return
        }
        
        NSLog("🔐 [OAuth] Starting authentication process...")

        self.isAuthenticating = true
        self.authenticationError = nil
        self.completionHandler = completion
        self.currentServer = formatServerURL(server)

        // Generate security parameters
        self.state = generateRandomState()
        self.codeVerifier = generateCodeVerifier()

        Task {
            do {
                NSLog("🔐 [OAuth] Step 1: Registering app or getting cached credentials...")
                // Step 1: Register app with server (or get cached credentials)
                let (clientId, clientSecret) = try await getOrRegisterApp(server: currentServer!)
                self.clientId = clientId
                self.clientSecret = clientSecret
                
                NSLog("🔐 [OAuth] Step 2: Starting OAuth flow")

                // Step 2: Start OAuth flow
                await MainActor.run {
                    self.startOAuthFlow(clientId: clientId)
                }

            } catch {
                NSLog("❌ [OAuth] Authentication failed during registration: \(error.localizedDescription)")
                await MainActor.run {
                    self.isAuthenticating = false
                    self.authenticationError = error
                    completion(.failure(error))
                }
            }
        }
    }

    /// Handle callback URL from OAuth redirect
    func handleCallback(url: URL) {
        guard let completionHandler = self.completionHandler else {
            NSLog("No completion handler available for OAuth callback")
            return
        }

        // Parse callback URL
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let queryItems = components.queryItems
        else {
            let error = OAuthError.invalidCallbackURL
            self.authenticationError = error
            completionHandler(.failure(error))
            return
        }

        // Check for state parameter
        let receivedState = queryItems.first { $0.name == "state" }?.value
        guard receivedState == self.state else {
            let error = OAuthError.stateMismatch
            self.authenticationError = error
            completionHandler(.failure(error))
            return
        }

        // Check for authorization code
        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            let error = OAuthError.missingAuthorizationCode
            self.authenticationError = error
            completionHandler(.failure(error))
            return
        }

        // Exchange code for tokens
        Task {
            await exchangeCodeForTokens(code: code)
        }
    }

    // MARK: - Private Methods

    /// Get or register app with the Mastodon server
    private func getOrRegisterApp(server: String) async throws -> (
        clientId: String, clientSecret: String
    ) {
        // Check cache first
        if let cached = appRegistrationCache[server] {
            NSLog("🔐 [OAuth] Using cached app credentials for: %@", server)
            return cached
        }

        NSLog("🔐 [OAuth] No cached credentials, registering new app for: %@", server)
        // Register new app
        let credentials = try await registerApp(server: server)
        appRegistrationCache[server] = credentials
        return credentials
    }

    /// Register the app with a Mastodon server
    private func registerApp(server: String) async throws -> (
        clientId: String, clientSecret: String
    ) {
        NSLog("🔐 [OAuth] Registering app with server: %@", server)
        guard let url = URL(string: "\(server)/api/v1/apps") else {
            NSLog("❌ [OAuth] Invalid URL for app registration: %@", server)
            throw OAuthError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("SocialFusion/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30.0 // Increased to 30 seconds

        let parameters: [String: Any] = [
            "client_name": "SocialFusion",
            "redirect_uris": "socialfusion://oauth",
            "scopes": "read write follow push",
            "website": "https://github.com/frankramblings/SocialFusion",
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        NSLog("🔐 [OAuth] Sending app registration request to: %@", url.absoluteString)
        let (data, response) = try await URLSession.shared.data(for: request)
        NSLog("🔐 [OAuth] Received response from app registration")

        guard let httpResponse = response as? HTTPURLResponse else {
            NSLog("❌ [OAuth] Registration failed: No HTTP response")
            throw OAuthError.registrationFailed
        }
        
        NSLog("🔐 [OAuth] Registration response status code: %d", httpResponse.statusCode)
        
        if httpResponse.statusCode != 200 {
            NSLog("❌ [OAuth] Registration failed with status: %d", httpResponse.statusCode)
            if let errorString = String(data: data, encoding: .utf8) {
                NSLog("❌ [OAuth] Registration error body: %@", errorString)
            }
            throw OAuthError.registrationFailed
        }

        let app = try JSONDecoder().decode(MastodonApp.self, from: data)
        return (app.clientId, app.clientSecret)
    }

    /// Start the OAuth authorization flow
    private func startOAuthFlow(clientId: String) {
        guard let server = currentServer else {
            NSLog("❌ [OAuth] Error: No current server set")
            return
        }

        let authURL = buildAuthorizationURL(server: server, clientId: clientId)
        NSLog("🔐 [OAuth] Building ASWebAuthenticationSession with URL: \(authURL.absoluteString)")

        authenticationSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "socialfusion"
        ) { [weak self] callbackURL, error in
            guard let self = self else { return }

            if let error = error {
                NSLog("❌ [OAuth] ASWebAuthenticationSession returned error: \(error.localizedDescription)")
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    self.authenticationError = OAuthError.authenticationCancelled
                } else {
                    self.authenticationError = error
                }
                self.isAuthenticating = false
                self.completionHandler?(.failure(error))
                return
            }

            if let callbackURL = callbackURL {
                NSLog("✅ [OAuth] Received callback URL: \(callbackURL.absoluteString)")
                self.handleCallback(url: callbackURL)
            }
        }

        authenticationSession?.presentationContextProvider = self
        authenticationSession?.prefersEphemeralWebBrowserSession = false
        
        NSLog("🔐 [OAuth] Starting ASWebAuthenticationSession...")
        let started = authenticationSession?.start() ?? false
        if !started {
            NSLog("❌ [OAuth] Failed to start ASWebAuthenticationSession")
            self.isAuthenticating = false
            self.completionHandler?(.failure(OAuthError.registrationFailed))
        } else {
            NSLog("✅ [OAuth] ASWebAuthenticationSession started successfully")
        }
    }

    /// Build the authorization URL
    private func buildAuthorizationURL(server: String, clientId: String) -> URL {
        var components = URLComponents(string: "\(server)/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: "socialfusion://oauth"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "read write follow push"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// Exchange authorization code for access token
    private func exchangeCodeForTokens(code: String) async {
        guard let server = currentServer,
            let clientId = self.clientId,
            let clientSecret = self.clientSecret,
            let completionHandler = self.completionHandler
        else {
            return
        }

        do {
            guard let url = URL(string: "\(server)/oauth/token") else {
                throw OAuthError.invalidServerURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("SocialFusion/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 30.0

            let parameters: [String: Any] = [
                "client_id": clientId,
                "client_secret": clientSecret,
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": "socialfusion://oauth",
                "scope": "read write follow push",
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                throw OAuthError.tokenExchangeFailed
            }

            let token = try JSONDecoder().decode(MastodonToken.self, from: data)

            // Get user info
            let userInfo = try await getUserInfo(server: server, accessToken: token.accessToken)

            // Create credentials object
            let credentials = OAuthCredentials(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken,
                expiresAt: token.expirationDate,
                accountId: userInfo.id,
                username: userInfo.username,
                displayName: userInfo.displayName ?? userInfo.username,
                serverURL: server,
                clientId: clientId,
                clientSecret: clientSecret
            )

            await MainActor.run {
                self.isAuthenticating = false
                completionHandler(.success(credentials))
            }

        } catch {
            await MainActor.run {
                self.isAuthenticating = false
                self.authenticationError = error
                completionHandler(.failure(error))
            }
        }
    }

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
            return max(0, secondsUntilReset) // Ensure non-negative
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
    
    /// Format time interval as human-readable string
    private func formatRetryTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.0f seconds", seconds)
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            if minutes > 0 {
                return "\(hours) hour\(hours == 1 ? "" : "s"), \(minutes) minute\(minutes == 1 ? "" : "s")"
            } else {
                return "\(hours) hour\(hours == 1 ? "" : "s")"
            }
        }
    }

    /// Get user information from the server
    private func getUserInfo(server: String, accessToken: String) async throws -> MastodonAccount {
        let urlString = "\(server)/api/v1/accounts/verify_credentials"
        NSLog("🔐 [OAuth] Getting user info from: %@", urlString)
        
        guard let url = URL(string: urlString) else {
            NSLog("❌ [OAuth] Invalid URL for verify_credentials: %@", urlString)
            throw OAuthError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("SocialFusion/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30.0

        NSLog("🔐 [OAuth] Making verify_credentials request...")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            NSLog("❌ [OAuth] No HTTP response received")
            throw OAuthError.userInfoFailed
        }
        
        NSLog("🔐 [OAuth] verify_credentials response status: %d", httpResponse.statusCode)
        
        guard httpResponse.statusCode == 200 else {
            // Log error details
            let errorBody = String(data: data, encoding: .utf8) ?? "No error details"
            NSLog("❌ [OAuth] verify_credentials error response (status \(httpResponse.statusCode)): %@", errorBody)
            
            // Handle rate limiting (429) with specific messaging and retry logic
            if httpResponse.statusCode == 429 {
                let resetHeader = httpResponse.value(forHTTPHeaderField: "x-ratelimit-reset")
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                
                // Parse rate limit reset time
                let retrySeconds: TimeInterval
                if let resetTime = parseRateLimitReset(resetHeader) {
                    retrySeconds = resetTime
                } else if let retryAfterValue = retryAfter, let seconds = TimeInterval(retryAfterValue) {
                    retrySeconds = seconds
                } else {
                    retrySeconds = 60 // Default to 60 seconds if we can't parse
                }
                
                let retryTimeFormatted = formatRetryTime(retrySeconds)
                let errorMessage = "Too many requests to Mastodon server. Please wait \(retryTimeFormatted) and try adding the account again."
                
                NSLog("❌ [OAuth] Rate limited during account addition - retry after: %.0f seconds (reset header: %@, retry-after: %@)", retrySeconds, resetHeader ?? "nil", retryAfter ?? "nil")
                throw OAuthError.serverError(error: "rate_limit", description: errorMessage)
            }
            
            // Provide more specific error messages based on status code
            let errorMessage: String
            switch httpResponse.statusCode {
            case 401:
                errorMessage = "Authentication failed. The access token may be invalid or expired. Please try adding the account again."
            case 403:
                errorMessage = "Access forbidden. Your token may not have the required permissions. Please try adding the account again."
            case 404:
                errorMessage = "Server endpoint not found. Please check the server URL and try again."
            case 500...599:
                errorMessage = "Mastodon server error (\(httpResponse.statusCode)). The server may be experiencing issues. Please try again later."
            default:
                errorMessage = "Failed to retrieve user information (HTTP \(httpResponse.statusCode)). Please try adding the account again."
            }
            
            NSLog("❌ [OAuth] verify_credentials failed: %@", errorMessage)
            throw OAuthError.serverError(error: "http_\(httpResponse.statusCode)", description: errorMessage)
        }

        // Check if response is empty
        if data.isEmpty {
            NSLog("❌ [OAuth] Empty response from verify_credentials")
            throw OAuthError.userInfoFailed
        }

        do {
            let account = try JSONDecoder().decode(MastodonAccount.self, from: data)
            NSLog("✅ [OAuth] Successfully retrieved user info for: %@", account.username)
            return account
        } catch {
            NSLog("❌ [OAuth] Failed to decode MastodonAccount: %@", error.localizedDescription)
            if let jsonString = String(data: data, encoding: .utf8) {
                NSLog("❌ [OAuth] Response body: %@", String(jsonString.prefix(500)))
            }
            throw OAuthError.userInfoFailed
        }
    }

    /// Formats a server URL to ensure it has the correct scheme
    private func formatServerURL(_ server: String) -> String {
        var formatted = server.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure scheme
        if !formatted.hasPrefix("http://") && !formatted.hasPrefix("https://") {
            formatted = "https://" + formatted
        }
        
        // Remove trailing slashes
        while formatted.hasSuffix("/") {
            formatted.removeLast()
        }
        
        return formatted
    }

    // Helper method to generate random state string for CSRF protection
    private func generateRandomState() -> String {
        return UUID().uuidString
    }

    // Helper method to generate PKCE code verifier
    private func generateCodeVerifier() -> String {
        return UUID().uuidString
    }

    // Helper method to generate code challenge from verifier
    private func generateCodeChallenge(from verifier: String) -> String {
        return verifier  // simplified
    }
}

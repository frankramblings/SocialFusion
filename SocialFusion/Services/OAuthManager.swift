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
            return "Server error: \(error) - \(description)"
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
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        let window = windowScene?.windows.first ?? UIWindow()
        return window
    }

    // MARK: - Public Methods

    /// Begin OAuth authentication process for a Mastodon server
    func authenticateMastodon(
        server: String,
        completion: @escaping (Result<OAuthCredentials, Error>) -> Void
    ) {
        guard !isAuthenticating else { return }

        self.isAuthenticating = true
        self.authenticationError = nil
        self.completionHandler = completion
        self.currentServer = formatServerURL(server)

        // Generate security parameters
        self.state = generateRandomState()
        self.codeVerifier = generateCodeVerifier()

        Task {
            do {
                // Step 1: Register app with server (or get cached credentials)
                let (clientId, clientSecret) = try await getOrRegisterApp(server: currentServer!)
                self.clientId = clientId
                self.clientSecret = clientSecret

                // Step 2: Start OAuth flow
                await MainActor.run {
                    self.startOAuthFlow(clientId: clientId)
                }

            } catch {
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
            print("No completion handler available for OAuth callback")
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
            return cached
        }

        // Register new app
        let credentials = try await registerApp(server: server)
        appRegistrationCache[server] = credentials
        return credentials
    }

    /// Register the app with a Mastodon server
    private func registerApp(server: String) async throws -> (
        clientId: String, clientSecret: String
    ) {
        guard let url = URL(string: "\(server)/api/v1/apps") else {
            throw OAuthError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let parameters: [String: Any] = [
            "client_name": "SocialFusion",
            "redirect_uris": "socialfusion://oauth",
            "scopes": "read write follow push",
            "website": "https://github.com/yourusername/socialfusion",  // Update with actual repo
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw OAuthError.registrationFailed
        }

        let app = try JSONDecoder().decode(MastodonApp.self, from: data)
        return (app.clientId, app.clientSecret)
    }

    /// Start the OAuth authorization flow
    private func startOAuthFlow(clientId: String) {
        guard let server = currentServer else { return }

        let authURL = buildAuthorizationURL(server: server, clientId: clientId)

        authenticationSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "socialfusion"
        ) { [weak self] callbackURL, error in
            guard let self = self else { return }

            if let error = error {
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
                self.handleCallback(url: callbackURL)
            }
        }

        authenticationSession?.presentationContextProvider = self
        authenticationSession?.prefersEphemeralWebBrowserSession = false
        authenticationSession?.start()
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

    /// Get user information from the server
    private func getUserInfo(server: String, accessToken: String) async throws -> MastodonAccount {
        guard let url = URL(string: "\(server)/api/v1/accounts/verify_credentials") else {
            throw OAuthError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw OAuthError.userInfoFailed
        }

        return try JSONDecoder().decode(MastodonAccount.self, from: data)
    }

    /// Formats a server URL to ensure it has the correct scheme
    private func formatServerURL(_ server: String) -> String {
        let lowercasedServer = server.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if !lowercasedServer.hasPrefix("http://") && !lowercasedServer.hasPrefix("https://") {
            return "https://" + lowercasedServer
        }
        return lowercasedServer
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

import Foundation

/// Manages OAuth token lifecycle including refreshing and expiration
class TokenManager {

    enum TokenError: Error, LocalizedError {
        case refreshFailed
        case noRefreshToken
        case noClientCredentials
        case invalidServerURL
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .refreshFailed:
                return "Failed to refresh token"
            case .noRefreshToken:
                return "No refresh token available"
            case .noClientCredentials:
                return "Missing client credentials"
            case .invalidServerURL:
                return "Invalid server URL"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            }
        }
    }

    /// Refresh an expired token for a Mastodon account
    /// - Parameter account: The account whose token needs refreshing
    /// - Returns: Updated access token and expiration date
    static func refreshMastodonToken(for account: SocialAccount) async throws -> (
        token: String, expiresAt: Date?
    ) {
        guard let refreshToken = account.getRefreshToken() else {
            throw TokenError.noRefreshToken
        }

        guard let clientId = account.getClientId(),
            let clientSecret = account.getClientSecret()
        else {
            throw TokenError.noClientCredentials
        }

        // Prepare the server URL
        let serverURL = account.serverURL

        guard let url = URL(string: "\(serverURL)/oauth/token") else {
            throw TokenError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Set up token refresh request
        let parameters: [String: Any] = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "read write follow push",
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: parameters)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200
            else {
                throw TokenError.refreshFailed
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let accessToken = json["access_token"] as? String
            else {
                throw TokenError.refreshFailed
            }

            // Calculate expiration date if provided
            var expirationDate: Date? = nil
            if let expiresIn = json["expires_in"] as? Int {
                expirationDate = Date().addingTimeInterval(TimeInterval(expiresIn))
            }

            // If we received a new refresh token, store it
            if let newRefreshToken = json["refresh_token"] as? String {
                UserDefaults.saveRefreshToken(newRefreshToken, for: account.id)
                account.saveRefreshToken(newRefreshToken)
            }

            // Return the new token and expiration
            return (accessToken, expirationDate)

        } catch {
            throw TokenError.networkError(error)
        }
    }

    /// Ensures an account has a valid, non-expired token
    /// - Parameter account: The account to validate
    /// - Returns: The valid access token
    static func ensureValidToken(for account: SocialAccount) async throws -> String {
        // Only refresh if token is expired and we have refresh token
        if account.isTokenExpired && account.getRefreshToken() != nil {
            switch account.platform {
            case .mastodon:
                do {
                    let refreshResult = try await refreshMastodonToken(for: account)

                    // Save the token
                    UserDefaults.saveAccessToken(refreshResult.token, for: account.id)

                    // Update the account
                    account.saveAccessToken(refreshResult.token)
                    account.saveTokenExpirationDate(refreshResult.expiresAt)

                    return refreshResult.token
                } catch {
                    throw error
                }

            case .bluesky:
                // Handle Bluesky refresh here
                break
            }
        }

        // Use existing token if available
        if let token = account.getAccessToken() {
            return token
        }

        throw TokenError.refreshFailed
    }
}

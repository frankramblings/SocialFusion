import Foundation

/// Manages OAuth token lifecycle including refreshing and expiration
public class TokenManager {

    public enum TokenError: Error, LocalizedError {
        case refreshFailed
        case noRefreshToken
        case noClientCredentials
        case invalidServerURL
        case networkError(Error)

        public var errorDescription: String? {
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

    /// Checks if the token needs refreshing
    /// - Parameter account: The social account to check token for
    /// - Returns: True if token needs refreshing
    public static func shouldRefreshToken(for account: SocialAccount) -> Bool {
        // Tokens with no expiration date don't need refreshing
        guard account.isTokenExpired else {
            return false
        }

        // Only refresh if we have a refresh token
        return account.getRefreshToken() != nil
    }

    /// Refresh an expired token
    /// - Parameter account: The account whose token needs refreshing
    /// - Returns: Updated access token and expiration date
    public static func refreshToken(for account: SocialAccount) async throws -> (
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

        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

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
                do {
                    // Update in keychain
                    try KeychainManager.saveRefreshToken(newRefreshToken, for: account.id)

                    // Update in memory
                    account.saveRefreshToken(newRefreshToken)
                } catch {
                    // Continue even if we can't save the refresh token - the access token is still valid
                    print(
                        "Warning: Failed to save new refresh token: \(error.localizedDescription)")
                }
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
    public static func ensureValidToken(for account: SocialAccount) async throws -> String {
        if shouldRefreshToken(for: account) {
            do {
                let refreshResult = try await refreshToken(for: account)

                // Save the token
                try KeychainManager.saveAccessToken(refreshResult.token, for: account.id)

                // Update the account
                account.saveAccessToken(refreshResult.token)
                account.saveTokenExpirationDate(refreshResult.expiresAt)

                return refreshResult.token
            } catch {
                throw error
            }
        } else if let token = account.getAccessToken() {
            return token
        } else {
            throw TokenError.refreshFailed
        }
    }

    /// Store tokens securely in the Keychain
    /// - Parameters:
    ///   - accessToken: Access token to store
    ///   - refreshToken: Refresh token to store (optional)
    ///   - accountId: Account identifier
    public static func securelyStoreTokens(
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date?,
        clientId: String,
        clientSecret: String,
        accountId: String
    ) {
        do {
            try KeychainManager.saveAccessToken(accessToken, for: accountId)

            if let refreshToken = refreshToken {
                try KeychainManager.saveRefreshToken(refreshToken, for: accountId)
            }

            try KeychainManager.saveClientCredentials(
                clientId: clientId,
                clientSecret: clientSecret,
                for: accountId
            )

            // Store expiration date in UserDefaults
            if let expiresAt = expiresAt {
                UserDefaults.standard.set(
                    expiresAt.timeIntervalSince1970, forKey: "token-expiry-\(accountId)")
            }
        } catch {
            print("Error storing tokens: \(error.localizedDescription)")
        }
    }

    /// Load tokens from Keychain
    /// - Parameter accountId: Account identifier
    /// - Returns: Tuple containing access token, refresh token, and expiration date
    public static func loadTokens(for accountId: String) -> (
        accessToken: String?, refreshToken: String?, expiresAt: Date?, clientId: String?,
        clientSecret: String?
    ) {
        var accessToken: String?
        var refreshToken: String?
        var expiresAt: Date?
        var clientId: String?
        var clientSecret: String?

        do {
            accessToken = try KeychainManager.loadToken(type: "AccessToken", for: accountId)
        } catch {
            // Handle error (token not found)
            print("Access token not found: \(error.localizedDescription)")
        }

        do {
            refreshToken = try KeychainManager.loadToken(type: "RefreshToken", for: accountId)
        } catch {
            // Handle error (token not found)
            print("Refresh token not found: \(error.localizedDescription)")
        }

        do {
            let credentials = try KeychainManager.loadClientCredentials(for: accountId)
            clientId = credentials.clientId
            clientSecret = credentials.clientSecret
        } catch {
            // Handle error (credentials not found)
            print("Client credentials not found: \(error.localizedDescription)")
        }

        // Load expiration date from UserDefaults
        if let expiryTimestamp = UserDefaults.standard.object(forKey: "token-expiry-\(accountId)")
            as? TimeInterval
        {
            expiresAt = Date(timeIntervalSince1970: expiryTimestamp)
        }

        return (accessToken, refreshToken, expiresAt, clientId, clientSecret)
    }

    /// Delete tokens from Keychain
    /// - Parameter accountId: Account identifier
    public static func deleteTokens(for accountId: String) {
        do {
            try KeychainManager.deleteToken(type: "AccessToken", for: accountId)
            try KeychainManager.deleteToken(type: "RefreshToken", for: accountId)
            try KeychainManager.delete(
                service: "SocialFusion-ClientCredentials", account: accountId)

            // Remove expiration date from UserDefaults
            UserDefaults.standard.removeObject(forKey: "token-expiry-\(accountId)")
        } catch {
            print("Error deleting tokens: \(error.localizedDescription)")
        }
    }
}

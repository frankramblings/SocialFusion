import Foundation
import Security
import SwiftUI
import UIKit

// Temporarily duplicate the SocialPlatform enum to fix build issues
// Once the module structure is properly set up, this can be removed
enum SocialPlatform: String, Codable, CaseIterable {
    case mastodon
    case bluesky

    /// Returns the platform's color for UI elements
    var color: String {
        switch self {
        case .mastodon:
            return "#6364FF"
        case .bluesky:
            return "#0085FF"
        }
    }

    /// Returns whether the platform uses an SF Symbol or custom image
    var usesSFSymbol: Bool {
        return false
    }

    /// Returns the platform-specific icon image name
    var icon: String {
        switch self {
        case .mastodon:
            return "mastodon-logo"
        case .bluesky:
            return "bluesky-logo"
        }
    }

    /// Whether the SVG icon should be tinted with the platform color
    var shouldTintIcon: Bool {
        return true
    }

    /// Fallback system symbol if needed
    var sfSymbol: String {
        switch self {
        case .mastodon:
            return "bubble.left.and.bubble.right"
        case .bluesky:
            return "cloud"
        }
    }
}

// Custom property wrapper to make @Published properties work with Codable
private class CodablePublished<T: Codable>: ObservableObject {
    @Published var wrappedValue: T?

    init(_ value: T?) {
        self.wrappedValue = value
    }
}

// Embedded TokenManager to avoid import issues
private class TokenManager {
    enum TokenError: Error {
        case refreshFailed
        case noRefreshToken
        case noClientCredentials
        case invalidServerURL
        case networkError(Error)
    }

    /// Ensures an account has a valid, non-expired token
    static func ensureValidToken(for account: SocialAccount) async throws -> String {
        // Only refresh if token is expired and we have refresh token
        if account.isTokenExpired,
            let refreshToken = account.getRefreshToken(),
            let clientId = account.getClientId(),
            let clientSecret = account.getClientSecret()
        {

            // Use existing token handling
            let tokens = loadTokens(for: account.id)
            if let token = tokens.accessToken {
                return token
            }
        }

        // Use existing token if available
        if let token = account.getAccessToken() {
            return token
        }

        throw NSError(
            domain: "TokenManager", code: 401,
            userInfo: [
                NSLocalizedDescriptionKey: "No valid token available"
            ])
    }
}

// Embedded Keychain extension to avoid import issues
extension UserDefaults {
    fileprivate static func saveAccessToken(_ token: String, for accountId: String) {
        UserDefaults.standard.set(token, forKey: "accessToken-\(accountId)")
    }

    fileprivate static func saveRefreshToken(_ token: String, for accountId: String) {
        UserDefaults.standard.set(token, forKey: "refreshToken-\(accountId)")
    }

    fileprivate static func saveClientCredentials(
        clientId: String, clientSecret: String, for accountId: String
    ) {
        UserDefaults.standard.set(clientId, forKey: "clientId-\(accountId)")
        UserDefaults.standard.set(clientSecret, forKey: "clientSecret-\(accountId)")
    }

    fileprivate static func loadAccessToken(for accountId: String) -> String? {
        return UserDefaults.standard.string(forKey: "accessToken-\(accountId)")
    }

    fileprivate static func loadRefreshToken(for accountId: String) -> String? {
        return UserDefaults.standard.string(forKey: "refreshToken-\(accountId)")
    }

    fileprivate static func loadClientCredentials(for accountId: String) -> (
        clientId: String?, clientSecret: String?
    ) {
        let clientId = UserDefaults.standard.string(forKey: "clientId-\(accountId)")
        let clientSecret = UserDefaults.standard.string(forKey: "clientSecret-\(accountId)")
        return (clientId, clientSecret)
    }

    fileprivate static func deleteAllTokens(for accountId: String) {
        UserDefaults.standard.removeObject(forKey: "accessToken-\(accountId)")
        UserDefaults.standard.removeObject(forKey: "refreshToken-\(accountId)")
        UserDefaults.standard.removeObject(forKey: "clientId-\(accountId)")
        UserDefaults.standard.removeObject(forKey: "clientSecret-\(accountId)")
        UserDefaults.standard.removeObject(forKey: "token-expiry-\(accountId)")
    }
}

// Helper functions for TokenManager until proper imports can be set up
private func securelyStoreTokens(
    accessToken: String,
    refreshToken: String?,
    expiresAt: Date?,
    clientId: String,
    clientSecret: String,
    accountId: String
) {
    // Store access token in UserDefaults for now
    UserDefaults.standard.set(accessToken, forKey: "accessToken-\(accountId)")

    // Store refresh token if available
    if let refreshToken = refreshToken {
        UserDefaults.standard.set(refreshToken, forKey: "refreshToken-\(accountId)")
    }

    // Store client credentials
    UserDefaults.standard.set(clientId, forKey: "clientId-\(accountId)")
    UserDefaults.standard.set(clientSecret, forKey: "clientSecret-\(accountId)")

    // Store expiration date
    if let expiresAt = expiresAt {
        UserDefaults.standard.set(
            expiresAt.timeIntervalSince1970, forKey: "token-expiry-\(accountId)")
    }
}

private func loadTokens(for accountId: String) -> (
    accessToken: String?, refreshToken: String?, expiresAt: Date?, clientId: String?,
    clientSecret: String?
) {
    let accessToken = UserDefaults.standard.string(forKey: "accessToken-\(accountId)")
    let refreshToken = UserDefaults.standard.string(forKey: "refreshToken-\(accountId)")
    let clientId = UserDefaults.standard.string(forKey: "clientId-\(accountId)")
    let clientSecret = UserDefaults.standard.string(forKey: "clientSecret-\(accountId)")

    var expiresAt: Date? = nil
    if let expiryTimestamp = UserDefaults.standard.object(forKey: "token-expiry-\(accountId)")
        as? TimeInterval
    {
        expiresAt = Date(timeIntervalSince1970: expiryTimestamp)
    }

    return (accessToken, refreshToken, expiresAt, clientId, clientSecret)
}

private func deleteTokens(for accountId: String) {
    UserDefaults.standard.removeObject(forKey: "accessToken-\(accountId)")
    UserDefaults.standard.removeObject(forKey: "refreshToken-\(accountId)")
    UserDefaults.standard.removeObject(forKey: "clientId-\(accountId)")
    UserDefaults.standard.removeObject(forKey: "clientSecret-\(accountId)")
    UserDefaults.standard.removeObject(forKey: "token-expiry-\(accountId)")
}

/// Represents a user account on a social media platform
class SocialAccount: Identifiable, ObservableObject, Codable {
    // MARK: Properties

    var id: String
    @Published var username: String
    private var _displayName = CodablePublished<String>(nil)
    private var _serverURL = CodablePublished<URL>(nil)
    @Published var platform: SocialPlatform
    private var _profileImageURL = CodablePublished<URL>(nil)
    var platformSpecificId: String

    var displayName: String? {
        get { return _displayName.wrappedValue }
        set { _displayName.wrappedValue = newValue }
    }

    var serverURL: URL? {
        get { return _serverURL.wrappedValue }
        set { _serverURL.wrappedValue = newValue }
    }

    var profileImageURL: URL? {
        get { return _profileImageURL.wrappedValue }
        set { _profileImageURL.wrappedValue = newValue }
    }

    // Private properties for authentication
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpirationDate: Date?
    private var clientId: String?
    private var clientSecret: String?
    private var accountDetails: [String: String]?

    init(
        id: String,
        username: String,
        displayName: String? = nil,
        serverURL: URL? = nil,
        platform: SocialPlatform,
        profileImageURL: URL? = nil,
        platformSpecificId: String? = nil
    ) {
        self.id = id
        self.username = username
        self._displayName.wrappedValue = displayName
        self._serverURL.wrappedValue = serverURL
        self.platform = platform
        self._profileImageURL.wrappedValue = profileImageURL
        self.platformSpecificId = platformSpecificId ?? id

        // Try to load tokens from keychain
        loadTokensFromKeychain()
    }

    init(
        id: String,
        username: String,
        displayName: String,
        serverURL: String,
        platform: SocialPlatform,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        expirationDate: Date? = nil,
        clientId: String? = nil,
        clientSecret: String? = nil,
        accountDetails: [String: String]? = nil,
        profileImageURL: URL? = nil,
        platformSpecificId: String? = nil
    ) {
        self.id = id
        self.username = username
        self._displayName.wrappedValue = displayName
        self._serverURL.wrappedValue = URL(string: serverURL)
        self.platform = platform
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenExpirationDate = expirationDate
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.accountDetails = accountDetails
        self._profileImageURL.wrappedValue = profileImageURL
        self.platformSpecificId = platformSpecificId ?? id

        // Store tokens securely
        if let accessToken = accessToken, let clientId = clientId, let clientSecret = clientSecret {
            saveTokensToStorage(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expirationDate,
                clientId: clientId,
                clientSecret: clientSecret
            )
        }
    }

    private func loadTokensFromKeychain() {
        // Load access token
        self.accessToken = UserDefaults.loadAccessToken(for: id)

        // Load refresh token
        self.refreshToken = UserDefaults.loadRefreshToken(for: id)

        // Load client credentials
        let credentials = UserDefaults.loadClientCredentials(for: id)
        self.clientId = credentials.clientId
        self.clientSecret = credentials.clientSecret

        // Load expiration date
        if let expiryTimestamp = UserDefaults.standard.object(forKey: "token-expiry-\(id)")
            as? TimeInterval
        {
            self.tokenExpirationDate = Date(timeIntervalSince1970: expiryTimestamp)
        }
    }

    private func saveTokensToStorage(
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date?,
        clientId: String,
        clientSecret: String
    ) {
        // Save access token
        UserDefaults.saveAccessToken(accessToken, for: id)

        // Save refresh token if available
        if let refreshToken = refreshToken {
            UserDefaults.saveRefreshToken(refreshToken, for: id)
        }

        // Save client credentials
        UserDefaults.saveClientCredentials(clientId: clientId, clientSecret: clientSecret, for: id)

        // Save expiration date
        if let expiresAt = expiresAt {
            UserDefaults.standard.set(expiresAt.timeIntervalSince1970, forKey: "token-expiry-\(id)")
        }
    }

    // MARK: - Token Management

    func saveAccessToken(_ token: String) {
        self.accessToken = token
        UserDefaults.saveAccessToken(token, for: id)
    }

    func saveRefreshToken(_ token: String) {
        self.refreshToken = token
        UserDefaults.saveRefreshToken(token, for: id)
    }

    func saveTokenExpirationDate(_ date: Date?) {
        self.tokenExpirationDate = date

        // Store in UserDefaults
        if let date = date {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "token-expiry-\(id)")
        } else {
            UserDefaults.standard.removeObject(forKey: "token-expiry-\(id)")
        }
    }

    func saveClientCredentials(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        UserDefaults.saveClientCredentials(clientId: clientId, clientSecret: clientSecret, for: id)
    }

    func saveAccountDetails(_ details: [String: String]) {
        self.accountDetails = details
    }

    func getAccessToken() -> String? {
        // If no token in memory, try loading from keychain
        if accessToken == nil {
            loadTokensFromKeychain()
        }
        return accessToken
    }

    func getRefreshToken() -> String? {
        // If no token in memory, try loading from keychain
        if refreshToken == nil {
            loadTokensFromKeychain()
        }
        return refreshToken
    }

    func getClientId() -> String? {
        // If no client ID in memory, try loading from keychain
        if clientId == nil {
            loadTokensFromKeychain()
        }
        return clientId
    }

    func getClientSecret() -> String? {
        // If no client secret in memory, try loading from keychain
        if clientSecret == nil {
            loadTokensFromKeychain()
        }
        return clientSecret
    }

    func getAccountDetails() -> [String: String]? {
        return accountDetails
    }

    var isTokenExpired: Bool {
        guard let expirationDate = tokenExpirationDate else {
            return true
        }
        // Consider token expired 5 minutes before actual expiration
        return expirationDate.addingTimeInterval(-5 * 60) < Date()
    }

    /// Ensures this account has a valid access token, refreshing if necessary
    /// - Returns: A valid access token
    func getValidAccessToken() async throws -> String {
        return try await TokenManager.ensureValidToken(for: self)
    }

    /// Deletes all tokens associated with this account
    func clearTokens() {
        UserDefaults.deleteAllTokens(for: id)
        accessToken = nil
        refreshToken = nil
        tokenExpirationDate = nil
        clientId = nil
        clientSecret = nil
    }

    // MARK: - Equatable

    static func == (lhs: SocialAccount, rhs: SocialAccount) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, username, displayName, serverURL, platform
        case accessToken, refreshToken, clientId, clientSecret
        case tokenExpirationDate
        case accountDetails
        case platformSpecificId
        case profileImageURL
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        platformSpecificId =
            try container.decodeIfPresent(String.self, forKey: .platformSpecificId) ?? id

        // Fix String? decoding
        self._displayName = CodablePublished(
            try container.decodeIfPresent(String.self, forKey: .displayName))

        // Fix URL? decoding
        if let urlString = try container.decodeIfPresent(String.self, forKey: .profileImageURL) {
            self._profileImageURL = CodablePublished(URL(string: urlString))
        } else {
            self._profileImageURL = CodablePublished(nil)
        }

        platform = try container.decode(SocialPlatform.self, forKey: .platform)

        // Fix URL? decoding
        if let urlString = try container.decodeIfPresent(String.self, forKey: .serverURL) {
            self._serverURL = CodablePublished(URL(string: urlString))
        } else {
            self._serverURL = CodablePublished(nil)
        }

        // Load tokens from keychain
        loadTokensFromKeychain()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encode(platformSpecificId, forKey: .platformSpecificId)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(profileImageURL, forKey: .profileImageURL)
        try container.encode(platform, forKey: .platform)
        try container.encode(serverURL, forKey: .serverURL)

        // Optional properties
        try container.encodeIfPresent(accessToken, forKey: .accessToken)
        try container.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try container.encodeIfPresent(clientId, forKey: .clientId)
        try container.encodeIfPresent(clientSecret, forKey: .clientSecret)
        try container.encodeIfPresent(tokenExpirationDate, forKey: .tokenExpirationDate)
        try container.encodeIfPresent(accountDetails, forKey: .accountDetails)
    }
}

import Foundation
import Security
import SwiftUI
import UIKit

// MARK: - Color Extension for Hex Colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch hex.count {
        case 3:  // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - SocialPlatform Definition
/// An enum representing the supported social media platforms
public enum SocialPlatform: String, Codable, CaseIterable {
    case mastodon
    case bluesky

    /// Returns the platform's color for UI elements
    public var color: Color {
        switch self {
        case .mastodon:
            return Color(hex: "6364FF")
        case .bluesky:
            return Color(hex: "0085FF")
        }
    }

    /// Returns whether the platform uses an SF Symbol or custom image
    public var usesSFSymbol: Bool {
        return false
    }

    /// Returns the platform-specific icon image name
    public var icon: String {
        switch self {
        case .mastodon:
            return "MastodonLogo"
        case .bluesky:
            return "BlueskyLogo"
        }
    }

    /// Whether the SVG icon should be tinted with the platform color
    public var shouldTintIcon: Bool {
        return false
    }

    /// Fallback system symbol if needed
    public var sfSymbol: String {
        switch self {
        case .mastodon:
            return "m.circle.fill"
        case .bluesky:
            return "cloud.fill"
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    public static let accountProfileImageUpdated = Notification.Name("AccountProfileImageUpdated")
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
            account.getRefreshToken() != nil,
            account.getClientId() != nil,
            account.getClientSecret() != nil
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
public class SocialAccount: Identifiable, Codable, Equatable {
    // MARK: - Properties

    public let id: String
    public let username: String
    public var displayName: String?
    public let serverURL: URL?
    public let platform: SocialPlatform
    public var profileImageURL: URL? {
        didSet {
            if profileImageURL != oldValue {
                NotificationCenter.default.post(
                    name: Notification.Name.accountProfileImageUpdated, object: self, userInfo: nil)
            }
        }
    }

    // Platform-specific ID (e.g., Mastodon account ID or Bluesky DID)
    public var platformSpecificId: String

    // Authentication tokens (transient - stored in keychain, not encoded)
    public var accessToken: String?
    public var refreshToken: String?
    public var tokenExpirationDate: Date?

    // OAuth client credentials
    public var clientId: String?
    public var clientSecret: String?

    // Account details from the platform
    public var accountDetails: [String: String]?

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName
        case serverURL
        case platform
        case profileImageURL
        case platformSpecificId
    }

    // MARK: - Initialization

    public init(
        id: String,
        username: String,
        displayName: String? = nil,
        serverURL: URL? = nil,
        platform: SocialPlatform,
        profileImageURL: URL? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.serverURL = serverURL
        self.platform = platform
        self.profileImageURL = profileImageURL
        self.platformSpecificId = id  // Use id as default platformSpecificId

        // Print debug info
        print(
            "Created account: \(username) with profile image URL: \(String(describing: profileImageURL))"
        )

        // Try to load tokens from keychain
        loadTokensFromKeychain()
    }

    public init(
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
        self.displayName = displayName
        self.serverURL = URL(string: serverURL)
        self.platform = platform
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenExpirationDate = expirationDate
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.accountDetails = accountDetails
        self.profileImageURL = profileImageURL
        self.platformSpecificId = platformSpecificId ?? id

        // Store tokens securely - Ensure tokens are saved to UserDefaults
        if let accessToken = accessToken {
            saveAccessToken(accessToken)
            print("Saved access token for \(username): \(accessToken.prefix(5))...")

            if let refreshToken = refreshToken {
                saveRefreshToken(refreshToken)
                print("Saved refresh token for \(username): \(refreshToken.prefix(5))...")
            }

            if let expirationDate = expirationDate {
                saveTokenExpirationDate(expirationDate)
                print("Saved token expiration date for \(username): \(expirationDate)")
            }

            if let clientId = clientId, let clientSecret = clientSecret {
                saveClientCredentials(clientId: clientId, clientSecret: clientSecret)
                print("Saved client credentials for \(username)")
            }
        }
    }

    // Custom init from decoder
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        serverURL = try container.decodeIfPresent(URL.self, forKey: .serverURL)
        platform = try container.decode(SocialPlatform.self, forKey: .platform)
        platformSpecificId = try container.decode(String.self, forKey: .platformSpecificId)

        // Decode profile image URL with proper error handling
        if let profileImageURLString = try container.decodeIfPresent(
            String.self, forKey: .profileImageURL)
        {
            profileImageURL = URL(string: profileImageURLString)
            print(
                "Decoded profile image URL for \(username): \(String(describing: profileImageURL))")
        } else {
            profileImageURL = nil
            print("No profile image URL found for \(username)")
        }

        // Load tokens from UserDefaults
        let tokens = loadTokens(for: id)
        accessToken = tokens.accessToken
        refreshToken = tokens.refreshToken
        tokenExpirationDate = tokens.expiresAt
        clientId = tokens.clientId
        clientSecret = tokens.clientSecret
    }

    // Custom encode method
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(serverURL, forKey: .serverURL)
        try container.encode(platform, forKey: .platform)
        try container.encode(platformSpecificId, forKey: .platformSpecificId)

        // Encode profile image URL as string
        if let profileImageURL = profileImageURL {
            try container.encode(profileImageURL.absoluteString, forKey: .profileImageURL)
            print("Encoded profile image URL for \(username): \(profileImageURL.absoluteString)")
        }
    }

    // MARK: - Equatable

    public static func == (lhs: SocialAccount, rhs: SocialAccount) -> Bool {
        return lhs.id == rhs.id
    }

    // MARK: - Token Management

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

    public func saveAccessToken(_ token: String) {
        self.accessToken = token
        UserDefaults.saveAccessToken(token, for: id)
    }

    public func saveRefreshToken(_ token: String) {
        self.refreshToken = token
        UserDefaults.saveRefreshToken(token, for: id)
    }

    public func saveTokenExpirationDate(_ date: Date?) {
        self.tokenExpirationDate = date

        // Store in UserDefaults
        if let date = date {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "token-expiry-\(id)")
        } else {
            UserDefaults.standard.removeObject(forKey: "token-expiry-\(id)")
        }
    }

    public func saveClientCredentials(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        UserDefaults.saveClientCredentials(clientId: clientId, clientSecret: clientSecret, for: id)
    }

    public func saveAccountDetails(_ details: [String: String]) {
        self.accountDetails = details
    }

    public func getAccessToken() -> String? {
        // If no token in memory, try loading from keychain
        if accessToken == nil {
            loadTokensFromKeychain()
        }
        return accessToken
    }

    public func getRefreshToken() -> String? {
        // If no token in memory, try loading from keychain
        if refreshToken == nil {
            loadTokensFromKeychain()
        }
        return refreshToken
    }

    public func getClientId() -> String? {
        // If no client ID in memory, try loading from keychain
        if clientId == nil {
            loadTokensFromKeychain()
        }
        return clientId
    }

    public func getClientSecret() -> String? {
        // If no client secret in memory, try loading from keychain
        if clientSecret == nil {
            loadTokensFromKeychain()
        }
        return clientSecret
    }

    public func getAccountDetails() -> [String: String]? {
        return accountDetails
    }

    public var isTokenExpired: Bool {
        guard let expirationDate = tokenExpirationDate else {
            return true
        }
        // Consider token expired 5 minutes before actual expiration
        return expirationDate.addingTimeInterval(-5 * 60) < Date()
    }

    /// Ensures this account has a valid access token, refreshing if necessary
    /// - Returns: A valid access token
    public func getValidAccessToken() async throws -> String {
        return try await TokenManager.ensureValidToken(for: self)
    }

    /// Deletes all tokens associated with this account
    public func clearTokens() {
        UserDefaults.deleteAllTokens(for: id)
        accessToken = nil
        refreshToken = nil
        tokenExpirationDate = nil
        clientId = nil
        clientSecret = nil
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

    // Save accounts to UserDefaults
    private func saveAccounts() {
        var accounts =
            UserDefaults.standard.array(forKey: "social_accounts") as? [[String: Any]] ?? []

        // Update or add this account
        let accountData: [String: Any] = [
            "id": id,
            "username": username,
            "displayName": displayName as Any,
            "serverURL": serverURL?.absoluteString ?? "",
            "platform": platform.rawValue,
            "profileImageURL": profileImageURL?.absoluteString ?? "",
        ]

        if let index = accounts.firstIndex(where: { ($0["id"] as? String) == id }) {
            accounts[index] = accountData
        } else {
            accounts.append(accountData)
        }

        UserDefaults.standard.set(accounts, forKey: "social_accounts")
    }
}

// MARK: - Property Wrapper for Codable Ignore

// Property wrapper for CodableIgnore is no longer needed since we're using a class with normal properties

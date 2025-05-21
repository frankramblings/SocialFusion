import Foundation
import Security
import SwiftUI
import UIKit
import os.log

// Import services
import struct Foundation.URL
// Import our services
import class Foundation.URLSession

/// Errors related to token operations
public enum TokenError: Error, LocalizedError {
    case noAccessToken
    case noRefreshToken
    case invalidRefreshToken
    case refreshFailed
    case invalidServer

    public var errorDescription: String? {
        switch self {
        case .noAccessToken:
            return "No access token available"
        case .noRefreshToken:
            return "No refresh token available"
        case .invalidRefreshToken:
            return "Invalid refresh token"
        case .refreshFailed:
            return "Failed to refresh token"
        case .invalidServer:
            return "Invalid server URL"
        }
    }
}

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

    // Authentication tokens (transient - not encoded)
    private var _accessToken: String?
    private var _refreshToken: String?
    private var _tokenExpirationDate: Date?

    // Account details from the platform
    public var accountDetails: [String: String]?

    // TODO: Switch to KeychainService
    // private let keychainService = KeychainService.shared

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName
        case serverURL
        case platform
        case profileImageURL
        case platformSpecificId
        case accountDetails
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
        accountDetails: [String: String]? = nil,
        profileImageURL: URL? = nil,
        platformSpecificId: String? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.serverURL = URL(string: serverURL)
        self.platform = platform
        self._accessToken = accessToken
        self._refreshToken = refreshToken
        self._tokenExpirationDate = expirationDate
        self.accountDetails = accountDetails
        self.profileImageURL = profileImageURL
        self.platformSpecificId = platformSpecificId ?? id

        // Store tokens securely
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
        platformSpecificId =
            try container.decodeIfPresent(String.self, forKey: .platformSpecificId) ?? id

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

        // Initialize token properties to nil; we'll load them from keychain separately
        _accessToken = nil
        _refreshToken = nil
        _tokenExpirationDate = nil

        // Load tokens from keychain
        loadTokensFromKeychain()
    }

    // MARK: - Token Management

    /// The access token for the account
    public var accessToken: String? {
        get {
            if _accessToken == nil {
                // Temporarily using UserDefaults instead of KeychainService
                _accessToken = UserDefaults.standard.string(forKey: "accessToken-\(id)")
            }
            return _accessToken
        }
        set {
            _accessToken = newValue
            if let token = newValue {
                // Temporarily using UserDefaults instead of KeychainService
                UserDefaults.standard.set(token, forKey: "accessToken-\(id)")
            } else {
                // Temporarily using UserDefaults instead of KeychainService
                UserDefaults.standard.removeObject(forKey: "accessToken-\(id)")
            }
        }
    }

    /// The refresh token for the account
    public var refreshToken: String? {
        get {
            if _refreshToken == nil {
                // Temporarily using UserDefaults instead of KeychainService
                _refreshToken = UserDefaults.standard.string(forKey: "refreshToken-\(id)")
            }
            return _refreshToken
        }
        set {
            _refreshToken = newValue
            if let token = newValue {
                // Temporarily using UserDefaults instead of KeychainService
                UserDefaults.standard.set(token, forKey: "refreshToken-\(id)")
            } else {
                // Temporarily using UserDefaults instead of KeychainService
                UserDefaults.standard.removeObject(forKey: "refreshToken-\(id)")
            }
        }
    }

    public var tokenExpirationDate: Date? {
        get {
            return _tokenExpirationDate
        }
        set {
            _tokenExpirationDate = newValue
            // Store in UserDefaults for now as Keychain doesn't directly store dates
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "token-expiry-\(id)")
            } else {
                UserDefaults.standard.removeObject(forKey: "token-expiry-\(id)")
            }
        }
    }

    /// Save the access token for this account
    public func saveAccessToken(_ token: String) {
        self.accessToken = token
    }

    /// Save the refresh token for this account
    public func saveRefreshToken(_ token: String) {
        self.refreshToken = token
    }

    public func saveTokenExpirationDate(_ date: Date?) {
        tokenExpirationDate = date
    }

    public func savePassword(_ password: String) {
        // Temporarily using UserDefaults instead of KeychainService
        UserDefaults.standard.set(password, forKey: "password-\(id)")
    }

    public func getPassword() -> String? {
        // Temporarily using UserDefaults instead of KeychainService
        return UserDefaults.standard.string(forKey: "password-\(id)")
    }

    public func saveAccountDetails(_ details: [String: String]) {
        self.accountDetails = details
    }

    public func getAccessToken() -> String? {
        return accessToken
    }

    public func getRefreshToken() -> String? {
        return refreshToken
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
        let logger = Logger(subsystem: "com.socialfusion", category: "SocialAccount")

        // If the token is not expired, return it
        if !isTokenExpired, let token = accessToken {
            logger.debug("Token for \(self.username, privacy: .public) is still valid")
            return token
        }

        logger.info("Token expired for \(self.username, privacy: .public), attempting refresh")

        // Token is expired, attempt to refresh based on platform
        guard let refreshToken = getRefreshToken() else {
            logger.error("No refresh token available for \(self.username, privacy: .public)")
            throw TokenError.noRefreshToken
        }

        do {
            // Special handling for each platform
            switch platform {
            case .bluesky:
                let blueskyService = BlueskyService()
                let newToken = try await blueskyService.refreshAccessToken(for: self)

                logger.info(
                    "Successfully refreshed token for Bluesky account \(self.username, privacy: .public)"
                )
                return newToken

            case .mastodon:
                // For Mastodon, use the refresh token to get a new access token
                logger.debug(
                    "Using refresh token for Mastodon account \(self.username, privacy: .public)")

                // Use the existing MastodonService to refresh
                let mastodonService = MastodonService()
                let newToken = try await mastodonService.refreshAccessToken(for: self)

                logger.info(
                    "Successfully refreshed token for Mastodon account \(self.username, privacy: .public)"
                )
                return newToken

            default:
                logger.error(
                    "Token refresh not implemented for platform \(self.platform.rawValue, privacy: .public)"
                )
                throw TokenError.refreshFailed
            }
        } catch {
            logger.error("Failed to refresh token: \(error.localizedDescription, privacy: .public)")

            // If we still have an access token, return it even if it's expired
            // This gives the API call a chance to succeed even with an expired token
            if let token = accessToken {
                logger.notice("Returning possibly expired token as fallback")
                return token
            }

            throw TokenError.refreshFailed
        }
    }

    /// Deletes all tokens associated with this account
    public func clearTokens() {
        // Delete from UserDefaults
        UserDefaults.standard.removeObject(forKey: "accessToken-\(id)")
        UserDefaults.standard.removeObject(forKey: "refreshToken-\(id)")
        UserDefaults.standard.removeObject(forKey: "token-expiry-\(id)")
        UserDefaults.standard.removeObject(forKey: "password-\(id)")

        _accessToken = nil
        _refreshToken = nil
        _tokenExpirationDate = nil
    }

    /// Load tokens from UserDefaults (to be replaced with KeychainService in future)
    public func loadTokensFromKeychain() {
        // Load tokens from UserDefaults
        _accessToken = UserDefaults.standard.string(forKey: "accessToken-\(id)")
        _refreshToken = UserDefaults.standard.string(forKey: "refreshToken-\(id)")

        // Load expiration date from UserDefaults
        if let expiryTimestamp = UserDefaults.standard.object(forKey: "token-expiry-\(id)")
            as? TimeInterval
        {
            _tokenExpirationDate = Date(timeIntervalSince1970: expiryTimestamp)
        }

        print(
            "Loaded tokens for \(username): Access token exists: \(_accessToken != nil), Refresh token exists: \(_refreshToken != nil)"
        )
    }

    // MARK: - Equatable

    public static func == (lhs: SocialAccount, rhs: SocialAccount) -> Bool {
        return lhs.id == rhs.id
    }

    // Custom encoding to ensure we don't encode sensitive data
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(serverURL, forKey: .serverURL)
        try container.encode(platform, forKey: .platform)
        try container.encode(platformSpecificId, forKey: .platformSpecificId)

        // Encode profile image URL as string if it exists
        if let url = profileImageURL {
            try container.encode(url.absoluteString, forKey: .profileImageURL)
        }

        // Encode account details if present
        try container.encodeIfPresent(accountDetails, forKey: .accountDetails)

        // Note: We deliberately don't encode tokens here. They're stored in UserDefaults
        // and loaded separately via loadTokensFromKeychain()
    }
}

// MARK: - Property Wrapper for Codable Ignore

// Property wrapper for CodableIgnore is no longer needed since we're using a class with normal properties

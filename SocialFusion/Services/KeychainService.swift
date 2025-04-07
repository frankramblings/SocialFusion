import Foundation
import Security
import os.log

/// A service for securely storing and retrieving sensitive account information in the Keychain
public class KeychainService {
    // MARK: - Properties

    public static let shared = KeychainService()
    private let logger = Logger(subsystem: "com.socialfusion", category: "KeychainService")

    // MARK: - Error Definitions

    public enum KeychainError: Error {
        case itemNotFound
        case duplicateItem
        case unexpectedStatus(OSStatus)
        case dataEncodingFailed
        case dataDecodingFailed
    }

    // MARK: - Key Constants

    private enum KeyType {
        static let accessToken = "accessToken"
        static let refreshToken = "refreshToken"
        static let clientId = "clientId"
        static let clientSecret = "clientSecret"
        static let password = "password"
    }

    // Service prefix for different platforms
    private let servicePrefix = "com.socialfusion"

    // MARK: - Initialization

    private init() {}

    // MARK: - Core Keychain Operations

    /// Save data to the keychain
    private func saveToKeychain(data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        // First try to delete any existing item
        SecItemDelete(query as CFDictionary)

        // Add the new item
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            logger.error("Failed to save to keychain: status \(status)")
            throw KeychainError.unexpectedStatus(status)
        }

        logger.debug("Successfully saved data to keychain for account \(account, privacy: .public)")
    }

    /// Load data from the keychain
    private func loadFromKeychain(service: String, account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                logger.notice("Item not found in keychain for account \(account, privacy: .public)")
                throw KeychainError.itemNotFound
            } else {
                logger.error("Failed to load from keychain: status \(status)")
                throw KeychainError.unexpectedStatus(status)
            }
        }

        guard let data = result as? Data else {
            logger.error("Retrieved item is not Data for account \(account, privacy: .public)")
            throw KeychainError.dataDecodingFailed
        }

        return data
    }

    /// Delete data from the keychain
    private func deleteFromKeychain(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Failed to delete from keychain: status \(status)")
            throw KeychainError.unexpectedStatus(status)
        }

        logger.debug(
            "Successfully deleted data from keychain for account \(account, privacy: .public)")
    }

    // MARK: - String Helpers

    /// Save a string value to the keychain
    private func saveString(_ value: String, service: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            logger.error("Failed to encode string to data")
            throw KeychainError.dataEncodingFailed
        }

        try saveToKeychain(data: data, service: service, account: account)
    }

    /// Load a string value from the keychain
    private func loadString(service: String, account: String) throws -> String {
        let data = try loadFromKeychain(service: service, account: account)

        guard let string = String(data: data, encoding: .utf8) else {
            logger.error("Failed to decode data to string")
            throw KeychainError.dataDecodingFailed
        }

        return string
    }

    // MARK: - Social Account Specific Methods

    // Generate a service name for a specific platform and key type
    private func serviceName(for platform: String, keyType: String) -> String {
        return "\(servicePrefix).\(platform).\(keyType)"
    }

    /// Save access token for a social account
    public func saveAccessToken(_ token: String, for accountId: String, platform: String) throws {
        let service = serviceName(for: platform, keyType: KeyType.accessToken)
        try saveString(token, service: service, account: accountId)
        logger.info("Saved access token for account \(accountId, privacy: .public)")
    }

    /// Load access token for a social account
    public func loadAccessToken(for accountId: String, platform: String) throws -> String {
        let service = serviceName(for: platform, keyType: KeyType.accessToken)
        return try loadString(service: service, account: accountId)
    }

    /// Save refresh token for a social account
    public func saveRefreshToken(_ token: String, for accountId: String, platform: String) throws {
        let service = serviceName(for: platform, keyType: KeyType.refreshToken)
        try saveString(token, service: service, account: accountId)
        logger.info("Saved refresh token for account \(accountId, privacy: .public)")
    }

    /// Load refresh token for a social account
    public func loadRefreshToken(for accountId: String, platform: String) throws -> String {
        let service = serviceName(for: platform, keyType: KeyType.refreshToken)
        return try loadString(service: service, account: accountId)
    }

    /// Save client credentials for a social account
    public func saveClientCredentials(
        clientId: String, clientSecret: String, for accountId: String, platform: String
    ) throws {
        // Save client ID
        let clientIdService = serviceName(for: platform, keyType: KeyType.clientId)
        try saveString(clientId, service: clientIdService, account: accountId)

        // Save client secret
        let clientSecretService = serviceName(for: platform, keyType: KeyType.clientSecret)
        try saveString(clientSecret, service: clientSecretService, account: accountId)

        logger.info("Saved client credentials for account \(accountId, privacy: .public)")
    }

    /// Load client credentials for a social account
    public func loadClientCredentials(for accountId: String, platform: String) throws -> (
        clientId: String, clientSecret: String
    ) {
        // Load client ID
        let clientIdService = serviceName(for: platform, keyType: KeyType.clientId)
        let clientId = try loadString(service: clientIdService, account: accountId)

        // Load client secret
        let clientSecretService = serviceName(for: platform, keyType: KeyType.clientSecret)
        let clientSecret = try loadString(service: clientSecretService, account: accountId)

        return (clientId, clientSecret)
    }

    /// Save password for a social account (used for services like Bluesky that need password for refresh)
    public func savePassword(_ password: String, for accountId: String, platform: String) throws {
        let service = serviceName(for: platform, keyType: KeyType.password)
        try saveString(password, service: service, account: accountId)
        logger.info("Saved password for account \(accountId, privacy: .public)")
    }

    /// Load password for a social account
    public func loadPassword(for accountId: String, platform: String) throws -> String {
        let service = serviceName(for: platform, keyType: KeyType.password)
        return try loadString(service: service, account: accountId)
    }

    /// Delete all credentials for a social account
    public func deleteAllCredentials(for accountId: String, platform: String) throws {
        // Delete access token
        try? deleteFromKeychain(
            service: serviceName(for: platform, keyType: KeyType.accessToken),
            account: accountId
        )

        // Delete refresh token
        try? deleteFromKeychain(
            service: serviceName(for: platform, keyType: KeyType.refreshToken),
            account: accountId
        )

        // Delete client ID
        try? deleteFromKeychain(
            service: serviceName(for: platform, keyType: KeyType.clientId),
            account: accountId
        )

        // Delete client secret
        try? deleteFromKeychain(
            service: serviceName(for: platform, keyType: KeyType.clientSecret),
            account: accountId
        )

        // Delete password
        try? deleteFromKeychain(
            service: serviceName(for: platform, keyType: KeyType.password),
            account: accountId
        )

        logger.info("Deleted all credentials for account \(accountId, privacy: .public)")
    }
}

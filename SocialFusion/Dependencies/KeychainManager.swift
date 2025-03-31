import Foundation
import Security

/// A utility class for securely storing and retrieving sensitive information in the Keychain
public class KeychainManager {

    public enum KeychainError: Error {
        case itemNotFound
        case duplicateItem
        case unexpectedStatus(OSStatus)
    }

    public static func save(service: String, account: String, data: Data) throws {
        // Create a query dictionary
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]

        // Delete any existing item
        SecItemDelete(query as CFDictionary)

        // Add the new item
        let status = SecItemAdd(query as CFDictionary, nil)

        // Check for errors
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public static func load(service: String, account: String) throws -> Data {
        // Create a query dictionary
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        // Execute the query
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        // Check for errors
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            } else {
                throw KeychainError.unexpectedStatus(status)
            }
        }

        // Return the data
        guard let data = result as? Data else {
            throw KeychainError.unexpectedStatus(errSecInternalError)
        }

        return data
    }

    public static func delete(service: String, account: String) throws {
        // Create a query dictionary
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Delete the item
        let status = SecItemDelete(query as CFDictionary)

        // Check for errors
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Convenience Methods for OAuth Tokens

    public static func saveToken(_ token: String, type: String, for accountId: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.unexpectedStatus(errSecInvalidData)
        }

        try save(service: "SocialFusion-\(type)", account: accountId, data: data)
    }

    public static func loadToken(type: String, for accountId: String) throws -> String {
        let data = try load(service: "SocialFusion-\(type)", account: accountId)

        guard let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedStatus(errSecInvalidData)
        }

        return token
    }

    public static func deleteToken(type: String, for accountId: String) throws {
        try delete(service: "SocialFusion-\(type)", account: accountId)
    }

    public static func saveAccessToken(_ token: String, for accountId: String) throws {
        try saveToken(token, type: "AccessToken", for: accountId)
    }

    public static func saveRefreshToken(_ token: String, for accountId: String) throws {
        try saveToken(token, type: "RefreshToken", for: accountId)
    }

    public static func saveClientCredentials(
        clientId: String, clientSecret: String, for accountId: String
    ) throws {
        let credentials = [
            "clientId": clientId,
            "clientSecret": clientSecret,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: credentials) else {
            throw KeychainError.unexpectedStatus(errSecInvalidData)
        }

        try save(service: "SocialFusion-ClientCredentials", account: accountId, data: data)
    }

    public static func loadClientCredentials(for accountId: String) throws -> (
        clientId: String, clientSecret: String
    ) {
        let data = try load(service: "SocialFusion-ClientCredentials", account: accountId)

        guard let credentials = try? JSONSerialization.jsonObject(with: data) as? [String: String],
            let clientId = credentials["clientId"],
            let clientSecret = credentials["clientSecret"]
        else {
            throw KeychainError.unexpectedStatus(errSecInvalidData)
        }

        return (clientId, clientSecret)
    }
}

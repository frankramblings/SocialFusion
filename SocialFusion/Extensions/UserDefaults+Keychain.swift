import Foundation
import Security

// This extension provides a keychain-like API with proper keychain storage
extension UserDefaults {

    // MARK: - Keychain Error Handling

    enum KeychainError: Error {
        case itemNotFound
        case duplicateItem
        case unexpectedStatus(OSStatus)
    }

    // MARK: - Core Keychain Methods

    private static func save(service: String, account: String, data: Data) {
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
        if status != errSecSuccess {
            print("Error saving to keychain: \(status)")
        }
    }

    private static func load(service: String, account: String) -> Data? {
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
            return nil
        }

        return result as? Data
    }

    private static func delete(service: String, account: String) {
        // Create a query dictionary
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Delete the item
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - OAuth Token Storage

    static func saveAccessToken(_ token: String, for accountId: String) {
        if let data = token.data(using: .utf8) {
            save(service: "SocialFusion-AccessToken", account: accountId, data: data)
        }
    }

    static func saveRefreshToken(_ token: String, for accountId: String) {
        if let data = token.data(using: .utf8) {
            save(service: "SocialFusion-RefreshToken", account: accountId, data: data)
        }
    }

    static func saveClientCredentials(clientId: String, clientSecret: String, for accountId: String)
    {
        let credentials = [
            "clientId": clientId,
            "clientSecret": clientSecret,
        ]

        if let data = try? JSONSerialization.data(withJSONObject: credentials) {
            save(service: "SocialFusion-ClientCredentials", account: accountId, data: data)
        }
    }

    static func loadAccessToken(for accountId: String) -> String? {
        guard let data = load(service: "SocialFusion-AccessToken", account: accountId) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func loadRefreshToken(for accountId: String) -> String? {
        guard let data = load(service: "SocialFusion-RefreshToken", account: accountId) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func loadClientCredentials(for accountId: String) -> (
        clientId: String?, clientSecret: String?
    ) {
        guard let data = load(service: "SocialFusion-ClientCredentials", account: accountId),
            let credentials = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else {
            return (nil, nil)
        }

        return (credentials["clientId"], credentials["clientSecret"])
    }

    static func deleteAccessToken(for accountId: String) {
        delete(service: "SocialFusion-AccessToken", account: accountId)
    }

    static func deleteRefreshToken(for accountId: String) {
        delete(service: "SocialFusion-RefreshToken", account: accountId)
    }

    static func deleteClientCredentials(for accountId: String) {
        delete(service: "SocialFusion-ClientCredentials", account: accountId)
    }

    static func deleteAllTokens(for accountId: String) {
        deleteAccessToken(for: accountId)
        deleteRefreshToken(for: accountId)
        deleteClientCredentials(for: accountId)
        UserDefaults.standard.removeObject(forKey: "token-expiry-\(accountId)")
    }
}

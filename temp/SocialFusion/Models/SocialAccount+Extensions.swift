import Foundation

// MARK: - Authentication Extensions
extension SocialAccount {
    // Storage keys for secure storage
    private enum StorageKeys {
        static func accessToken(for id: String) -> String { "accessToken_\(id)" }
        static func refreshToken(for id: String) -> String { "refreshToken_\(id)" }
        static func tokenExpirationDate(for id: String) -> String { "tokenExpirationDate_\(id)" }
        static func appClientId(for id: String) -> String { "appClientId_\(id)" }
        static func appClientSecret(for id: String) -> String { "appClientSecret_\(id)" }
    }
    
    // Secure storage methods for tokens
    func saveAccessToken(_ token: String) {
        KeychainHelper.standard.save(token, service: "SocialFusion", account: StorageKeys.accessToken(for: id))
    }
    
    func getAccessToken() -> String? {
        return KeychainHelper.standard.read(service: "SocialFusion", account: StorageKeys.accessToken(for: id))
    }
    
    func saveRefreshToken(_ token: String?) {
        guard let token = token else { return }
        KeychainHelper.standard.save(token, service: "SocialFusion", account: StorageKeys.refreshToken(for: id))
    }
    
    func getRefreshToken() -> String? {
        return KeychainHelper.standard.read(service: "SocialFusion", account: StorageKeys.refreshToken(for: id))
    }
    
    func saveTokenExpirationDate(_ date: Date?) {
        guard let date = date else { return }
        UserDefaults.standard.set(date, forKey: StorageKeys.tokenExpirationDate(for: id))
    }
    
    func getTokenExpirationDate() -> Date? {
        return UserDefaults.standard.object(forKey: StorageKeys.tokenExpirationDate(for: id)) as? Date
    }
    
    func saveClientCredentials(clientId: String, clientSecret: String) {
        KeychainHelper.standard.save(clientId, service: "SocialFusion", account: StorageKeys.appClientId(for: id))
        KeychainHelper.standard.save(clientSecret, service: "SocialFusion", account: StorageKeys.appClientSecret(for: id))
    }
    
    func getClientId() -> String? {
        return KeychainHelper.standard.read(service: "SocialFusion", account: StorageKeys.appClientId(for: id))
    }
    
    func getClientSecret() -> String? {
        return KeychainHelper.standard.read(service: "SocialFusion", account: StorageKeys.appClientSecret(for: id))
    }
    
    // Check if token is expired and needs refresh
    var isTokenExpired: Bool {
        guard let expirationDate = getTokenExpirationDate() else {
            return true
        }
        // Consider token expired 5 minutes before actual expiration to avoid edge cases
        return Date() > expirationDate.addingTimeInterval(-300)
    }
}
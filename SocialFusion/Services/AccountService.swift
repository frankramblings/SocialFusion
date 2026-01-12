import Foundation

/// Protocol that all social account services must implement
protocol AccountService {
    /// The social platform for this service
    var platform: SocialPlatform { get }

    /// Load all accounts from persistent storage
    func loadAccounts() -> [SocialAccount]

    /// Save account to persistent storage
    func saveAccount(_ account: SocialAccount) -> Bool

    /// Delete account from persistent storage
    func deleteAccount(_ account: SocialAccount) -> Bool

    /// Authenticate user and create account
    func authenticate(serverURL: URL?, username: String, password: String) async throws
        -> SocialAccount

    /// Refresh authentication tokens for an account
    func refreshAuthentication(for account: SocialAccount) async throws -> SocialAccount

    /// Validate if an account has valid credentials and tokens
    func validateAccount(_ account: SocialAccount) -> Bool
}

/// Base class for Mastodon account operations
class MastodonAccountService: AccountService {
    static let shared = MastodonAccountService()

    var platform: SocialPlatform { .mastodon }

    private let keychainService = "com.socialfusion.mastodonAccounts"
    private let userDefaultsKey = "mastodonAccounts"

    private init() {}

    func loadAccounts() -> [SocialAccount] {
        // Delegate to AccountManager's implementation to avoid duplication
        return AccountManager.shared.mastodonAccounts
    }

    func saveAccount(_ account: SocialAccount) -> Bool {
        // Ensure account is for the correct platform
        guard account.platform == .mastodon else {
            print("Cannot save non-Mastodon account to Mastodon account service")
            return false
        }

        // Let the AccountManager handle the actual saving
        AccountManager.shared.addAccount(account)
        return true
    }

    func deleteAccount(_ account: SocialAccount) -> Bool {
        guard account.platform == .mastodon else {
            print("Cannot delete non-Mastodon account from Mastodon account service")
            return false
        }

        AccountManager.shared.removeAccount(id: account.id)
        return true
    }

    func authenticate(serverURL: URL?, username: String, password: String) async throws
        -> SocialAccount
    {
        // This would be implemented using the Mastodon API
        // For now, we're just creating a placeholder method
        // that will be implemented when we refactor the MastodonService

        throw NSError(
            domain: "com.socialfusion", code: 501,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Mastodon authentication functionality will be implemented in the MastodonService refactoring"
            ])
    }

    func refreshAuthentication(for account: SocialAccount) async throws -> SocialAccount {
        // This would refresh the tokens using the Mastodon API
        // For now, placeholder for future implementation

        throw NSError(
            domain: "com.socialfusion", code: 501,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Token refresh functionality will be implemented in the MastodonService refactoring"
            ])
    }

    func validateAccount(_ account: SocialAccount) -> Bool {
        guard account.platform == .mastodon else { return false }

        // Basic validation
        guard !account.id.isEmpty,
            !account.username.isEmpty,
            account.serverURL != nil,
            account.accessToken != nil
        else {
            return false
        }

        return true
    }
}

/// Base class for Bluesky account operations
class BlueskyAccountService: AccountService {
    static let shared = BlueskyAccountService()

    var platform: SocialPlatform { .bluesky }

    private let keychainService = "com.socialfusion.blueskyAccounts"
    private let userDefaultsKey = "blueskyAccounts"

    private init() {}

    func loadAccounts() -> [SocialAccount] {
        // Delegate to AccountManager's implementation
        return AccountManager.shared.blueskyAccounts
    }

    func saveAccount(_ account: SocialAccount) -> Bool {
        guard account.platform == .bluesky else {
            print("Cannot save non-Bluesky account to Bluesky account service")
            return false
        }

        AccountManager.shared.addAccount(account)
        return true
    }

    func deleteAccount(_ account: SocialAccount) -> Bool {
        guard account.platform == .bluesky else {
            print("Cannot delete non-Bluesky account from Bluesky account service")
            return false
        }

        AccountManager.shared.removeAccount(id: account.id)
        return true
    }

    func authenticate(serverURL: URL?, username: String, password: String) async throws
        -> SocialAccount
    {
        // Use the BlueskyService to authenticate
        do {
            let account = try await BlueskyService.shared.authenticate(
                server: serverURL,
                username: username,
                password: password
            )

            // Save the new account
            _ = saveAccount(account)

            return account
        } catch {
            // Log the error
            print("Bluesky authentication failed: \(error.localizedDescription)")

            // Rethrow to let caller handle it
            throw error
        }
    }

    func refreshAuthentication(for account: SocialAccount) async throws -> SocialAccount {
        guard account.platform == .bluesky else {
            throw NSError(
                domain: "BlueskyAccountService", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Not a Bluesky account"]
            )
        }

        do {
            // Use BlueskyService to refresh the authentication
            _ = try await BlueskyService.shared.refreshSession(for: account)

            // Return the updated account
            return account
        } catch {
            print("Failed to refresh Bluesky authentication: \(error.localizedDescription)")
            throw error
        }
    }

    func validateAccount(_ account: SocialAccount) -> Bool {
        guard account.platform == .bluesky else { return false }

        // Basic validation
        guard !account.id.isEmpty,
            !account.username.isEmpty,
            account.accessToken != nil
        else {
            return false
        }

        return true
    }
}

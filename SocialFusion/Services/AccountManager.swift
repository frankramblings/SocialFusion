import Combine
import Foundation
import Security
import SwiftUI

/// AccountManager handles all operations related to social media accounts
class AccountManager: ObservableObject {
    static let shared = AccountManager()

    // Published properties for UI updating
    @Published var mastodonAccounts: [SocialAccount] = []
    @Published var blueskyAccounts: [SocialAccount] = []
    @Published var selectedAccountIds: Set<String> = []
    @Published var isLoading = false
    @Published var error: Error? = nil

    // Notification names
    static let accountsChangedNotification = Notification.Name("AccountsChangedNotification")
    static let selectedAccountsChangedNotification = Notification.Name(
        "SelectedAccountsChangedNotification")

    // Keychain service names
    private let mastodonKeychainService = "com.socialfusion.mastodonAccounts"
    private let blueskyKeychainService = "com.socialfusion.blueskyAccounts"

    // UserDefaults keys
    private let selectedAccountsKey = "selectedAccountIds"

    // Private initializer for singleton
    private init() {
        loadAccounts()
        loadSelectedAccounts()

        // PHASE 3+: Removed NotificationCenter observers to prevent AttributeGraph cycles
        // Account state management will be handled through normal data flow instead
    }

    // MARK: - Account Loading

    /// Load all accounts from secure storage
    func loadAccounts() {
        isLoading = true

        // Load Mastodon accounts from Keychain
        mastodonAccounts = loadAccountsFromKeychain(service: mastodonKeychainService)
            .filter { validateAccount($0) }

        // Load Bluesky accounts from Keychain
        blueskyAccounts = loadAccountsFromKeychain(service: blueskyKeychainService)
            .filter { validateAccount($0) }

        print(
            "Loaded \(mastodonAccounts.count) Mastodon accounts and \(blueskyAccounts.count) Bluesky accounts"
        )

        isLoading = false

        // Validate selected accounts
        validateSelectedAccounts()
    }

    /// Load selected account IDs from UserDefaults
    private func loadSelectedAccounts() {
        if let savedIDs = UserDefaults.standard.array(forKey: selectedAccountsKey) as? [String] {
            selectedAccountIds = Set(savedIDs)
        }

        // Ensure we have valid selection
        validateSelectedAccounts()
    }

    /// Ensures selected account IDs correspond to actual accounts
    private func validateSelectedAccounts() {
        // Remove any account IDs that don't match loaded accounts
        let validIDs = selectedAccountIds.filter { id in
            mastodonAccounts.contains(where: { $0.id == id })
                || blueskyAccounts.contains(where: { $0.id == id })
        }

        // If no valid IDs, reset to empty
        if validIDs.isEmpty && !selectedAccountIds.isEmpty {
            selectedAccountIds = []
            saveSelectedAccounts()
        } else if validIDs.count != selectedAccountIds.count {
            // Update with only valid IDs
            selectedAccountIds = validIDs
            saveSelectedAccounts()
        }
    }

    // MARK: - Account Management

    /// Add a new account to the appropriate platform
    func addAccount(_ account: SocialAccount) {
        switch account.platform {
        case .mastodon:
            // Check for duplicates
            if !mastodonAccounts.contains(where: { $0.id == account.id }) {
                mastodonAccounts.append(account)
                saveAccounts(accounts: mastodonAccounts, service: mastodonKeychainService)

                // Auto-select newly added account
                selectAccount(account.id)

                // Notify listeners
                NotificationCenter.default.post(name: Self.accountsChangedNotification, object: nil)
            }

        case .bluesky:
            // Check for duplicates
            if !blueskyAccounts.contains(where: { $0.id == account.id }) {
                blueskyAccounts.append(account)
                saveAccounts(accounts: blueskyAccounts, service: blueskyKeychainService)

                // Auto-select newly added account
                selectAccount(account.id)

                // Notify listeners
                NotificationCenter.default.post(name: Self.accountsChangedNotification, object: nil)
            }
        }
    }

    /// Remove an account by ID
    func removeAccount(id: String) {
        // Check Mastodon accounts
        if let index = mastodonAccounts.firstIndex(where: { $0.id == id }) {
            mastodonAccounts.remove(at: index)
            saveAccounts(accounts: mastodonAccounts, service: mastodonKeychainService)

            // Remove from selected accounts if needed
            if selectedAccountIds.contains(id) {
                selectedAccountIds.remove(id)
                saveSelectedAccounts()
            }

            // Notify listeners
            NotificationCenter.default.post(name: Self.accountsChangedNotification, object: nil)
        }

        // Check Bluesky accounts
        if let index = blueskyAccounts.firstIndex(where: { $0.id == id }) {
            blueskyAccounts.remove(at: index)
            saveAccounts(accounts: blueskyAccounts, service: blueskyKeychainService)

            // Remove from selected accounts if needed
            if selectedAccountIds.contains(id) {
                selectedAccountIds.remove(id)
                saveSelectedAccounts()
            }

            // Notify listeners
            NotificationCenter.default.post(name: Self.accountsChangedNotification, object: nil)
        }
    }

    /// Update an existing account
    func updateAccount(_ account: SocialAccount) {
        switch account.platform {
        case .mastodon:
            if let index = mastodonAccounts.firstIndex(where: { $0.id == account.id }) {
                mastodonAccounts[index] = account
                saveAccounts(accounts: mastodonAccounts, service: mastodonKeychainService)

                // Notify listeners
                NotificationCenter.default.post(name: Self.accountsChangedNotification, object: nil)
            }

        case .bluesky:
            if let index = blueskyAccounts.firstIndex(where: { $0.id == account.id }) {
                blueskyAccounts[index] = account
                saveAccounts(accounts: blueskyAccounts, service: blueskyKeychainService)

                // Notify listeners
                NotificationCenter.default.post(name: Self.accountsChangedNotification, object: nil)
            }
        }
    }

    // MARK: - Account Selection

    /// Select a specific account by ID
    func selectAccount(_ id: String) {
        // Verify the account exists
        guard getAccountById(id) != nil else {
            print("Cannot select non-existent account ID: \(id)")
            return
        }

        selectedAccountIds.insert(id)
        saveSelectedAccounts()

        // Notify listeners
        NotificationCenter.default.post(name: Self.selectedAccountsChangedNotification, object: nil)
    }

    /// Deselect a specific account by ID
    func deselectAccount(_ id: String) {
        if selectedAccountIds.contains(id) {
            selectedAccountIds.remove(id)
            saveSelectedAccounts()

            // Notify listeners
            NotificationCenter.default.post(
                name: Self.selectedAccountsChangedNotification, object: nil)
        }
    }

    /// Select all accounts
    func selectAllAccounts() {
        let allIds = mastodonAccounts.map { $0.id } + blueskyAccounts.map { $0.id }
        selectedAccountIds = Set(allIds)
        saveSelectedAccounts()

        // Notify listeners
        NotificationCenter.default.post(name: Self.selectedAccountsChangedNotification, object: nil)
    }

    /// Deselect all accounts
    func deselectAllAccounts() {
        selectedAccountIds.removeAll()
        saveSelectedAccounts()

        // Notify listeners
        NotificationCenter.default.post(name: Self.selectedAccountsChangedNotification, object: nil)
    }

    // MARK: - Helper Methods

    /// Get an account by ID
    func getAccountById(_ id: String) -> SocialAccount? {
        if let account = mastodonAccounts.first(where: { $0.id == id }) {
            return account
        }

        if let account = blueskyAccounts.first(where: { $0.id == id }) {
            return account
        }

        return nil
    }

    /// Get all selected accounts
    var selectedAccounts: [SocialAccount] {
        let selected =
            mastodonAccounts.filter { selectedAccountIds.contains($0.id) }
            + blueskyAccounts.filter { selectedAccountIds.contains($0.id) }
        return selected
    }

    /// Get platforms of selected accounts
    var selectedPlatforms: Set<SocialPlatform> {
        var platforms = Set<SocialPlatform>()

        // If no accounts are selected, return all platforms
        if selectedAccountIds.isEmpty {
            return [.mastodon, .bluesky]
        }

        // Add platforms of selected accounts
        for id in selectedAccountIds {
            if mastodonAccounts.contains(where: { $0.id == id }) {
                platforms.insert(.mastodon)
            } else if blueskyAccounts.contains(where: { $0.id == id }) {
                platforms.insert(.bluesky)
            }
        }

        return platforms
    }

    /// Check if account data is valid
    private func validateAccount(_ account: SocialAccount) -> Bool {
        guard !account.id.isEmpty,
            !account.username.isEmpty,
            account.serverURL != nil
        else {
            print("Account validation failed - missing required fields for \(account.username)")
            return false
        }

        return true
    }

    // MARK: - Persistence

    /// Save the list of selected account IDs to UserDefaults
    private func saveSelectedAccounts() {
        UserDefaults.standard.set(Array(selectedAccountIds), forKey: selectedAccountsKey)
    }

    /// Load accounts from Keychain
    private func loadAccountsFromKeychain(service: String) -> [SocialAccount] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let items = result as? [[String: Any]] {
            return items.compactMap { item in
                guard let data = item[kSecValueData as String] as? Data else { return nil }

                do {
                    let decoder = JSONDecoder()
                    return try decoder.decode(SocialAccount.self, from: data)
                } catch {
                    print("Error decoding account: \(error)")
                    return nil
                }
            }
        } else {
            // Fallback to UserDefaults for migration
            return migrateFromUserDefaults(service: service)
        }

        return []
    }

    /// Save accounts to Keychain
    private func saveAccounts(accounts: [SocialAccount], service: String) {
        // First delete existing items
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]

        SecItemDelete(deleteQuery as CFDictionary)

        // Now save each account
        for account in accounts {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(account)

                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account.id,
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                ]

                let status = SecItemAdd(query as CFDictionary, nil)
                if status != errSecSuccess {
                    print("Error saving account to Keychain: \(status)")
                }
            } catch {
                print("Error encoding account: \(error)")
            }
        }
    }

    /// Migrate accounts from UserDefaults for backward compatibility
    private func migrateFromUserDefaults(service: String) -> [SocialAccount] {
        let key = service == mastodonKeychainService ? "mastodonAccounts" : "blueskyAccounts"

        if let data = UserDefaults.standard.data(forKey: key) {
            do {
                let decoder = JSONDecoder()
                let accounts = try decoder.decode([SocialAccount].self, from: data)

                // Save to keychain for future use
                saveAccounts(accounts: accounts, service: service)

                return accounts
            } catch {
                print("Error migrating accounts from UserDefaults: \(error)")
            }
        }

        return []
    }
}

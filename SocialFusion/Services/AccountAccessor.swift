import Foundation
import os.log

/// Global account accessor that tries multiple sources to find accounts
@MainActor
class AccountAccessor {
    static let shared = AccountAccessor()
    private let logger = Logger(subsystem: "com.socialfusion.app", category: "AccountAccessor")
    
    private init() {}
    
    /// Gets an account for the given platform, trying multiple sources
    /// This method ensures accounts are loaded before checking
    func getAccountForPlatform(_ platform: SocialPlatform) async -> SocialAccount? {
        let accountManager = AccountManager.shared
        
        // Ensure accounts are loaded - wait for loadAccounts to complete
        await accountManager.loadAccountsAsync()
        
        var account: SocialAccount?
        switch platform {
        case .bluesky:
            account = accountManager.blueskyAccounts.first
            if account != nil {
                logger.info("✅ Found Bluesky account in AccountManager: \(account!.username, privacy: .public)")
                return account
            }
        case .mastodon:
            account = accountManager.mastodonAccounts.first
            if account != nil {
                logger.info("✅ Found Mastodon account in AccountManager: \(account!.username, privacy: .public)")
                return account
            }
        }
        
        logger.warning("⚠️ No account found in AccountManager for \(platform.rawValue, privacy: .public) - Mastodon: \(accountManager.mastodonAccounts.count), Bluesky: \(accountManager.blueskyAccounts.count)")
        
        return nil
    }
    
    /// Gets all accounts for a platform
    func getAccountsForPlatform(_ platform: SocialPlatform) -> [SocialAccount] {
        let accountManager = AccountManager.shared
        
        switch platform {
        case .bluesky:
            return accountManager.blueskyAccounts
        case .mastodon:
            return accountManager.mastodonAccounts
        }
    }
}


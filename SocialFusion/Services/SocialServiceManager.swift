import AuthenticationServices  // For authentication-related functionality
import Combine
import Foundation
import SwiftUI
import UIKit
import os
import os.log

// Define notification names
extension Notification.Name {
    static let profileImageUpdated = Notification.Name("AccountProfileImageUpdated")
    static let accountUpdated = Notification.Name("AccountUpdated")
}

// Define service errors
public enum ServiceError: Error, LocalizedError {
    case invalidInput(reason: String)
    case invalidAccount(reason: String)
    case duplicateAccount
    case authenticationFailed(reason: String)
    case networkError(underlying: Error)
    case rateLimitError(reason: String, retryAfter: TimeInterval = 60)
    case timelineError(underlying: Error)
    case invalidContent(reason: String)
    case noPlatformsSelected
    case postFailed(reason: String)
    case unsupportedPlatform
    case apiError(String)
    case unauthorized(String)
    case emptyResponse
    case dataFormatError(String)
    case unknown(String)
    case timeout(String)
    case authenticationExpired(String)

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let reason):
            return "Invalid input: \(reason)"
        case .invalidAccount(let reason):
            return "Invalid account: \(reason)"
        case .duplicateAccount:
            return "This account has already been added"
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .rateLimitError(let reason, _):
            return "Rate limit exceeded: \(reason)"
        case .timelineError(let underlying):
            return "Timeline error: \(underlying.localizedDescription)"
        case .invalidContent(let reason):
            return "Invalid content: \(reason)"
        case .noPlatformsSelected:
            return "No platforms selected for post"
        case .postFailed(let reason):
            return "Failed to post: \(reason)"
        case .unsupportedPlatform:
            return "Unsupported platform"
        case .apiError(let message):
            return "API error: \(message)"
        case .unauthorized(let reason):
            return "Unauthorized: \(reason)"
        case .emptyResponse:
            return "Empty response"
        case .dataFormatError(let reason):
            return "Data format error: \(reason)"
        case .unknown(let reason):
            return "Unknown error: \(reason)"
        case .timeout(let reason):
            return "Request timed out: \(reason)"
        case .authenticationExpired(let reason):
            return "Authentication expired: \(reason)"
        }
    }
}

// Rate limit tracking structure
struct RateLimitInfo {
    var platformName: String
    var lastHit: Date
    var retryAfter: TimeInterval
    var consecutiveHits: Int

    var canMakeRequest: Bool {
        Date() > lastHit.addingTimeInterval(retryAfter)
    }

    var nextAllowedRequestTime: Date {
        lastHit.addingTimeInterval(retryAfter)
    }
}

/// Service manager for handling all social platform interactions
/// Manages authentication, timeline loading, and post interactions for Mastodon and Bluesky
@MainActor
public final class SocialServiceManager: ObservableObject {

    @Published var accounts: [SocialAccount] = []
    @Published var isLoading: Bool = false
    @Published var error: Error?

    // Selected account IDs (Set to store unique IDs)
    @Published var selectedAccountIds: Set<String> = [] {
        didSet {
            print("🔧 SocialServiceManager: selectedAccountIds changed to: \(selectedAccountIds)")
        }
    }

    // Filtered account lists
    @Published var mastodonAccounts: [SocialAccount] = []
    @Published var blueskyAccounts: [SocialAccount] = []

    // Timeline data
    @Published var unifiedTimeline: [Post] = []
    @Published var isLoadingTimeline: Bool = false
    @Published var timelineError: Error?
    private var lastTimelineUpdate: Date = Date.distantPast

    // Strong refresh control with circuit breaker pattern
    private var isRefreshInProgress: Bool = false
    private var lastRefreshAttempt: Date = Date.distantPast
    private var consecutiveFailures: Int = 0
    private let maxConsecutiveFailures: Int = 3
    private var isCircuitBreakerOpen: Bool = false
    private var circuitBreakerOpenTime: Date?
    private let circuitBreakerResetInterval: TimeInterval = 300  // 5 minutes

    // Global refresh lock to prevent multiple simultaneous refreshes from ANY source
    private static var globalRefreshLock = false
    private static var globalRefreshLockTime: Date = Date.distantPast

    // Pagination state
    @Published var isLoadingNextPage: Bool = false
    @Published var hasNextPage: Bool = true
    private var paginationTokens: [String: String] = [:]  // accountId -> nextPageToken

    // Services for each platform
    private let mastodonService = MastodonService()
    private let blueskyService = BlueskyService()

    // Cache for Mastodon parent posts to avoid redundant fetches
    private var mastodonPostCache: [String: (post: Post, timestamp: Date)] = [:]
    // Cache for Bluesky parent posts to avoid redundant fetches
    private var blueskyPostCache: [String: Post] = [:]
    // Track in-progress parent fetches to avoid redundant network calls
    private var parentFetchInProgress: Set<String> = []

    // Automatic token refresh service
    public var automaticTokenRefreshService: AutomaticTokenRefreshService?

    // MARK: - Initialization

    // Make initializer public so it can be used in SocialFusionApp
    public init() {
        print("🔧 SocialServiceManager: Starting initialization...")

        // Load saved accounts first
        loadAccounts()

        // Initialize automatic token refresh service after main initialization
        self.automaticTokenRefreshService = AutomaticTokenRefreshService(socialServiceManager: self)

        print("🔧 SocialServiceManager: After loadAccounts() - accounts.count = \(accounts.count)")
        print("🔧 SocialServiceManager: Mastodon accounts: \(mastodonAccounts.count)")
        print("🔧 SocialServiceManager: Bluesky accounts: \(blueskyAccounts.count)")

        // Initialize selectedAccountIds based on whether accounts exist
        if !accounts.isEmpty {
            selectedAccountIds = ["all"]  // Default to "all" if accounts exist
            print(
                "🔧 SocialServiceManager: Initialized selectedAccountIds to 'all' with \(accounts.count) accounts"
            )
            print(
                "🔧 SocialServiceManager: Mastodon accounts: \(mastodonAccounts.count), Bluesky accounts: \(blueskyAccounts.count)"
            )

            // List all accounts for debugging
            for (index, account) in accounts.enumerated() {
                print(
                    "🔧 SocialServiceManager: Account \(index): \(account.username) (\(account.platform)) - ID: \(account.id)"
                )
            }
        } else {
            selectedAccountIds = []  // No accounts available
            print("🔧 SocialServiceManager: No accounts found - selectedAccountIds set to empty")
        }

        print("🔧 SocialServiceManager: Initialization completed")
        print("🔧 SocialServiceManager: Final selectedAccountIds = \(selectedAccountIds)")
        print("🔧 SocialServiceManager: Final accounts count = \(accounts.count)")
        print("🔧 SocialServiceManager: Final unifiedTimeline count = \(unifiedTimeline.count)")

        // Note: Timeline refresh will be handled by UI lifecycle events
        // This ensures reliable refresh when the user actually opens the app

        // Register for app termination notification to save accounts
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveAccountsBeforeTermination),
            name: UIApplication.willTerminateNotification,
            object: nil
        )

        // Register for profile image update notifications to save accounts
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProfileImageUpdate),
            name: .profileImageUpdated,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func saveAccountsBeforeTermination() {
        saveAccounts()
    }

    @objc private func handleProfileImageUpdate(_ notification: Notification) {
        // Save accounts when profile images are updated to persist the new URLs
        saveAccounts()
        print("💾 [SocialServiceManager] Saved accounts after profile image update")
    }

    // MARK: - Account Management

    /// Load saved accounts from UserDefaults
    private func loadAccounts() {
        let logger = Logger(subsystem: "com.socialfusion", category: "AccountPersistence")
        logger.info("Loading saved accounts")
        print("🔧 SocialServiceManager: loadAccounts() called")

        guard let data = UserDefaults.standard.data(forKey: "savedAccounts") else {
            logger.info("No saved accounts found")
            print("🔧 SocialServiceManager: No saved accounts data found in UserDefaults")
            updateAccountLists()
            return
        }

        print("🔧 SocialServiceManager: Found saved accounts data, attempting to decode...")

        do {
            let decoder = JSONDecoder()
            let decodedAccounts = try decoder.decode([SocialAccount].self, from: data)
            accounts = decodedAccounts

            logger.info("Successfully loaded \(decodedAccounts.count) accounts")
            print("🔧 SocialServiceManager: Successfully decoded \(decodedAccounts.count) accounts")

            // Load tokens for each account from keychain
            for (index, account) in accounts.enumerated() {
                print(
                    "🔧 SocialServiceManager: Loading tokens for account \(index): \(account.username) (\(account.platform))"
                )
                account.loadTokensFromKeychain()
                logger.debug("Loaded tokens for account: \(account.username, privacy: .public)")
            }
        } catch {
            logger.error(
                "Failed to decode saved accounts: \(error.localizedDescription, privacy: .public)")
            print(
                "🔧 SocialServiceManager: Failed to decode saved accounts: \(error.localizedDescription)"
            )
        }

        // After loading accounts, separate them by platform
        updateAccountLists()
        print(
            "🔧 SocialServiceManager: Updated account lists - Mastodon: \(mastodonAccounts.count), Bluesky: \(blueskyAccounts.count)"
        )

        // MIGRATION: Check for and migrate old DID-based Bluesky accounts
        migrateOldBlueskyAccounts()

        print("🔧 SocialServiceManager: loadAccounts() completed")

        // PROFILE REFRESH: Update profile images for all loaded accounts (after method is defined)
        refreshAccountProfiles()
    }

    /// Save accounts to UserDefaults
    public func saveAccounts() {
        let logger = Logger(subsystem: "com.socialfusion", category: "AccountPersistence")
        logger.info("Saving \(self.accounts.count) accounts")

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(self.accounts)
            UserDefaults.standard.set(data, forKey: "savedAccounts")
            logger.info("Successfully saved accounts")
        } catch {
            logger.error(
                "Failed to encode accounts: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Update the platform-specific account lists
    private func updateAccountLists() {
        // Separate accounts by platform
        mastodonAccounts = accounts.filter { $0.platform == .mastodon }
        blueskyAccounts = accounts.filter { $0.platform == .bluesky }
    }

    /// Refresh profile information for all accounts
    private func refreshAccountProfiles() {
        print("🔄 SocialServiceManager: Refreshing profile images for all accounts...")

        Task {
            for account in accounts {
                do {
                    switch account.platform {
                    case .mastodon:
                        await mastodonService.updateProfileImage(for: account)
                    case .bluesky:
                        try await blueskyService.updateProfileInfo(for: account)
                    }
                    print("✅ Refreshed profile for \(account.username) (\(account.platform))")
                } catch {
                    print("⚠️ Failed to refresh profile for \(account.username): \(error)")
                }

                // Small delay to avoid overwhelming the APIs
                try? await Task.sleep(nanoseconds: 250_000_000)  // 0.25 seconds
            }

            // Save updated accounts
            await MainActor.run {
                saveAccounts()
                print("💾 Saved accounts after profile refresh")
            }
        }
    }

    /// Public method to manually refresh profile images for all accounts
    @MainActor
    public func refreshAllProfileImages() async {
        refreshAccountProfiles()
    }

    /// Get accounts to fetch based on current selection
    private func getAccountsToFetch() -> [SocialAccount] {
        print("🔧 SocialServiceManager: getAccountsToFetch() called")
        print("🔧 SocialServiceManager: selectedAccountIds = \(selectedAccountIds)")
        print("🔧 SocialServiceManager: total accounts = \(accounts.count)")

        let accountsToFetch: [SocialAccount]
        if selectedAccountIds.contains("all") {
            accountsToFetch = accounts
            print("🔧 SocialServiceManager: Using ALL accounts (\(accounts.count))")
        } else {
            accountsToFetch = accounts.filter { selectedAccountIds.contains($0.id) }
            print("🔧 SocialServiceManager: Using filtered accounts (\(accountsToFetch.count))")
        }

        for (index, account) in accountsToFetch.enumerated() {
            print(
                "🔧 SocialServiceManager: Account \(index): \(account.username) (\(account.platform)) - ID: \(account.id)"
            )
        }

        return accountsToFetch
    }

    /// Force reload accounts for debugging
    @MainActor
    func forceReloadAccounts() async {
        print("🔄 SocialServiceManager: Force reloading accounts...")
        loadAccounts()
        print("🔄 SocialServiceManager: Force reload completed")
        print("🔄 Total accounts: \(accounts.count)")
        print("🔄 Mastodon accounts: \(mastodonAccounts.count)")
        print("🔄 Bluesky accounts: \(blueskyAccounts.count)")
        print("🔄 Selected account IDs: \(selectedAccountIds)")

        // Also trigger a timeline refresh
        do {
            try await refreshTimeline(force: true)
        } catch {
            print("🔄 Error refreshing timeline after force reload: \(error)")
        }
    }

    /// Add a new account
    func addAccount(_ account: SocialAccount) {

        accounts.append(account)
        // Save to UserDefaults
        saveAccounts()

        // Update platform-specific lists
        updateAccountLists()

        // If this is the first account, set selectedAccountIds to "all"
        if accounts.count == 1 {
            selectedAccountIds = ["all"]
            print(
                "📊 [SocialServiceManager] First account added, setting selectedAccountIds to 'all'")
        } else {
            // If "all" is already selected, keep it
            if selectedAccountIds.contains("all") {
                // Keep "all" selected
            } else {
                // Add the new account to selectedAccountIds or switch to "all"
                selectedAccountIds.insert(account.id)
            }
        }

        // Automatically refresh timeline after adding account
        Task {
            do {
                try await refreshTimeline(force: true)
            } catch {
                // Error is already logged by the timeline refresh method
            }
        }
    }

    /// Add a Mastodon account
    func addMastodonAccount(server: String, username: String, password: String) async throws
        -> SocialAccount
    {
        let account = try await mastodonService.authenticate(
            server: URL(string: server),
            username: username,
            password: password
        )

        // Add the account to our collection
        await MainActor.run {
            addAccount(account)
        }

        return account
    }

    /// Add a Mastodon account using an access token
    func addMastodonAccountWithToken(serverURL: String, accessToken: String) async throws
        -> SocialAccount
    {
        let account = try await mastodonService.authenticateWithToken(
            server: URL(string: serverURL)!,
            accessToken: accessToken
        )

        // Add the account to our collection
        await MainActor.run {
            addAccount(account)
        }

        return account
    }

    /// Add a Mastodon account using OAuth credentials (proper flow with refresh token)
    func addMastodonAccountWithOAuth(credentials: OAuthCredentials) async throws -> SocialAccount {
        // Create account from OAuth credentials
        let account = SocialAccount(
            id: credentials.accountId,
            username: credentials.username,
            displayName: credentials.displayName,
            serverURL: credentials.serverURL,
            platform: .mastodon,
            accessToken: credentials.accessToken,
            platformSpecificId: credentials.accountId
        )

        // Store all the necessary tokens and credentials
        account.saveAccessToken(credentials.accessToken)
        if let refreshToken = credentials.refreshToken {
            account.saveRefreshToken(refreshToken)
        }
        account.saveClientCredentials(
            clientId: credentials.clientId, clientSecret: credentials.clientSecret)

        // Set token expiration
        if let expiresAt = credentials.expiresAt {
            account.saveTokenExpirationDate(expiresAt)
        } else {
            // Default to 30 days if no expiration provided (more realistic than 24 hours)
            account.saveTokenExpirationDate(Date().addingTimeInterval(30 * 24 * 60 * 60))
        }

        // Add the account to our collection
        await MainActor.run {
            addAccount(account)
        }

        return account
    }

    /// Helper to extract server URL from account ID (for Mastodon)
    private func extractServerURL(from accountId: String) -> String {
        // For now, we'll need to store this separately or derive it
        // This is a limitation - we should pass server URL in credentials
        return "https://mastodon.social"  // Placeholder - should be improved
    }

    /// Add a Bluesky account
    func addBlueskyAccount(username: String, password: String) async throws -> SocialAccount {
        let account = try await blueskyService.authenticate(
            username: username,
            password: password
        )

        // Add the account to our collection
        await MainActor.run {
            addAccount(account)
        }

        return account
    }

    /// Remove an account
    func removeAccount(_ account: SocialAccount) {
        accounts.removeAll { $0.id == account.id }
        // Would normally remove from UserDefaults or Keychain

        // Update platform-specific lists
        updateAccountLists()
    }

    // MARK: - Timeline

    /// Fetch posts for a specific account
    func fetchPostsForAccount(_ account: SocialAccount) async throws -> [Post] {
        print(
            "🔄 SocialServiceManager: fetchPostsForAccount called for \(account.username) (\(account.platform))"
        )

        do {
            let posts: [Post]
            switch account.platform {
            case .mastodon:
                print("🔄 SocialServiceManager: Fetching Mastodon timeline for \(account.username)")
                let result = try await mastodonService.fetchHomeTimeline(for: account)
                posts = result.posts
                print("🔄 SocialServiceManager: Mastodon fetch completed - \(posts.count) posts")
            case .bluesky:
                print("🔄 SocialServiceManager: Fetching Bluesky timeline for \(account.username)")
                let result = try await blueskyService.fetchTimeline(for: account)
                posts = result.posts
                print("🔄 SocialServiceManager: Bluesky fetch completed - \(posts.count) posts")
            }
            return posts
        } catch {
            print(
                "❌ SocialServiceManager: fetchPostsForAccount failed for \(account.username): \(error.localizedDescription)"
            )
            throw error
        }
    }

    /// Refresh timeline, with option to force refresh
    func refreshTimeline(force: Bool = false) async throws {
        let debugRefresh = UserDefaults.standard.bool(forKey: "debugRefresh")
        if debugRefresh {
            print("🔄 SocialServiceManager: refreshTimeline(force: \(force)) called - ENTRY POINT")
            print("🔄 SocialServiceManager: globalRefreshLock: \(Self.globalRefreshLock)")
            print("🔄 SocialServiceManager: isCircuitBreakerOpen: \(isCircuitBreakerOpen)")
            print("🔄 SocialServiceManager: isRefreshInProgress: \(isRefreshInProgress)")
            print("🔄 SocialServiceManager: isLoadingTimeline: \(isLoadingTimeline)")
            print("🔄 SocialServiceManager: lastRefreshAttempt: \(lastRefreshAttempt)")
            print("🔄 SocialServiceManager: consecutiveFailures: \(consecutiveFailures)")
        } else {
            print("🔄 SocialServiceManager: refreshTimeline(force: \(force)) called")
        }

        let now = Date()

        // Allow initial load to bypass restrictions if timeline is completely empty
        let isInitialLoad = unifiedTimeline.isEmpty && !isLoadingTimeline
        let isUserInitiated = force  // Force flag indicates user-initiated refresh (pull-to-refresh)
        let shouldBypassRestrictions = isUserInitiated || isInitialLoad

        print(
            "🔄 SocialServiceManager: isInitialLoad = \(isInitialLoad), isUserInitiated = \(isUserInitiated), shouldBypassRestrictions = \(shouldBypassRestrictions)"
        )
        print(
            "🔄 SocialServiceManager: unifiedTimeline.count = \(unifiedTimeline.count), isLoadingTimeline = \(isLoadingTimeline)"
        )

        // IMPROVED GLOBAL LOCK: Only block automatic refreshes, allow user-initiated ones
        if Self.globalRefreshLock && !shouldBypassRestrictions {
            // Check if lock is stale (older than 10 seconds)
            if now.timeIntervalSince(Self.globalRefreshLockTime) > 10.0 {
                Self.globalRefreshLock = false
                print("🔓 SocialServiceManager: Stale refresh lock reset")
            } else {
                // Lock is active - BLOCK only automatic attempts, allow user-initiated
                print("🔒 SocialServiceManager: Refresh blocked by global lock (automatic refresh)")
                return
            }
        }

        // For user-initiated refreshes, cancel any existing refresh and proceed immediately
        if isUserInitiated && Self.globalRefreshLock {
            print("🔄 SocialServiceManager: User-initiated refresh - canceling existing refresh")
            Self.globalRefreshLock = false
        }

        // Set global lock immediately to block other attempts
        Self.globalRefreshLock = true
        Self.globalRefreshLockTime = now

        defer {
            Self.globalRefreshLock = false
        }

        // Circuit breaker: if too many failures, temporarily stop automatic requests
        // BUT allow user-initiated refreshes and initial loads to proceed
        if isCircuitBreakerOpen && !shouldBypassRestrictions {
            if let openTime = circuitBreakerOpenTime,
                now.timeIntervalSince(openTime) > circuitBreakerResetInterval
            {
                // Reset circuit breaker
                isCircuitBreakerOpen = false
                circuitBreakerOpenTime = nil
                consecutiveFailures = 0
                print("🔄 SocialServiceManager: Circuit breaker reset - resuming requests")
            } else {
                // Circuit breaker is still open - block only automatic requests
                print(
                    "🚫 SocialServiceManager: Refresh blocked by circuit breaker (automatic refresh)"
                )
                return
            }
        }

        // For user-initiated refreshes, allow them even if circuit breaker is open
        // but reset the circuit breaker after successful user refresh
        if isUserInitiated && isCircuitBreakerOpen {
            print("🔄 SocialServiceManager: User-initiated refresh - bypassing circuit breaker")
        }

        // Rate limiting - minimum time between attempts
        // User-initiated refreshes get more lenient rate limiting
        let minimumInterval: TimeInterval
        if isUserInitiated {
            minimumInterval = 0.5  // Allow user to refresh every 0.5 seconds
        } else if isInitialLoad {
            minimumInterval = 1.0  // Initial loads get 1 second
        } else {
            minimumInterval = 3.0  // Automatic refreshes get 3 seconds
        }

        guard
            shouldBypassRestrictions || now.timeIntervalSince(lastRefreshAttempt) > minimumInterval
        else {
            let timeRemaining = minimumInterval - now.timeIntervalSince(lastRefreshAttempt)
            print(
                "🕐 SocialServiceManager: Refresh blocked by rate limiting (wait \(String(format: "%.1f", timeRemaining))s)"
            )
            return
        }

        // Additional check: if we're already loading or refreshing, abort (unless forced or initial)
        guard shouldBypassRestrictions || (!isLoadingTimeline && !isRefreshInProgress) else {
            print("🔄 SocialServiceManager: Refresh blocked - already in progress")
            return
        }

        if isInitialLoad {
            print("🚀 SocialServiceManager: Initial load detected - bypassing restrictions")
        }

        isRefreshInProgress = true
        lastRefreshAttempt = now

        defer { isRefreshInProgress = false }

        do {
            try await fetchTimeline(force: isUserInitiated)
            // Reset failure count on success
            consecutiveFailures = 0

            // If this was a user-initiated refresh that succeeded, reset circuit breaker
            if isUserInitiated && isCircuitBreakerOpen {
                isCircuitBreakerOpen = false
                circuitBreakerOpenTime = nil
                print("✅ SocialServiceManager: Circuit breaker reset after successful user refresh")
            }

            print("✅ SocialServiceManager: Timeline refresh completed successfully")
        } catch {
            consecutiveFailures += 1
            let errorMessage = "Timeline refresh failed: \(error.localizedDescription)"
            print("❌ SocialServiceManager: \(errorMessage)")

            // For user-initiated refreshes, be more lenient with circuit breaker
            let failureThreshold =
                isUserInitiated ? maxConsecutiveFailures * 2 : maxConsecutiveFailures

            if consecutiveFailures >= failureThreshold {
                isCircuitBreakerOpen = true
                circuitBreakerOpenTime = now
                print(
                    "🚫 SocialServiceManager: Circuit breaker opened after \(consecutiveFailures) failures"
                )
            }

            // Provide more detailed error information for user-initiated refreshes
            if isUserInitiated {
                print(
                    "ℹ️ SocialServiceManager: User-initiated refresh failed - providing detailed error"
                )
                // Throw the original error for now
                throw error
            }

            throw error
        }
    }

    /// Create user-friendly error messages for refresh failures
    private func createUserFriendlyError(from error: Error) -> Error {
        if let networkError = error as? NetworkError {
            switch networkError {
            case .networkUnavailable:
                return NSError(
                    domain: "SocialFusion",
                    code: 1001,
                    userInfo: [
                        NSLocalizedDescriptionKey: "No internet connection",
                        NSLocalizedRecoverySuggestionErrorKey:
                            "Please check your internet connection and try again.",
                    ]
                )
            case .timeout:
                return NSError(
                    domain: "SocialFusion",
                    code: 1002,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Request timed out",
                        NSLocalizedRecoverySuggestionErrorKey:
                            "The server is taking too long to respond. Please try again.",
                    ]
                )
            case .rateLimitExceeded(let retryAfter):
                return NSError(
                    domain: "SocialFusion",
                    code: 1003,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Rate limit exceeded",
                        NSLocalizedRecoverySuggestionErrorKey:
                            "Please wait \(Int(retryAfter ?? 60)) seconds before trying again.",
                    ]
                )
            case .serverError:
                return NSError(
                    domain: "SocialFusion",
                    code: 1004,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Server error",
                        NSLocalizedRecoverySuggestionErrorKey:
                            "The server is experiencing issues. Please try again later.",
                    ]
                )
            case .unauthorized:
                return NSError(
                    domain: "SocialFusion",
                    code: 1005,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Authentication failed",
                        NSLocalizedRecoverySuggestionErrorKey:
                            "Please check your account settings and try again.",
                    ]
                )
            default:
                break
            }
        }

        // Default fallback
        return NSError(
            domain: "SocialFusion",
            code: 1000,
            userInfo: [
                NSLocalizedDescriptionKey: "Refresh failed",
                NSLocalizedRecoverySuggestionErrorKey:
                    "Unable to refresh timeline. Please try again.",
            ]
        )
    }

    /// Refresh timeline from the specified accounts and return all posts
    func refreshTimeline(accounts: [SocialAccount]) async throws -> [Post] {
        print(
            "🔄 SocialServiceManager: refreshTimeline(accounts:) called with \(accounts.count) accounts"
        )

        // Drastically reduce logging spam
        if accounts.isEmpty {
            print("🔄 SocialServiceManager: No accounts provided, returning empty array")
            return []
        }

        print("🔄 SocialServiceManager: Accounts to fetch from:")
        for account in accounts {
            print("🔄   - \(account.username) (\(account.platform)) - ID: \(account.id)")
        }

        var allPosts: [Post] = []

        // Use Task.detached to prevent cancellation during navigation
        return try await Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: [Post].self) { group in
                for account in accounts {
                    group.addTask {
                        do {
                            print("🔄 SocialServiceManager: Starting fetch for \(account.username)")
                            let posts = try await self.fetchPostsForAccount(account)
                            print(
                                "🔄 SocialServiceManager: Fetched \(posts.count) posts for \(account.username)"
                            )
                            return posts
                        } catch {
                            // Check for cancellation and handle appropriately
                            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                                print(
                                    "🔄 SocialServiceManager: Fetch cancelled for \(account.username)"
                                )
                            } else {
                                print(
                                    "❌ Error fetching \(account.username): \(error.localizedDescription)"
                                )
                            }
                            return []
                        }
                    }
                }

                for await posts in group {
                    allPosts.append(contentsOf: posts)
                }
            }

            print("🔄 SocialServiceManager: Total posts collected: \(allPosts.count)")
            return allPosts
        }.value
    }

    /// Fetch the unified timeline for all accounts
    private func fetchTimeline(force: Bool = false) async throws {
        print("🔄 SocialServiceManager: fetchTimeline(force: \(force)) called")

        // Check if we're already loading or if too many rapid requests
        let now = Date()
        let isInitialLoad = unifiedTimeline.isEmpty && !isLoadingTimeline
        let shouldBypassRestrictions = force || isInitialLoad

        // Allow initial loads and forced refreshes to proceed even if refresh is in progress
        guard !isLoadingTimeline && (!isRefreshInProgress || shouldBypassRestrictions) else {
            print(
                "🔄 SocialServiceManager: Already loading or refreshing - aborting (isInitialLoad: \(isInitialLoad), force: \(force))"
            )
            return  // Silent return - avoid spam
        }

        // Prevent rapid successive refreshes (minimum 2 seconds between attempts)
        // But allow initial loads and forced refreshes to bypass this restriction
        guard now.timeIntervalSince(lastRefreshAttempt) > 2.0 || shouldBypassRestrictions else {
            print(
                "🔄 SocialServiceManager: Too soon since last attempt - aborting (isInitialLoad: \(isInitialLoad), force: \(force))"
            )
            return  // Silent return - avoid spam
        }

        lastRefreshAttempt = now
        isRefreshInProgress = true
        defer { isRefreshInProgress = false }

        // Only log important info, not spam
        let accountsToFetch = getAccountsToFetch()
        print(
            "🔄 SocialServiceManager: Fetching timeline for \(accountsToFetch.count) accounts (isInitialLoad: \(isInitialLoad))"
        )

        for (index, account) in accountsToFetch.enumerated() {
            print(
                "🔄 SocialServiceManager: Account \(index): \(account.username) (\(account.platform))"
            )
        }

        // Reset loading state
        await MainActor.run {
            isLoadingTimeline = true
            timelineError = nil
        }

        defer {
            Task { @MainActor in
                isLoadingTimeline = false
            }
        }

        do {
            let collectedPosts = try await refreshTimeline(accounts: accountsToFetch)
            print("🔄 SocialServiceManager: Collected \(collectedPosts.count) posts from accounts")

            // Process and update timeline
            let sortedPosts = collectedPosts.sorted { $0.createdAt > $1.createdAt }
            print("🔄 SocialServiceManager: Sorted posts, updating timeline...")

            // Update UI on main thread with proper delay to prevent rapid updates and AttributeGraph cycles
            Task { @MainActor in
                self.safelyUpdateTimeline(sortedPosts)
                print("🔄 SocialServiceManager: Timeline updated with \(sortedPosts.count) posts")
            }
        } catch {
            print("🔄 SocialServiceManager: fetchTimeline failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Fetch trending posts from public sources
    @MainActor
    func fetchTrendingPosts() async {
        // Don't fetch trending posts if there are no accounts - this should show the "Add Account" state
        guard !accounts.isEmpty else {
            return
        }

        isLoadingTimeline = true
        defer { isLoadingTimeline = false }

        do {
            // Try to fetch trending posts from Mastodon
            let posts = try await mastodonService.fetchTrendingPosts()
            self.unifiedTimeline = posts
        } catch {
            // If API call fails, show empty timeline and let the error handling in the UI deal with it
            self.unifiedTimeline = []
            self.error = error
        }
    }

    /// Fetch the next page of posts for infinite scrolling
    func fetchNextPage() async throws {
        guard !isLoadingNextPage && hasNextPage else {
            return
        }

        await MainActor.run {
            isLoadingNextPage = true
        }

        do {
            // Determine which accounts to fetch based on selection
            var accountsToFetch: [SocialAccount] = []

            if selectedAccountIds.contains("all") {
                accountsToFetch = accounts
            } else {
                accountsToFetch = accounts.filter { selectedAccountIds.contains($0.id) }
            }

            guard !accountsToFetch.isEmpty else {
                await MainActor.run {
                    isLoadingNextPage = false
                }
                return
            }

            var allNewPosts: [Post] = []
            var hasMorePages = false

            // Fetch next page from each account
            for account in accountsToFetch {
                do {
                    let result = try await fetchNextPageForAccount(account)
                    allNewPosts.append(contentsOf: result.posts)
                    if result.pagination.hasNextPage {
                        hasMorePages = true
                        // Store pagination token for this account
                        if let token = result.pagination.nextPageToken {
                            paginationTokens[account.id] = token
                        }
                    }
                } catch {
                    print("Error fetching next page for \(account.username): \(error)")
                    // Continue with other accounts even if one fails
                }
            }

            // Process and append new posts
            let uniquePosts = allNewPosts.map { post -> Post in
                if let original = post.originalPost {
                    let boostId = "boost-\(post.authorUsername)-\(original.id)"
                    if post.id == original.id {
                        let patched = post.copy(with: boostId)
                        patched.originalPost = original
                        return patched
                    }
                }
                return post
            }

            let sortedNewPosts = uniquePosts.sorted(by: { $0.createdAt > $1.createdAt })

            await MainActor.run {
                // Deduplicate new posts against existing timeline before appending
                let existingIds = Set(self.unifiedTimeline.map { $0.stableId })
                let deduplicatedNewPosts = sortedNewPosts.filter {
                    !existingIds.contains($0.stableId)
                }

                print(
                    "📊 SocialServiceManager: Deduplicating \(sortedNewPosts.count) new posts -> \(deduplicatedNewPosts.count) unique posts"
                )

                // Append new posts to existing timeline
                self.unifiedTimeline.append(contentsOf: deduplicatedNewPosts)
                self.hasNextPage = hasMorePages
                self.isLoadingNextPage = false
            }
        } catch {
            print("❌ SocialServiceManager: Error loading next page: \(error)")
            await MainActor.run {
                self.isLoadingNextPage = false
            }
            throw error
        }
    }

    /// Fetch next page for a specific account
    private func fetchNextPageForAccount(_ account: SocialAccount) async throws -> TimelineResult {
        let token = paginationTokens[account.id]

        switch account.platform {
        case .mastodon:
            return try await mastodonService.fetchHomeTimeline(for: account, maxId: token)
        case .bluesky:
            return try await blueskyService.fetchHomeTimeline(for: account, cursor: token)
        }
    }

    /// Reset pagination state for a fresh timeline fetch
    func resetPagination() {
        paginationTokens.removeAll()
        hasNextPage = true
    }

    /// Fetch a specific post by ID from Bluesky
    func fetchBlueskyPostByID(_ postId: String) async throws -> Post? {
        // Find a Bluesky account to use for the API call
        guard let account = blueskyAccounts.first else {
            throw ServiceError.invalidAccount(reason: "No Bluesky account available")
        }

        return try await blueskyService.fetchPostByID(postId, account: account)
    }

    /// Fetch a specific post by ID from Mastodon with caching
    func fetchMastodonStatus(id: String, account: SocialAccount) async throws -> Post? {
        print("📊 SocialServiceManager: Fetching Mastodon status with ID: \(id)")

        // Check cache first (valid for 5 minutes)
        if let cached = mastodonPostCache[id],
            Date().timeIntervalSince(cached.timestamp) < 300
        {  // 5 minutes
            print("📊 SocialServiceManager: Using cached Mastodon post for ID: \(id)")
            return cached.post
        }

        guard account.platform == .mastodon else {
            print(
                "📊 SocialServiceManager: Invalid account platform - expected Mastodon but got \(account.platform)"
            )
            throw ServiceError.invalidAccount(
                reason: "The provided account is not a Mastodon account")
        }

        do {
            // Use a task with higher priority for better UI responsiveness
            return try await Task.detached(priority: .userInitiated) {
                let result = try await self.mastodonService.fetchStatus(id: id, account: account)
                if let post = result {
                    print(
                        "📊 SocialServiceManager: Successfully fetched Mastodon post \(post.id), inReplyToID: \(post.inReplyToID ?? "nil")"
                    )

                    // Store in cache
                    await MainActor.run {
                        self.mastodonPostCache[id] = (post: post, timestamp: Date())
                    }
                } else {
                    print(
                        "📊 SocialServiceManager: Mastodon service returned nil post for ID: \(id)")
                }
                return result
            }.value
        } catch {
            print("📊 SocialServiceManager: Error fetching Mastodon status: \(error)")
            throw error
        }
    }

    /// Fetch posts for the specified account
    func fetchPosts(for account: SocialAccount? = nil) async throws -> [Post] {
        await MainActor.run {
            isLoading = true
            error = nil
        }

        do {
            var posts: [Post] = []

            if let account = account {
                // Fetch for specific account
                posts = try await fetchPostsForAccount(account)
            } else {
                // Fetch for all accounts
                for account in accounts {
                    do {
                        let accountPosts = try await fetchPostsForAccount(account)
                        posts.append(contentsOf: accountPosts)
                    } catch {
                        print("Error fetching posts for \(account.username): \(error)")
                        // Continue with other accounts even if one fails
                    }
                }
            }

            // Don't fall back to sample posts - if API calls fail, show empty timeline
            // posts.isEmpty is okay - we'll show the proper empty state in the UI

            await MainActor.run {
                isLoading = false
            }

            return posts
        } catch {
            await MainActor.run {
                self.error = error
                isLoading = false
            }
            throw error
        }
    }

    // MARK: - TimelineEntry Construction

    /// Converts an array of Post objects into TimelineEntry objects for robust SwiftUI rendering
    func makeTimelineEntries(from posts: [Post]) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []
        for post in posts {
            if let original = post.originalPost {
                // This is a boost/repost - pass the wrapper post so PostCardView can access boostedBy
                let entry = TimelineEntry(
                    id: "boost-\(post.authorUsername)-\(original.id)",
                    kind: .boost(boostedBy: post.authorUsername),
                    post: post,  // Pass the wrapper post, not the original
                    createdAt: post.createdAt
                )
                entries.append(entry)
            } else if let parentId = post.inReplyToID {
                // This is a reply
                let entry = TimelineEntry(
                    id: "reply-\(post.id)",
                    kind: .reply(parentId: parentId),
                    post: post,
                    createdAt: post.createdAt
                )
                entries.append(entry)
            } else {
                // Normal post
                let entry = TimelineEntry(
                    id: post.id,
                    kind: .normal,
                    post: post,
                    createdAt: post.createdAt
                )
                entries.append(entry)
            }
        }
        // Sort by date, newest first
        return entries.sorted(by: { $0.createdAt > $1.createdAt })
    }

    /// Reply to a post (Mastodon or Bluesky)
    func replyToPost(_ post: Post, content: String) async throws -> Post {
        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            do {
                return try await mastodonService.replyToPost(
                    post, content: content, account: account)
            } catch {
                // If it's an authentication error, show a helpful message
                if error.localizedDescription.contains("noRefreshToken")
                    || error.localizedDescription.contains("Token expired")
                    || error.localizedDescription.contains("No refresh token available")
                {
                    print(
                        "❌ Mastodon authentication expired for \(account.username). Please re-add this account in settings."
                    )
                    throw ServiceError.authenticationExpired(
                        "Your Mastodon account needs to be re-added with proper authentication. Please go to Settings → Accounts and add your Mastodon account again using OAuth."
                    )
                } else {
                    throw error
                }
            }
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            return try await blueskyService.replyToPost(post, content: content, account: account)
        }
    }

    /// Like a post
    public func likePost(_ post: Post) async throws -> Post {
        print("🔄 [SocialServiceManager] likePost called for platform: \(post.platform)")

        switch post.platform {
        case .mastodon:
            print("🔄 [SocialServiceManager] Processing Mastodon like request")
            print("🔄 [SocialServiceManager] Available Mastodon accounts: \(mastodonAccounts.count)")

            for (index, account) in mastodonAccounts.enumerated() {
                print(
                    "🔄 [SocialServiceManager] Mastodon account \(index): \(account.username) (ID: \(account.id))"
                )
                print(
                    "🔄 [SocialServiceManager] Account has access token: \(account.getAccessToken() != nil)"
                )
                print("🔄 [SocialServiceManager] Account token expired: \(account.isTokenExpired)")
            }

            guard let account = mastodonAccounts.first else {
                print("❌ [SocialServiceManager] No Mastodon account available")
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }

            print("✅ [SocialServiceManager] Using Mastodon account: \(account.username)")

            do {
                print("🔄 [SocialServiceManager] Calling mastodonService.likePost")
                let result = try await mastodonService.likePost(post, account: account)
                print("✅ [SocialServiceManager] mastodonService.likePost succeeded")
                return result
            } catch {
                print("❌ [SocialServiceManager] mastodonService.likePost failed: \(error)")

                // If it's an authentication error, show a helpful message
                if error.localizedDescription.contains("noRefreshToken")
                    || error.localizedDescription.contains("Token expired")
                    || error.localizedDescription.contains("No refresh token available")
                {
                    print(
                        "❌ Mastodon authentication expired for \(account.username). Please re-add this account in settings."
                    )
                    throw ServiceError.authenticationExpired(
                        "Your Mastodon account needs to be re-added with proper authentication. Please go to Settings → Accounts and add your Mastodon account again using OAuth."
                    )
                } else {
                    throw error
                }
            }
        case .bluesky:
            print("🔄 [SocialServiceManager] Processing Bluesky like request")
            guard let account = blueskyAccounts.first else {
                print("❌ [SocialServiceManager] No Bluesky account available")
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            print("✅ [SocialServiceManager] Using Bluesky account: \(account.username)")
            return try await blueskyService.likePost(post, account: account)
        }
    }

    /// Unlike a post
    func unlikePost(_ post: Post) async throws -> Post {
        print("🔄 [SocialServiceManager] unlikePost called for platform: \(post.platform)")

        switch post.platform {
        case .mastodon:
            print("🔄 [SocialServiceManager] Processing Mastodon unlike request")
            print("🔄 [SocialServiceManager] Available Mastodon accounts: \(mastodonAccounts.count)")

            guard let account = mastodonAccounts.first else {
                print("❌ [SocialServiceManager] No Mastodon account available")
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }

            print("✅ [SocialServiceManager] Using Mastodon account: \(account.username)")

            do {
                print("🔄 [SocialServiceManager] Calling mastodonService.unlikePost")
                let result = try await mastodonService.unlikePost(post, account: account)
                print("✅ [SocialServiceManager] mastodonService.unlikePost succeeded")
                return result
            } catch {
                print("❌ [SocialServiceManager] mastodonService.unlikePost failed: \(error)")

                // If it's an authentication error, show a helpful message
                if error.localizedDescription.contains("noRefreshToken")
                    || error.localizedDescription.contains("Token expired")
                    || error.localizedDescription.contains("No refresh token available")
                {
                    print(
                        "❌ Mastodon authentication expired for \(account.username). Please re-add this account in settings."
                    )
                    throw ServiceError.authenticationExpired(
                        "Your Mastodon account needs to be re-added with proper authentication. Please go to Settings → Accounts and add your Mastodon account again using OAuth."
                    )
                } else {
                    throw error
                }
            }
        case .bluesky:
            print("🔄 [SocialServiceManager] Processing Bluesky unlike request")
            guard let account = blueskyAccounts.first else {
                print("❌ [SocialServiceManager] No Bluesky account available")
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            print("✅ [SocialServiceManager] Using Bluesky account: \(account.username)")
            return try await blueskyService.unlikePost(post, account: account)
        }
    }

    /// Repost a post (Mastodon or Bluesky)
    public func repostPost(_ post: Post) async throws -> Post {
        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            do {
                return try await mastodonService.repostPost(post, account: account)
            } catch {
                // If it's an authentication error, show a helpful message
                if error.localizedDescription.contains("noRefreshToken")
                    || error.localizedDescription.contains("Token expired")
                    || error.localizedDescription.contains("No refresh token available")
                {
                    print(
                        "❌ Mastodon authentication expired for \(account.username). Please re-add this account in settings."
                    )
                    throw ServiceError.authenticationExpired(
                        "Your Mastodon account needs to be re-added with proper authentication. Please go to Settings → Accounts and add your Mastodon account again using OAuth."
                    )
                } else {
                    throw error
                }
            }
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            return try await blueskyService.repostPost(post, account: account)
        }
    }

    /// Unrepost a post (Mastodon or Bluesky)
    func unrepostPost(_ post: Post) async throws -> Post {
        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            do {
                return try await mastodonService.unrepostPost(post, account: account)
            } catch {
                // If it's an authentication error, show a helpful message
                if error.localizedDescription.contains("noRefreshToken")
                    || error.localizedDescription.contains("Token expired")
                    || error.localizedDescription.contains("No refresh token available")
                {
                    print(
                        "❌ Mastodon authentication expired for \(account.username). Please re-add this account in settings."
                    )
                    throw ServiceError.authenticationExpired(
                        "Your Mastodon account needs to be re-added with proper authentication. Please go to Settings → Accounts and add your Mastodon account again using OAuth."
                    )
                } else {
                    throw error
                }
            }
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            return try await blueskyService.unrepostPost(post, account: account)
        }
    }

    // MARK: - Post Creation

    /// Create a new post on selected platforms
    /// - Parameters:
    ///   - content: The text content of the post
    ///   - platforms: Set of platforms to post to
    ///   - mediaAttachments: Optional media attachments as Data arrays
    ///   - visibility: Post visibility (public, unlisted, followers_only)
    /// - Returns: Array of created posts (one per platform)
    func createPost(
        content: String,
        platforms: Set<SocialPlatform>,
        mediaAttachments: [Data] = [],
        visibility: String = "public"
    ) async throws -> [Post] {
        guard !platforms.isEmpty else {
            throw ServiceError.noPlatformsSelected
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalidContent(reason: "Post content cannot be empty")
        }

        var createdPosts: [Post] = []
        var errors: [Error] = []

        // Post to each selected platform
        for platform in platforms {
            do {
                let post = try await createPost(
                    content: content,
                    platform: platform,
                    mediaAttachments: mediaAttachments,
                    visibility: visibility
                )
                createdPosts.append(post)
            } catch {
                errors.append(error)
                print("Failed to post to \(platform): \(error.localizedDescription)")
            }
        }

        // If no posts were created successfully, throw the first error
        if createdPosts.isEmpty && !errors.isEmpty {
            throw ServiceError.postFailed(
                reason: "Failed to post to any platform: \(errors.first!.localizedDescription)")
        }

        // If some posts failed but at least one succeeded, log warnings but don't throw
        if !errors.isEmpty {
            print(
                "Warning: Posted successfully to \(createdPosts.count) platforms, but \(errors.count) failed"
            )
        }

        return createdPosts
    }

    /// Create a post on a specific platform
    private func createPost(
        content: String,
        platform: SocialPlatform,
        mediaAttachments: [Data] = [],
        visibility: String = "public"
    ) async throws -> Post {
        switch platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            return try await mastodonService.createPost(
                content: content,
                mediaAttachments: mediaAttachments,
                visibility: visibility,
                account: account
            )
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            // For now, Bluesky doesn't support media attachments in our implementation
            // We'll implement a basic text post
            return try await createBlueskyPost(content: content, account: account)
        }
    }

    /// Create a Bluesky post (temporary implementation until BlueskyService.createPost is added)
    private func createBlueskyPost(content: String, account: SocialAccount) async throws -> Post {
        guard let accessToken = account.getAccessToken() else {
            throw ServiceError.unauthorized("No access token available for Bluesky account")
        }

        var serverURLString = account.serverURL?.absoluteString ?? "bsky.social"
        if serverURLString.hasPrefix("https://") {
            serverURLString = String(serverURLString.dropFirst(8))
        }

        let apiURL = "https://\(serverURLString)/xrpc/com.atproto.repo.createRecord"
        guard let url = URL(string: apiURL) else {
            throw ServiceError.invalidInput(reason: "Invalid server URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "repo": account.platformSpecificId,  // Use DID instead of stable ID
            "collection": "app.bsky.feed.post",
            "record": [
                "text": content,
                "createdAt": ISO8601DateFormatter().string(from: Date()),
                "$type": "app.bsky.feed.post",
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.networkError(
                underlying: NSError(domain: "HTTP", code: 0, userInfo: nil))
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ServiceError.postFailed(
                reason: "Bluesky API error (\(httpResponse.statusCode)): \(errorMessage)")
        }

        // Parse the response to get the created post URI
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let uri = json["uri"] as? String
        else {
            throw ServiceError.postFailed(reason: "Invalid response from Bluesky API")
        }

        // Create a Post object from the successful creation
        // Note: This is a minimal implementation - in a real app you'd fetch the full post data
        return Post(
            id: uri,
            content: content,
            authorName: account.displayName ?? account.username,
            authorUsername: account.username,
            authorProfilePictureURL: account.profileImageURL?.absoluteString ?? "",
            createdAt: Date(),
            platform: .bluesky,
            originalURL: "",
            attachments: [],
            mentions: [],
            tags: [],
            platformSpecificId: uri
        )
    }

    /// Create a quote post
    func createQuotePost(content: String, quotedPost: Post, platforms: Set<SocialPlatform>)
        async throws -> [Post]
    {
        var createdPosts: [Post] = []

        for platform in platforms {
            switch platform {
            case .bluesky:
                if let account = blueskyAccounts.first {
                    let post = try await createBlueskyQuotePost(
                        content: content, quotedPost: quotedPost, account: account)
                    createdPosts.append(post)
                }
            case .mastodon:
                if let account = mastodonAccounts.first {
                    // For Mastodon, include the quoted post URL in the content
                    let quotedContent = "\(content)\n\n\(quotedPost.originalURL)"
                    let post = try await mastodonService.createPost(
                        content: quotedContent, account: account)
                    createdPosts.append(post)
                }
            }
        }

        return createdPosts
    }

    /// Create a Bluesky quote post with proper embed
    private func createBlueskyQuotePost(content: String, quotedPost: Post, account: SocialAccount)
        async throws -> Post
    {
        guard let accessToken = account.getAccessToken() else {
            throw ServiceError.unauthorized("No access token available for Bluesky account")
        }

        var serverURLString = account.serverURL?.absoluteString ?? "bsky.social"
        if serverURLString.hasPrefix("https://") {
            serverURLString = String(serverURLString.dropFirst(8))
        }

        let apiURL = "https://\(serverURLString)/xrpc/com.atproto.repo.createRecord"
        guard let url = URL(string: apiURL) else {
            throw ServiceError.invalidInput(reason: "Invalid server URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Create the quote post embed
        let embed: [String: Any] = [
            "$type": "app.bsky.embed.record",
            "record": [
                "uri": quotedPost.quotedPostUri ?? quotedPost.platformSpecificId,
                "cid": quotedPost.cid ?? "",
            ],
        ]

        let body: [String: Any] = [
            "repo": account.platformSpecificId,
            "collection": "app.bsky.feed.post",
            "record": [
                "text": content,
                "createdAt": ISO8601DateFormatter().string(from: Date()),
                "$type": "app.bsky.feed.post",
                "embed": embed,
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.networkError(
                underlying: NSError(domain: "HTTP", code: 0, userInfo: nil))
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ServiceError.postFailed(
                reason: "Bluesky quote post API error (\(httpResponse.statusCode)): \(errorMessage)"
            )
        }

        // Parse the response to get the created post URI
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let uri = json["uri"] as? String
        else {
            throw ServiceError.postFailed(reason: "Invalid response from Bluesky quote post API")
        }

        // Create a Post object from the successful creation
        return Post(
            id: uri,
            content: content,
            authorName: account.displayName ?? account.username,
            authorUsername: account.username,
            authorProfilePictureURL: account.profileImageURL?.absoluteString ?? "",
            createdAt: Date(),
            platform: .bluesky,
            originalURL: "",
            attachments: [],
            mentions: [],
            tags: [],
            platformSpecificId: uri,
            quotedPostUri: quotedPost.quotedPostUri ?? quotedPost.platformSpecificId,
            quotedPostAuthorHandle: quotedPost.quotedPostAuthorHandle ?? quotedPost.authorUsername,
            quotedPost: quotedPost
        )
    }

    /// Safely update the timeline with proper isolation to prevent AttributeGraph cycles
    @MainActor
    private func safelyUpdateTimeline(_ posts: [Post]) {
        print("🔄 SocialServiceManager: Updating unifiedTimeline with \(posts.count) posts")
        self.unifiedTimeline = posts
        print("✅ SocialServiceManager: unifiedTimeline updated - new count: \(posts.count)")

        // Proactively fetch parent posts in the background to prevent jittery reply banner animations
        Task.detached(priority: .background) { [weak self] in
            print("🔄 SocialServiceManager: Starting background proactive parent fetching task")
            await self?.proactivelyFetchParentPosts(from: posts)
        }
    }

    @MainActor
    private func updateLoadingState(_ isLoading: Bool, error: Error? = nil) {
        // Immediate update - no delays
        self.isLoadingTimeline = isLoading
        if let error = error {
            self.timelineError = error
        } else if !isLoading {
            self.timelineError = nil
        }
    }

    // MARK: - Migration Logic

    private func migrateOldBlueskyAccounts() {
        // Check for Bluesky accounts that might have DID-based IDs
        var accountsToMigrate: [SocialAccount] = []
        var migratedAccounts: [SocialAccount] = []

        for account in accounts where account.platform == .bluesky {
            // Check if this account has a DID-based ID (starts with "did:")
            if account.id.hasPrefix("did:") {
                print(
                    "🔄 [Migration] Found old DID-based Bluesky account: \(account.username) with ID: \(account.id)"
                )
                accountsToMigrate.append(account)

                // Create new stable ID
                let serverString = account.serverURL?.absoluteString ?? "bsky.social"
                let serverHostname: String
                if let url = URL(string: serverString), let host = url.host {
                    serverHostname = host
                } else {
                    let cleanedServer = serverString.replacingOccurrences(of: "https://", with: "")
                        .replacingOccurrences(of: "http://", with: "")
                    serverHostname =
                        cleanedServer.components(separatedBy: "/").first ?? "bsky.social"
                }
                let stableId = "bluesky-\(account.username)-\(serverHostname)"

                // Create migrated account with new ID but same data
                let migratedAccount = SocialAccount(
                    id: stableId,
                    username: account.username,
                    displayName: account.displayName ?? account.username,
                    serverURL: account.serverURL?.absoluteString ?? "bsky.social",
                    platform: .bluesky,
                    profileImageURL: account.profileImageURL,
                    platformSpecificId: account.id  // Store old DID as platformSpecificId
                )

                // Copy over token information
                if let accessToken = account.getAccessToken() {
                    migratedAccount.saveAccessToken(accessToken)
                }
                if let refreshToken = account.getRefreshToken() {
                    migratedAccount.saveRefreshToken(refreshToken)
                }
                if let expirationDate = account.tokenExpirationDate {
                    migratedAccount.saveTokenExpirationDate(expirationDate)
                }

                migratedAccounts.append(migratedAccount)

                print(
                    "🔄 [Migration] Migrated account \(account.username) from ID: \(account.id) to ID: \(stableId)"
                )
            }
        }

        // Replace old accounts with migrated ones
        if !accountsToMigrate.isEmpty {

            // Remove old accounts
            for oldAccount in accountsToMigrate {
                accounts.removeAll { $0.id == oldAccount.id }
                // Clean up old token storage
                oldAccount.clearTokens()
            }

            // Add migrated accounts
            accounts.append(contentsOf: migratedAccounts)

            // Save updated accounts
            saveAccounts()
            updateAccountLists()

            print(
                "✅ [Migration] Successfully migrated \(migratedAccounts.count) Bluesky accounts to new stable ID format"
            )
        }
    }

    // MARK: - Reliable Refresh Methods

    /// Ensures timeline is refreshed when app becomes active or user navigates to timeline
    /// This is the primary method that should be called from UI lifecycle events
    func ensureTimelineRefresh(force: Bool = false) async {
        print("🔄 SocialServiceManager: ensureTimelineRefresh called (force: \(force))")

        // Simple check: if timeline is empty or force is true, refresh
        let shouldRefresh = force || unifiedTimeline.isEmpty || shouldRefreshBasedOnTime()

        if shouldRefresh {
            print("🔄 SocialServiceManager: Timeline needs refresh - proceeding")
            do {
                try await refreshTimeline(force: true)
                print("✅ SocialServiceManager: Timeline refresh completed successfully")
            } catch {
                print(
                    "❌ SocialServiceManager: Timeline refresh failed: \(error.localizedDescription)"
                )
            }
        } else {
            print("🔄 SocialServiceManager: Timeline is fresh, no refresh needed")
        }
    }

    /// Check if timeline should be refreshed based on time elapsed
    private func shouldRefreshBasedOnTime() -> Bool {
        let now = Date()
        let timeSinceLastRefresh = now.timeIntervalSince(lastRefreshAttempt)

        // Refresh if more than 5 minutes have passed since last refresh
        return timeSinceLastRefresh > 300
    }

    /// Force refresh timeline regardless of current state - for pull-to-refresh
    func forceRefreshTimeline() async {
        print("🔄 SocialServiceManager: forceRefreshTimeline called")
        await ensureTimelineRefresh(force: true)
    }

    // MARK: - Thread Context Loading

    /// Fetch thread context for a post (ancestors and descendants)
    func fetchThreadContext(for post: Post) async throws -> ThreadContext {
        print(
            "📊 SocialServiceManager: fetchThreadContext called for post \(post.id) on \(post.platform)"
        )

        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                print("❌ SocialServiceManager: No Mastodon account available for thread loading")
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            print(
                "📊 SocialServiceManager: Using Mastodon account \(account.username) for thread loading"
            )
            return try await fetchMastodonThreadContext(
                postId: post.platformSpecificId, account: account)
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                print("❌ SocialServiceManager: No Bluesky account available for thread loading")
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            print(
                "📊 SocialServiceManager: Using Bluesky account \(account.username) for thread loading"
            )
            return try await fetchBlueskyThreadContext(
                postId: post.platformSpecificId, account: account)
        }
    }

    /// Fetch Mastodon thread context using the context API
    private func fetchMastodonThreadContext(postId: String, account: SocialAccount) async throws
        -> ThreadContext
    {
        return try await mastodonService.fetchStatusContext(statusId: postId, account: account)
    }

    /// Fetch Bluesky thread context using the getPostThread API
    private func fetchBlueskyThreadContext(postId: String, account: SocialAccount) async throws
        -> ThreadContext
    {
        return try await blueskyService.fetchPostThreadContext(postId: postId, account: account)
    }

    /// Efficiently load thread context with intelligent caching and deduplication
    func loadThreadContextIntelligently(
        for post: Post, existingParents: [Post] = [], existingReplies: [Post] = []
    ) async throws -> ThreadContext {
        let context = try await fetchThreadContext(for: post)

        // Deduplicate against existing posts to avoid redundant data
        let existingParentIds = Set(existingParents.map { $0.platformSpecificId })
        let existingReplyIds = Set(existingReplies.map { $0.platformSpecificId })

        let newParents = context.ancestors.filter {
            !existingParentIds.contains($0.platformSpecificId)
        }
        let newReplies = context.descendants.filter {
            !existingReplyIds.contains($0.platformSpecificId)
        }

        print(
            "📊 SocialServiceManager: Thread context loaded - \(newParents.count) new parents, \(newReplies.count) new replies"
        )

        return ThreadContext(
            ancestors: existingParents + newParents,
            descendants: existingReplies + newReplies
        )
    }

    // MARK: - Helper Methods

    /// Proactively fetch parent posts in the background to prevent jittery reply banner animations
    private func proactivelyFetchParentPosts(from posts: [Post]) async {
        print(
            "🔄 SocialServiceManager: Starting proactive parent post fetching for \(posts.count) posts"
        )

        // Collect all posts that have parent IDs but no cached parent data
        var parentsToFetch: [(postId: String, parentId: String, platform: SocialPlatform)] = []

        for post in posts {
            guard let parentId = post.inReplyToID else { continue }

            // Check if we already have this parent in cache
            let cacheKey = "\(post.platform.rawValue):\(parentId)"
            print("🔍 SocialServiceManager: Checking cache for key: \(cacheKey)")

            if PostParentCache.shared.getCachedPost(id: cacheKey) != nil {
                print("✅ SocialServiceManager: Parent \(parentId) already cached, skipping")
                continue  // Already cached, skip
            }

            // Check if we're already fetching this parent
            if parentFetchInProgress.contains(cacheKey) {
                print("⏳ SocialServiceManager: Parent \(parentId) already being fetched, skipping")
                continue  // Already in progress, skip
            }

            print(
                "📝 SocialServiceManager: Adding parent \(parentId) to fetch queue for post \(post.id)"
            )
            parentsToFetch.append((postId: post.id, parentId: parentId, platform: post.platform))
        }

        guard !parentsToFetch.isEmpty else {
            print("✅ SocialServiceManager: No parent posts need fetching")
            return
        }

        print("🔄 SocialServiceManager: Fetching \(parentsToFetch.count) parent posts in background")

        // Fetch parent posts concurrently with a limit to avoid overwhelming the APIs
        let maxConcurrentFetches = 5
        let batches = Array(parentsToFetch).chunked(into: maxConcurrentFetches)

        for batch in batches {
            await withTaskGroup(of: Void.self) { group in
                for fetchRequest in batch {
                    group.addTask { [weak self] in
                        await self?.fetchSingleParentPost(
                            parentId: fetchRequest.parentId,
                            platform: fetchRequest.platform
                        )
                    }
                }
            }

            // Small delay between batches to be respectful to APIs
            try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
        }

        print("✅ SocialServiceManager: Completed proactive parent post fetching")
    }

    /// Fetch a single parent post and cache it
    private func fetchSingleParentPost(parentId: String, platform: SocialPlatform) async {
        let cacheKey = "\(platform.rawValue):\(parentId)"
        print("🔄 SocialServiceManager: Starting fetch for parent \(parentId) on \(platform)")

        // Mark as in progress
        await MainActor.run {
            parentFetchInProgress.insert(cacheKey)
        }

        defer {
            // Remove from in-progress set when done
            Task { @MainActor in
                parentFetchInProgress.remove(cacheKey)
            }
        }

        do {
            let parentPost: Post?

            switch platform {
            case .mastodon:
                guard let account = mastodonAccounts.first else {
                    print("⚠️ SocialServiceManager: No Mastodon account available for parent fetch")
                    return
                }
                parentPost = try await fetchMastodonStatus(id: parentId, account: account)

            case .bluesky:
                parentPost = try await fetchBlueskyPostByID(parentId)
            }

            // Cache the result if successful
            if let parentPost = parentPost {
                await MainActor.run {
                    PostParentCache.shared.cache[cacheKey] = parentPost
                }
                print("✅ SocialServiceManager: Cached parent post \(parentId) for \(platform)")
            }

        } catch {
            print(
                "⚠️ SocialServiceManager: Failed to fetch parent post \(parentId): \(error.localizedDescription)"
            )
            // Don't throw - just log the error and continue
        }
    }


}

// MARK: - Array Extension for Chunking
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

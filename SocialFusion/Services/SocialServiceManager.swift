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
    @Published var offlineQueueStore = OfflineQueueStore()
    private var cancellables = Set<AnyCancellable>()
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
    @Published var unifiedTimeline: [Post] = [] {
        didSet {
            saveTimelineToDisk()
        }
    }
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

    // Disk Caching
    private let timelineCacheURL: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
        return documents.appendingPathComponent("timeline_cache.json")
    }()

    // Services for each platform
    nonisolated internal let mastodonService: MastodonService
    nonisolated internal let blueskyService: BlueskyService
    private let actionLogger = Logger(subsystem: "com.socialfusion", category: "PostActions")

    // Post action V2 infrastructure - accessible within module
    internal lazy var postActionStore = PostActionStore()
    internal lazy var postActionCoordinator = PostActionCoordinator(
        store: postActionStore, service: self)

    // Edge case handling - temporarily disabled
    // private let edgeCase = EdgeCaseHandler.shared

    // Cache for Mastodon parent posts to avoid redundant fetches
    private var mastodonPostCache: [String: (post: Post, timestamp: Date)] = [:]
    // Cache for Bluesky parent posts to avoid redundant fetches
    private var blueskyPostCache: [String: Post] = [:]
    // Track in-progress parent fetches to avoid redundant network calls
    private var parentFetchInProgress: Set<String> = []

    // Automatic token refresh service
    public var automaticTokenRefreshService: AutomaticTokenRefreshService?

    // Reply filtering
    private lazy var postFeedFilter: PostFeedFilter = {
        let manager = self
        let mastodonResolver = MastodonThreadResolver(service: mastodonService) { [weak manager] in
            guard let manager = manager else { return nil }
            return await MainActor.run { manager.mastodonAccounts.first }
        }
        let blueskyResolver = BlueskyThreadResolver(service: blueskyService) { [weak manager] in
            guard let manager = manager else { return nil }
            return await MainActor.run { manager.blueskyAccounts.first }
        }
        let filter = PostFeedFilter(
            mastodonResolver: mastodonResolver, blueskyResolver: blueskyResolver)
        // Sync initial state from feature flag
        filter.isReplyFilteringEnabled = FeatureFlagManager.isEnabled(.replyFiltering)

        // Load blocked keywords
        if let data = UserDefaults.standard.data(forKey: "blockedKeywords"),
            let keywords = try? JSONDecoder().decode([String].self, from: data)
        {
            filter.blockedKeywords = keywords
        }

        return filter
    }()

    public func updateBlockedKeywords(_ keywords: [String]) {
        if let data = try? JSONEncoder().encode(keywords) {
            UserDefaults.standard.set(data, forKey: "blockedKeywords")
            postFeedFilter.blockedKeywords = keywords
        }
    }

    public var currentBlockedKeywords: [String] {
        postFeedFilter.blockedKeywords
    }

    // MARK: - Initialization

    // Make initializer public so it can be used in SocialFusionApp
    public init(
        mastodonService: MastodonService = MastodonService(),
        blueskyService: BlueskyService = BlueskyService()
    ) {
        self.mastodonService = mastodonService
        self.blueskyService = blueskyService
        print("🔧 SocialServiceManager: Starting initialization...")

        // Load saved accounts first
        loadAccounts()

        // Initialize automatic token refresh service after main initialization
        self.automaticTokenRefreshService = AutomaticTokenRefreshService(socialServiceManager: self)

        // Setup network monitoring for offline queue
        setupNetworkMonitoring()

        // Load cached timeline from disk
        loadTimelineFromDisk()

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

        // Set up PostNormalizerImpl with service manager reference
        PostNormalizerImpl.shared.setServiceManager(self)
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

    /// Load saved accounts
    private func loadAccounts() {
        let logger = Logger(subsystem: "com.socialfusion", category: "AccountPersistence")
        logger.info("Loading saved accounts")
        print("🔧 SocialServiceManager: loadAccounts() called")

        Task {
            // Try to load from new PersistenceManager first
            var loadedAccounts = await PersistenceManager.shared.loadAccounts()

            // Fallback to legacy UserDefaults if not found
            if loadedAccounts == nil {
                if let data = UserDefaults.standard.data(forKey: "savedAccounts") {
                    do {
                        let decoder = JSONDecoder()
                        loadedAccounts = try decoder.decode([SocialAccount].self, from: data)
                        print("🔧 SocialServiceManager: Loaded accounts from legacy UserDefaults")
                    } catch {
                        ErrorHandler.shared.handleError(error)
                        print("🔧 SocialServiceManager: Failed to decode legacy accounts: \(error)")
                    }
                }
            }

            await MainActor.run {
                if let accounts = loadedAccounts {
                    self.accounts = accounts
                    logger.info("Successfully loaded \(accounts.count) accounts")

                    // Load tokens for each account from keychain
                    for account in self.accounts {
                        account.loadTokensFromKeychain()
                    }
                } else {
                    logger.info("No saved accounts found")
                }

                self.updateAccountLists()
                self.migrateOldBlueskyAccounts()
                self.refreshAccountProfiles()
                print("🔧 SocialServiceManager: loadAccounts() completed")
            }
        }
    }

    /// Save accounts
    public func saveAccounts() {
        let accounts = self.accounts
        Task {
            await PersistenceManager.shared.saveAccounts(accounts)
        }
    }

    /// Save the current timeline to disk for offline access
    private func saveTimelineToDisk() {
        let timeline = unifiedTimeline
        Task {
            if #available(iOS 17.0, *) {
                await TimelineSwiftDataStore.shared.saveTimeline(timeline)
            } else {
                await PersistenceManager.shared.saveTimeline(timeline)
            }
        }
    }

    /// Load the cached timeline from disk
    private func loadTimelineFromDisk() {
        Task {
            let cachedPosts: [Post]?
            if #available(iOS 17.0, *) {
                cachedPosts = await TimelineSwiftDataStore.shared.loadTimeline()
            } else {
                cachedPosts = await PersistenceManager.shared.loadTimeline()
            }

            if let posts = cachedPosts {
                await MainActor.run {
                    // Only update if current timeline is empty
                    if self.unifiedTimeline.isEmpty {
                        self.unifiedTimeline = posts
                        print("✅ Successfully loaded \(posts.count) posts from offline cache")
                    }
                }
            }
        }
    }

    /// Update the platform-specific account lists
    private func updateAccountLists() {
        // Separate accounts by platform
        mastodonAccounts = accounts.filter { $0.platform == .mastodon }
        blueskyAccounts = accounts.filter { $0.platform == .bluesky }
    }

    /// Update authentication state for edge case handling - temporarily disabled
    /*
    private func updateAuthenticationState() {
        let totalAccounts = accounts.count
        let authenticatedAccounts = accounts.filter { account in
            // Check if account has valid tokens
            switch account.platform {
            case .mastodon:
                return account.accessToken != nil && !account.accessToken!.isEmpty
            case .bluesky:
                return account.accessToken != nil && !account.accessToken!.isEmpty
            }
        }.count
    
        edgeCase.updateAuthenticationState(
            totalAccounts: totalAccounts,
            authenticatedAccounts: authenticatedAccounts
        )
    }
    */

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
                    ErrorHandler.shared.handleError(error)
                    print("⚠️ Failed to refresh profile for \(account.username): \(error)")
                }

                // Small delay to avoid overwhelming the APIs
                try? await Task.sleep(nanoseconds: 250_000_000)  // 0.25 seconds
            }

            // Save updated accounts
            Task { @MainActor in
                saveAccounts()
                print("💾 Saved accounts after profile refresh")
            }
        }
    }

    /// Public method to manually refresh profile images for all accounts
    @MainActor
    public func refreshAllProfileImages() async {
        await refreshAccountProfiles()
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
            ErrorHandler.shared.handleError(error) {
                Task {
                    try? await self.refreshTimeline(force: true)
                }
            }
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
        Task { @MainActor in
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
        Task { @MainActor in
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
        Task { @MainActor in
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
        Task { @MainActor in
            addAccount(account)
        }

        return account
    }

    /// Remove an account
    @MainActor
    public func removeAccount(_ account: SocialAccount) async {
        print("🗑️ Removing account: \(account.username) (\(account.platform))")

        // Remove from memory
        accounts.removeAll { $0.id == account.id }

        // Update selected IDs
        selectedAccountIds.remove(account.id)
        if selectedAccountIds.isEmpty {
            selectedAccountIds = ["all"]
        }

        // Clear tokens and credentials
        account.logout()

        // Save changes to disk
        saveAccounts()

        // Update platform-specific lists
        updateAccountLists()

        // Reset timeline if no accounts left
        if accounts.isEmpty {
            unifiedTimeline = []
            await PersistenceManager.shared.clearAll()
        } else {
            // Trigger a refresh to remove posts from the deleted account
            try? await refreshTimeline(force: true)
        }
    }

    /// Log out all accounts and clear all data
    @MainActor
    public func logout() async {
        print("🚪 Logging out all accounts...")

        // Logout each individual account (clears tokens)
        for account in accounts {
            account.logout()
        }

        // Clear all memory state
        accounts = []
        mastodonAccounts = []
        blueskyAccounts = []
        unifiedTimeline = []
        selectedAccountIds = []

        // Clear all persisted data
        await PersistenceManager.shared.clearAll()
        if #available(iOS 17.0, *) {
            await TimelineSwiftDataStore.shared.clearAll()
        }

        // Save empty state to persistence
        saveAccounts()

        print("🚪 Logout complete")
    }

    /// Refresh account profile information from the network
    func refreshAccountProfiles() async {
        for account in accounts {
            do {
                if account.platform == .mastodon {
                    let mastodonAccount = try await mastodonService.verifyCredentials(
                        account: account)
                    Task { @MainActor in
                        account.avatarURL = URL(string: mastodonAccount.avatar)
                        account.displayName = mastodonAccount.displayName
                        account.username = mastodonAccount.username
                        // Note: SocialAccount doesn't store followingCount, etc., currently
                        // but we could extend it if needed for the profile switcher
                    }
                } else if account.platform == .bluesky {
                    let profile = try await blueskyService.getProfile(
                        actor: account.username, account: account)
                    Task { @MainActor in
                        account.avatarURL = URL(string: profile.avatar ?? "")
                        account.displayName = profile.displayName
                        // account.username is already correct
                    }
                }
            } catch {
                ErrorHandler.shared.handleError(error)
                print("Failed to refresh profile for \(account.username): \(error)")
            }
        }
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
            let appError = AppError(
                type: .general,
                message: errorMessage,
                isRetryable: false
            )
            ErrorHandler.shared.handleError(appError)
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
        return await Task.detached(priority: .userInitiated) {
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

    /// Get all followed accounts across all platforms
    private func getFollowedAccounts() async -> Set<UserID> {
        var followedAccounts = Set<UserID>()

        await withTaskGroup(of: Set<UserID>.self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        switch account.platform {
                        case .mastodon:
                            return try await self.mastodonService.fetchFollowing(for: account)
                        case .bluesky:
                            return try await self.blueskyService.fetchFollowing(for: account)
                        }
                    } catch {
                        print(
                            "⚠️ Error fetching following for \(account.username): \(error.localizedDescription)"
                        )
                        return []
                    }
                }
            }

            for await accountFollows in group {
                followedAccounts.formUnion(accountFollows)
            }
        }

        // Also add our own accounts as followed
        for account in accounts {
            followedAccounts.insert(UserID(value: account.username, platform: account.platform))
        }

        return followedAccounts
    }

    /// Filter replies in the timeline based on following rules
    private func filterRepliesInTimeline(_ posts: [Post]) async -> [Post] {
        let isEnabled = FeatureFlagManager.isEnabled(.replyFiltering)
        postFeedFilter.isReplyFilteringEnabled = isEnabled

        guard isEnabled else { return posts }

        print("🔍 SocialServiceManager: Starting reply filtering for \(posts.count) posts")
        let startTime = Date()

        let followedAccounts = await getFollowedAccounts()
        var filteredPosts: [Post] = []

        await withTaskGroup(of: (Post, Bool).self) { group in
            for post in posts {
                group.addTask {
                    let shouldInclude = await self.postFeedFilter.shouldIncludePost(
                        post, followedAccounts: followedAccounts)
                    return (post, shouldInclude)
                }
            }

            for await (post, shouldInclude) in group {
                if shouldInclude {
                    filteredPosts.append(post)
                }
            }
        }

        // Sorting is lost in task group, so re-sort by date
        filteredPosts.sort { $0.createdAt > $1.createdAt }

        let duration = Date().timeIntervalSince(startTime)
        print(
            "✅ SocialServiceManager: Filtering complete. Filtered \(posts.count) -> \(filteredPosts.count) posts in \(String(format: "%.2f", duration))s"
        )

        return filteredPosts
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
        Task { @MainActor in
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

            // Filter replies if enabled
            let filteredPosts = await filterRepliesInTimeline(collectedPosts)

            // Process and update timeline
            let sortedPosts = filteredPosts.sorted { $0.createdAt > $1.createdAt }
            print("🔄 SocialServiceManager: Sorted posts, updating timeline...")

            // Update UI on main thread with proper delay to prevent rapid updates and AttributeGraph cycles
            Task { @MainActor in
                self.safelyUpdateTimeline(sortedPosts)
                print("🔄 SocialServiceManager: Timeline updated with \(sortedPosts.count) posts")
            }
        } catch {
            ErrorHandler.shared.handleError(error) {
                Task {
                    try? await self.refreshTimeline(force: false)
                }
            }
            print("🔄 SocialServiceManager: fetchTimeline failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Fetch trending tags across platforms
    public func fetchTrendingTags() async throws -> [SearchTag] {
        guard let account = mastodonAccounts.first else { return [] }

        do {
            let tags = try await mastodonService.fetchTrendingTags(account: account)
            return tags.map { SearchTag(id: $0.name, name: $0.name, platform: .mastodon) }
        } catch {
            ErrorHandler.shared.handleError(error)
            print("Failed to fetch trending tags: \(error)")
            return []
        }
    }

    /// Search for content across platforms
    public func search(
        query: String,
        platforms: Set<SocialPlatform> = [.mastodon, .bluesky],
        onlyMedia: Bool = false
    ) async throws -> SearchResult {
        let accountsToSearch = getAccountsToFetch().filter { platforms.contains($0.platform) }

        var allPosts: [Post] = []
        var allUsers: [SearchUser] = []
        var allTags: [SearchTag] = []

        await withTaskGroup(of: SearchResult?.self) { group in
            for account in accountsToSearch {
                group.addTask {
                    do {
                        switch account.platform {
                        case .mastodon:
                            let result = try await self.mastodonService.search(
                                query: query, account: account)
                            var posts = result.statuses.map {
                                self.mastodonService.convertMastodonStatusToPost(
                                    $0, account: account)
                            }

                            if onlyMedia {
                                posts = posts.filter { !$0.attachments.isEmpty }
                            }

                            let users = result.accounts.map {
                                SearchUser(
                                    id: $0.id, username: $0.acct, displayName: $0.displayName,
                                    avatarURL: $0.avatar, platform: .mastodon)
                            }
                            let tags = result.hashtags.map {
                                SearchTag(id: $0.name, name: $0.name, platform: .mastodon)
                            }
                            return SearchResult(posts: posts, users: users, tags: tags)
                        case .bluesky:
                            // Bluesky search is separate for posts and actors
                            async let postsResult = self.blueskyService.searchPosts(
                                query: query, account: account)
                            async let actorsResult = self.blueskyService.searchActors(
                                query: query, account: account)

                            let (postsData, actorsData) = try await (postsResult, actorsResult)

                            // Convert BlueskyPostDTO to [String: Any] for processTimelineResponse
                            let encoder = JSONEncoder()
                            encoder.dateEncodingStrategy = .iso8601

                            var feedItems: [[String: Any]] = []
                            for postDTO in postsData.posts {
                                if let data = try? encoder.encode(postDTO),
                                    let json = try? JSONSerialization.jsonObject(with: data)
                                        as? [String: Any]
                                {
                                    feedItems.append(["post": json])
                                }
                            }

                            var posts = try await self.blueskyService.processTimelineResponse(
                                feedItems, account: account)

                            if onlyMedia {
                                posts = posts.filter { !$0.attachments.isEmpty }
                            }

                            let users = actorsData.actors.map {
                                SearchUser(
                                    id: $0.did, username: $0.handle, displayName: $0.displayName,
                                    avatarURL: $0.avatar, platform: .bluesky)
                            }
                            return SearchResult(posts: posts, users: users, tags: [])
                        }
                    } catch {
                        ErrorHandler.shared.handleError(error)
                        print("Search failed for \(account.username): \(error)")
                        return nil
                    }
                }
            }

            for await result in group {
                if let result = result {
                    allPosts.append(contentsOf: result.posts)
                    allUsers.append(contentsOf: result.users)
                    allTags.append(contentsOf: result.tags)
                }
            }
        }

        // Sort posts by date
        let sortedPosts = allPosts.sorted { $0.createdAt > $1.createdAt }

        return SearchResult(posts: sortedPosts, users: allUsers, tags: allTags)
    }

    /// Fetch notifications across all platforms
    public func fetchNotifications() async throws -> [AppNotification] {
        let accountsToFetch = getAccountsToFetch()
        var allNotifications: [AppNotification] = []

        await withTaskGroup(of: [AppNotification].self) { group in
            for account in accountsToFetch {
                group.addTask {
                    do {
                        switch account.platform {
                        case .mastodon:
                            let result = try await self.mastodonService.fetchNotifications(
                                for: account)
                            return result.map { mNotif in
                                AppNotification(
                                    id: mNotif.id,
                                    type: self.mapMastodonNotificationType(mNotif.type),
                                    createdAt: DateParser.parse(mNotif.createdAt) ?? Date(),
                                    account: account,
                                    fromAccount: NotificationAccount(
                                        id: mNotif.account.id,
                                        username: mNotif.account.acct,
                                        displayName: mNotif.account.displayName,
                                        avatarURL: mNotif.account.avatar
                                    ),
                                    post: mNotif.status.map {
                                        self.mastodonService.convertMastodonStatusToPost(
                                            $0, account: account)
                                    }
                                )
                            }
                        case .bluesky:
                            let result = try await self.blueskyService.fetchNotifications(
                                for: account)

                            // Collect URIs of posts we need to fetch (likes, reposts, mentions, replies)
                            let urisToFetch = Set(
                                result.notifications.compactMap { $0.reasonSubject })
                            var postsByUri: [String: Post] = [:]

                            if !urisToFetch.isEmpty {
                                do {
                                    let fetchedPosts = try await self.blueskyService.getPosts(
                                        uris: Array(urisToFetch), account: account)
                                    for post in fetchedPosts {
                                        postsByUri[post.platformSpecificId] = post
                                    }
                                } catch {
                                    print(
                                        "Failed to fetch notification posts for Bluesky: \(error)")
                                }
                            }

                            var mappedNotifs: [AppNotification] = []
                            for bNotif in result.notifications {
                                let relatedPost = bNotif.reasonSubject.flatMap { postsByUri[$0] }

                                mappedNotifs.append(
                                    AppNotification(
                                        id: bNotif.cid,
                                        type: self.mapBlueskyNotificationType(bNotif.reason),
                                        createdAt: DateParser.parse(bNotif.indexedAt) ?? Date(),
                                        account: account,
                                        fromAccount: NotificationAccount(
                                            id: bNotif.author.did,
                                            username: bNotif.author.handle,
                                            displayName: bNotif.author.displayName,
                                            avatarURL: bNotif.author.avatar
                                        ),
                                        post: relatedPost
                                    ))
                            }
                            return mappedNotifs
                        }
                    } catch {
                        ErrorHandler.shared.handleError(error)
                        print("Failed to fetch notifications for \(account.username): \(error)")
                        return []
                    }
                }
            }

            for await notifs in group {
                allNotifications.append(contentsOf: notifs)
            }
        }

        return allNotifications.sorted { $0.createdAt > $1.createdAt }
    }

    nonisolated private func mapMastodonNotificationType(_ type: String)
        -> AppNotification.NotificationType
    {
        switch type {
        case "mention": return .mention
        case "reblog": return .repost
        case "favourite": return .like
        case "follow": return .follow
        case "poll": return .poll
        case "update": return .update
        default: return .mention
        }
    }

    nonisolated private func mapBlueskyNotificationType(_ reason: String)
        -> AppNotification.NotificationType
    {
        switch reason {
        case "like": return .like
        case "repost": return .repost
        case "follow": return .follow
        case "mention": return .mention
        case "reply": return .mention  // Bluesky uses reason "reply" for mentions in replies
        case "quote": return .mention  // Bluesky uses reason "quote" for quotes
        default: return .mention
        }
    }

    /// Fetch posts for a specific user across their account with pagination
    public func fetchUserPosts(
        user: SearchUser, account: SocialAccount, limit: Int = 20, cursor: String? = nil
    ) async throws -> ([Post], String?) {
        switch user.platform {
        case .mastodon:
            let posts = try await mastodonService.fetchUserTimeline(
                userId: user.id, for: account, limit: limit, maxId: cursor)
            let nextCursor = posts.last?.platformSpecificId
            return (posts, nextCursor)
        case .bluesky:
            let result = try await blueskyService.fetchAuthorFeed(
                actor: user.id, for: account, limit: limit, cursor: cursor)
            return (result.posts, result.pagination.nextPageToken)
        }
    }

    /// Fetch profile details for a user
    public func fetchUserProfile(user: SearchUser, account: SocialAccount) async throws
        -> UserProfile
    {
        switch user.platform {
        case .mastodon:
            // For Mastodon, we can use the account ID to get details
            let serverUrl = mastodonService.formatServerURL(account.serverURL?.absoluteString ?? "")
            guard let url = URL(string: "\(serverUrl)/api/v1/accounts/\(user.id)") else {
                throw ServiceError.invalidInput(reason: "Invalid user ID")
            }
            let request = try await mastodonService.createAuthenticatedRequest(
                url: url, method: "GET", account: account)
            let (data, _) = try await URLSession.shared.data(for: request)
            let mAccount = try JSONDecoder().decode(MastodonAccount.self, from: data)

            // Fetch relationship
            let relationships = try? await mastodonService.fetchRelationships(
                accountIds: [user.id], account: account)
            let relationship = relationships?.first

            return UserProfile(
                id: mAccount.id,
                username: mAccount.acct,
                displayName: mAccount.displayName,
                avatarURL: mAccount.avatar,
                headerURL: mAccount.header,
                bio: mAccount.note,
                followersCount: mAccount.followersCount,
                followingCount: mAccount.followingCount,
                statusesCount: mAccount.statusesCount,
                platform: .mastodon,
                following: relationship?.following,
                followedBy: relationship?.followedBy,
                muting: relationship?.muting,
                blocking: relationship?.blocking
            )

        case .bluesky:
            let profile = try await blueskyService.getProfile(actor: user.id, account: account)
            return UserProfile(
                id: profile.did,
                username: profile.handle,
                displayName: profile.displayName,
                avatarURL: profile.avatar,
                headerURL: profile.banner,
                bio: profile.description,
                followersCount: profile.followersCount,
                followingCount: profile.followsCount,
                statusesCount: profile.postsCount,
                platform: .bluesky,
                following: profile.viewer?.following != nil,
                followedBy: profile.viewer?.followedBy != nil,
                muting: profile.viewer?.muted == true,
                blocking: profile.viewer?.blockedBy == true
            )
        }
    }

    /// Fetch the next page of posts for infinite scrolling
    func fetchNextPage() async throws {
        guard !isLoadingNextPage && hasNextPage else {
            return
        }

        Task { @MainActor in
            isLoadingNextPage = true
        }

        // Determine which accounts to fetch based on selection
        var accountsToFetch: [SocialAccount] = []

        if selectedAccountIds.contains("all") {
            accountsToFetch = accounts
        } else {
            accountsToFetch = accounts.filter { selectedAccountIds.contains($0.id) }
        }

        guard !accountsToFetch.isEmpty else {
            Task { @MainActor in
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

        Task { @MainActor in
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
                    Task { @MainActor in
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
        Task { @MainActor in
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

            Task { @MainActor in
                isLoading = false
            }

            return posts
        } catch {
            Task { @MainActor in
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
                // Use post.boostedBy if available, otherwise fall back to post.authorUsername
                let boostedByHandle = post.boostedBy ?? post.authorUsername
                let entry = TimelineEntry(
                    id: "boost-\(post.authorUsername)-\(original.id)",
                    kind: .boost(boostedBy: boostedByHandle),
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
    func replyToPost(
        _ post: Post,
        content: String,
        mediaAttachments: [Data] = [],
        mediaAltTexts: [String] = [],
        pollOptions: [String] = [],
        pollExpiresIn: Int? = nil,
        visibility: String = "public",
        accountOverride: SocialAccount? = nil
    ) async throws -> Post {
        switch post.platform {
        case .mastodon:
            guard let account = accountOverride ?? mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            do {
                return try await mastodonService.replyToPost(
                    post,
                    content: content,
                    mediaAttachments: mediaAttachments,
                    mediaAltTexts: mediaAltTexts,
                    pollOptions: pollOptions,
                    pollExpiresIn: pollExpiresIn,
                    visibility: visibility,
                    account: account
                )
            } catch {
                // ... (rest of error handling)
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
            guard let account = accountOverride ?? blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            return try await blueskyService.replyToPost(
                post,
                content: content,
                mediaAttachments: mediaAttachments,
                mediaAltTexts: mediaAltTexts,
                account: account
            )
        }
    }

    /// Retry wrapper for network operations
    private func withRetry<T>(
        maxAttempts: Int = 2,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
                }
            }
        }

        throw lastError ?? ServiceError.unknown("Retry failed")
    }

    private func sendLike(_ post: Post) async throws -> Post {
        actionLogger.debug("sendLike invoked for \(post.stableId, privacy: .public)")

        switch post.platform {
        case .mastodon:
            actionLogger.debug("Processing Mastodon like request")
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }

            do {
                let result = try await mastodonService.likePost(post, account: account)
                return result
            } catch {
                if error.localizedDescription.contains("noRefreshToken")
                    || error.localizedDescription.contains("Token expired")
                    || error.localizedDescription.contains("No refresh token available")
                {
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
            return try await blueskyService.likePost(post, account: account)
        }
    }

    private func sendUnlike(_ post: Post) async throws -> Post {
        actionLogger.debug("sendUnlike invoked for \(post.stableId, privacy: .public)")

        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }

            do {
                let result = try await mastodonService.unlikePost(post, account: account)
                return result
            } catch {
                if error.localizedDescription.contains("noRefreshToken")
                    || error.localizedDescription.contains("Token expired")
                    || error.localizedDescription.contains("No refresh token available")
                {
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
            return try await blueskyService.unlikePost(post, account: account)
        }
    }

    private func sendRepost(_ post: Post) async throws -> Post {
        actionLogger.debug("sendRepost invoked for \(post.stableId, privacy: .public)")

        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }

            do {
                let result = try await mastodonService.repostPost(post, account: account)
                return result
            } catch {
                if error.localizedDescription.contains("noRefreshToken")
                    || error.localizedDescription.contains("Token expired")
                    || error.localizedDescription.contains("No refresh token available")
                {
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

    private func sendUnrepost(_ post: Post) async throws -> Post {
        actionLogger.debug("sendUnrepost invoked for \(post.stableId, privacy: .public)")

        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }

            do {
                let result = try await mastodonService.unrepostPost(post, account: account)
                return result
            } catch {
                if error.localizedDescription.contains("noRefreshToken")
                    || error.localizedDescription.contains("Token expired")
                    || error.localizedDescription.contains("No refresh token available")
                {
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

    private func sendFetchActions(_ post: Post) async throws -> Post {
        actionLogger.debug("sendFetchActions invoked for \(post.stableId, privacy: .public)")

        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            if let refreshed = try await fetchMastodonStatus(
                id: post.platformSpecificId, account: account)
            {
                return refreshed
            }
            return post
        case .bluesky:
            if let refreshed = try await fetchBlueskyPostByID(post.platformSpecificId) {
                return refreshed
            }
            return post
        }
    }

    private func apply(_ state: PostActionState, to post: Post) {
        post.isLiked = state.isLiked
        post.isReposted = state.isReposted
        post.likeCount = state.likeCount
        post.repostCount = state.repostCount
        post.replyCount = state.replyCount
    }

    private func isTransientError(_ error: Error) -> Bool {
        if let networkError = error as? NetworkError {
            return networkError.isRetriable
        }

        if let serviceError = error as? ServiceError {
            switch serviceError {
            case .networkError, .timeout, .rateLimitError:
                return true
            default:
                break
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return nsError.code == NSURLErrorTimedOut
                || nsError.code == NSURLErrorCannotConnectToHost
                || nsError.code == NSURLErrorNetworkConnectionLost
                || nsError.code == NSURLErrorNotConnectedToInternet
        }

        return false
    }

    private func withExponentialBackoff<T>(
        operationName: String,
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 0.4,
        maxDelay: TimeInterval = 3.0,
        execute: @escaping () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var delay = initialDelay

        while attempt < maxAttempts {
            do {
                return try await execute()
            } catch {
                attempt += 1
                if !isTransientError(error) || attempt >= maxAttempts {
                    throw error
                }

                let jitter = Double.random(in: 0...(delay * 0.25))
                let waitTime = min(maxDelay, delay) + jitter

                actionLogger.warning(
                    "Retrying \(operationName, privacy: .public) in \(waitTime, privacy: .public)s (attempt \(attempt + 1) of \(maxAttempts))"
                )

                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                delay = min(maxDelay, delay * 2)
            }
        }

        throw ServiceError.unknown("Exceeded retry attempts for \(operationName)")
    }

    private func performBackoffAction(
        for post: Post,
        name: String,
        execute: @escaping () async throws -> Post
    ) async throws -> Post {
        try await withExponentialBackoff(operationName: name) {
            try await execute()
        }
    }

    private func performPostActionWithBackoff(
        for post: Post,
        name: String,
        execute: @escaping () async throws -> Post
    ) async throws -> (Post, PostActionState) {
        if !EdgeCaseHandler.shared.networkStatus.isConnected {
            // Queue for later if offline
            if let type = queuedActionType(from: name) {
                offlineQueueStore.queueAction(postId: post.id, platform: post.platform, type: type)
                scheduleOfflineActionNotification(type: type)

                // Return an optimistic update if possible
                var updatedPost = post
                applyOptimisticUpdate(to: &updatedPost, action: name)
                let state = PostActionState(post: updatedPost)
                apply(state, to: post)
                return (updatedPost, state)
            }
        }

        do {
            let updatedPost = try await performBackoffAction(
                for: post, name: name, execute: execute)
            let state = PostActionState(post: updatedPost)
            apply(state, to: post)
            return (updatedPost, state)
        } catch {
            if isTransientError(error), let type = queuedActionType(from: name) {
                // Queue for later if it's a network error
                offlineQueueStore.queueAction(postId: post.id, platform: post.platform, type: type)
                scheduleOfflineActionNotification(type: type)

                // Still return the error so the UI can show a "Queued for later" message
                throw ServiceError.networkError(underlying: error)
            }
            throw error
        }
    }

    private func queuedActionType(from name: String) -> QueuedActionType? {
        switch name {
        case "like": return .like
        case "unlike": return .unlike
        case "repost": return .repost
        case "unrepost": return .unrepost
        case "follow": return .follow
        case "unfollow": return .unfollow
        case "mute": return .mute
        case "unmute": return .unmute
        case "block": return .block
        case "unblock": return .unblock
        default: return nil
        }
    }

    private func scheduleOfflineActionNotification(type: QueuedActionType) {
        let content = UNMutableNotificationContent()
        content.title = "Action Queued"
        content.body = "Your \(type.rawValue) will be posted as soon as you're back online."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }

    private func applyOptimisticUpdate(to post: inout Post, action: String) {
        switch action {
        case "like":
            post.isLiked = true
            post.likeCount = (post.likeCount) + 1
        case "unlike":
            post.isLiked = false
            post.likeCount = max(0, (post.likeCount) - 1)
        case "repost":
            post.isReposted = true
            post.repostCount = (post.repostCount) + 1
        case "unrepost":
            post.isReposted = false
            post.repostCount = max(0, (post.repostCount) - 1)
        case "follow":
            post.isFollowingAuthor = true
        case "unfollow":
            post.isFollowingAuthor = false
        case "mute":
            post.isMutedAuthor = true
        case "unmute":
            post.isMutedAuthor = false
        case "block":
            post.isBlockedAuthor = true
        case "unblock":
            post.isBlockedAuthor = false
        default:
            break
        }
    }

    /// Like a post
    public func likePost(_ post: Post) async throws -> Post {
        if FeatureFlagManager.isEnabled(.postActionsV2) {
            let (updatedPost, _) = try await performPostActionWithBackoff(for: post, name: "like") {
                try await self.sendLike(post)
            }
            return updatedPost
        }

        return try await withRetry { [self] in
            try await self.sendLike(post)
        }
    }

    /// Unlike a post
    func unlikePost(_ post: Post) async throws -> Post {
        if FeatureFlagManager.isEnabled(.postActionsV2) {
            let (updatedPost, _) = try await performPostActionWithBackoff(for: post, name: "unlike")
            {
                try await self.sendUnlike(post)
            }
            return updatedPost
        }

        return try await withRetry { [self] in
            try await self.sendUnlike(post)
        }
    }

    /// Repost a post (Mastodon or Bluesky)
    public func repostPost(_ post: Post) async throws -> Post {
        if FeatureFlagManager.isEnabled(.postActionsV2) {
            let (updatedPost, _) = try await performPostActionWithBackoff(for: post, name: "repost")
            {
                try await self.sendRepost(post)
            }
            return updatedPost
        }

        return try await withRetry { [self] in
            try await self.sendRepost(post)
        }
    }

    /// Unrepost a post (Mastodon or Bluesky)
    func unrepostPost(_ post: Post) async throws -> Post {
        if FeatureFlagManager.isEnabled(.postActionsV2) {
            let (updatedPost, _) = try await performPostActionWithBackoff(
                for: post, name: "unrepost"
            ) {
                try await self.sendUnrepost(post)
            }
            return updatedPost
        }

        return try await withRetry { [self] in
            try await self.sendUnrepost(post)
        }
    }

    /// Follow a user
    public func followUser(_ post: Post) async throws {
        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            _ = try await mastodonService.followAccount(
                userId: post.authorUsername, account: account)
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            // For Bluesky, we ideally need the author's DID.
            // If authorProfilePictureURL or originalURL contains the DID, we might be able to extract it.
            // For now, let's assume authorUsername might be the DID or handle.
            _ = try await blueskyService.followUser(did: post.authorUsername, account: account)
        }
    }

    /// Unfollow a user
    public func unfollowUser(_ post: Post) async throws {
        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            _ = try await mastodonService.unfollowAccount(
                userId: post.authorUsername, account: account)
        case .bluesky:
            // Unfollow on Bluesky requires the follow record URI.
            // This is complex because we don't usually have it on the post object.
            // We might need to fetch the relationship first.
            throw ServiceError.apiError("Unfollow not yet fully implemented for Bluesky")
        }
    }

    /// Mute a user
    public func muteUser(_ post: Post) async throws {
        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            _ = try await mastodonService.muteAccount(userId: post.authorUsername, account: account)
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            try await blueskyService.muteActor(did: post.authorUsername, account: account)
        }
    }

    /// Block a user
    public func blockUser(_ post: Post) async throws {
        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            _ = try await mastodonService.blockAccount(
                userId: post.authorUsername, account: account)
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            _ = try await blueskyService.blockUser(did: post.authorUsername, account: account)
        }
    }

    /// Unmute a user
    public func unmuteUser(_ post: Post) async throws {
        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            _ = try await mastodonService.unmuteAccount(
                userId: post.authorUsername, account: account)
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            try await blueskyService.unmuteActor(did: post.authorUsername, account: account)
        }
    }

    /// Unblock a user
    public func unblockUser(_ post: Post) async throws {
        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            _ = try await mastodonService.unblockAccount(
                userId: post.authorUsername, account: account)
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            try await blueskyService.unblockUser(did: post.authorUsername, account: account)
        }
    }

    // MARK: - Generalized Relationship Management

    public func followUser(userId: String, platform: SocialPlatform) async throws {
        switch platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            _ = try await mastodonService.followAccount(userId: userId, account: account)
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            _ = try await blueskyService.followUser(did: userId, account: account)
        }
    }

    public func unfollowUser(userId: String, platform: SocialPlatform, followUri: String? = nil)
        async throws
    {
        switch platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            _ = try await mastodonService.unfollowAccount(userId: userId, account: account)
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            if let uri = followUri {
                try await blueskyService.unfollowUser(followUri: uri, account: account)
            } else {
                // If URI not provided, we might need to fetch the profile first to get the following URI
                let profile = try await blueskyService.getProfile(actor: userId, account: account)
                if let uri = profile.viewer?.following {
                    try await blueskyService.unfollowUser(followUri: uri, account: account)
                } else {
                    throw ServiceError.apiError("User is not being followed")
                }
            }
        }
    }

    public func muteUser(userId: String, platform: SocialPlatform) async throws {
        switch platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            _ = try await mastodonService.muteAccount(userId: userId, account: account)
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            try await blueskyService.muteActor(did: userId, account: account)
        }
    }

    public func unmuteUser(userId: String, platform: SocialPlatform) async throws {
        switch platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            _ = try await mastodonService.unmuteAccount(userId: userId, account: account)
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            try await blueskyService.unmuteActor(did: userId, account: account)
        }
    }

    public func blockUser(userId: String, platform: SocialPlatform) async throws {
        switch platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            _ = try await mastodonService.blockAccount(userId: userId, account: account)
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            _ = try await blueskyService.blockUser(did: userId, account: account)
        }
    }

    public func unblockUser(userId: String, platform: SocialPlatform) async throws {
        switch platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            _ = try await mastodonService.unblockAccount(userId: userId, account: account)
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            try await blueskyService.unblockUser(did: userId, account: account)
        }
    }

    /// Report a post
    public func reportPost(_ post: Post, reason: String? = nil) async throws {
        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            try await mastodonService.reportAccount(
                userId: post.authorUsername, statusIds: [post.platformSpecificId], comment: reason,
                account: account)
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            let subject: [String: Any] = [
                "$type": "com.atproto.repo.strongRef",
                "uri": post.platformSpecificId,
                "cid": post.cid ?? "",
            ]
            try await blueskyService.createReport(
                reasonType: "com.atproto.moderation.defs#reasonSpam", subject: subject,
                comment: reason, account: account)
        }
    }

    /// Update profile for an account
    public func updateProfile(
        account: SocialAccount, displayName: String?, bio: String?, avatarData: Data?
    ) async throws -> SocialAccount {
        switch account.platform {
        case .mastodon:
            return try await mastodonService.updateProfile(
                displayName: displayName, note: bio, avatarData: avatarData, account: account)
        case .bluesky:
            return try await blueskyService.updateProfile(
                displayName: displayName, description: bio, avatarData: avatarData, account: account
            )
        }
    }

    /// Fetch all lists for a Mastodon account
    public func fetchMastodonLists(account: SocialAccount) async throws -> [MastodonList] {
        guard account.platform == .mastodon else {
            throw ServiceError.unsupportedPlatform
        }
        return try await mastodonService.fetchLists(account: account)
    }

    /// Add an account to a Mastodon list
    public func addAccountToMastodonList(
        listId: String, accountToLink: String, account: SocialAccount
    ) async throws {
        guard account.platform == .mastodon else {
            throw ServiceError.unsupportedPlatform
        }
        try await mastodonService.addToList(
            listId: listId, accountId: accountToLink, account: account)
    }

    /// Vote in a poll
    public func voteInPoll(post: Post, optionIndex: Int) async throws {
        guard let poll = post.poll else { return }

        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            try await mastodonService.voteInPoll(
                pollId: poll.id, optionIndex: optionIndex, account: account)

        // Optimistically update the poll state if needed, or re-fetch the post
        // For now, we'll just let the UI handle the immediate state change
        // and assume the next refresh will bring the updated poll data.
        case .bluesky:
            // Bluesky doesn't support polls yet
            throw ServiceError.unsupportedPlatform
        }
    }

    /// Fetch direct messages for all accounts
    public func fetchDirectMessages() async throws -> [DMConversation] {
        var allConversations: [DMConversation] = []

        for account in accounts {
            do {
                switch account.platform {
                case .mastodon:
                    let mastodonConversations = try await mastodonService.fetchConversations(
                        account: account)
                    allConversations.append(contentsOf: mastodonConversations)
                case .bluesky:
                    let blueskyConvos = try await blueskyService.fetchConvos(for: account)
                    let mappedConvos = blueskyConvos.map { convo -> DMConversation in
                        // Get the other participant (not the account itself)
                        let otherParticipant =
                            convo.members.first { $0.did != account.platformSpecificId }
                            ?? convo.members.first!

                        let participant = NotificationAccount(
                            id: otherParticipant.did,
                            username: otherParticipant.handle,
                            displayName: otherParticipant.displayName,
                            avatarURL: otherParticipant.avatar
                        )

                        let currentUserAccount = NotificationAccount(
                            id: account.platformSpecificId,
                            username: account.username,
                            displayName: account.displayName,
                            avatarURL: account.profileImageURL?.absoluteString
                        )

                        let lastMsg = convo.lastMessage
                        let content: String
                        let createdAt: Date
                        let sender: NotificationAccount
                        let recipient: NotificationAccount

                        switch lastMsg {
                        case .message(let view):
                            content = view.text
                            // Parse ISO8601 date
                            createdAt =
                                ISO8601DateFormatter().date(from: view.sentAt) ?? Date()
                            if view.sender.did == account.platformSpecificId {
                                sender = currentUserAccount
                                recipient = participant
                            } else {
                                sender = participant
                                recipient = currentUserAccount
                            }
                        case .deleted(let view):
                            content = "(Deleted Message)"
                            createdAt =
                                ISO8601DateFormatter().date(from: view.sentAt) ?? Date()
                            if view.sender.did == account.platformSpecificId {
                                sender = currentUserAccount
                                recipient = participant
                            } else {
                                sender = participant
                                recipient = currentUserAccount
                            }
                        case .none:
                            content = "No messages"
                            createdAt = Date.distantPast
                            sender = participant
                            recipient = currentUserAccount
                        }

                        let dm = DirectMessage(
                            id: convo.id,
                            sender: sender,
                            recipient: recipient,
                            content: content,
                            createdAt: createdAt,
                            platform: .bluesky
                        )

                        return DMConversation(
                            id: convo.id,
                            participant: participant,
                            lastMessage: dm,
                            unreadCount: convo.unreadCount,
                            platform: .bluesky
                        )
                    }
                    allConversations.append(contentsOf: mappedConvos)
                }
            } catch {
                print("⚠️ Failed to fetch DMs for \(account.username): \(error)")
            }
        }

        return allConversations.sorted { $0.lastMessage.createdAt > $1.lastMessage.createdAt }
    }

    /// Fetch all messages in a conversation
    public func fetchConversationMessages(conversation: DMConversation) async throws
        -> [UnifiedChatMessage]
    {
        // Find the account for this conversation
        guard
            let account = accounts.first(where: { acc in
                if conversation.platform == .mastodon {
                    // For Mastodon, we might need to find which account owns this conversation
                    // Since conversation ID is platform-specific, we check if this account has it
                    return acc.platform == .mastodon
                } else {
                    return acc.platform == .bluesky
                        && acc.platformSpecificId != conversation.participant.id
                }
            })
        else {
            // Fallback to first account of same platform
            guard
                let fallbackAccount = accounts.first(where: { $0.platform == conversation.platform }
                )
            else {
                throw ServiceError.invalidAccount(reason: "No account found for this conversation")
            }
            return try await _fetchMessages(for: conversation, account: fallbackAccount)
        }

        return try await _fetchMessages(for: conversation, account: account)
    }

    private func _fetchMessages(for conversation: DMConversation, account: SocialAccount)
        async throws -> [UnifiedChatMessage]
    {
        switch conversation.platform {
        case .mastodon:
            // Use status context to get the thread
            let context = try await mastodonService.fetchStatusContext(
                statusId: conversation.lastMessage.id, account: account)
            var messages = context.ancestors
            if let mainPost = context.mainPost {
                messages.append(mainPost)
            }
            messages.append(contentsOf: context.descendants)

            // Map to UnifiedChatMessage
            return messages.map { UnifiedChatMessage.mastodon($0) }

        case .bluesky:
            let messages = try await blueskyService.fetchMessages(
                convoId: conversation.id, for: account)
            return messages.map { UnifiedChatMessage.bluesky($0) }
        }
    }

    public func sendChatMessage(conversation: DMConversation, text: String) async throws
        -> UnifiedChatMessage
    {
        // Find account
        guard let account = accounts.first(where: { $0.platform == conversation.platform }) else {
            throw ServiceError.invalidAccount(reason: "No account found")
        }

        switch conversation.platform {
        case .mastodon:
            // For Mastodon, sending a DM is posting a status with direct visibility
            // and mentioning the user.
            let content = "@\(conversation.participant.username) \(text)"
            // Attempt to reply in-thread to the last message for continuity; fallback to direct post
            do {
                let targetPost = try await fetchPost(
                    id: conversation.lastMessage.id, platform: .mastodon)
                let status = try await mastodonService.replyToPost(
                    targetPost,
                    content: content,
                    mediaAttachments: [],
                    mediaAltTexts: [],
                    pollOptions: [],
                    pollExpiresIn: nil,
                    visibility: "direct",
                    account: account
                )
                return .mastodon(status)
            } catch {
                let status = try await mastodonService.createPost(
                    content: content,
                    mediaAttachments: [],
                    mediaAltTexts: [],
                    pollOptions: [],
                    pollExpiresIn: nil,
                    visibility: "direct",
                    account: account
                )
                return .mastodon(status)
            }

        case .bluesky:
            let sentMessage = try await blueskyService.sendMessage(
                convoId: conversation.id, text: text, for: account)
            return .bluesky(.message(sentMessage))
        }
    }

    // MARK: - Offline Queue Management

    private func setupNetworkMonitoring() {
        EdgeCaseHandler.shared.$networkStatus
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status.isConnected {
                    Task {
                        await self?.processOfflineQueue()
                    }
                }
            }
            .store(in: &cancellables)
    }

    public func fetchPost(id: String, platform: SocialPlatform) async throws -> Post {
        switch platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            guard let post = try await mastodonService.fetchPostByID(id, account: account) else {
                throw ServiceError.apiError("Post not found")
            }
            return post
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            guard let post = try await blueskyService.fetchPostByID(id, account: account) else {
                throw ServiceError.apiError("Post not found")
            }
            return post
        }
    }

    public func processOfflineQueue() async {
        let actions = offlineQueueStore.queuedActions
        guard !actions.isEmpty else { return }

        print("🌐 [SocialServiceManager] Processing \(actions.count) offline actions...")

        for action in actions {
            do {
                // Fetch the post first to ensure we have current state
                let post = try await fetchPost(id: action.postId, platform: action.platform)

                switch action.type {
                case .like:
                    _ = try await likePost(post)
                case .unlike:
                    _ = try await unlikePost(post)
                case .repost:
                    _ = try await repostPost(post)
                case .unrepost:
                    _ = try await unrepostPost(post)
                case .follow:
                    _ = try await follow(post: post, shouldFollow: true)
                case .unfollow:
                    _ = try await follow(post: post, shouldFollow: false)
                case .mute:
                    _ = try await mute(post: post, shouldMute: true)
                case .unmute:
                    _ = try await mute(post: post, shouldMute: false)
                case .block:
                    _ = try await block(post: post, shouldBlock: true)
                case .unblock:
                    _ = try await block(post: post, shouldBlock: false)
                }

                // Remove from queue on success
                offlineQueueStore.removeAction(action)
                print(
                    "✅ [SocialServiceManager] Successfully processed offline \(action.type) for post \(action.postId)"
                )
            } catch {
                print(
                    "❌ [SocialServiceManager] Failed to process offline action: \(error.localizedDescription)"
                )
                // Keep in queue for next retry if it's still a transient error
                if !isTransientError(error) {
                    offlineQueueStore.removeAction(action)
                }
            }
        }
    }

    public func like(post: Post) async throws -> PostActionState {
        let (_, state) = try await performPostActionWithBackoff(for: post, name: "like") {
            try await self.sendLike(post)
        }
        return state
    }

    public func unlike(post: Post) async throws -> PostActionState {
        let (_, state) = try await performPostActionWithBackoff(for: post, name: "unlike") {
            try await self.sendUnlike(post)
        }
        return state
    }

    public func repost(post: Post) async throws -> PostActionState {
        let (_, state) = try await performPostActionWithBackoff(for: post, name: "repost") {
            try await self.sendRepost(post)
        }
        return state
    }

    public func unrepost(post: Post) async throws -> PostActionState {
        let (_, state) = try await performPostActionWithBackoff(for: post, name: "unrepost") {
            try await self.sendUnrepost(post)
        }
        return state
    }

    public func fetchActions(for post: Post) async throws -> PostActionState {
        let (_, state) = try await performPostActionWithBackoff(for: post, name: "fetch_actions") {
            try await self.sendFetchActions(post)
        }
        return state
    }

    public func follow(post: Post, shouldFollow: Bool) async throws -> PostActionState {
        let (_, state) = try await performPostActionWithBackoff(
            for: post, name: shouldFollow ? "follow" : "unfollow"
        ) {
            if shouldFollow {
                try await self.followUser(post)
            } else {
                try await self.unfollowUser(post)
            }
            post.isFollowingAuthor = shouldFollow
            return post
        }
        return state
    }

    public func mute(post: Post, shouldMute: Bool) async throws -> PostActionState {
        let (_, state) = try await performPostActionWithBackoff(
            for: post, name: shouldMute ? "mute" : "unmute"
        ) {
            if shouldMute {
                try await self.muteUser(post)
            } else {
                try await self.unmuteUser(post)
            }
            post.isMutedAuthor = shouldMute
            return post
        }
        return state
    }

    public func block(post: Post, shouldBlock: Bool) async throws -> PostActionState {
        let (_, state) = try await performPostActionWithBackoff(
            for: post, name: shouldBlock ? "block" : "unblock"
        ) {
            if shouldBlock {
                try await self.blockUser(post)
            } else {
                try await self.unblockUser(post)
            }
            post.isBlockedAuthor = shouldBlock
            return post
        }
        return state
    }

    // MARK: - Post Creation

    /// Create a new post on selected platforms
    /// - Parameters:
    ///   - content: The text content of the post
    ///   - platforms: Set of platforms to post to
    ///   - mediaAttachments: Optional media attachments as Data arrays
    ///   - pollOptions: Optional poll options
    ///   - pollExpiresIn: Optional poll expiration in seconds
    ///   - visibility: Post visibility (public, unlisted, followers_only)
    /// - Returns: Array of created posts (one per platform)
    func createPost(
        content: String,
        platforms: Set<SocialPlatform>,
        mediaAttachments: [Data] = [],
        mediaAltTexts: [String] = [],
        pollOptions: [String] = [],
        pollExpiresIn: Int? = nil,
        visibility: String = "public",
        accountOverrides: [SocialPlatform: SocialAccount] = [:]
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
                    mediaAltTexts: mediaAltTexts,
                    pollOptions: pollOptions,
                    pollExpiresIn: pollExpiresIn,
                    visibility: visibility,
                    accountOverride: accountOverrides[platform]
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
        mediaAltTexts: [String] = [],
        pollOptions: [String] = [],
        pollExpiresIn: Int? = nil,
        visibility: String = "public",
        accountOverride: SocialAccount? = nil
    ) async throws -> Post {
        switch platform {
        case .mastodon:
            guard let account = accountOverride ?? mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            return try await mastodonService.createPost(
                content: content,
                mediaAttachments: mediaAttachments,
                mediaAltTexts: mediaAltTexts,
                pollOptions: pollOptions,
                pollExpiresIn: pollExpiresIn,
                visibility: visibility,
                account: account
            )
        case .bluesky:
            guard let account = accountOverride ?? blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            // Bluesky doesn't support polls via the standard post API yet
            return try await blueskyService.createPost(
                content: content,
                mediaAttachments: mediaAttachments,
                mediaAltTexts: mediaAltTexts,
                account: account
            )
        }
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
            mainPost: context.mainPost,
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

    /// Fetch a single parent post and its ancestors recursively
    private func fetchSingleParentPost(parentId: String, platform: SocialPlatform, depth: Int = 0)
        async
    {
        // Limit depth to avoid infinite loops and API abuse
        guard depth < 5 else { return }

        let cacheKey = "\(platform.rawValue):\(parentId)"

        // Check cache before fetching to avoid redundant requests
        if PostParentCache.shared.getCachedPost(id: cacheKey) != nil {
            return
        }

        print(
            "🔄 SocialServiceManager: Starting fetch for parent \(parentId) on \(platform) (depth \(depth))"
        )

        // Mark as in progress
        Task { @MainActor in
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
                Task { @MainActor in
                    PostParentCache.shared.cache[cacheKey] = parentPost
                }
                print("✅ SocialServiceManager: Cached parent post \(parentId) for \(platform)")

                // Proactively fetch its parent if it's also a reply
                if let grandParentId = parentPost.inReplyToID {
                    await fetchSingleParentPost(
                        parentId: grandParentId, platform: platform, depth: depth + 1)
                }
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

// MARK: - PostActionNetworking Conformance

extension SocialServiceManager: PostActionNetworking {}

public enum QueuedActionType: String, Codable {
    case like
    case unlike
    case repost
    case unrepost
    case follow
    case unfollow
    case mute
    case unmute
    case block
    case unblock
}

public struct QueuedAction: Identifiable, Codable {
    public let id: UUID
    public let postId: String
    public let platform: SocialPlatform
    public let type: QueuedActionType
    public let createdAt: Date

    public init(
        id: UUID = UUID(), postId: String, platform: SocialPlatform, type: QueuedActionType,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.postId = postId
        self.platform = platform
        self.type = type
        self.createdAt = createdAt
    }
}

@MainActor
public class OfflineQueueStore: ObservableObject {
    @Published public var queuedActions: [QueuedAction] = []

    private let saveKey = "socialfusion_offline_queue"

    public init() {
        loadQueue()
    }

    public func queueAction(postId: String, platform: SocialPlatform, type: QueuedActionType) {
        let action = QueuedAction(postId: postId, platform: platform, type: type)
        queuedActions.append(action)
        persist()
    }

    public func removeAction(_ action: QueuedAction) {
        queuedActions.removeAll { $0.id == action.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(queuedActions) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    private func loadQueue() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
            let decoded = try? JSONDecoder().decode([QueuedAction].self, from: data)
        {
            queuedActions = decoded
        }
    }
}

/// Thread-safe manager for persisting app state to disk
actor PersistenceManager {
    static let shared = PersistenceManager()

    private let logger = Logger(subsystem: "com.socialfusion", category: "Persistence")
    private let fileManager = FileManager.default

    private let timelineCacheURL: URL
    private let accountsCacheURL: URL

    private init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.timelineCacheURL = documents.appendingPathComponent("timeline_cache.json")
        self.accountsCacheURL = documents.appendingPathComponent("accounts_cache.json")
    }

    // MARK: - Timeline Persistence

    func saveTimeline(_ posts: [Post]) {
        guard !posts.isEmpty else { return }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(posts)
            try data.write(to: timelineCacheURL, options: [.atomic, .completeFileProtection])
            logger.debug("Successfully saved \(posts.count) posts to disk cache")
        } catch {
            logger.error("Failed to save timeline to disk: \(error.localizedDescription)")
        }
    }

    func loadTimeline() -> [Post]? {
        guard fileManager.fileExists(atPath: timelineCacheURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: timelineCacheURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let posts = try decoder.decode([Post].self, from: data)
            logger.debug("Successfully loaded \(posts.count) posts from disk cache")
            return posts
        } catch {
            logger.error("Failed to load timeline from disk: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Accounts Persistence

    func saveAccounts(_ accounts: [SocialAccount]) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(accounts)
            try data.write(to: accountsCacheURL, options: [.atomic, .completeFileProtection])
            logger.debug("Successfully saved \(accounts.count) accounts to disk cache")
        } catch {
            logger.error("Failed to save accounts to disk: \(error.localizedDescription)")
        }
    }

    func loadAccounts() -> [SocialAccount]? {
        guard fileManager.fileExists(atPath: accountsCacheURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: accountsCacheURL)
            let decoder = JSONDecoder()
            let accounts = try decoder.decode([SocialAccount].self, from: data)
            logger.debug("Successfully loaded \(accounts.count) accounts from disk cache")
            return accounts
        } catch {
            logger.error("Failed to load accounts from disk: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Cleanup

    func clearAll() {
        try? fileManager.removeItem(at: timelineCacheURL)
        try? fileManager.removeItem(at: accountsCacheURL)
        logger.info("Cleared all persisted data")
    }
}

import AuthenticationServices  // For authentication-related functionality
import Combine
import Foundation
import SwiftUI
import UIKit
import os
import os.log
import os.signpost

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

    // MARK: - Backward Compatibility Shim
    // selectedAccountIds is derived from currentTimelineFeedSelection for views
    // that still reference it. Will be removed once all views are migrated.
    var selectedAccountIds: Set<String> {
        get {
            switch currentTimelineFeedSelection {
            case .unified, .allMastodon, .allBluesky:
                return ["all"]
            case .mastodon(let accountId, _), .bluesky(let accountId, _):
                return [accountId]
            }
        }
        set {
            if newValue.contains("all") || newValue.isEmpty {
                currentTimelineFeedSelection = .unified
            } else if let id = newValue.first, let account = accounts.first(where: { $0.id == id }) {
                switch account.platform {
                case .mastodon:
                    currentTimelineFeedSelection = .mastodon(accountId: id, feed: .home)
                case .bluesky:
                    currentTimelineFeedSelection = .bluesky(accountId: id, feed: .following)
                }
            }
        }
    }

    // Timeline selection state (scope derived from feed selection)
    var currentTimelineScope: TimelineScope {
        switch currentTimelineFeedSelection {
        case .unified, .allMastodon, .allBluesky:
            return .allAccounts
        case .mastodon(let accountId, _):
            return .account(id: accountId)
        case .bluesky(let accountId, _):
            return .account(id: accountId)
        }
    }
    @Published private(set) var currentTimelineFeedSelection: TimelineFeedSelection = .unified
    private let timelineFeedSelectionKeyV2 = "timelineFeedSelectionV2"
    private var currentTimelinePlan: TimelineFetchPlan?

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
    @Published var isComposing: Bool = false
    private var lastTimelineUpdate: Date = Date.distantPast
    private var shouldMergeOnRefresh: Bool = false  // Track if current refresh should merge (pull-to-refresh at top)
    private var shouldReplaceTimelineOnNextRefresh: Bool = false  // Force replace on feed switch

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

    struct PaginationOutcome: Equatable {
        let hasNextPage: Bool
        let shouldEmitError: Bool
        let shouldThrow: Bool
    }

    private struct PaginationFailureSummaryError: LocalizedError {
        let failedAccounts: [String]

        var errorDescription: String? {
            guard !failedAccounts.isEmpty else { return "Failed to load more posts." }
            let list = failedAccounts.joined(separator: ", ")
            return "Some accounts failed to load more posts: \(list)"
        }
    }

    nonisolated static func _test_resolvePaginationOutcome(
        hadSuccessfulFetch: Bool,
        hasMorePagesFromSuccess: Bool,
        failureCount: Int
    ) -> PaginationOutcome {
        if hadSuccessfulFetch {
            return PaginationOutcome(
                hasNextPage: hasMorePagesFromSuccess || failureCount > 0,
                shouldEmitError: failureCount > 0,
                shouldThrow: false
            )
        }

        if failureCount > 0 {
            return PaginationOutcome(
                hasNextPage: true,
                shouldEmitError: true,
                shouldThrow: true
            )
        }

        return PaginationOutcome(
            hasNextPage: hasMorePagesFromSuccess,
            shouldEmitError: false,
            shouldThrow: false
        )
    }

    nonisolated static func _test_shouldCommitRefreshGeneration(active: UInt64, candidate: UInt64)
        -> Bool
    {
        return candidate == active
    }

    // Disk Caching
    private let timelineCacheURL: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
        return documents.appendingPathComponent("timeline_cache.json")
    }()
    private var hasHydratedUnifiedTimelineCache = false
    private var hasPresentedUnifiedTimeline = false

    // Services for each platform
    nonisolated internal let mastodonService: MastodonService
    nonisolated internal let blueskyService: BlueskyService
    private let actionLogger = Logger(subsystem: "com.socialfusion", category: "PostActions")
    private let refreshLogger = Logger(subsystem: "com.socialfusion", category: "TimelineRefresh")
    private let refreshSignpostLog = OSLog(
        subsystem: "com.socialfusion",
        category: .pointsOfInterest
    )
    private let networkSignpostLog = OSLog(
        subsystem: "com.socialfusion",
        category: "NetworkRefresh"
    )

    // Post action V2 infrastructure - accessible within module
    internal lazy var postActionStore = PostActionStore()
    internal lazy var postActionCoordinator = PostActionCoordinator(
        store: postActionStore, service: self)
    private let canonicalPostStore = CanonicalPostStore()
    private let canonicalUnifiedTimelineID = CanonicalPostStore.unifiedTimelineID
    typealias RefreshGeneration = UInt64
    private var refreshGeneration: RefreshGeneration = 0
    private let followGraphCache = FollowGraphCache(defaultTTL: 300)
    private let timelineCacheWriter = TimelineCacheWriter.shared
    
    // Relationship management
    public let relationshipStore = RelationshipStore()
    private lazy var mastodonGraphService = MastodonGraphService(mastodonService: mastodonService)
    private lazy var blueskyGraphService = BlueskyGraphService(blueskyService: blueskyService)
    
    // Timeline context provider for autocomplete (shared instance)
    public lazy var timelineContextProvider: UnifiedTimelineContextProvider = UnifiedTimelineContextProvider()
    
    /// Get the appropriate graph service for a platform
    public func graphService(for platform: SocialPlatform) -> SocialGraphService {
        switch platform {
        case .mastodon:
            return mastodonGraphService
        case .bluesky:
            return blueskyGraphService
        }
    }

    // Edge case handling - temporarily disabled
    // private let edgeCase = EdgeCaseHandler.shared

    // Cache for Mastodon parent posts to avoid redundant fetches
    private var mastodonPostCache: [String: (post: Post, timestamp: Date)] = [:]
    // Cache for Bluesky parent posts to avoid redundant fetches
    private var blueskyPostCache: [String: Post] = [:]
    // Track in-progress parent fetches to avoid redundant network calls
    private var parentFetchInProgress: Set<String> = []
    private var mastodonAcctIdCache: [String: String] = [:]

    // Automatic token refresh service
    public var automaticTokenRefreshService: AutomaticTokenRefreshService?

    // Reply filtering with strict reply target resolution
    private lazy var postFeedFilter: PostFeedFilter = {
        let manager = self
        let replyTargetResolver = UnifiedReplyTargetResolver(
            mastodonService: mastodonService,
            blueskyService: blueskyService,
            accountProvider: { [weak manager] in
                guard let manager = manager else { return [] }
                return await MainActor.run { manager.accounts }
            }
        )
        let filter = PostFeedFilter(replyTargetResolver: replyTargetResolver)
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
        DebugLog.verbose("🔧 SocialServiceManager: Starting initialization...")

        // Load saved accounts first
        loadAccounts()

        // Initialize automatic token refresh service after main initialization
        self.automaticTokenRefreshService = AutomaticTokenRefreshService(socialServiceManager: self)

        // Setup network monitoring for offline queue
        setupNetworkMonitoring()

        // Load cached timeline from disk
        loadTimelineFromDisk()

        DebugLog.verbose("🔧 SocialServiceManager: After loadAccounts() - accounts.count = \(accounts.count)")
        DebugLog.verbose("🔧 SocialServiceManager: Mastodon accounts: \(mastodonAccounts.count)")
        DebugLog.verbose("🔧 SocialServiceManager: Bluesky accounts: \(blueskyAccounts.count)")

        // Restore persisted feed selection and validate it
        if !accounts.isEmpty {
            loadTimelineFeedSelection()
            updateTimelineSelectionFromScope()
            DebugLog.verbose(
                "🔧 SocialServiceManager: Restored feed selection: \(currentTimelineFeedSelection) with \(accounts.count) accounts"
            )
        }

        DebugLog.verbose("🔧 SocialServiceManager: Initialization completed")
        DebugLog.verbose("🔧 SocialServiceManager: Final feed selection = \(currentTimelineFeedSelection)")
        DebugLog.verbose("🔧 SocialServiceManager: Final accounts count = \(accounts.count)")

        // Set up PostNormalizerImpl with service manager reference
        PostNormalizerImpl.shared.setServiceManager(self)
        DebugLog.verbose("🔧 SocialServiceManager: Final unifiedTimeline count = \(unifiedTimeline.count)")

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
        DebugLog.verbose("💾 [SocialServiceManager] Saved accounts after profile image update")
    }

    // MARK: - Timeline Selection

    func updateTimelineSelectionFromScope() {
        let previous = currentTimelineFeedSelection
        switch currentTimelineFeedSelection {
        case .unified, .allMastodon, .allBluesky:
            break
        case .mastodon(let accountId, _):
            if !accounts.contains(where: { $0.id == accountId }) {
                currentTimelineFeedSelection = .unified
            }
        case .bluesky(let accountId, _):
            if !accounts.contains(where: { $0.id == accountId }) {
                currentTimelineFeedSelection = .unified
            }
        }
        if previous != currentTimelineFeedSelection {
            resetPagination()
        }
    }

    func setTimelineFeedSelection(_ selection: TimelineFeedSelection) {
        let changed = currentTimelineFeedSelection != selection
        currentTimelineFeedSelection = selection
        persistTimelineFeedSelection()
        resetPagination()
        if changed {
            shouldReplaceTimelineOnNextRefresh = true
        }
    }

    func resolveTimelineFetchPlan() -> TimelineFetchPlan? {
        let selection = currentTimelineFeedSelection
        switch selection {
        case .unified:
            return .unified(accounts: accounts)
        case .allMastodon:
            let mastodon = accounts.filter { $0.platform == .mastodon }
            return mastodon.isEmpty ? nil : .allMastodon(accounts: mastodon)
        case .allBluesky:
            let bluesky = accounts.filter { $0.platform == .bluesky }
            return bluesky.isEmpty ? nil : .allBluesky(accounts: bluesky)
        case .mastodon(let accountId, let feed):
            guard let account = accounts.first(where: { $0.id == accountId }) else { return nil }
            return .mastodon(account: account, feed: feed)
        case .bluesky(let accountId, let feed):
            guard let account = accounts.first(where: { $0.id == accountId }) else { return nil }
            return .bluesky(account: account, feed: feed)
        }
    }

    private func persistTimelineFeedSelection() {
        if let data = try? JSONEncoder().encode(currentTimelineFeedSelection) {
            UserDefaults.standard.set(data, forKey: timelineFeedSelectionKeyV2)
        }
    }

    private func loadTimelineFeedSelection() {
        if let data = UserDefaults.standard.data(forKey: timelineFeedSelectionKeyV2),
           let selection = try? JSONDecoder().decode(TimelineFeedSelection.self, from: data) {
            currentTimelineFeedSelection = selection
        }
    }

    // MARK: - Account Management

    /// Load saved accounts
    private func loadAccounts() {
        let logger = Logger(subsystem: "com.socialfusion", category: "AccountPersistence")
        logger.info("Loading saved accounts")
        DebugLog.verbose("🔧 SocialServiceManager: loadAccounts() called")

        Task {
            // Try to load from new PersistenceManager first
            var loadedAccounts = await PersistenceManager.shared.loadAccounts()

            // Fallback to legacy UserDefaults if not found
            if loadedAccounts == nil {
                if let data = UserDefaults.standard.data(forKey: "savedAccounts") {
                    do {
                        let decoder = JSONDecoder()
                        loadedAccounts = try decoder.decode([SocialAccount].self, from: data)
                        DebugLog.verbose("🔧 SocialServiceManager: Loaded accounts from legacy UserDefaults")
                    } catch {
                        ErrorHandler.shared.handleError(error)
                        DebugLog.verbose("🔧 SocialServiceManager: Failed to decode legacy accounts: \(error)")
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
                DebugLog.verbose("🔧 SocialServiceManager: loadAccounts() completed")
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
            await timelineCacheWriter.saveTimeline(timeline)
        }
    }

    /// Load the cached timeline from disk
    private func loadTimelineFromDisk() {
        Task {
            let policy = CacheHydrationPolicy()
            let canHydrate = await MainActor.run {
                policy.shouldHydrate(
                    hasHydrated: self.hasHydratedUnifiedTimelineCache,
                    hasPresented: self.hasPresentedUnifiedTimeline,
                    isTimelineEmpty: self.unifiedTimeline.isEmpty
                )
            }
            guard canHydrate else {
                DebugLog.verbose("🧊 SocialServiceManager: Skipping cache hydration (policy)")
                return
            }

            let cachedPosts: [Post]?
            if #available(iOS 17.0, *) {
                cachedPosts = await TimelineSwiftDataStore.shared.loadTimeline()
            } else {
                cachedPosts = await PersistenceManager.shared.loadTimeline()
            }

            if let posts = cachedPosts {
                await MainActor.run {
                    // Only update if current timeline is empty
                    if self.unifiedTimeline.isEmpty
                        && !self.hasPresentedUnifiedTimeline
                        && !self.hasHydratedUnifiedTimelineCache
                    {
                        let sourceContext = TimelineSourceContext(source: .system)
                        self.canonicalPostStore.replaceTimeline(
                            timelineID: self.canonicalUnifiedTimelineID,
                            posts: posts,
                            sourceContext: sourceContext
                        )
                        self.unifiedTimeline = self.canonicalPostStore.timelinePosts(
                            for: self.canonicalUnifiedTimelineID
                        )
                        self.hasHydratedUnifiedTimelineCache = true
                        DebugLog.verbose("✅ Successfully loaded \(posts.count) posts from offline cache")
                    }
                }
            }
        }
    }

    @MainActor
    func markUnifiedTimelinePresented() {
        if !hasPresentedUnifiedTimeline {
            hasPresentedUnifiedTimeline = true
        }
    }

    /// Update the platform-specific account lists
    private func updateAccountLists() {
        // Deduplicate accounts by ID to prevent duplicate API calls
        var seenIds = Set<String>()
        var deduplicatedAccounts: [SocialAccount] = []

        for account in accounts {
            if !seenIds.contains(account.id) {
                seenIds.insert(account.id)
                deduplicatedAccounts.append(account)
            } else {
                DebugLog.verbose(
                    "⚠️ SocialServiceManager: Found duplicate account with ID \(account.id) (\(account.username)), removing duplicate"
                )
            }
        }

        // Update accounts array if duplicates were found
        if deduplicatedAccounts.count != accounts.count {
            DebugLog.verbose(
                "🔧 SocialServiceManager: Removed \(accounts.count - deduplicatedAccounts.count) duplicate account(s)"
            )
            accounts = deduplicatedAccounts
            // Save the deduplicated accounts
            saveAccounts()
        }

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
        DebugLog.verbose("🔄 SocialServiceManager: Refreshing profile images for all accounts...")

        Task {
            for account in accounts {
                do {
                    switch account.platform {
                    case .mastodon:
                        await mastodonService.updateProfileImage(for: account)
                    case .bluesky:
                        try await blueskyService.updateProfileInfo(for: account)
                    }
                    DebugLog.verbose("✅ Refreshed profile for \(account.username) (\(account.platform))")
                } catch {
                    ErrorHandler.shared.handleError(error)
                    DebugLog.verbose("⚠️ Failed to refresh profile for \(account.username): \(error)")
                }

                // Small delay to avoid overwhelming the APIs
                try? await Task.sleep(nanoseconds: 250_000_000)  // 0.25 seconds
            }

            // Save updated accounts
            Task { @MainActor in
                saveAccounts()
                DebugLog.verbose("💾 Saved accounts after profile refresh")
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
        guard let plan = resolveTimelineFetchPlan() else { return [] }
        switch plan {
        case .unified(let accts), .allMastodon(let accts), .allBluesky(let accts):
            return accts
        case .mastodon(let account, _):
            return [account]
        case .bluesky(let account, _):
            return [account]
        }
    }

    /// Public wrapper for timeline account selection (used by auto-refresh buffering)
    @MainActor
    func timelineAccountsToFetch() -> [SocialAccount] {
        return getAccountsToFetch()
    }

    /// Force reload accounts for debugging
    @MainActor
    func forceReloadAccounts() async {
        DebugLog.verbose("🔄 SocialServiceManager: Force reloading accounts...")
        loadAccounts()
        DebugLog.verbose("🔄 SocialServiceManager: Force reload completed")
        DebugLog.verbose("🔄 Total accounts: \(accounts.count)")
        DebugLog.verbose("🔄 Mastodon accounts: \(mastodonAccounts.count)")
        DebugLog.verbose("🔄 Bluesky accounts: \(blueskyAccounts.count)")
        DebugLog.verbose("🔄 Current feed selection: \(currentTimelineFeedSelection)")

        // Also trigger a timeline refresh
        do {
            try await refreshTimeline(intent: .manualRefresh)
        } catch {
            ErrorHandler.shared.handleError(error) {
                Task {
                    try? await self.refreshTimeline(intent: .manualRefresh)
                }
            }
            DebugLog.verbose("🔄 Error refreshing timeline after force reload: \(error)")
        }
    }

    /// Add a new account
    func addAccount(_ account: SocialAccount) {

        accounts.append(account)
        scheduleFollowGraphCacheInvalidation(reason: "account_added")
        // Save to UserDefaults
        saveAccounts()

        // Update platform-specific lists
        updateAccountLists()

        // Keep current feed selection as-is (defaults to .unified)
        DebugLog.verbose(
            "📊 [SocialServiceManager] Account added, current feed selection: \(currentTimelineFeedSelection)"
        )

        // Automatically refresh timeline after adding account
        Task {
            do {
                try await refreshTimeline(intent: .manualRefresh)
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
        DebugLog.verbose("🗑️ Removing account: \(account.username) (\(account.platform))")

        // Remove from memory
        accounts.removeAll { $0.id == account.id }

        // If the removed account was the active selection, reset to unified
        switch currentTimelineFeedSelection {
        case .mastodon(let accountId, _), .bluesky(let accountId, _):
            if accountId == account.id {
                setTimelineFeedSelection(.unified)
            }
        default:
            break
        }

        // Clear tokens and credentials
        account.logout()

        // Save changes to disk
        saveAccounts()

        // Update platform-specific lists
        updateAccountLists()
        await invalidateFollowGraphCache(reason: "account_removed")

        // Reset timeline if no accounts left
        if accounts.isEmpty {
            resetUnifiedTimelineStore()
            await PersistenceManager.shared.clearAll()
        } else {
            resetUnifiedTimelineStore()
            // Trigger a refresh to remove posts from the deleted account
            try? await refreshTimeline(intent: .manualRefresh)
        }
    }

    /// Log out all accounts and clear all data
    @MainActor
    public func logout() async {
        DebugLog.verbose("🚪 Logging out all accounts...")

        // Logout each individual account (clears tokens)
        for account in accounts {
            account.logout()
        }

        // Clear all memory state
        accounts = []
        mastodonAccounts = []
        blueskyAccounts = []
        unifiedTimeline = []
        currentTimelineFeedSelection = .unified

        // Clear all persisted data
        await PersistenceManager.shared.clearAll()
        if #available(iOS 17.0, *) {
            await TimelineSwiftDataStore.shared.clearAll()
        }

        // Save empty state to persistence
        saveAccounts()
        await invalidateFollowGraphCache(reason: "logout")

        resetUnifiedTimelineStore()
        DebugLog.verbose("🚪 Logout complete")
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
                DebugLog.verbose("Failed to refresh profile for \(account.username): \(error)")
            }
        }
    }

    // MARK: - Timeline

    @MainActor
    private func resetUnifiedTimelineStore() {
        let sourceContext = TimelineSourceContext(source: .refresh)
        canonicalPostStore.replaceTimeline(
            timelineID: canonicalUnifiedTimelineID,
            posts: [],
            sourceContext: sourceContext
        )
        unifiedTimeline = []
    }

    /// Fetch posts for a specific account
    func fetchPostsForAccount(_ account: SocialAccount) async throws -> [Post] {
        DebugLog.verbose(
            "🔄 SocialServiceManager: fetchPostsForAccount called for \(account.username) (\(account.platform))"
        )
        let signpostID = OSSignpostID(log: networkSignpostLog)
        os_signpost(
            .begin,
            log: networkSignpostLog,
            name: "AccountFetch",
            signpostID: signpostID,
            "platform=%{public}s",
            account.platform.rawValue
        )

        if Task.isCancelled {
            os_signpost(
                .end,
                log: networkSignpostLog,
                name: "AccountFetch",
                signpostID: signpostID,
                "status=cancelled"
            )
            throw CancellationError()
        }

        do {
            let posts: [Post]
            switch account.platform {
            case .mastodon:
                DebugLog.verbose("🔄 SocialServiceManager: Fetching Mastodon timeline for \(account.username)")
                let result = try await mastodonService.fetchHomeTimeline(for: account)
                if Task.isCancelled { throw CancellationError() }
                posts = result.posts
                DebugLog.verbose("🔄 SocialServiceManager: Mastodon fetch completed - \(posts.count) posts")
            case .bluesky:
                DebugLog.verbose("🔄 SocialServiceManager: Fetching Bluesky timeline for \(account.username)")
                let result = try await blueskyService.fetchTimeline(for: account)
                if Task.isCancelled { throw CancellationError() }
                posts = result.posts
                DebugLog.verbose("🔄 SocialServiceManager: Bluesky fetch completed - \(posts.count) posts")
            }
            os_signpost(
                .end,
                log: networkSignpostLog,
                name: "AccountFetch",
                signpostID: signpostID,
                "status=success count=%{public}d",
                posts.count
            )
            return posts
        } catch {
            os_signpost(
                .end,
                log: networkSignpostLog,
                name: "AccountFetch",
                signpostID: signpostID,
                "status=error"
            )
            DebugLog.verbose(
                "❌ SocialServiceManager: fetchPostsForAccount failed for \(account.username): \(error.localizedDescription)"
            )
            throw error
        }
    }

    /// Refresh timeline with explicit intent
    func refreshTimeline(intent: TimelineRefreshIntent) async throws {
        assert(
            intent == .manualRefresh || intent == .mergeTap,
            "refreshTimeline must be called with explicit user intent"
        )
        let debugRefresh = UserDefaults.standard.bool(forKey: "debugRefresh")
        if debugRefresh {
            DebugLog.verbose(
                "🔄 SocialServiceManager: refreshTimeline(intent: \(intent.rawValue)) called - ENTRY POINT"
            )
            DebugLog.verbose("🔄 SocialServiceManager: globalRefreshLock: \(Self.globalRefreshLock)")
            DebugLog.verbose("🔄 SocialServiceManager: isCircuitBreakerOpen: \(isCircuitBreakerOpen)")
            DebugLog.verbose("🔄 SocialServiceManager: isRefreshInProgress: \(isRefreshInProgress)")
            DebugLog.verbose("🔄 SocialServiceManager: isLoadingTimeline: \(isLoadingTimeline)")
            DebugLog.verbose("🔄 SocialServiceManager: lastRefreshAttempt: \(lastRefreshAttempt)")
            DebugLog.verbose("🔄 SocialServiceManager: consecutiveFailures: \(consecutiveFailures)")
        } else {
            DebugLog.verbose(
                "🔄 SocialServiceManager: refreshTimeline(intent: \(intent.rawValue)) called"
            )
        }

        let now = Date()

        // Allow initial load to bypass restrictions if timeline is completely empty
        let isInitialLoad = unifiedTimeline.isEmpty && !isLoadingTimeline
        let isUserInitiated = true
        let shouldBypassRestrictions = isUserInitiated || isInitialLoad

        DebugLog.verbose(
            "🔄 SocialServiceManager: isInitialLoad = \(isInitialLoad), isUserInitiated = \(isUserInitiated), shouldBypassRestrictions = \(shouldBypassRestrictions)"
        )
        DebugLog.verbose(
            "🔄 SocialServiceManager: unifiedTimeline.count = \(unifiedTimeline.count), isLoadingTimeline = \(isLoadingTimeline)"
        )

        // IMPROVED GLOBAL LOCK: Only block automatic refreshes, allow user-initiated ones
        if Self.globalRefreshLock && !shouldBypassRestrictions {
            // Check if lock is stale (older than 10 seconds)
            if now.timeIntervalSince(Self.globalRefreshLockTime) > 10.0 {
                Self.globalRefreshLock = false
                DebugLog.verbose("🔓 SocialServiceManager: Stale refresh lock reset")
            } else {
                // Lock is active - BLOCK only automatic attempts, allow user-initiated
                DebugLog.verbose("🔒 SocialServiceManager: Refresh blocked by global lock (automatic refresh)")
                return
            }
        }

        // For user-initiated refreshes, cancel any existing refresh and proceed immediately
        if isUserInitiated && Self.globalRefreshLock {
            DebugLog.verbose("🔄 SocialServiceManager: User-initiated refresh - canceling existing refresh")
            Self.globalRefreshLock = false
        }

        // Set global lock immediately to block other attempts
        Self.globalRefreshLock = true
        Self.globalRefreshLockTime = now

        defer {
            Self.globalRefreshLock = false
            shouldMergeOnRefresh = false  // Reset after refresh completes
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
                DebugLog.verbose("🔄 SocialServiceManager: Circuit breaker reset - resuming requests")
            } else {
                // Circuit breaker is still open - block only automatic requests
                DebugLog.verbose(
                    "🚫 SocialServiceManager: Refresh blocked by circuit breaker (automatic refresh)"
                )
                return
            }
        }

        // For user-initiated refreshes, allow them even if circuit breaker is open
        // but reset the circuit breaker after successful user refresh
        if isUserInitiated && isCircuitBreakerOpen {
            DebugLog.verbose("🔄 SocialServiceManager: User-initiated refresh - bypassing circuit breaker")
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
            DebugLog.verbose(
                "🕐 SocialServiceManager: Refresh blocked by rate limiting (wait \(String(format: "%.1f", timeRemaining))s)"
            )
            return
        }

        // Additional check: if we're already loading or refreshing, abort (unless forced or initial)
        guard shouldBypassRestrictions || (!isLoadingTimeline && !isRefreshInProgress) else {
            DebugLog.verbose("🔄 SocialServiceManager: Refresh blocked - already in progress")
            return
        }

        if isInitialLoad {
            DebugLog.verbose("🚀 SocialServiceManager: Initial load detected - bypassing restrictions")
        }

        isRefreshInProgress = true
        lastRefreshAttempt = now

        defer { isRefreshInProgress = false }

        // For pull-to-refresh (manualRefresh), use merge mode for smooth experience
        shouldMergeOnRefresh = (intent == .manualRefresh)

        if intent == .manualRefresh {
            await invalidateFollowGraphCache(reason: "manual_refresh")
        }
        
        do {
            try await fetchTimeline(force: isUserInitiated)
            // Reset failure count on success
            consecutiveFailures = 0

            // If this was a user-initiated refresh that succeeded, reset circuit breaker
            if isUserInitiated && isCircuitBreakerOpen {
                isCircuitBreakerOpen = false
                circuitBreakerOpenTime = nil
                DebugLog.verbose("✅ SocialServiceManager: Circuit breaker reset after successful user refresh")
            }

            DebugLog.verbose("✅ SocialServiceManager: Timeline refresh completed successfully")
        } catch {
            consecutiveFailures += 1
            let errorMessage = "Timeline refresh failed: \(error.localizedDescription)"
            let appError = AppError(
                type: .general,
                message: errorMessage,
                isRetryable: false
            )
            ErrorHandler.shared.handleError(appError)
            DebugLog.verbose("❌ SocialServiceManager: \(errorMessage)")

            // For user-initiated refreshes, be more lenient with circuit breaker
            let failureThreshold =
                isUserInitiated ? maxConsecutiveFailures * 2 : maxConsecutiveFailures

            if consecutiveFailures >= failureThreshold {
                isCircuitBreakerOpen = true
                circuitBreakerOpenTime = now
                DebugLog.verbose(
                    "🚫 SocialServiceManager: Circuit breaker opened after \(consecutiveFailures) failures"
                )
            }

            // Provide more detailed error information for user-initiated refreshes
            if isUserInitiated {
                DebugLog.verbose(
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
    func refreshTimeline(
        accounts: [SocialAccount],
        shouldMerge: Bool = false,
        generation: RefreshGeneration? = nil
    ) async throws -> [Post] {
        DebugLog.verbose(
            "🔄 SocialServiceManager: refreshTimeline(accounts:) called with \(accounts.count) accounts, shouldMerge: \(shouldMerge)"
        )

        // Drastically reduce logging spam
        if accounts.isEmpty {
            DebugLog.verbose("🔄 SocialServiceManager: No accounts provided, returning empty array")
            return []
        }

        DebugLog.verbose("🔄 SocialServiceManager: Accounts to fetch from:")
        for account in accounts {
            DebugLog.verbose("🔄   - \(account.username) (\(account.platform)) - ID: \(account.id)")
        }

        let fetchSignpostID = OSSignpostID(log: refreshSignpostLog)
        os_signpost(
            .begin,
            log: refreshSignpostLog,
            name: "RefreshFetch",
            signpostID: fetchSignpostID,
            "accounts=%{public}d",
            accounts.count
        )
        var collectedPosts: [Post] = []
        await withTaskGroup(of: [Post].self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        DebugLog.verbose("🔄 SocialServiceManager: Starting fetch for \(account.username)")
                        let posts = try await self.fetchPostsForAccount(account)
                        DebugLog.verbose(
                            "🔄 SocialServiceManager: Fetched \(posts.count) posts for \(account.username)"
                        )
                        return posts
                    } catch {
                        if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                            DebugLog.verbose(
                                "🔄 SocialServiceManager: Fetch cancelled for \(account.username)"
                            )
                        } else {
                            DebugLog.verbose(
                                "❌ Error fetching \(account.username): \(error.localizedDescription)"
                            )
                        }
                        return []
                    }
                }
            }

            for await posts in group {
                collectedPosts.append(contentsOf: posts)
            }
        }
        os_signpost(
            .end,
            log: refreshSignpostLog,
            name: "RefreshFetch",
            signpostID: fetchSignpostID,
            "posts=%{public}d",
            collectedPosts.count
        )
        DebugLog.verbose("🔄 SocialServiceManager: Total posts collected: \(collectedPosts.count)")

        let followedAccounts = await getFollowedAccounts()
        let filteredPosts = await filterRepliesInTimeline(
            collectedPosts,
            followedAccounts: followedAccounts
        )
        if let generation, !shouldCommitRefresh(generation: generation, stage: "accounts_commit") {
            return canonicalPostStore.timelinePosts(for: canonicalUnifiedTimelineID)
        }

        let mergeSignpostID = OSSignpostID(log: refreshSignpostLog)
        os_signpost(
            .begin,
            log: refreshSignpostLog,
            name: "RefreshMerge",
            signpostID: mergeSignpostID,
            "incoming=%{public}d",
            filteredPosts.count
        )
        let sourceContext = TimelineSourceContext(source: .refresh)
        // When shouldMerge is true (pull-to-refresh at top), always use processIncomingPosts for smooth merging
        // Otherwise, use replaceTimeline when replyFiltering is enabled to ensure clean state
        if shouldMerge || !FeatureFlagManager.isEnabled(.replyFiltering) {
            canonicalPostStore.processIncomingPosts(
                filteredPosts,
                timelineID: canonicalUnifiedTimelineID,
                sourceContext: sourceContext
            )
        } else {
            canonicalPostStore.replaceTimeline(
                timelineID: canonicalUnifiedTimelineID,
                posts: filteredPosts,
                sourceContext: sourceContext
            )
        }
        let mergedTimeline = canonicalPostStore.timelinePosts(for: canonicalUnifiedTimelineID)
        os_signpost(
            .end,
            log: refreshSignpostLog,
            name: "RefreshMerge",
            signpostID: mergeSignpostID,
            "timeline_count=%{public}d",
            mergedTimeline.count
        )
        return mergedTimeline
    }

    /// Convert UserID to CanonicalUserID, detecting stable IDs (DIDs) vs handles
    private func canonicalID(from userID: UserID) -> CanonicalUserID {
        let normalizedHandle = CanonicalUserID.normalizeHandle(userID.value, platform: userID.platform)
        
        // Check if the value is a DID (Bluesky) or account ID (Mastodon)
        let stableID: String?
        if userID.value.hasPrefix("did:") {
            // Bluesky DID
            stableID = userID.value
        } else if userID.platform == .mastodon {
            // For Mastodon, we don't have account ID in UserID, so use nil
            // The handle will be used for matching
            stableID = nil
        } else {
            // Bluesky handle - no stable ID from UserID alone
            stableID = nil
        }
        
        return CanonicalUserID(platform: userID.platform, stableID: stableID, normalizedHandle: normalizedHandle)
    }

    private func followedAccountsCacheKey() -> String {
        let accountKey = accounts
            .map { "\($0.platform.rawValue):\($0.id):\($0.platformSpecificId)" }
            .sorted()
            .joined(separator: "|")
        return "followed:\(accountKey)"
    }

    private func invalidateFollowGraphCache(reason: String) async {
        await followGraphCache.invalidateAll()
        refreshLogger.debug("follow_graph_cache_invalidated reason=\(reason, privacy: .public)")
    }

    private func scheduleFollowGraphCacheInvalidation(reason: String) {
        Task {
            await invalidateFollowGraphCache(reason: reason)
        }
    }
    
    /// Get all followed accounts across all platforms as canonical IDs
    private func getFollowedAccounts() async -> Set<CanonicalUserID> {
        let cacheKey = followedAccountsCacheKey()
        if let cached = await followGraphCache.value(for: cacheKey) {
            refreshLogger.debug("follow_graph_cache_hit key=\(cacheKey, privacy: .public)")
            return cached
        }

        var followedAccounts = Set<CanonicalUserID>()

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
                        DebugLog.verbose(
                            "⚠️ Error fetching following for \(account.username): \(error.localizedDescription)"
                        )
                        return []
                    }
                }
            }

            for await accountFollows in group {
                // Convert UserIDs to CanonicalUserIDs
                for userID in accountFollows {
                    followedAccounts.insert(canonicalID(from: userID))
                }
            }
        }

        // Also add our own accounts as followed
        for account in accounts {
            switch account.platform {
            case .mastodon:
                let handle: String
                if account.username.contains("@") {
                    handle = account.username
                } else if let host = account.serverURL?.host, !host.isEmpty {
                    handle = "\(account.username)@\(host)"
                } else {
                    handle = account.username
                }
                let normalizedHandle = CanonicalUserID.normalizeHandle(handle, platform: .mastodon)
                // Use platformSpecificId as stable ID if available
                let stableID = account.platformSpecificId.isEmpty ? nil : account.platformSpecificId
                followedAccounts.insert(CanonicalUserID(platform: .mastodon, stableID: stableID, normalizedHandle: normalizedHandle))
            case .bluesky:
                let normalizedHandle = CanonicalUserID.normalizeHandle(account.username, platform: .bluesky)
                // Use platformSpecificId (DID) as stable ID
                let stableID = account.platformSpecificId.isEmpty ? nil : account.platformSpecificId
                followedAccounts.insert(CanonicalUserID(platform: .bluesky, stableID: stableID, normalizedHandle: normalizedHandle))
                // Also add handle as a separate entry if we have a DID
                if !account.platformSpecificId.isEmpty && account.platformSpecificId.hasPrefix("did:") {
                    followedAccounts.insert(CanonicalUserID(platform: .bluesky, stableID: account.platformSpecificId, normalizedHandle: normalizedHandle))
                }
            }
        }

        await followGraphCache.set(followedAccounts, for: cacheKey)
        refreshLogger.debug(
            "follow_graph_cache_store key=\(cacheKey, privacy: .public) count=\(followedAccounts.count, privacy: .public)"
        )
        return followedAccounts
    }

    /// Filter replies in the timeline based on following rules
    private func filterRepliesInTimeline(
        _ posts: [Post],
        followedAccounts cachedFollowedAccounts: Set<CanonicalUserID>? = nil
    ) async -> [Post] {
        let isEnabled = FeatureFlagManager.isEnabled(.replyFiltering)
        postFeedFilter.isReplyFilteringEnabled = isEnabled

        guard isEnabled else { return posts }

        DebugLog.verbose("🔍 SocialServiceManager: Starting reply filtering for \(posts.count) posts")
        let startTime = Date()
        let signpostID = OSSignpostID(log: refreshSignpostLog)
        os_signpost(
            .begin,
            log: refreshSignpostLog,
            name: "RefreshFilter",
            signpostID: signpostID,
            "count=%{public}d",
            posts.count
        )

        let followedAccounts: Set<CanonicalUserID>
        if let cachedFollowedAccounts {
            followedAccounts = cachedFollowedAccounts
        } else {
            followedAccounts = await getFollowedAccounts()
        }
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
        DebugLog.verbose(
            "✅ SocialServiceManager: Filtering complete. Filtered \(posts.count) -> \(filteredPosts.count) posts in \(String(format: "%.2f", duration))s"
        )
        os_signpost(
            .end,
            log: refreshSignpostLog,
            name: "RefreshFilter",
            signpostID: signpostID,
            "duration_ms=%{public}.2f",
            duration * 1000
        )

        return filteredPosts
    }

    /// Apply timeline filters (reply filtering, keyword filtering, etc.) to a candidate set of posts.
    public func filterPostsForTimeline(_ posts: [Post]) async -> [Post] {
        return await filterRepliesInTimeline(posts)
    }

    /// Fetch posts for the currently selected timeline, scoped to a specific platform.
    public func fetchPostsForTimeline(platform: SocialPlatform) async throws -> [Post] {
        guard let plan = resolveTimelineFetchPlan() else { return [] }

        switch plan {
        case .unified(let accounts), .allMastodon(let accounts), .allBluesky(let accounts):
            let accountsToFetch = accounts.filter { $0.platform == platform }
            guard !accountsToFetch.isEmpty else { return [] }
            var collected: [Post] = []
            await withTaskGroup(of: [Post].self) { group in
                for account in accountsToFetch {
                    group.addTask {
                        do {
                            return try await self.fetchPostsForAccount(account)
                        } catch {
                            return []
                        }
                    }
                }
                for await posts in group {
                    collected.append(contentsOf: posts)
                }
            }
            return collected.sorted { $0.createdAt > $1.createdAt }
        case .mastodon(let account, let feed):
            guard platform == .mastodon else { return [] }
            let result = try await fetchMastodonTimeline(account: account, feed: feed, maxId: nil)
            return result.posts
        case .bluesky(let account, let feed):
            guard platform == .bluesky else { return [] }
            let result = try await fetchBlueskyTimeline(account: account, feed: feed, cursor: nil)
            return result.posts
        }
    }

    /// Fetch the unified timeline for all accounts
    public func fetchTimeline(force: Bool = false) async throws {
        DebugLog.verbose("🔄 SocialServiceManager: fetchTimeline(force: \(force)) called")

        // Check if we're already loading or if too many rapid requests
        let now = Date()
        let isInitialLoad = unifiedTimeline.isEmpty && !isLoadingTimeline
        let shouldBypassRestrictions = force || isInitialLoad

        if !shouldBypassRestrictions && (isLoadingTimeline || isRefreshInProgress) {
            DebugLog.verbose("🔄 SocialServiceManager: Already loading or refreshing - aborting")
            return
        }

        // Prevent rapid successive refreshes (minimum 2 seconds between attempts)
        // But allow initial loads and forced refreshes to bypass this restriction
        guard now.timeIntervalSince(lastRefreshAttempt) > 2.0 || shouldBypassRestrictions else {
            DebugLog.verbose(
                "🔄 SocialServiceManager: Too soon since last attempt - aborting (isInitialLoad: \(isInitialLoad), force: \(force))"
            )
            return  // Silent return - avoid spam
        }

        lastRefreshAttempt = now
        isRefreshInProgress = true
        defer { isRefreshInProgress = false }

        guard let plan = resolveTimelineFetchPlan() else {
            DebugLog.verbose("🔄 SocialServiceManager: No timeline plan available")
            return
        }

        currentTimelinePlan = plan
        let generation = beginRefreshGeneration()
        let refreshSignpostID = OSSignpostID(log: refreshSignpostLog)
        os_signpost(
            .begin,
            log: refreshSignpostLog,
            name: "TimelineRefresh",
            signpostID: refreshSignpostID,
            "generation=%{public}llu",
            generation
        )
        updateLoadingState(true)

        do {
            let canonicalPosts = try await refreshTimeline(plan: plan, generation: generation)
            guard shouldCommitRefresh(generation: generation, stage: "ui_commit") else {
                os_signpost(
                    .end,
                    log: refreshSignpostLog,
                    name: "TimelineRefresh",
                    signpostID: refreshSignpostID,
                    "status=stale"
                )
                return
            }
            DebugLog.verbose("🔄 SocialServiceManager: Canonical timeline updated with \(canonicalPosts.count) posts")

            let uiCommitSignpostID = OSSignpostID(log: refreshSignpostLog)
            os_signpost(
                .begin,
                log: refreshSignpostLog,
                name: "RefreshUICommit",
                signpostID: uiCommitSignpostID,
                "count=%{public}d",
                canonicalPosts.count
            )
            safelyUpdateTimeline(canonicalPosts)
            os_signpost(
                .end,
                log: refreshSignpostLog,
                name: "RefreshUICommit",
                signpostID: uiCommitSignpostID
            )
            updateLoadingState(false)
            os_signpost(
                .end,
                log: refreshSignpostLog,
                name: "TimelineRefresh",
                signpostID: refreshSignpostID,
                "status=success count=%{public}d",
                canonicalPosts.count
            )
            DebugLog.verbose("🔄 SocialServiceManager: Timeline updated with \(canonicalPosts.count) posts")
        } catch {
            guard shouldCommitRefresh(generation: generation, stage: "error_commit") else {
                os_signpost(
                    .end,
                    log: refreshSignpostLog,
                    name: "TimelineRefresh",
                    signpostID: refreshSignpostID,
                    "status=stale_error"
                )
                return
            }
            ErrorHandler.shared.handleError(error)
            DebugLog.verbose("🔄 SocialServiceManager: fetchTimeline failed: \(error.localizedDescription)")
            updateLoadingState(false, error: error)
            os_signpost(
                .end,
                log: refreshSignpostLog,
                name: "TimelineRefresh",
                signpostID: refreshSignpostID,
                "status=error"
            )
            throw error
        }
    }

    private func refreshTimeline(plan: TimelineFetchPlan, generation: RefreshGeneration? = nil)
        async throws -> [Post]
    {
        switch plan {
        case .unified(let accounts):
            return try await refreshTimeline(
                accounts: accounts,
                shouldMerge: shouldMergeOnRefresh,
                generation: generation
            )
        case .allMastodon(let accounts):
            return try await refreshTimeline(
                accounts: accounts,
                shouldMerge: shouldMergeOnRefresh,
                generation: generation
            )
        case .allBluesky(let accounts):
            return try await refreshTimeline(
                accounts: accounts,
                shouldMerge: shouldMergeOnRefresh,
                generation: generation
            )
        case .mastodon(let account, let feed):
            let result = try await fetchMastodonTimeline(account: account, feed: feed, maxId: nil)
            updatePaginationTokens(
                for: account,
                selection: .mastodon(accountId: account.id, feed: feed),
                pagination: result.pagination
            )
            hasNextPage = result.pagination.hasNextPage
            return await applyTimelinePosts(
                result.posts,
                source: .refresh,
                shouldMerge: shouldMergeOnRefresh,
                generation: generation
            )
        case .bluesky(let account, let feed):
            let result = try await fetchBlueskyTimeline(account: account, feed: feed, cursor: nil)
            updatePaginationTokens(
                for: account,
                selection: .bluesky(accountId: account.id, feed: feed),
                pagination: result.pagination
            )
            hasNextPage = result.pagination.hasNextPage
            return await applyTimelinePosts(
                result.posts,
                source: .refresh,
                shouldMerge: shouldMergeOnRefresh,
                generation: generation
            )
        }
    }

    private func applyTimelinePosts(
        _ posts: [Post],
        source: TimelineSource,
        shouldMerge: Bool = false,
        generation: RefreshGeneration? = nil
    ) async -> [Post] {
        let filteredPosts = await filterRepliesInTimeline(posts)
        if let generation, !shouldCommitRefresh(generation: generation, stage: "apply_\(source)") {
            return canonicalPostStore.timelinePosts(for: canonicalUnifiedTimelineID)
        }
        // Feed switch: force replace to clear old feed's posts
        let forceReplace = shouldReplaceTimelineOnNextRefresh
        if forceReplace {
            shouldReplaceTimelineOnNextRefresh = false
        }

        let sourceContext = TimelineSourceContext(source: source)
        // When shouldMerge is true (pull-to-refresh at top), always use processIncomingPosts for smooth merging
        // Feed switch overrides merge to ensure clean slate
        // Otherwise, use replaceTimeline when replyFiltering is enabled to ensure clean state
        if !forceReplace && (shouldMerge || !FeatureFlagManager.isEnabled(.replyFiltering)) {
            canonicalPostStore.processIncomingPosts(
                filteredPosts,
                timelineID: canonicalUnifiedTimelineID,
                sourceContext: sourceContext
            )
        } else {
            canonicalPostStore.replaceTimeline(
                timelineID: canonicalUnifiedTimelineID,
                posts: filteredPosts,
                sourceContext: sourceContext
            )
        }
        return canonicalPostStore.timelinePosts(for: canonicalUnifiedTimelineID)
    }

    private func fetchMastodonTimeline(
        account: SocialAccount,
        feed: MastodonTimelineFeed,
        maxId: String?
    ) async throws -> TimelineResult {
        switch feed {
        case .home:
            return try await mastodonService.fetchHomeTimeline(for: account, maxId: maxId)
        case .local:
            return try await mastodonService.fetchPublicTimeline(
                for: account,
                local: true,
                maxId: maxId
            )
        case .federated:
            return try await mastodonService.fetchPublicTimeline(
                for: account,
                local: false,
                maxId: maxId
            )
        case .list(let id, _):
            return try await mastodonService.fetchListTimeline(
                for: account,
                listId: id,
                maxId: maxId
            )
        case .instance(let server):
            guard let url = URL(string: "https://\(server)") else {
                throw ServiceError.invalidInput(reason: "Invalid server URL")
            }
            return try await mastodonService.fetchPublicTimeline(
                serverURL: url,
                limit: 40,
                maxId: maxId,
                local: true
            )
        }
    }

    private func fetchBlueskyTimeline(
        account: SocialAccount,
        feed: BlueskyTimelineFeed,
        cursor: String?
    ) async throws -> TimelineResult {
        switch feed {
        case .following:
            return try await blueskyService.fetchHomeTimeline(for: account, cursor: cursor)
        case .custom(let uri, _):
            return try await blueskyService.fetchCustomFeed(
                for: account,
                feedURI: uri,
                cursor: cursor
            )
        }
    }

    private func updatePaginationTokens(
        for account: SocialAccount,
        selection: TimelineFeedSelection,
        pagination: PaginationInfo
    ) {
        let key = paginationTokenKey(for: account, selection: selection)
        if let token = pagination.nextPageToken {
            paginationTokens[key] = token
        } else {
            paginationTokens.removeValue(forKey: key)
        }
    }

    private func paginationTokenKey(for account: SocialAccount, selection: TimelineFeedSelection)
        -> String
    {
        switch selection {
        case .unified, .allMastodon, .allBluesky:
            return account.id
        case .mastodon(_, let feed):
            return "\(account.id):\(feed.cacheKey)"
        case .bluesky(_, let feed):
            return "\(account.id):\(feed.cacheKey)"
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
            DebugLog.verbose("Failed to fetch trending tags: \(error)")
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
                        DebugLog.verbose("Search failed for \(account.username): \(error)")
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
        var accountsToFetch = getAccountsToFetch()
        
        // If no accounts are selected, default to all accounts for notifications
        // This ensures notifications always work even if account selection isn't set up
        if accountsToFetch.isEmpty && !accounts.isEmpty {
            DebugLog.verbose("📬 SocialServiceManager: No accounts selected for notifications, using all accounts")
            accountsToFetch = accounts
        }
        
        // If still no accounts, return empty array
        guard !accountsToFetch.isEmpty else {
            DebugLog.verbose("📬 SocialServiceManager: No accounts available for notifications")
            return []
        }
        
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
                                // Extract emoji map from notification account
                                let emojiMap: [String: String]? = {
                                    guard let emojis = mNotif.account.emojis, !emojis.isEmpty else { return nil }
                                    var map: [String: String] = [:]
                                    for emoji in emojis {
                                        let url = emoji.staticUrl.isEmpty ? emoji.url : emoji.staticUrl
                                        if !url.isEmpty { map[emoji.shortcode] = url }
                                    }
                                    return map.isEmpty ? nil : map
                                }()

                                return AppNotification(
                                    id: mNotif.id,
                                    type: self.mapMastodonNotificationType(mNotif.type),
                                    createdAt: DateParser.parse(mNotif.createdAt) ?? Date(),
                                    account: account,
                                    fromAccount: NotificationAccount(
                                        id: mNotif.account.id,
                                        username: mNotif.account.acct,
                                        displayName: mNotif.account.displayName,
                                        avatarURL: mNotif.account.avatar,
                                        displayNameEmojiMap: emojiMap
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
                                    DebugLog.verbose(
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
                        // Check if this is a cancellation error - if so, don't log as error
                        let nsError = error as NSError
                        let isCancellation = nsError.domain == NSURLErrorDomain && 
                                            nsError.code == NSURLErrorCancelled
                        
                        if isCancellation {
                            DebugLog.verbose("⚠️ Notifications fetch cancelled for \(account.username)")
                        } else {
                            ErrorHandler.shared.handleError(error)
                            DebugLog.verbose("Failed to fetch notifications for \(account.username): \(error)")
                        }
                        // Return empty array - caller will handle preserving existing notifications
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
            // If userId is empty, try to fetch it from verify_credentials
            var userId = user.id
            if userId.isEmpty {
                DebugLog.verbose("⚠️ SocialServiceManager: userId is empty, fetching from verify_credentials")
                do {
                    let mastodonAccount = try await mastodonService.verifyCredentials(
                        account: account)
                    userId = mastodonAccount.id
                    // Update the account's platformSpecificId for future use
                    account.platformSpecificId = userId
                    DebugLog.verbose("✅ SocialServiceManager: Retrieved account ID: \(userId)")
                } catch {
                    DebugLog.verbose("❌ SocialServiceManager: Failed to fetch account ID: \(error)")
                    throw NSError(
                        domain: "SocialServiceManager",
                        code: 400,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Unable to determine account ID. Please re-authenticate your Mastodon account."
                        ])
                }
            }

            let posts = try await mastodonService.fetchUserTimeline(
                userId: userId, for: account, limit: limit, maxId: cursor)
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
                headerURL: mAccount.header ?? "",
                bio: mAccount.note ?? "",
                followersCount: mAccount.followersCount ?? 0,
                followingCount: mAccount.followingCount ?? 0,
                statusesCount: mAccount.statusesCount ?? 0,
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

    /// Fetch boosters for a post and normalize them into User models.
    public func fetchBoosters(for post: Post) async throws -> [User] {
        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }

            let statusId = post.platformSpecificId.isEmpty ? post.id : post.platformSpecificId
            let accounts = try await mastodonService.fetchRebloggedBy(
                statusId: statusId, account: account)
            let relationshipLookup = await mastodonRelationshipLookup(
                for: accounts.map { $0.id }, account: account)
            let instanceDomain = mastodonInstanceDomain(for: account)

            return accounts.map { acct in
                let username =
                    acct.acct.contains("@")
                    ? acct.acct : "\(acct.acct)@\(instanceDomain)"
                let relationship = relationshipLookup[acct.id]
                let isBlocked =
                    (relationship?.blocking ?? false) || (relationship?.blockedBy ?? false)

                // Extract display name emoji map
                let emojiMap: [String: String]? = {
                    guard let emojis = acct.emojis, !emojis.isEmpty else { return nil }
                    var map: [String: String] = [:]
                    for emoji in emojis {
                        let url = emoji.staticUrl.isEmpty ? emoji.url : emoji.staticUrl
                        if !url.isEmpty { map[emoji.shortcode] = url }
                    }
                    return map.isEmpty ? nil : map
                }()

                return User(
                    id: acct.id,
                    displayName: acct.displayName,
                    username: username,
                    avatarURL: URL(string: acct.avatar),
                    isFollowedByMe: relationship?.following ?? false,
                    followsMe: relationship?.followedBy ?? false,
                    isBlocked: isBlocked,
                    boostedAt: nil,
                    displayNameEmojiMap: emojiMap
                )
            }
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            let uri = blueskyPostURI(for: post)
            return try await blueskyService.fetchRepostedBy(uri: uri, account: account)
        }
    }

    /// Fetch the next page of posts for infinite scrolling
    func fetchNextPage() async throws {
        guard !isLoadingNextPage && hasNextPage else {
            return
        }

        isLoadingNextPage = true
        timelineError = nil
        defer { isLoadingNextPage = false }

        guard let plan = currentTimelinePlan ?? resolveTimelineFetchPlan() else {
            return
        }

        var allNewPosts: [Post] = []
        var hasMorePagesFromSuccess = false
        var hadSuccessfulFetch = false
        var firstFailure: Error?
        var failedAccounts: [String] = []

        func recordPaginationFailure(accountName: String, error: Error) {
            DebugLog.verbose("Error fetching next page for \(accountName): \(error)")
            failedAccounts.append(accountName)
            if firstFailure == nil {
                firstFailure = error
            }
        }

        switch plan {
        case .unified(let accountsToFetch):
            guard !accountsToFetch.isEmpty else {
                return
            }

            // Fetch next page from each account
            for account in accountsToFetch {
                do {
                    let result = try await fetchNextPageForAccount(account, selection: currentTimelineFeedSelection)
                    hadSuccessfulFetch = true
                    allNewPosts.append(contentsOf: result.posts)
                    updatePaginationTokens(
                        for: account,
                        selection: currentTimelineFeedSelection,
                        pagination: result.pagination
                    )
                    if result.pagination.hasNextPage {
                        hasMorePagesFromSuccess = true
                    }
                } catch {
                    recordPaginationFailure(accountName: account.username, error: error)
                }
            }
        case .allMastodon(let accountsToFetch):
            guard !accountsToFetch.isEmpty else {
                return
            }

            for account in accountsToFetch {
                do {
                    let result = try await fetchNextPageForAccount(account, selection: currentTimelineFeedSelection)
                    hadSuccessfulFetch = true
                    allNewPosts.append(contentsOf: result.posts)
                    updatePaginationTokens(
                        for: account,
                        selection: currentTimelineFeedSelection,
                        pagination: result.pagination
                    )
                    if result.pagination.hasNextPage {
                        hasMorePagesFromSuccess = true
                    }
                } catch {
                    recordPaginationFailure(accountName: account.username, error: error)
                }
            }
        case .allBluesky(let accountsToFetch):
            guard !accountsToFetch.isEmpty else {
                return
            }

            for account in accountsToFetch {
                do {
                    let result = try await fetchNextPageForAccount(account, selection: currentTimelineFeedSelection)
                    hadSuccessfulFetch = true
                    allNewPosts.append(contentsOf: result.posts)
                    updatePaginationTokens(
                        for: account,
                        selection: currentTimelineFeedSelection,
                        pagination: result.pagination
                    )
                    if result.pagination.hasNextPage {
                        hasMorePagesFromSuccess = true
                    }
                } catch {
                    recordPaginationFailure(accountName: account.username, error: error)
                }
            }
        case .mastodon(let account, let feed):
            do {
                let result = try await fetchNextPageForAccount(
                    account,
                    selection: .mastodon(accountId: account.id, feed: feed)
                )
                hadSuccessfulFetch = true
                allNewPosts.append(contentsOf: result.posts)
                hasMorePagesFromSuccess = result.pagination.hasNextPage
                updatePaginationTokens(
                    for: account,
                    selection: .mastodon(accountId: account.id, feed: feed),
                    pagination: result.pagination
                )
            } catch {
                recordPaginationFailure(accountName: account.username, error: error)
            }
        case .bluesky(let account, let feed):
            do {
                let result = try await fetchNextPageForAccount(
                    account,
                    selection: .bluesky(accountId: account.id, feed: feed)
                )
                hadSuccessfulFetch = true
                allNewPosts.append(contentsOf: result.posts)
                hasMorePagesFromSuccess = result.pagination.hasNextPage
                updatePaginationTokens(
                    for: account,
                    selection: .bluesky(accountId: account.id, feed: feed),
                    pagination: result.pagination
                )
            } catch {
                recordPaginationFailure(accountName: account.username, error: error)
            }
        }

        let outcome = Self._test_resolvePaginationOutcome(
            hadSuccessfulFetch: hadSuccessfulFetch,
            hasMorePagesFromSuccess: hasMorePagesFromSuccess,
            failureCount: failedAccounts.count
        )
        hasNextPage = outcome.hasNextPage

        if outcome.shouldEmitError {
            if failedAccounts.count > 1 {
                timelineError = PaginationFailureSummaryError(failedAccounts: failedAccounts)
            } else if let failure = firstFailure {
                timelineError = failure
            }
        }

        if outcome.shouldThrow, let failure = firstFailure {
            throw failure
        }

        guard hadSuccessfulFetch else { return }

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
        let followedAccounts = await getFollowedAccounts()
        let filteredNewPosts = await filterRepliesInTimeline(
            sortedNewPosts,
            followedAccounts: followedAccounts
        )
        let sourceContext = TimelineSourceContext(source: .pagination)

        canonicalPostStore.processIncomingPosts(
            filteredNewPosts,
            timelineID: canonicalUnifiedTimelineID,
            sourceContext: sourceContext
        )
        let canonicalPosts = canonicalPostStore.timelinePosts(for: canonicalUnifiedTimelineID)

        unifiedTimeline = canonicalPosts

#if DEBUG
        if FeatureFlagManager.isEnabled(.replyFiltering)
            && UserDefaults.standard.bool(forKey: "debugReplyFilteringInvariant")
        {
            let recentWindow = Array(filteredNewPosts.suffix(200))
            if !recentWindow.isEmpty {
                let filteredWindow = await filterRepliesInTimeline(
                    recentWindow,
                    followedAccounts: followedAccounts
                )
                if filteredWindow.count != recentWindow.count {
                    DebugLog.verbose(
                        "⚠️ SocialServiceManager: Reply filtering invariant failed for pagination window (\(recentWindow.count - filteredWindow.count) replies reintroduced)"
                    )
                }
            }
        }
#endif
    }

    /// Fetch next page for a specific account
    private func fetchNextPageForAccount(
        _ account: SocialAccount,
        selection: TimelineFeedSelection
    ) async throws -> TimelineResult {
        let tokenKey = paginationTokenKey(for: account, selection: selection)
        let token = paginationTokens[tokenKey]

        switch selection {
        case .unified, .allMastodon, .allBluesky:
            switch account.platform {
            case .mastodon:
                return try await mastodonService.fetchHomeTimeline(for: account, maxId: token)
            case .bluesky:
                return try await blueskyService.fetchHomeTimeline(for: account, cursor: token)
            }
        case .mastodon(_, let feed):
            return try await fetchMastodonTimeline(account: account, feed: feed, maxId: token)
        case .bluesky(_, let feed):
            return try await fetchBlueskyTimeline(account: account, feed: feed, cursor: token)
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
        DebugLog.verbose("📊 SocialServiceManager: Fetching Mastodon status with ID: \(id)")

        // Check cache first (valid for 5 minutes)
        if let cached = mastodonPostCache[id],
            Date().timeIntervalSince(cached.timestamp) < 300
        {  // 5 minutes
            DebugLog.verbose("📊 SocialServiceManager: Using cached Mastodon post for ID: \(id)")
            return cached.post
        }

        guard account.platform == .mastodon else {
            DebugLog.verbose(
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
                    DebugLog.verbose(
                        "📊 SocialServiceManager: Successfully fetched Mastodon post \(post.id), inReplyToID: \(post.inReplyToID ?? "nil")"
                    )

                    // Store in cache
                    Task { @MainActor in
                        self.mastodonPostCache[id] = (post: post, timestamp: Date())
                    }
                } else {
                    DebugLog.verbose(
                        "📊 SocialServiceManager: Mastodon service returned nil post for ID: \(id)")
                }
                return result
            }.value
        } catch {
            DebugLog.verbose("📊 SocialServiceManager: Error fetching Mastodon status: \(error)")
            throw error
        }
    }

    /// Search Mastodon for content (statuses, accounts, hashtags)
    /// Uses resolve=true to federate remote content
    func searchMastodon(
        query: String,
        account: SocialAccount,
        type: String? = nil,
        limit: Int = 20
    ) async throws -> MastodonSearchResult {
        DebugLog.verbose("📊 SocialServiceManager: Searching Mastodon for: \(query)")
        
        guard account.platform == .mastodon else {
            throw ServiceError.invalidAccount(
                reason: "The provided account is not a Mastodon account")
        }
        
        return try await mastodonService.search(
            query: query,
            account: account,
            type: type,
            limit: limit
        )
    }
    
    /// Search Mastodon and return posts (converts MastodonStatus to Post)
    /// This is the preferred method for fetching remote posts by URL
    func searchMastodonWithPosts(
        query: String,
        account: SocialAccount,
        type: String? = nil,
        limit: Int = 20
    ) async throws -> [Post] {
        DebugLog.verbose("📊 SocialServiceManager: Searching Mastodon (with Post conversion) for: \(query)")
        
        guard account.platform == .mastodon else {
            throw ServiceError.invalidAccount(
                reason: "The provided account is not a Mastodon account")
        }
        
        let searchResult = try await mastodonService.search(
            query: query,
            account: account,
            type: type,
            limit: limit
        )
        
        // Convert MastodonStatus to Post using the service's converter
        let posts = searchResult.statuses.map { status in
            mastodonService.convertMastodonStatusToPost(status, account: account)
        }
        
        DebugLog.verbose("📊 SocialServiceManager: Search returned \(posts.count) posts")
        return posts
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
                        DebugLog.verbose("Error fetching posts for \(account.username): \(error)")
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
        var seenCanonicalIDs = Set<String>()

        for post in posts {
            let resolution = CanonicalPostResolver.resolve(post: post)
            let canonicalPostID = resolution.canonicalPostID

            guard !seenCanonicalIDs.contains(canonicalPostID) else { continue }
            seenCanonicalIDs.insert(canonicalPostID)

            let canonicalPost =
                canonicalPostStore.canonicalPost(for: canonicalPostID)?.post
                ?? resolution.canonicalPost.post

            let boostText =
                canonicalPostStore.boostSummaryText(for: canonicalPostID)
                ?? (post.originalPost != nil ? (post.boostedBy ?? post.authorUsername) : nil)

            let kind: TimelineEntryKind
            if let boostText = boostText {
                kind = .boost(boostedBy: boostText)
            } else if let parentId = canonicalPost.inReplyToID {
                kind = .reply(parentId: parentId)
            } else {
                kind = .normal
            }

            let sortKey =
                canonicalPostStore.canonicalPost(for: canonicalPostID) != nil
                ? canonicalPostStore.sortKeyForCanonicalPost(canonicalPostID)
                : canonicalPost.createdAt

            entries.append(
                TimelineEntry(
                    id: canonicalPostID,
                    kind: kind,
                    post: canonicalPost,
                    createdAt: sortKey
                )
            )
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
        accountOverride: SocialAccount? = nil,
        blueskyRoot: BlueskyStrongRef? = nil,
        cwText: String? = nil,
        cwEnabled: Bool = false,
        attachmentSensitiveFlags: [Bool] = [],
        composerTextModel: ComposerTextModel? = nil
    ) async throws -> Post {
        switch post.platform {
        case .mastodon:
            guard let account = accountOverride ?? mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            do {
                // Calculate sensitive flag
                let sensitive = cwEnabled || attachmentSensitiveFlags.contains(true)
                
                return try await mastodonService.replyToPost(
                    post,
                    content: content,
                    mediaAttachments: mediaAttachments,
                    mediaAltTexts: mediaAltTexts,
                    pollOptions: pollOptions,
                    pollExpiresIn: pollExpiresIn,
                    visibility: visibility,
                    account: account,
                    spoilerText: cwText,
                    sensitive: sensitive,
                    composerTextModel: composerTextModel
                )
            } catch {
                // Enhanced error messages for common Mastodon failures
                let errorDesc = error.localizedDescription

                if errorDesc.contains("401") || errorDesc.contains("Unauthorized") {
                    throw ServiceError.authenticationExpired(
                        "Your Mastodon authentication has expired. Please re-add your account in Settings."
                    )
                } else if errorDesc.contains("429") || errorDesc.contains("Rate") {
                    throw ServiceError.rateLimitError(
                        reason:
                            "Mastodon rate limit exceeded. Please wait a moment and try again.",
                        retryAfter: 60
                    )
                } else if errorDesc.contains("does not appear to exist")
                    || errorDesc.contains("Not Found") || errorDesc.contains("not found")
                {
                    throw ServiceError.invalidInput(
                        reason: "The post you're replying to no longer exists or was deleted.")
                } else if errorDesc.contains("noRefreshToken")
                    || errorDesc.contains("Token expired")
                    || errorDesc.contains("No refresh token available")
                {
                    DebugLog.verbose(
                        "❌ Mastodon authentication expired for \(account.username). Please re-add this account in settings."
                    )
                    throw ServiceError.authenticationExpired(
                        "Please re-add your Mastodon account in Settings → Accounts using OAuth."
                    )
                } else {
                    // Just pass through the Mastodon error with its localized description
                    throw error
                }
            }
        case .bluesky:
            guard let account = accountOverride ?? blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            // Compile entities from composerTextModel if provided
            var finalContent = content
            if let model = composerTextModel {
                finalContent = model.toPlainText()
            }
            
            return try await blueskyService.replyToPost(
                post,
                content: finalContent,
                mediaAttachments: mediaAttachments,
                mediaAltTexts: mediaAltTexts,
                account: account,
                root: blueskyRoot,
                composerTextModel: composerTextModel
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
                offlineQueueStore.queueAction(
                    postId: post.id,
                    platformPostId: post.platformSpecificId,
                    platform: post.platform,
                    type: type
                )
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
                offlineQueueStore.queueAction(
                    postId: post.id,
                    platformPostId: post.platformSpecificId,
                    platform: post.platform,
                    type: type
                )
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
                DebugLog.verbose("❌ Failed to schedule notification: \(error.localizedDescription)")
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
        await invalidateFollowGraphCache(reason: "follow_user_post")
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
            await invalidateFollowGraphCache(reason: "unfollow_user_post")
        case .bluesky:
            // Unfollow on Bluesky requires the follow record URI.
            // This is complex because we don't usually have it on the post object.
            // We might need to fetch the relationship first.
            throw ServiceError.apiError("Unfollow not yet fully implemented for Bluesky")
        }
    }

    /// Mute a user
    public func muteUser(_ post: Post) async throws {
        let actorID = ActorID(from: post)
        
        // Optimistic update
        relationshipStore.setMuted(actorID, true)
        
        do {
            switch post.platform {
            case .mastodon:
                guard let account = mastodonAccounts.first else {
                    relationshipStore.setMuted(actorID, false)  // Revert on error
                    throw ServiceError.invalidAccount(reason: "No Mastodon account available")
                }
                _ = try await mastodonService.muteAccount(userId: post.authorUsername, account: account)
            case .bluesky:
                guard let account = blueskyAccounts.first else {
                    relationshipStore.setMuted(actorID, false)  // Revert on error
                    throw ServiceError.invalidAccount(reason: "No Bluesky account available")
                }
                try await blueskyService.muteActor(did: post.authorUsername, account: account)
            }
        } catch {
            // Revert optimistic update on failure
            relationshipStore.setMuted(actorID, false)
            throw error
        }
    }

    /// Block a user
    public func blockUser(_ post: Post) async throws {
        let actorID = ActorID(from: post)
        
        // Optimistic update
        relationshipStore.setBlocked(actorID, true)
        
        do {
            switch post.platform {
            case .mastodon:
                guard let account = mastodonAccounts.first else {
                    relationshipStore.setBlocked(actorID, false)  // Revert on error
                    throw ServiceError.invalidAccount(reason: "No Mastodon account available")
                }
                _ = try await mastodonService.blockAccount(
                    userId: post.authorUsername, account: account)
            case .bluesky:
                guard let account = blueskyAccounts.first else {
                    relationshipStore.setBlocked(actorID, false)  // Revert on error
                    throw ServiceError.invalidAccount(reason: "No Bluesky account available")
                }
                _ = try await blueskyService.blockUser(did: post.authorUsername, account: account)
            }
        } catch {
            // Revert optimistic update on failure
            relationshipStore.setBlocked(actorID, false)
            throw error
        }
    }

    /// Unmute a user
    public func unmuteUser(_ post: Post) async throws {
        let actorID = ActorID(from: post)
        
        // Optimistic update
        relationshipStore.setMuted(actorID, false)
        
        do {
            switch post.platform {
            case .mastodon:
                guard let account = mastodonAccounts.first else {
                    relationshipStore.setMuted(actorID, true)  // Revert on error
                    throw ServiceError.invalidAccount(reason: "No Mastodon account available")
                }
                _ = try await mastodonService.unmuteAccount(
                    userId: post.authorUsername, account: account)
            case .bluesky:
                guard let account = blueskyAccounts.first else {
                    relationshipStore.setMuted(actorID, true)  // Revert on error
                    throw ServiceError.invalidAccount(reason: "No Bluesky account available")
                }
                try await blueskyService.unmuteActor(did: post.authorUsername, account: account)
            }
        } catch {
            // Revert optimistic update on failure
            relationshipStore.setMuted(actorID, true)
            throw error
        }
    }

    /// Unblock a user
    public func unblockUser(_ post: Post) async throws {
        let actorID = ActorID(from: post)
        
        // Optimistic update
        relationshipStore.setBlocked(actorID, false)
        
        do {
            switch post.platform {
            case .mastodon:
                guard let account = mastodonAccounts.first else {
                    relationshipStore.setBlocked(actorID, true)  // Revert on error
                    throw ServiceError.invalidAccount(reason: "No Mastodon account available")
                }
                _ = try await mastodonService.unblockAccount(
                    userId: post.authorUsername, account: account)
            case .bluesky:
                guard let account = blueskyAccounts.first else {
                    relationshipStore.setBlocked(actorID, true)  // Revert on error
                    throw ServiceError.invalidAccount(reason: "No Bluesky account available")
                }
                try await blueskyService.unblockUser(did: post.authorUsername, account: account)
            }
        } catch {
            // Revert optimistic update on failure
            relationshipStore.setBlocked(actorID, true)
            throw error
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
        await invalidateFollowGraphCache(reason: "follow_user_id")
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
        await invalidateFollowGraphCache(reason: "unfollow_user_id")
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

    /// Fetch saved custom feeds for a Bluesky account
    public func fetchBlueskySavedFeeds(account: SocialAccount) async throws -> [BlueskyFeedGenerator]
    {
        guard account.platform == .bluesky else {
            throw ServiceError.unsupportedPlatform
        }
        return try await blueskyService.fetchSavedFeeds(for: account)
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
    public func voteInPoll(post: Post, choices: [Int]) async throws {
        guard let poll = post.poll else { return }
        let uniqueChoices = Array(Set(choices)).sorted()
        guard !uniqueChoices.isEmpty else { return }
        let previousPoll = poll
        let optimisticPoll = makeOptimisticPollUpdate(
            poll: poll,
            choices: uniqueChoices
        )

        await MainActor.run {
            post.poll = optimisticPoll
        }

        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            do {
                try await mastodonService.voteInPoll(
                    pollId: poll.id, choices: uniqueChoices, account: account)
            } catch {
                await MainActor.run {
                    post.poll = previousPoll
                }
                throw error
            }

        case .bluesky:
            // Bluesky doesn't support polls yet
            throw ServiceError.unsupportedPlatform
        }

        let refreshedId = post.platformSpecificId.isEmpty ? post.id : post.platformSpecificId
        if let refreshedPost = try? await fetchPost(id: refreshedId, platform: post.platform) {
            await MainActor.run {
                if let refreshedPoll = refreshedPost.poll {
                    post.poll = refreshedPoll
                }
            }
        }
    }

    private func makeOptimisticPollUpdate(poll: Post.Poll, choices: [Int]) -> Post.Poll {
        let uniqueChoices = Array(Set(choices)).sorted()
        var options = poll.options
        let newVotesCount = poll.votesCount + uniqueChoices.count
        var newVotersCount = poll.votersCount

        for index in uniqueChoices {
            guard options.indices.contains(index) else { continue }
            let currentVotes = options[index].votesCount ?? 0
            options[index] = Post.Poll.PollOption(
                title: options[index].title,
                votesCount: currentVotes + 1
            )
        }

        if let votersCount = poll.votersCount {
            newVotersCount = votersCount + 1
        }

        return Post.Poll(
            id: poll.id,
            expiresAt: poll.expiresAt,
            expired: poll.expired,
            multiple: poll.multiple,
            votesCount: newVotesCount,
            votersCount: newVotersCount,
            voted: true,
            ownVotes: uniqueChoices,
            options: options
        )
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
                DebugLog.verbose("⚠️ Failed to fetch DMs for \(account.username): \(error)")
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

            // Filter to only messages relevant to this conversation's participants.
            // Mastodon DMs are posts with direct visibility; fetchStatusContext returns the
            // entire reply tree which can span across separate conversations with different people.
            let participantUsername = conversation.participant.username.lowercased()
            let myId = account.platformSpecificId ?? account.id
            messages = messages.filter { post in
                let mentionedUsers = Set(post.mentions.map { $0.lowercased() })
                let isFromParticipant = post.authorId == conversation.participant.id
                let isFromMe = post.authorId == myId
                let mentionsParticipant = mentionedUsers.contains(participantUsername)
                // Keep messages that are between me and this conversation's participant
                return (isFromMe && mentionsParticipant) || (isFromParticipant && !isFromMe)
            }

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

    /// Start or find an existing Bluesky DM conversation with a user
    public func startOrFindBlueskyConversation(withDid did: String) async throws -> DMConversation {
        guard let account = accounts.first(where: { $0.platform == .bluesky }) else {
            throw ServiceError.invalidAccount(reason: "No Bluesky account found")
        }

        let convo = try await blueskyService.getConvoForMembers(memberDids: [did], for: account)

        let otherMember = convo.members.first { $0.did != account.platformSpecificId } ?? convo.members.first!
        let participant = NotificationAccount(
            id: otherMember.did,
            username: otherMember.handle,
            displayName: otherMember.displayName,
            avatarURL: otherMember.avatar
        )

        let lastMsg: DirectMessage
        if case .message(let view) = convo.lastMessage {
            let sender = NotificationAccount(
                id: view.sender.did,
                username: view.sender.handle,
                displayName: view.sender.displayName,
                avatarURL: view.sender.avatar
            )
            lastMsg = DirectMessage(
                id: view.id,
                sender: sender,
                recipient: participant,
                content: view.text,
                createdAt: ISO8601DateFormatter().date(from: view.sentAt) ?? Date(),
                platform: .bluesky
            )
        } else {
            lastMsg = DirectMessage(
                id: UUID().uuidString,
                sender: participant,
                recipient: participant,
                content: "",
                createdAt: Date(),
                platform: .bluesky
            )
        }

        return DMConversation(
            id: convo.id,
            participant: participant,
            lastMessage: lastMsg,
            unreadCount: convo.unreadCount,
            platform: .bluesky
        )
    }

    /// Mark a conversation as read (Bluesky only)
    public func markConversationRead(conversation: DMConversation) async {
        guard conversation.platform == .bluesky,
              let account = accounts.first(where: { $0.platform == .bluesky }) else { return }
        do {
            try await blueskyService.updateRead(convoId: conversation.id, for: account)
        } catch {
            print("[Messages] Failed to mark conversation read: \(error.localizedDescription)")
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

        DebugLog.verbose("🌐 [SocialServiceManager] Processing \(actions.count) offline actions...")

        for action in actions {
            do {
                // Fetch the post first to ensure we have current state
                let post = try await fetchPost(id: action.fetchPostId, platform: action.platform)

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
                DebugLog.verbose(
                    "✅ [SocialServiceManager] Successfully processed offline \(action.type) for post \(action.postId)"
                )
            } catch {
                DebugLog.verbose(
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

    // MARK: - Relationship Refresh

    @MainActor
    public func refreshRelationshipStateForMenu(for post: Post) async {
        guard post.platform == .mastodon else { return }
        let host = URL(string: post.originalURL)?.host
        let account =
            mastodonAccounts.first(where: { $0.serverURL?.host == host }) ?? mastodonAccounts.first
        guard let account else { return }

        func resolveAccountId(_ idOrAcct: String) async -> String? {
            guard !idOrAcct.isEmpty else { return nil }
            if idOrAcct.allSatisfy({ $0.isNumber }) {
                return idOrAcct
            }
            if let cached = mastodonAcctIdCache[idOrAcct] {
                return cached
            }
            if let resolved = try? await mastodonService.lookupAccountId(
                acct: idOrAcct, account: account)
            {
                mastodonAcctIdCache[idOrAcct] = resolved
                return resolved
            }
            return nil
        }

        let rawAuthorIds = [post.authorId, post.originalPost?.authorId ?? ""]
        var resolvedAuthorIds: [String] = []
        for rawId in rawAuthorIds {
            if let resolved = await resolveAccountId(rawId) {
                resolvedAuthorIds.append(resolved)
            }
        }

        let authorIds = Set(resolvedAuthorIds)

        guard !authorIds.isEmpty else { return }

        do {
            let relationships = try await mastodonService.fetchRelationships(
                accountIds: Array(authorIds),
                account: account
            )
            var relationshipMap: [String: MastodonRelationship] = [:]
            for rel in relationships {
                relationshipMap[rel.id] = rel
            }

            let resolvedPostAuthorId =
                await resolveAccountId(post.authorId) ?? post.authorId
            if let relationship = relationshipMap[resolvedPostAuthorId] {
                post.isFollowingAuthor = relationship.following
                post.isMutedAuthor = relationship.muting
                post.isBlockedAuthor = relationship.blocking
            }
            if let original = post.originalPost,
                let resolvedOriginalAuthorId = await resolveAccountId(original.authorId),
                let relationship = relationshipMap[resolvedOriginalAuthorId]
            {
                original.isFollowingAuthor = relationship.following
                original.isMutedAuthor = relationship.muting
                original.isBlockedAuthor = relationship.blocking
            }

            postActionStore.ensureState(for: post)
            if let original = post.originalPost {
                postActionStore.ensureState(for: original)
            }
        } catch {
            actionLogger.warning(
                "Failed to refresh Mastodon relationship state: \(error.localizedDescription)")
        }
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
        accountOverrides: [SocialPlatform: SocialAccount] = [:],
        cwText: String? = nil,
        cwEnabled: Bool = false,
        attachmentSensitiveFlags: [Bool] = [],
        composerTextModel: ComposerTextModel? = nil
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
                    accountOverride: accountOverrides[platform],
                    cwText: cwText,
                    cwEnabled: cwEnabled,
                    attachmentSensitiveFlags: attachmentSensitiveFlags,
                    composerTextModel: composerTextModel
                )
                createdPosts.append(post)
            } catch {
                errors.append(error)
                DebugLog.verbose("Failed to post to \(platform): \(error.localizedDescription)")
            }
        }

        // If no posts were created successfully, throw the first error
        if createdPosts.isEmpty && !errors.isEmpty {
            throw ServiceError.postFailed(
                reason: "Failed to post to any platform: \(errors.first!.localizedDescription)")
        }

        // If some posts failed but at least one succeeded, log warnings but don't throw
        if !errors.isEmpty {
            DebugLog.verbose(
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
        accountOverride: SocialAccount? = nil,
        cwText: String? = nil,
        cwEnabled: Bool = false,
        attachmentSensitiveFlags: [Bool] = [],
        composerTextModel: ComposerTextModel? = nil
    ) async throws -> Post {
        switch platform {
        case .mastodon:
            guard let account = accountOverride ?? mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            // Calculate sensitive flag: cwEnabled OR any attachment marked sensitive
            let sensitive = cwEnabled || attachmentSensitiveFlags.contains(true)
            
            // Compile entities from composerTextModel if provided (for mentions/hashtags)
            var finalContent = content
            if let model = composerTextModel {
                finalContent = model.toPlainText()
                // Entities will be compiled in MastodonService.createPost if needed
            }
            
            return try await mastodonService.createPost(
                content: finalContent,
                mediaAttachments: mediaAttachments,
                mediaAltTexts: mediaAltTexts,
                pollOptions: pollOptions,
                pollExpiresIn: pollExpiresIn,
                visibility: visibility,
                account: account,
                spoilerText: cwText,
                sensitive: sensitive,
                composerTextModel: composerTextModel
            )
        case .bluesky:
            guard let account = accountOverride ?? blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            // Bluesky doesn't support polls via the standard post API yet
            // Compile entities from composerTextModel if provided
            var finalContent = content
            if let model = composerTextModel {
                // Use plain text (entities are metadata for API)
                finalContent = model.toPlainText()
                // Entities will be compiled in BlueskyService.createPost if needed
            }
            
            return try await blueskyService.createPost(
                content: finalContent,
                mediaAttachments: mediaAttachments,
                mediaAltTexts: mediaAltTexts,
                account: account,
                composerTextModel: composerTextModel
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

    @discardableResult
    private func beginRefreshGeneration() -> RefreshGeneration {
        guard FeatureFlagManager.isEnabled(.refreshGenerationGuard) else {
            return refreshGeneration
        }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        refreshLogger.debug("refresh_generation_begin generation=\(generation, privacy: .public)")
        return generation
    }

    private func shouldCommitRefresh(generation: RefreshGeneration, stage: String) -> Bool {
        guard FeatureFlagManager.isEnabled(.refreshGenerationGuard) else {
            return true
        }
        guard Self._test_shouldCommitRefreshGeneration(active: refreshGeneration, candidate: generation)
        else {
            refreshLogger.debug(
                "refresh_generation_stale stage=\(stage, privacy: .public) candidate=\(generation, privacy: .public) active=\(self.refreshGeneration, privacy: .public)"
            )
            return false
        }
        return true
    }

    /// Safely update the timeline with proper isolation to prevent AttributeGraph cycles
    @MainActor
    private func safelyUpdateTimeline(_ posts: [Post]) {
        DebugLog.verbose("🔄 SocialServiceManager: Updating unifiedTimeline with \(posts.count) posts")
        self.unifiedTimeline = posts
        DebugLog.verbose("✅ SocialServiceManager: unifiedTimeline updated - new count: \(posts.count)")

        // Proactively fetch parent posts in the background to prevent jittery reply banner animations
        Task.detached(priority: .background) { [weak self] in
            DebugLog.verbose("🔄 SocialServiceManager: Starting background proactive parent fetching task")
            await self?.proactivelyFetchParentPosts(from: posts)
        }
    }

    @MainActor
    private func updateLoadingState(_ isLoading: Bool, error: Error? = nil) {
        // Immediate update - no delays
        self.isLoadingTimeline = isLoading
        if isLoading {
            self.timelineError = nil
        } else if let error = error {
            self.timelineError = error
        } else {
            self.timelineError = nil
        }
    }

    /// Merge buffered posts into the canonical unified timeline without forcing a full refresh.
    @MainActor
    func mergeBufferedPosts(_ posts: [Post]) {
        guard !posts.isEmpty else { return }
        DebugLog.verbose("🔄 SocialServiceManager: Merging \(posts.count) buffered posts into unified timeline")
        
        // Apply filtering to buffered posts before merging (critical: must go through choke point)
        Task {
            let filteredPosts = await filterRepliesInTimeline(posts)
            await MainActor.run {
                let sourceContext = TimelineSourceContext(source: .buffer)
                canonicalPostStore.processIncomingPosts(
                    filteredPosts,
                    timelineID: canonicalUnifiedTimelineID,
                    sourceContext: sourceContext
                )
                let mergedPosts = canonicalPostStore.timelinePosts(for: canonicalUnifiedTimelineID)
                safelyUpdateTimeline(mergedPosts)
            }
        }
    }

    @MainActor
    func seedAccountSwitchFixturesForUITests() {
        guard UITestHooks.isEnabled else { return }

        let mastodonFixture = SocialAccount(
            id: "ui-test-mastodon",
            username: "ui-test-mastodon",
            displayName: "UI Test Mastodon",
            serverURL: URL(string: "https://example.social"),
            platform: .mastodon,
            profileImageURL: nil
        )
        mastodonFixture.platformSpecificId = "ui-test-mastodon-native"

        let blueskyFixture = SocialAccount(
            id: "ui-test-bluesky",
            username: "ui-test.bsky.social",
            displayName: "UI Test Bluesky",
            serverURL: URL(string: "https://bsky.social"),
            platform: .bluesky,
            profileImageURL: nil
        )
        blueskyFixture.platformSpecificId = "did:plc:ui-test-bluesky"

        accounts = [mastodonFixture, blueskyFixture]
        currentTimelineFeedSelection = .unified
        updateAccountLists()
        resetUnifiedTimelineStore()
        scheduleFollowGraphCacheInvalidation(reason: "ui_test_seed_accounts")
    }

#if DEBUG
    @MainActor
    func debugSeedUnifiedTimeline(_ posts: [Post]) {
        let sourceContext = TimelineSourceContext(source: .system)
        canonicalPostStore.replaceTimeline(
            timelineID: canonicalUnifiedTimelineID,
            posts: posts,
            sourceContext: sourceContext
        )
        unifiedTimeline = canonicalPostStore.timelinePosts(for: canonicalUnifiedTimelineID)
        DebugLog.verbose("🧪 SocialServiceManager: Seeded unified timeline with \(posts.count) posts")
    }
#endif

    // MARK: - Migration Logic

    private func migrateOldBlueskyAccounts() {
        // Check for Bluesky accounts that might have DID-based IDs
        var accountsToMigrate: [SocialAccount] = []
        var migratedAccounts: [SocialAccount] = []

        for account in accounts where account.platform == .bluesky {
            // Check if this account has a DID-based ID (starts with "did:")
            if account.id.hasPrefix("did:") {
                DebugLog.verbose(
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

                DebugLog.verbose(
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

            DebugLog.verbose(
                "✅ [Migration] Successfully migrated \(migratedAccounts.count) Bluesky accounts to new stable ID format"
            )
        }
    }

    // MARK: - Prefetch / Manual Refresh

    /// No-op prefetch placeholder; refresh is coordinated by TimelineRefreshCoordinator.
    func ensureTimelinePrefetch() async {
        DebugLog.verbose("🔄 SocialServiceManager: ensureTimelinePrefetch called")
    }

    /// Force refresh timeline regardless of current state - for explicit user intent
    func forceRefreshTimeline() async {
        DebugLog.verbose("🔄 SocialServiceManager: forceRefreshTimeline called")
        try? await refreshTimeline(intent: .manualRefresh)
    }

    // MARK: - Thread Context Loading

    /// Fetch thread context for a post (ancestors and descendants)
    func fetchThreadContext(for post: Post) async throws -> ThreadContext {
        DebugLog.verbose(
            "📊 SocialServiceManager: fetchThreadContext called for post \(post.id) on \(post.platform)"
        )

        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                DebugLog.verbose("❌ SocialServiceManager: No Mastodon account available for thread loading")
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            DebugLog.verbose(
                "📊 SocialServiceManager: Using Mastodon account \(account.username) for thread loading"
            )
            return try await fetchMastodonThreadContext(
                postId: post.platformSpecificId, account: account)
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                DebugLog.verbose("❌ SocialServiceManager: No Bluesky account available for thread loading")
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            DebugLog.verbose(
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

        DebugLog.verbose(
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
        DebugLog.verbose(
            "🔄 SocialServiceManager: Starting proactive parent post fetching for \(posts.count) posts"
        )

        // Collect all posts that have parent IDs but no cached parent data
        var parentsToFetch: [(postId: String, parentId: String, platform: SocialPlatform)] = []

        for post in posts {
            guard let parentId = post.inReplyToID else { continue }

            // Check if we already have this parent in cache
            let cacheKey = "\(post.platform.rawValue):\(parentId)"
            DebugLog.verbose("🔍 SocialServiceManager: Checking cache for key: \(cacheKey)")

            if PostParentCache.shared.getCachedPost(id: cacheKey) != nil {
                DebugLog.verbose("✅ SocialServiceManager: Parent \(parentId) already cached, skipping")
                continue  // Already cached, skip
            }

            // Check if we're already fetching this parent
            if parentFetchInProgress.contains(cacheKey) {
                DebugLog.verbose("⏳ SocialServiceManager: Parent \(parentId) already being fetched, skipping")
                continue  // Already in progress, skip
            }

            DebugLog.verbose(
                "📝 SocialServiceManager: Adding parent \(parentId) to fetch queue for post \(post.id)"
            )
            parentsToFetch.append((postId: post.id, parentId: parentId, platform: post.platform))
        }

        guard !parentsToFetch.isEmpty else {
            DebugLog.verbose("✅ SocialServiceManager: No parent posts need fetching")
            return
        }

        DebugLog.verbose("🔄 SocialServiceManager: Fetching \(parentsToFetch.count) parent posts in background")

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

        DebugLog.verbose("✅ SocialServiceManager: Completed proactive parent post fetching")
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

        DebugLog.verbose(
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
                    DebugLog.verbose("⚠️ SocialServiceManager: No Mastodon account available for parent fetch")
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
                DebugLog.verbose("✅ SocialServiceManager: Cached parent post \(parentId) for \(platform)")

                // Proactively fetch its parent if it's also a reply
                if let grandParentId = parentPost.inReplyToID {
                    await fetchSingleParentPost(
                        parentId: grandParentId, platform: platform, depth: depth + 1)
                }
            }
        } catch {
            DebugLog.verbose(
                "⚠️ SocialServiceManager: Failed to fetch parent post \(parentId): \(error.localizedDescription)"
            )
            // Don't throw - just log the error and continue
        }
    }

    private func mastodonInstanceDomain(for account: SocialAccount) -> String {
        let serverUrl = mastodonService.formatServerURL(account.serverURL?.absoluteString ?? "")
        return serverUrl
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }

    private func mastodonRelationshipLookup(
        for accountIds: [String],
        account: SocialAccount
    ) async -> [String: MastodonRelationship] {
        guard !accountIds.isEmpty else { return [:] }
        do {
            let relationships = try await mastodonService.fetchRelationships(
                accountIds: accountIds, account: account)
            return Dictionary(uniqueKeysWithValues: relationships.map { ($0.id, $0) })
        } catch {
            DebugLog.verbose(
                "⚠️ SocialServiceManager: Failed to fetch booster relationships: \(error.localizedDescription)"
            )
            return [:]
        }
    }

    private func blueskyPostURI(for post: Post) -> String {
        if post.platformSpecificId.hasPrefix("at://") {
            return post.platformSpecificId
        }
        if post.id.hasPrefix("at://") {
            return post.id
        }
        if !post.authorUsername.isEmpty && !post.platformSpecificId.isEmpty {
            return "at://\(post.authorUsername)/app.bsky.feed.post/\(post.platformSpecificId)"
        }
        return post.platformSpecificId
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
    public let platformPostId: String?
    public let platform: SocialPlatform
    public let type: QueuedActionType
    public let createdAt: Date

    /// Preferred identifier for replay fetches.
    /// Uses platform-native post IDs when available, and falls back to legacy postId.
    public var fetchPostId: String {
        guard let platformPostId, !platformPostId.isEmpty else { return postId }
        return platformPostId
    }

    public init(
        id: UUID = UUID(),
        postId: String,
        platformPostId: String? = nil,
        platform: SocialPlatform,
        type: QueuedActionType,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.postId = postId
        self.platformPostId = platformPostId
        self.platform = platform
        self.type = type
        self.createdAt = createdAt
    }
}

@MainActor
public class OfflineQueueStore: ObservableObject {
    @Published public var queuedActions: [QueuedAction] = []

    private let saveKey: String
    private let userDefaults: UserDefaults

    public init(saveKey: String = "socialfusion_offline_queue", userDefaults: UserDefaults = .standard) {
        self.saveKey = saveKey
        self.userDefaults = userDefaults
        loadQueue()
    }

    public func queueAction(
        postId: String,
        platformPostId: String? = nil,
        platform: SocialPlatform,
        type: QueuedActionType
    ) {
        let normalizedPlatformPostId: String? = {
            guard let platformPostId else { return nil }
            let trimmed = platformPostId.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()

        let action = QueuedAction(
            postId: postId,
            platformPostId: normalizedPlatformPostId,
            platform: platform,
            type: type
        )
        queuedActions.append(action)
        persist()
    }

    public func removeAction(_ action: QueuedAction) {
        queuedActions.removeAll { $0.id == action.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(queuedActions) {
            userDefaults.set(data, forKey: saveKey)
        }
    }

    private func loadQueue() {
        if let data = userDefaults.data(forKey: saveKey),
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

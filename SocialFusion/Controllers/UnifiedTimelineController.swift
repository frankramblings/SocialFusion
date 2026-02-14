import Combine
import Foundation
import SwiftUI

/// Unified timeline controller that manages posts from all platforms
/// Implements proper SwiftUI state management to prevent AttributeGraph cycles
@MainActor
class UnifiedTimelineController: ObservableObject {

    // MARK: - Published State (Single Source of Truth)

    @Published private(set) var posts: [Post] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error? = nil
    @Published private(set) var lastRefreshDate: Date?
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var isLoadingNextPage: Bool = false
    @Published private(set) var hasNextPage: Bool = true
    @Published private(set) var bufferCount: Int = 0
    @Published private(set) var bufferEarliestTimestamp: Date?
    @Published private(set) var bufferSources: Set<SocialPlatform> = []
    @Published private(set) var isNearTop: Bool = true
    @Published private(set) var isDeepHistory: Bool = false
    @Published private(set) var restorationAnchor: String?

    // MARK: - Unread Above Viewport Tracking
    /// Count of posts that are unread and above the current viewport
    @Published private(set) var unreadAboveViewportCount: Int = 0
    /// Bridge value: holds the buffer count during the async gap between
    /// mergeBufferedPosts() draining the buffer and updatePosts() setting unreadAboveViewportCount.
    /// Prevents the pill from flickering to 0 during the merge.
    @Published private(set) var pendingMergeCount: Int = 0
    /// IDs of posts that are above the current viewport and haven't been scrolled to yet
    private var unreadPostIds: Set<String> = []

    // MARK: - Scroll Policy

    enum ScrollPolicy {
        case preserveViewport
        case jumpToNow
    }

    var scrollPolicy: ScrollPolicy = .preserveViewport
    private var currentAnchorId: String?
    /// Captures whether user was scrolled down before a refresh started
    /// This is used to correctly track unread posts during pull-to-refresh
    private var wasScrolledDownBeforeRefresh: Bool = false

    // MARK: - Private Properties

    private let serviceManager: SocialServiceManager
    private let actionStore: PostActionStore
    private let actionCoordinator: PostActionCoordinator
    private let relationshipStore: RelationshipStore
    private let timelineContextProvider: UnifiedTimelineContextProvider
    private lazy var refreshCoordinator: TimelineRefreshCoordinator = {
        TimelineRefreshCoordinator(
            timelineID: "unified",
            platforms: SocialPlatform.allCases,
            isLoading: { [weak serviceManager] in serviceManager?.isLoadingTimeline ?? false },
            fetchPostsForPlatform: { [weak serviceManager] platform in
#if DEBUG
                if UITestHooks.isEnabled {
                    return Self.makeTestPosts(count: 3, platform: platform)
                }
#endif
                guard let serviceManager = serviceManager else { return [] }
                do {
                    let posts = try await serviceManager.fetchPostsForTimeline(platform: platform)
                    return posts.sorted { $0.createdAt > $1.createdAt }
                } catch {
                    return []
                }
            },
            filterPosts: { [weak serviceManager] posts in
                guard let serviceManager = serviceManager else { return posts }
                return await serviceManager.filterPostsForTimeline(posts)
            },
            mergeBufferedPosts: { [weak serviceManager] posts in
                serviceManager?.mergeBufferedPosts(posts)
            },
            refreshVisibleTimeline: { [weak serviceManager] intent in
                guard let serviceManager = serviceManager else { return }
                try? await serviceManager.refreshTimeline(intent: intent)
            },
            visiblePostsProvider: { [weak self] in
                self?.posts ?? []
            },
            log: { message in
                DebugLog.verbose(message)
            }
        )
    }()
    private var cancellables = Set<AnyCancellable>()
    private var isInitialized = false

    var postActionStore: PostActionStore { actionStore }
    var postActionCoordinator: PostActionCoordinator { actionCoordinator }
    var autocompleteTimelineContextProvider: TimelineContextProvider { timelineContextProvider }

    // MARK: - Initialization

    init(serviceManager: SocialServiceManager) {
        self.serviceManager = serviceManager
        self.actionStore = serviceManager.postActionStore
        self.actionCoordinator = serviceManager.postActionCoordinator
        self.relationshipStore = serviceManager.relationshipStore
        // Use shared provider from service manager
        self.timelineContextProvider = serviceManager.timelineContextProvider
        setupBindings()
    }

    deinit {
        cancellables.removeAll()
    }

    // MARK: - Private Setup

    /// Setup bindings for service manager updates
    private func setupBindings() {
        // Listen to timeline changes from service manager
        serviceManager.$unifiedTimeline
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPosts in
                self?.updatePosts(newPosts)
            }
            .store(in: &cancellables)

        serviceManager.$isLoadingTimeline
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.isLoading = isLoading
            }
            .store(in: &cancellables)

        serviceManager.$timelineError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.error = error
            }
            .store(in: &cancellables)

        serviceManager.$isLoadingNextPage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.isLoadingNextPage = isLoading
            }
            .store(in: &cancellables)

        serviceManager.$hasNextPage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasNext in
                self?.hasNextPage = hasNext
            }
            .store(in: &cancellables)

        serviceManager.$isComposing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isComposing in
                self?.refreshCoordinator.setComposing(isComposing)
            }
            .store(in: &cancellables)

        refreshCoordinator.$bufferCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.bufferCount = count
            }
            .store(in: &cancellables)

        refreshCoordinator.$bufferEarliestTimestamp
            .receive(on: DispatchQueue.main)
            .sink { [weak self] timestamp in
                self?.bufferEarliestTimestamp = timestamp
            }
            .store(in: &cancellables)

        refreshCoordinator.$bufferSources
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sources in
                self?.bufferSources = sources
            }
            .store(in: &cancellables)

        refreshCoordinator.$isNearTop
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isNearTop in
                self?.isNearTop = isNearTop
            }
            .store(in: &cancellables)

        refreshCoordinator.$isDeepHistory
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isDeepHistory in
                self?.isDeepHistory = isDeepHistory
            }
            .store(in: &cancellables)
        
        // Subscribe to relationship store changes for instant filtering
        relationshipStore.$blocked
            .combineLatest(relationshipStore.$muted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: Set<ActorID>, _: Set<ActorID>) in
                self?.recomputeVisiblePosts()
            }
            .store(in: &cancellables)
    }

    /// Update posts with proper state management
    private func updatePosts(_ newPosts: [Post]) {
        // Capture state before update for unread tracking
        let previousPostIds = Set(posts.map { $0.stableId })
        let anchorId = currentAnchorId
        let wasNearTop = isNearTop

        // Anchor & Compensate: Capture anchor before update
        if scrollPolicy == .preserveViewport {
            self.restorationAnchor = anchorId
        } else {
            self.restorationAnchor = nil
            // Reset policy to default after explicit jump
            scrollPolicy = .preserveViewport
            // Clear unread when jumping to top
            clearUnreadAboveViewport()
        }

        // Filter posts based on blocked/muted actors
        let filteredPosts = filterPosts(newPosts)

        self.posts = filteredPosts
        if pendingMergeCount > 0 { pendingMergeCount = 0 }
        if FeatureFlagManager.isEnabled(.postActionsV2) {
            filteredPosts.forEach { post in
                actionStore.ensureState(for: post)
            }
        }
        self.lastRefreshDate = Date()
        refreshCoordinator.handleVisibleTimelineUpdate(filteredPosts)

        // Update timeline context provider for autocomplete
        timelineContextProvider.updateSnapshot(posts: filteredPosts, scope: .unified)

        // Track unread posts inserted above anchor
        // Use wasScrolledDownBeforeRefresh to handle pull-to-refresh correctly
        // During pull gesture, isNearTop might temporarily be true even if user was scrolled down
        let shouldTrackUnread = wasScrolledDownBeforeRefresh || (!wasNearTop && anchorId != nil)

        if shouldTrackUnread, let anchorId = anchorId {
            trackUnreadPostsAboveAnchor(
                newPosts: filteredPosts,
                previousPostIds: previousPostIds,
                anchorId: anchorId
            )
        } else if !shouldTrackUnread && wasNearTop {
            // User was genuinely at top (not during pull-to-refresh) - clear unread
            // They're viewing the newest content
            clearUnreadAboveViewport()
        }

        if !isInitialized {
            isInitialized = true
        }
    }

    /// Track posts that were inserted above the anchor position
    private func trackUnreadPostsAboveAnchor(
        newPosts: [Post],
        previousPostIds: Set<String>,
        anchorId: String
    ) {
        // Find the anchor's position in the new list
        guard let anchorIndex = newPosts.firstIndex(where: { scrollIdentifier(for: $0) == anchorId }) else {
            return
        }

        // Find posts that are:
        // 1. NEW (not in previous list)
        // 2. Above the anchor (index < anchorIndex)
        var newUnreadIds = Set<String>()
        for (index, post) in newPosts.enumerated() {
            if index >= anchorIndex {
                break // All posts at or below anchor are not "above viewport"
            }
            let stableId = post.stableId
            if !previousPostIds.contains(stableId) {
                // This is a new post above the anchor
                newUnreadIds.insert(scrollIdentifier(for: post))
            }
        }

        if !newUnreadIds.isEmpty {
            DebugLog.verbose(
                "📊 [trackUnread] Found \(newUnreadIds.count) new posts above anchor at index \(anchorIndex). IDs: \(newUnreadIds.sorted().prefix(5))"
            )
            addUnreadAboveViewport(newUnreadIds)
        } else {
            DebugLog.verbose(
                "📊 [trackUnread] No new posts above anchor at index \(anchorIndex). Total posts: \(newPosts.count), previous: \(previousPostIds.count)"
            )
        }
    }

    /// Generate scroll identifier for a post (matches ConsolidatedTimelineView logic)
    private func scrollIdentifier(for post: Post) -> String {
        let stable = post.stableId
        return stable.hasSuffix("-") ? post.id : stable
    }
    
    /// Filter posts based on blocked/muted actors
    private func filterPosts(_ posts: [Post]) -> [Post] {
        return posts.filter { post in
            !relationshipStore.shouldFilter(post)
        }
    }
    
    /// Recompute visible posts when relationship store changes
    private func recomputeVisiblePosts() {
        // Re-filter current posts
        let filtered = filterPosts(posts)
        if filtered.count != posts.count {
            self.posts = filtered
        }
    }

    // MARK: - Public Interface

    func updateCurrentAnchor(_ id: String?) {
        self.currentAnchorId = id
    }

    /// Refresh timeline - proper async/await pattern
    /// Use this for scope changes or other non-user-initiated refreshes
    func refreshTimeline() {
        // Prevent multiple concurrent refreshes
        guard !isLoading else { return }

        // For scope changes, don't use merge mode - do a full refresh
        // This ensures clean state when switching between different timelines
        scrollPolicy = .preserveViewport  // Preserve position if possible, but don't merge

        Task {
            await refreshCoordinator.manualRefresh(intent: .manualRefresh)
        }
    }

    /// Called by the view BEFORE the pull-to-refresh gesture starts
    /// This captures the logical scroll state before the gesture affects isNearTop
    func prepareForRefresh(wasScrolledDown: Bool) {
        wasScrolledDownBeforeRefresh = wasScrolledDown
    }

    /// Refresh timeline with async/await for pull-to-refresh
    func refreshTimelineAsync() async {
        // Remove the guard - pull-to-refresh should always be allowed
        // The service manager will handle preventing duplicate refreshes properly

        // Ensure we preserve viewport position during pull-to-refresh
        // This allows new posts to appear above the user's current position
        scrollPolicy = .preserveViewport

        await refreshCoordinator.manualRefresh(intent: .manualRefresh)

        // Reset after refresh completes
        wasScrolledDownBeforeRefresh = false
    }

    /// Fetch new posts to buffer WITHOUT updating visible timeline.
    /// Used for pull-to-refresh to prevent scroll jump.
    /// Call mergeBufferedPosts() after to apply with offset compensation.
    /// Note: wasScrolledDownBeforeRefresh is NOT reset here - it's needed for unread tracking
    /// when mergeBufferedPosts() is called. Reset it manually after merge if needed.
    func fetchToBuffer() async -> Int {
        scrollPolicy = .preserveViewport
        return await refreshCoordinator.fetchToBuffer()
        // Don't reset wasScrolledDownBeforeRefresh here - needed for unread tracking in merge
    }

    /// Like or unlike a post - proper event-driven pattern
    func likePost(_ post: Post) {
        if FeatureFlagManager.isEnabled(.postActionsV2) {
            actionStore.ensureState(for: post)
            actionCoordinator.toggleLike(for: post)
            return
        }

        // Create intent for the action
        let intent = PostActionIntent.like(post: post)
        processPostAction(intent)
    }

    /// Repost or unrepost a post - proper event-driven pattern
    func repostPost(_ post: Post) {
        if FeatureFlagManager.isEnabled(.postActionsV2) {
            actionStore.ensureState(for: post)
            actionCoordinator.toggleRepost(for: post)
            return
        }

        // Create intent for the action
        let intent = PostActionIntent.repost(post: post)
        processPostAction(intent)
    }

    /// Clear error state
    func clearError() {
        self.error = nil
    }

    /// Load next page for infinite scroll
    func loadNextPage() async {
        guard !isLoadingNextPage && hasNextPage else { return }

        do {
            try await serviceManager.fetchNextPage()
        } catch {
            self.error = error
        }
    }

    // MARK: - Auto Refresh and Buffering

    func setTimelineVisible(_ isVisible: Bool) {
        refreshCoordinator.setTimelineVisible(isVisible)
    }

    func handleAppForegrounded() {
        refreshCoordinator.handleAppForegrounded()
    }

    func recordVisibleInteraction() {
        refreshCoordinator.recordVisibleInteraction()
    }

    func scrollInteractionBegan() {
        refreshCoordinator.scrollInteractionBegan()
    }

    func scrollInteractionEnded() {
        refreshCoordinator.scrollInteractionEnded()
    }

    func updateScrollState(isNearTop: Bool, isDeepHistory: Bool) {
        refreshCoordinator.updateScrollState(isNearTop: isNearTop, isDeepHistory: isDeepHistory)
    }

    func mergeBufferedPosts() {
        let count = bufferCount
        if count > 0 { pendingMergeCount = count }
        refreshCoordinator.mergeBufferedPostsIfNeeded()
    }

    // MARK: - Unread Tracking

    /// Mark posts as read when they become visible in the viewport
    func markPostsAsRead(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let previousCount = unreadPostIds.count
        unreadPostIds.subtract(ids)
        let newCount = unreadPostIds.count
        if newCount != previousCount {
            unreadAboveViewportCount = newCount
        }
    }

    /// Mark a single post as read
    func markPostAsRead(_ id: String) {
        guard unreadPostIds.contains(id) else { return }
        unreadPostIds.remove(id)
        unreadAboveViewportCount = unreadPostIds.count
    }

    /// Set posts as unread above viewport (called when posts are inserted above anchor)
    func setUnreadAboveViewport(_ ids: Set<String>) {
        unreadPostIds = ids
        unreadAboveViewportCount = ids.count
    }

    /// Add posts to unread above viewport
    func addUnreadAboveViewport(_ ids: Set<String>) {
        let previousCount = unreadPostIds.count
        unreadPostIds.formUnion(ids)
        let newCount = unreadPostIds.count
        if newCount != previousCount {
            unreadAboveViewportCount = newCount
        }
    }

    /// Clear all unread tracking (e.g., when user scrolls to top)
    func clearUnreadAboveViewport() {
        guard !unreadPostIds.isEmpty || pendingMergeCount > 0 else { return }
        unreadPostIds.removeAll()
        unreadAboveViewportCount = 0
        pendingMergeCount = 0
    }

    /// Check if a post is in the unread set
    func isPostUnread(_ id: String) -> Bool {
        return unreadPostIds.contains(id)
    }

    /// Update unread count based on the topmost visible post index
    /// This is more robust than tracking individual IDs for fast scrolling
    /// The index represents the position in the posts array (0 = newest/top)
    func updateUnreadFromTopVisibleIndex(_ index: Int) {
        // Posts 0 to (index-1) are above the viewport (unread)
        // Posts at index and below have been seen
        let newCount = max(0, index)

        DebugLog.verbose(
            "📊 [updateUnread] index=\(index) newCount=\(newCount) current=\(unreadAboveViewportCount) willUpdate=\(newCount < unreadAboveViewportCount)"
        )

        // Only update if the count decreased (user scrolled up to see more posts)
        // This prevents the count from increasing when scrolling back down
        if newCount < unreadAboveViewportCount {
            unreadAboveViewportCount = newCount
            // Also clear the IDs for posts we've now passed
            // (keeps the ID set in sync if other code checks it)
            unreadPostIds = Set(posts.prefix(newCount).map { scrollIdentifier(for: $0) })
        }
    }

    /// Mark visible posts as read, decrementing the unread count in real-time
    /// This is called with IDs of posts that are currently visible on screen
    func markVisiblePostsAsRead(_ visibleIds: Set<String>) {
        guard !unreadPostIds.isEmpty else { return }

        // Find unread posts that are now visible
        let nowRead = unreadPostIds.intersection(visibleIds)
        guard !nowRead.isEmpty else { return }

        // Remove from unread set
        unreadPostIds.subtract(nowRead)
        unreadAboveViewportCount = unreadPostIds.count
    }

    func requestInitialPrefetch() {
        Task { await refreshCoordinator.requestPrefetch(trigger: .foreground) }
    }

#if DEBUG
    func debugSeedTimeline() {
        guard UITestHooks.isEnabled else { return }
        let posts = Self.makeTestPosts(count: 8, platform: .mastodon)
        Task { @MainActor in
            serviceManager.debugSeedUnifiedTimeline(posts)
        }
    }

    func debugTriggerIdlePrefetch() {
        guard UITestHooks.isEnabled else { return }
        Task { await refreshCoordinator.requestPrefetch(trigger: .idlePolling) }
    }

    func debugTriggerForegroundPrefetch() {
        guard UITestHooks.isEnabled else { return }
        Task { await refreshCoordinator.debugForcePrefetch(trigger: .foreground) }
    }

    private static func makeTestPosts(count: Int, platform: SocialPlatform) -> [Post] {
        let now = Date()
        return (0..<count).map { index in
            let id = "ui-test-\(platform.rawValue)-\(UUID().uuidString)-\(index)"
            return Post(
                id: id,
                content: "UI Test Post \(index)",
                authorName: "UI Test",
                authorUsername: "ui-test",
                authorProfilePictureURL: "",
                createdAt: now.addingTimeInterval(-Double(index)),
                platform: platform,
                originalURL: "https://example.com/\(id)",
                platformSpecificId: id
            )
        }
    }
#endif

    // MARK: - Private Helpers

    /// Process post actions using proper intent pattern
    private func processPostAction(_ intent: PostActionIntent) {
        // Apply optimistic update
        applyOptimisticUpdate(for: intent)

        // Execute network request
        Task {
            do {
                let updatedPost = try await executePostAction(intent)
                await confirmOptimisticUpdate(for: intent, with: updatedPost)
            } catch {
                await revertOptimisticUpdate(for: intent)
            }
        }
    }

    /// Apply optimistic update for immediate UI feedback
    private func applyOptimisticUpdate(for intent: PostActionIntent) {
        // CRITICAL FIX: Defer state updates to prevent "Publishing changes from within view updates" warnings
        // Add delay to ensure we're outside the view update cycle
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000)  // 0.01 seconds delay
            updatePostInPlace(intent.postId) { post in
                switch intent {
                case .like:
                    post.isLiked.toggle()
                    post.likeCount += post.isLiked ? 1 : -1
                case .repost:
                    post.isReposted.toggle()
                    post.repostCount += post.isReposted ? 1 : -1
                }
            }
        }
    }

    /// Execute the actual network request
    private func executePostAction(_ intent: PostActionIntent) async throws -> Post {
        switch intent {
        case .like(let post):
            return post.isLiked
                ? try await serviceManager.unlikePost(post)
                : try await serviceManager.likePost(post)
        case .repost(let post):
            return post.isReposted
                ? try await serviceManager.unrepostPost(post)
                : try await serviceManager.repostPost(post)
        }
    }

    /// Confirm optimistic update with server response
    private func confirmOptimisticUpdate(for intent: PostActionIntent, with updatedPost: Post) async
    {
        // CRITICAL FIX: Defer state updates to prevent "Publishing changes from within view updates" warnings
        // Add delay to ensure we're outside the view update cycle
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000)  // 0.01 seconds delay
            updatePostInPlace(intent.postId) { post in
                post.isLiked = updatedPost.isLiked
                post.likeCount = updatedPost.likeCount
                post.isReposted = updatedPost.isReposted
                post.repostCount = updatedPost.repostCount
            }
        }
    }

    /// Revert optimistic update on failure
    private func revertOptimisticUpdate(for intent: PostActionIntent) async {
        // CRITICAL FIX: Defer state updates to prevent "Publishing changes from within view updates" warnings
        // Add delay to ensure we're outside the view update cycle
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000)  // 0.01 seconds delay
            updatePostInPlace(intent.postId) { post in
                switch intent {
                case .like:
                    post.isLiked.toggle()
                    post.likeCount += post.isLiked ? 1 : -1
                case .repost:
                    post.isReposted.toggle()
                    post.repostCount += post.isReposted ? 1 : -1
                }
            }

            // Show error to user
            showInteractionError(for: intent)
        }
    }

    /// Show error feedback for failed interactions
    private func showInteractionError(for intent: PostActionIntent) {
        // Set error state for UI to display
        let actionName: String
        switch intent {
        case .like:
            actionName = "like"
        case .repost:
            actionName = "repost"
        }

        error = ServiceError.networkError(
            underlying: NSError(
                domain: "InteractionError", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to \(actionName) post. Please try again."
                ]))
    }

    /// Update a specific post in place
    private func updatePostInPlace(_ postId: String, update: (inout Post) -> Void) {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return }
        update(&posts[index])
    }
}

// MARK: - Post Action Intent

/// Intent pattern for post actions to prevent AttributeGraph cycles
private enum PostActionIntent {
    case like(post: Post)
    case repost(post: Post)

    var postId: String {
        switch self {
        case .like(let post), .repost(let post):
            return post.id
        }
    }
}

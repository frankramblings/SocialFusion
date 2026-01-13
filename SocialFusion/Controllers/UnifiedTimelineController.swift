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

    // MARK: - Scroll Policy

    enum ScrollPolicy {
        case preserveViewport
        case jumpToNow
    }

    var scrollPolicy: ScrollPolicy = .preserveViewport
    private var currentAnchorId: String?

    // MARK: - Private Properties

    private let serviceManager: SocialServiceManager
    private let actionStore: PostActionStore
    private let actionCoordinator: PostActionCoordinator
    private let relationshipStore: RelationshipStore
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

    // MARK: - Initialization

    init(serviceManager: SocialServiceManager) {
        self.serviceManager = serviceManager
        self.actionStore = serviceManager.postActionStore
        self.actionCoordinator = serviceManager.postActionCoordinator
        self.relationshipStore = serviceManager.relationshipStore
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
        // Anchor & Compensate: Capture anchor before update
        if scrollPolicy == .preserveViewport {
            self.restorationAnchor = currentAnchorId
        } else {
            self.restorationAnchor = nil
            // Reset policy to default after explicit jump
            scrollPolicy = .preserveViewport
        }

        // Filter posts based on blocked/muted actors
        let filteredPosts = filterPosts(newPosts)

        self.posts = filteredPosts
        if FeatureFlagManager.isEnabled(.postActionsV2) {
            filteredPosts.forEach { post in
                actionStore.ensureState(for: post)
            }
        }
        self.lastRefreshDate = Date()
        refreshCoordinator.handleVisibleTimelineUpdate(filteredPosts)

        if !isInitialized {
            isInitialized = true
        }
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

    /// Refresh timeline with async/await for pull-to-refresh
    func refreshTimelineAsync() async {
        // Remove the guard - pull-to-refresh should always be allowed
        // The service manager will handle preventing duplicate refreshes properly
        
        // Ensure we preserve viewport position during pull-to-refresh
        // This allows new posts to appear above the user's current position
        scrollPolicy = .preserveViewport

        await refreshCoordinator.manualRefresh(intent: .manualRefresh)
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
            // Error is automatically propagated via binding
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
        refreshCoordinator.mergeBufferedPostsIfNeeded()
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
        refreshCoordinator.handleAppForegrounded()
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

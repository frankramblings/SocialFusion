import Combine
import Foundation
import os.log

@MainActor
protocol PostActionNetworking: AnyObject {
    func like(post: Post) async throws -> PostActionState
    func unlike(post: Post) async throws -> PostActionState
    func repost(post: Post) async throws -> PostActionState
    func unrepost(post: Post) async throws -> PostActionState
    func follow(post: Post, shouldFollow: Bool) async throws -> PostActionState
    func mute(post: Post, shouldMute: Bool) async throws -> PostActionState
    func block(post: Post, shouldBlock: Bool) async throws -> PostActionState
    func fetchActions(for post: Post) async throws -> PostActionState
}

/// Coordinates optimistic UI updates and server reconciliation for post interactions
@MainActor
final class PostActionCoordinator: ObservableObject {
    // Dispatcher/Clock for deterministic scheduling and time
    protocol ActionDispatcher {
        func now() -> Date
        func schedule(_ operation: @escaping @Sendable () async -> Void)
    }

    struct DefaultActionDispatcher: ActionDispatcher {
        func now() -> Date { Date() }
        func schedule(_ operation: @escaping @Sendable () async -> Void) {
            Task { await operation() }
        }
    }

    private let store: PostActionStore
    private let service: PostActionNetworking
    private let networkMonitor: SimpleEdgeCaseMonitor
    private let logger = Logger(subsystem: "com.socialfusion", category: "PostActionCoordinator")
    private let dispatcher: ActionDispatcher

    private var cancellables = Set<AnyCancellable>()
    private var offlineQueue: [PostActionStore.ActionKey: PendingAction] = [:]
    private var deferredActions: [PostActionStore.ActionKey: PendingAction] = [:]
    private var inflightTasks: [PostActionStore.ActionKey: Task<Void, Never>] = [:]
    private var lastActionTimestamps: [PostActionStore.ActionKey: Date] = [:]
    private let debounceInterval: TimeInterval  // 300ms debounce window (overrideable)

    private let staleInterval: TimeInterval

    init(
        store: PostActionStore,
        service: PostActionNetworking,
        networkMonitor: SimpleEdgeCaseMonitor? = nil,
        staleInterval: TimeInterval = 60,
        debounceInterval: TimeInterval = 0.3,
        dispatcher: ActionDispatcher = DefaultActionDispatcher()
    ) {
        let monitor = networkMonitor ?? SimpleEdgeCaseMonitor.shared
        self.store = store
        self.service = service
        self.networkMonitor = monitor
        self.staleInterval = staleInterval
        self.debounceInterval = debounceInterval
        self.dispatcher = dispatcher

        observeNetworkAvailability()
    }

    deinit {
        inflightTasks.values.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    func toggleLike(for post: Post) {
        guard FeatureFlagManager.isEnabled(.postActionsV2) else { return }

        let key = post.stableId

        // Debounce: ignore if action happened too recently
        if let lastTimestamp = lastActionTimestamps[key],
            dispatcher.now().timeIntervalSince(lastTimestamp) < debounceInterval
        {
            logger.debug("Debouncing toggleLike for key \(key, privacy: .public)")
            return
        }

        lastActionTimestamps[key] = dispatcher.now()

        let currentState = store.ensureState(for: post)
        let shouldLike = !currentState.isLiked

        let previousState =
            shouldLike
            ? store.optimisticLike(for: key)
            : store.optimisticUnlike(for: key)

        guard let previous = previousState else { return }

        let action = PendingAction(
            post: post,
            intent: .like(shouldBeLiked: shouldLike),
            previousState: previous,
            timestamp: Date()
        )

        handle(action: action)
    }

    func toggleRepost(for post: Post) {
        guard FeatureFlagManager.isEnabled(.postActionsV2) else { return }

        let key = post.stableId

        // Debounce: ignore if action happened too recently
        if let lastTimestamp = lastActionTimestamps[key],
            dispatcher.now().timeIntervalSince(lastTimestamp) < debounceInterval
        {
            logger.debug("Debouncing toggleRepost for key \(key, privacy: .public)")
            return
        }

        lastActionTimestamps[key] = dispatcher.now()

        let currentState = store.ensureState(for: post)
        let shouldRepost = !currentState.isReposted

        let previousState =
            shouldRepost
            ? store.optimisticRepost(for: key)
            : store.optimisticUnrepost(for: key)

        guard let previous = previousState else { return }

        let action = PendingAction(
            post: post,
            intent: .repost(shouldBeReposted: shouldRepost),
            previousState: previous,
            timestamp: Date()
        )

        handle(action: action)
    }

    func follow(for post: Post, shouldFollow: Bool) {
        guard FeatureFlagManager.isEnabled(.postActionsV2) else { return }
        let key = post.stableId
        let currentState = store.ensureState(for: post)
        let previousState = store.optimisticFollow(for: key, shouldFollow: shouldFollow)
        guard let previous = previousState else { return }

        let action = PendingAction(
            post: post,
            intent: .follow(shouldFollow: shouldFollow),
            previousState: previous,
            timestamp: Date()
        )
        handle(action: action)
    }

    func mute(for post: Post, shouldMute: Bool) {
        guard FeatureFlagManager.isEnabled(.postActionsV2) else { return }
        let key = post.stableId
        let currentState = store.ensureState(for: post)
        let previousState = store.optimisticMute(for: key, shouldMute: shouldMute)
        guard let previous = previousState else { return }

        let action = PendingAction(
            post: post,
            intent: .mute(shouldMute: shouldMute),
            previousState: previous,
            timestamp: Date()
        )
        handle(action: action)
    }

    func block(for post: Post, shouldBlock: Bool) {
        guard FeatureFlagManager.isEnabled(.postActionsV2) else { return }
        let key = post.stableId
        let currentState = store.ensureState(for: post)
        let previousState = store.optimisticBlock(for: key, shouldBlock: shouldBlock)
        guard let previous = previousState else { return }

        let action = PendingAction(
            post: post,
            intent: .block(shouldBlock: shouldBlock),
            previousState: previous,
            timestamp: Date()
        )
        handle(action: action)
    }

    func registerReplySuccess(for post: Post) {
        guard FeatureFlagManager.isEnabled(.postActionsV2) else { return }

        store.ensureState(for: post)
        store.registerLocalReply(for: post.stableId)
    }

    func registerQuoteSuccess(for post: Post) {
        guard FeatureFlagManager.isEnabled(.postActionsV2) else { return }

        store.ensureState(for: post)
        store.registerLocalQuote(for: post.stableId)
    }

    func refreshIfStale(for post: Post) {
        guard FeatureFlagManager.isEnabled(.postActionsV2) else { return }

        let state = store.ensureState(for: post)
        let age = Date().timeIntervalSince(state.lastUpdatedAt)
        guard age >= staleInterval else { return }

        let action = PendingAction(
            post: post,
            intent: .refresh,
            previousState: state,
            timestamp: Date()
        )

        handle(action: action)
    }

    // MARK: - Private helpers

    private func handle(action: PendingAction) {
        let key = action.post.stableId

        if !networkMonitor.isNetworkAvailable {
            queueOffline(action)
            return
        }

        if let existingTask = inflightTasks[key] {
            if !existingTask.isCancelled {
                deferredActions[key] = action
                return
            }
        }

        execute(action)
    }

    private func queueOffline(_ action: PendingAction) {
        let key = action.post.stableId
        offlineQueue[key] = action
        store.setPending(true, for: key)
        logger.info("Queued action offline for key \(key, privacy: .public)")
    }

    private func execute(_ action: PendingAction) {
        let key = action.post.stableId

        store.setPending(false, for: key)
        store.setInflight(true, for: key)

        let scheduleOp: @Sendable () async -> Void = { [weak self] in
            guard let self else { return }
            do {
                let state = try await self.perform(action)
                await MainActor.run {
                    self.completeSuccess(for: key, with: state, post: action.post)
                }
            } catch {
                await MainActor.run {
                    self.completeFailure(for: key, action: action, error: error)
                }
            }
        }
        // Schedule once via Task (dispatcher injection still used for time/debounce)
        inflightTasks[key]?.cancel()
        let task = Task { await scheduleOp() }
        inflightTasks[key] = task
    }

    private func perform(_ action: PendingAction) async throws -> PostActionState {
        switch action.intent {
        case .like(let shouldBeLiked):
            if shouldBeLiked {
                return try await service.like(post: action.post)
            } else {
                return try await service.unlike(post: action.post)
            }
        case .repost(let shouldBeReposted):
            if shouldBeReposted {
                return try await service.repost(post: action.post)
            } else {
                return try await service.unrepost(post: action.post)
            }
        case .follow(let shouldFollow):
            return try await service.follow(post: action.post, shouldFollow: shouldFollow)
        case .mute(let shouldMute):
            return try await service.mute(post: action.post, shouldMute: shouldMute)
        case .block(let shouldBlock):
            return try await service.block(post: action.post, shouldBlock: shouldBlock)
        case .refresh:
            return try await service.fetchActions(for: action.post)
        }
    }

    private func completeSuccess(for key: PostActionStore.ActionKey, with state: PostActionState, post: Post) {
        inflightTasks[key] = nil
        store.setInflight(false, for: key)
        store.reconcile(from: state)
        
        // CRITICAL: Update the Post model to keep it in sync with PostActionStore
        // This ensures that when PostDetailView creates a PostViewModel, it reads the correct state
        // Use the reconciled state from the store to ensure consistency with reconcile logic
        // IMPORTANT: Preserve originalPost and boostedBy - these should never be cleared by action updates
        let preservedOriginalPost = post.originalPost
        let preservedBoostedBy = post.boostedBy
        
        if let reconciledState = store.state(for: key) {
            post.isLiked = reconciledState.isLiked
            post.isReposted = reconciledState.isReposted
            post.likeCount = reconciledState.likeCount
            post.repostCount = reconciledState.repostCount
            post.replyCount = reconciledState.replyCount
            post.isReplied = reconciledState.isReplied
            post.isQuoted = reconciledState.isQuoted
            post.isFollowingAuthor = reconciledState.isFollowingAuthor
            post.isMutedAuthor = reconciledState.isMutedAuthor
            post.isBlockedAuthor = reconciledState.isBlockedAuthor
        } else {
            // Fallback to server state if reconciled state not available
            post.isLiked = state.isLiked
            post.isReposted = state.isReposted
            post.likeCount = state.likeCount
            post.repostCount = state.repostCount
            post.replyCount = state.replyCount
            post.isReplied = state.isReplied
            post.isQuoted = state.isQuoted
            post.isFollowingAuthor = state.isFollowingAuthor
            post.isMutedAuthor = state.isMutedAuthor
            post.isBlockedAuthor = state.isBlockedAuthor
        }
        
        // CRITICAL: Restore originalPost and boostedBy if they were accidentally cleared
        // These properties are essential for boost banners and should never be lost
        // CRITICAL FIX: Set synchronously - this happens during state reconciliation, not during view updates
        // Since we removed objectWillChange.send() from didSet handlers, setting these properties
        // won't trigger "Publishing changes from within view updates" warnings
        if post.originalPost == nil && preservedOriginalPost != nil {
            post.originalPost = preservedOriginalPost
            logger.warning("Restored originalPost for key \(key, privacy: .public) - it was cleared during update")
        }
        if post.boostedBy == nil && preservedBoostedBy != nil {
            post.boostedBy = preservedBoostedBy
            logger.warning("Restored boostedBy for key \(key, privacy: .public) - it was cleared during update")
        }
        
        logger.debug("Reconciled state for key \(key, privacy: .public) and updated Post model")
        drainDeferredActionIfNeeded(for: key)
    }

    private func completeFailure(
        for key: PostActionStore.ActionKey,
        action: PendingAction,
        error: Error
    ) {
        inflightTasks[key] = nil
        store.setInflight(false, for: key)

        if let previous = action.previousState {
            store.revert(to: previous)
        }

        let actionType = String(describing: action.intent)
        logger.error(
            "Failed to perform \(actionType, privacy: .public) for key \(key, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )

        let shouldRequeue = isNetworkDowntime(error)
        if shouldRequeue {
            queueOffline(action)
        }

        ErrorHandler.shared.handleError(error)
        drainDeferredActionIfNeeded(for: key)
    }

    private func drainDeferredActionIfNeeded(for key: PostActionStore.ActionKey) {
        guard let next = deferredActions.removeValue(forKey: key) else { return }

        if !networkMonitor.isNetworkAvailable {
            queueOffline(next)
            return
        }

        execute(next)
    }

    // Exposed as internal for @testable unit tests to drive deterministic flushing
    func flushQueuedOfflineActions() {
        guard !offlineQueue.isEmpty else { return }

        let queued = offlineQueue
        offlineQueue.removeAll()

        for (_, action) in queued {
            handle(action: action)
        }
    }

    private func observeNetworkAvailability() {
        networkMonitor.$isNetworkAvailable
            .removeDuplicates()
            .sink { [weak self] (available: Bool) in
                guard let self else { return }
                if available {
                    self.flushQueuedOfflineActions()
                }
            }
            .store(in: &cancellables)
    }

    private func isNetworkDowntime(_ error: Error) -> Bool {
        if let networkError = error as? NetworkError {
            switch networkError {
            case .networkUnavailable, .timeout, .serverError:
                return true
            default:
                return false
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return nsError.code == NSURLErrorNotConnectedToInternet
                || nsError.code == NSURLErrorTimedOut
                || nsError.code == NSURLErrorNetworkConnectionLost
        }

        return false
    }
}

extension PostActionCoordinator {
    fileprivate struct PendingAction {
        let post: Post
        let intent: ActionIntent
        let previousState: PostActionState?
        let timestamp: Date
    }

    fileprivate enum ActionIntent {
        case like(shouldBeLiked: Bool)
        case repost(shouldBeReposted: Bool)
        case follow(shouldFollow: Bool)
        case mute(shouldMute: Bool)
        case block(shouldBlock: Bool)
        case refresh
    }
}

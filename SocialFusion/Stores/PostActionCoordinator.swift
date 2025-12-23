import Combine
import Foundation
import os.log

@MainActor
protocol PostActionNetworking: AnyObject {
    func like(post: Post) async throws -> PostActionState
    func unlike(post: Post) async throws -> PostActionState
    func repost(post: Post) async throws -> PostActionState
    func unrepost(post: Post) async throws -> PostActionState
    func fetchActions(for post: Post) async throws -> PostActionState
}

/// Coordinates optimistic UI updates and server reconciliation for post interactions
@MainActor
final class PostActionCoordinator: ObservableObject {
    private let store: PostActionStore
    private let service: PostActionNetworking
    private let networkMonitor: SimpleEdgeCaseMonitor
    private let logger = Logger(subsystem: "com.socialfusion", category: "PostActionCoordinator")

    private var cancellables = Set<AnyCancellable>()
    private var offlineQueue: [PostActionStore.ActionKey: PendingAction] = [:]
    private var deferredActions: [PostActionStore.ActionKey: PendingAction] = [:]
    private var inflightTasks: [PostActionStore.ActionKey: Task<Void, Never>] = [:]
    private var lastActionTimestamps: [PostActionStore.ActionKey: Date] = [:]
    private let debounceInterval: TimeInterval = 0.3  // 300ms debounce window

    private let staleInterval: TimeInterval

    init(
        store: PostActionStore,
        service: PostActionNetworking,
        networkMonitor: SimpleEdgeCaseMonitor? = nil,
        staleInterval: TimeInterval = 60
    ) {
        let monitor = networkMonitor ?? SimpleEdgeCaseMonitor.shared
        self.store = store
        self.service = service
        self.networkMonitor = monitor
        self.staleInterval = staleInterval

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
            Date().timeIntervalSince(lastTimestamp) < debounceInterval
        {
            logger.debug("Debouncing toggleLike for key \(key, privacy: .public)")
            return
        }

        lastActionTimestamps[key] = Date()

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
            Date().timeIntervalSince(lastTimestamp) < debounceInterval
        {
            logger.debug("Debouncing toggleRepost for key \(key, privacy: .public)")
            return
        }

        lastActionTimestamps[key] = Date()

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

    func registerReplySuccess(for post: Post) {
        guard FeatureFlagManager.isEnabled(.postActionsV2) else { return }

        store.ensureState(for: post)
        store.registerLocalReply(for: post.stableId)
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

        let task = Task { [weak self] in
            guard let self else { return }

            do {
                let state = try await perform(action)
                await MainActor.run {
                    self.completeSuccess(for: key, with: state)
                }
            } catch {
                await MainActor.run {
                    self.completeFailure(for: key, action: action, error: error)
                }
            }
        }

        inflightTasks[key]?.cancel()
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
        case .refresh:
            return try await service.fetchActions(for: action.post)
        }
    }

    private func completeSuccess(for key: PostActionStore.ActionKey, with state: PostActionState) {
        inflightTasks[key] = nil
        store.setInflight(false, for: key)
        store.reconcile(from: state)
        logger.debug("Reconciled state for key \(key, privacy: .public)")
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

    private func flushQueuedOfflineActions() {
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
        case refresh
    }
}

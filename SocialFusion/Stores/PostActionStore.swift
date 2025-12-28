import Foundation
import os.log

/// Thin state container that centralizes optimistic post interaction state
@MainActor
final class PostActionStore: ObservableObject {
    typealias ActionKey = String

    @Published private(set) var actions: [ActionKey: PostActionState] = [:]
    @Published private(set) var pendingKeys: Set<ActionKey> = []
    @Published private(set) var inflightKeys: Set<ActionKey> = []

    private let logger = Logger(subsystem: "com.socialfusion", category: "PostActionStore")

    // MARK: - State Accessors

    @discardableResult
    func ensureState(for post: Post) -> PostActionState {
        let key = post.stableId
        if let existing = actions[key] {
            return existing
        }

        let snapshot = post.makeActionState()
        actions[key] = snapshot
        return snapshot
    }

    func state(for key: ActionKey) -> PostActionState? {
        actions[key]
    }

    func state(for post: Post) -> PostActionState {
        let key = post.stableId
        if let existing = actions[key] {
            return existing
        }
        // Return a snapshot from the post without modifying store during view reads
        // State will be created via ensureState when needed (e.g., during initialization or actions)
        return post.makeActionState()
    }

    // MARK: - Optimistic Mutations

    @discardableResult
    func optimisticLike(for key: ActionKey) -> PostActionState? {
        guard var current = actions[key] else {
            logger.debug("optimisticLike called without state for key \(key, privacy: .public)")
            return nil
        }

        guard current.isLiked == false else {
            return nil
        }

        let previous = current
        current.isLiked = true
        current.likeCount += 1
        current.lastUpdatedAt = Date()
        actions[key] = current
        return previous
    }

    @discardableResult
    func optimisticUnlike(for key: ActionKey) -> PostActionState? {
        guard var current = actions[key] else {
            logger.debug("optimisticUnlike called without state for key \(key, privacy: .public)")
            return nil
        }

        guard current.isLiked == true else {
            return nil
        }

        let previous = current
        current.isLiked = false
        current.likeCount = max(current.likeCount - 1, 0)
        current.lastUpdatedAt = Date()
        actions[key] = current
        return previous
    }

    @discardableResult
    func optimisticRepost(for key: ActionKey) -> PostActionState? {
        guard var current = actions[key] else {
            logger.debug("optimisticRepost called without state for key \(key, privacy: .public)")
            return nil
        }

        guard current.isReposted == false else {
            return nil
        }

        let previous = current
        current.isReposted = true
        current.repostCount += 1
        current.lastUpdatedAt = Date()
        actions[key] = current
        return previous
    }

    @discardableResult
    func optimisticUnrepost(for key: ActionKey) -> PostActionState? {
        guard var current = actions[key] else {
            logger.debug("optimisticUnrepost called without state for key \(key, privacy: .public)")
            return nil
        }

        guard current.isReposted == true else {
            return nil
        }

        let previous = current
        current.isReposted = false
        current.repostCount = max(current.repostCount - 1, 0)
        current.lastUpdatedAt = Date()
        actions[key] = current
        return previous
    }

    func registerLocalReply(for key: ActionKey) {
        guard var current = actions[key] else {
            logger.debug("registerLocalReply called without state for key \(key, privacy: .public)")
            return
        }

        current.replyCount += 1
        current.lastUpdatedAt = Date()
        actions[key] = current
    }

    @discardableResult
    func optimisticFollow(for key: ActionKey, shouldFollow: Bool) -> PostActionState? {
        guard var current = actions[key] else { return nil }
        let previous = current
        current.isFollowingAuthor = shouldFollow
        current.lastUpdatedAt = Date()
        actions[key] = current
        return previous
    }

    @discardableResult
    func optimisticMute(for key: ActionKey, shouldMute: Bool) -> PostActionState? {
        guard var current = actions[key] else { return nil }
        let previous = current
        current.isMutedAuthor = shouldMute
        current.lastUpdatedAt = Date()
        actions[key] = current
        return previous
    }

    @discardableResult
    func optimisticBlock(for key: ActionKey, shouldBlock: Bool) -> PostActionState? {
        guard var current = actions[key] else { return nil }
        let previous = current
        current.isBlockedAuthor = shouldBlock
        current.lastUpdatedAt = Date()
        actions[key] = current
        return previous
    }

    func revert(to state: PostActionState) {
        actions[state.stableId] = state.updated(with: Date())
    }

    func reconcile(from serverState: PostActionState) {
        actions[serverState.stableId] = serverState.updated(with: Date())
        pendingKeys.remove(serverState.stableId)
        inflightKeys.remove(serverState.stableId)
    }

    // MARK: - Pending & In-flight helpers

    func setPending(_ isPending: Bool, for key: ActionKey) {
        if isPending {
            pendingKeys.insert(key)
        } else {
            pendingKeys.remove(key)
        }
    }

    func setInflight(_ isInflight: Bool, for key: ActionKey) {
        if isInflight {
            inflightKeys.insert(key)
        } else {
            inflightKeys.remove(key)
        }
    }
}


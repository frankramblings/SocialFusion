import Foundation
import os.log

/// Thin state container that centralizes optimistic post interaction state
@MainActor
final class PostActionStore: ObservableObject {
    typealias ActionKey = String
    typealias AuthorKey = String

    @Published private(set) var actions: [ActionKey: PostActionState] = [:]
    @Published private(set) var pendingKeys: Set<ActionKey> = []
    @Published private(set) var inflightKeys: Set<ActionKey> = []

    /// Index from authorId to set of post stableIds for propagating author-level changes
    private var postsByAuthor: [AuthorKey: Set<ActionKey>] = [:]
    /// Reverse lookup from post stableId to authorId
    private var authorByPost: [ActionKey: AuthorKey] = [:]

    private let logger = Logger(subsystem: "com.socialfusion", category: "PostActionStore")

    // MARK: - State Accessors

    @discardableResult
    func ensureState(for post: Post) -> PostActionState {
        let key = post.stableId
        if var existing = actions[key] {
            if authorByPost[key] == nil {
                let authorKey = post.authorId
                if !authorKey.isEmpty {
                    authorByPost[key] = authorKey
                    postsByAuthor[authorKey, default: []].insert(key)
                }
            }
            // Sync state from latest server-backed post when not mid-action
            // This ensures that when posts are loaded from the server (e.g., on app launch),
            // the store state reflects the server's authoritative state for likes/reposts
            if !pendingKeys.contains(key), !inflightKeys.contains(key) {
                let newFollow = post.isFollowingAuthor
                let newMute = post.isMutedAuthor
                let newBlock = post.isBlockedAuthor
                let newLiked = post.isLiked
                let newReposted = post.isReposted
                let newLikeCount = post.likeCount
                let newRepostCount = post.repostCount
                let newReplyCount = post.replyCount
                let newReplied = post.isReplied
                let newQuoted = post.isQuoted

                let followChanged = existing.isFollowingAuthor != newFollow
                let muteChanged = existing.isMutedAuthor != newMute
                let blockChanged = existing.isBlockedAuthor != newBlock
                let likedChanged = existing.isLiked != newLiked
                let repostedChanged = existing.isReposted != newReposted
                let likeCountChanged = existing.likeCount != newLikeCount
                let repostCountChanged = existing.repostCount != newRepostCount
                let replyCountChanged = existing.replyCount != newReplyCount
                let repliedChanged = existing.isReplied != newReplied
                let quotedChanged = existing.isQuoted != newQuoted

                // Update if any state has changed
                if followChanged || muteChanged || blockChanged || likedChanged || repostedChanged ||
                    likeCountChanged || repostCountChanged || replyCountChanged || repliedChanged || quotedChanged {
                    existing.isFollowingAuthor = newFollow
                    existing.isMutedAuthor = newMute
                    existing.isBlockedAuthor = newBlock
                    existing.isLiked = newLiked
                    existing.isReposted = newReposted
                    existing.likeCount = newLikeCount
                    existing.repostCount = newRepostCount
                    // Only update reply count if server has higher value (server is authoritative for increases)
                    if newReplyCount > existing.replyCount {
                        existing.replyCount = newReplyCount
                    }
                    // Update isReplied if server says it's true
                    if newReplied {
                        existing.isReplied = newReplied
                    }
                    // Update isQuoted if server says it's true
                    if newQuoted {
                        existing.isQuoted = newQuoted
                    }
                    existing.lastUpdatedAt = Date()
                    actions[key] = existing

                    if followChanged { propagateFollowState(fromKey: key, shouldFollow: newFollow) }
                    if muteChanged { propagateMuteState(fromKey: key, shouldMute: newMute) }
                    if blockChanged { propagateBlockState(fromKey: key, shouldBlock: newBlock) }
                    
                    if likedChanged || likeCountChanged || repostedChanged || repostCountChanged {
                        logger.debug("Synced like/repost state from server for key \(key, privacy: .public): liked=\(newLiked), reposted=\(newReposted)")
                    }
                }
            }
            return actions[key] ?? existing
        }

        let snapshot = post.makeActionState()
        actions[key] = snapshot

        // Track author index for propagation
        let authorKey = post.authorId
        if !authorKey.isEmpty {
            authorByPost[key] = authorKey
            postsByAuthor[authorKey, default: []].insert(key)
        }

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

        current.isReplied = true
        current.replyCount += 1
        current.lastUpdatedAt = Date()
        actions[key] = current
    }

    func registerLocalQuote(for key: ActionKey) {
        guard var current = actions[key] else {
            logger.debug("registerLocalQuote called without state for key \(key, privacy: .public)")
            return
        }

        current.isQuoted = true
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

        // Propagate to all posts by the same author
        propagateFollowState(fromKey: key, shouldFollow: shouldFollow)

        return previous
    }

    @discardableResult
    func optimisticMute(for key: ActionKey, shouldMute: Bool) -> PostActionState? {
        guard var current = actions[key] else { return nil }
        let previous = current
        current.isMutedAuthor = shouldMute
        current.lastUpdatedAt = Date()
        actions[key] = current

        // Propagate to all posts by the same author
        propagateMuteState(fromKey: key, shouldMute: shouldMute)

        return previous
    }

    @discardableResult
    func optimisticBlock(for key: ActionKey, shouldBlock: Bool) -> PostActionState? {
        guard var current = actions[key] else { return nil }
        let previous = current
        current.isBlockedAuthor = shouldBlock
        current.lastUpdatedAt = Date()
        actions[key] = current

        // Propagate to all posts by the same author
        propagateBlockState(fromKey: key, shouldBlock: shouldBlock)

        return previous
    }

    // MARK: - Author-Level Propagation

    private func propagateFollowState(fromKey sourceKey: ActionKey, shouldFollow: Bool) {
        guard let authorKey = authorByPost[sourceKey],
              let siblingKeys = postsByAuthor[authorKey]
        else { return }

        let now = Date()
        for key in siblingKeys where key != sourceKey {
            guard var state = actions[key] else { continue }
            state.isFollowingAuthor = shouldFollow
            state.lastUpdatedAt = now
            actions[key] = state
        }

        logger.debug("Propagated follow state to \(siblingKeys.count - 1) sibling posts for author \(authorKey, privacy: .public)")
    }

    private func propagateMuteState(fromKey sourceKey: ActionKey, shouldMute: Bool) {
        guard let authorKey = authorByPost[sourceKey],
              let siblingKeys = postsByAuthor[authorKey]
        else { return }

        let now = Date()
        for key in siblingKeys where key != sourceKey {
            guard var state = actions[key] else { continue }
            state.isMutedAuthor = shouldMute
            state.lastUpdatedAt = now
            actions[key] = state
        }

        logger.debug("Propagated mute state to \(siblingKeys.count - 1) sibling posts for author \(authorKey, privacy: .public)")
    }

    private func propagateBlockState(fromKey sourceKey: ActionKey, shouldBlock: Bool) {
        guard let authorKey = authorByPost[sourceKey],
              let siblingKeys = postsByAuthor[authorKey]
        else { return }

        let now = Date()
        for key in siblingKeys where key != sourceKey {
            guard var state = actions[key] else { continue }
            state.isBlockedAuthor = shouldBlock
            state.lastUpdatedAt = now
            actions[key] = state
        }

        logger.debug("Propagated block state to \(siblingKeys.count - 1) sibling posts for author \(authorKey, privacy: .public)")
    }

    func revert(to state: PostActionState) {
        actions[state.stableId] = state.updated(with: Date())
    }

    func reconcile(from serverState: PostActionState) {
        let key = serverState.stableId

        // Capture existing relationship state for comparison
        let existingFollow = actions[key]?.isFollowingAuthor
        let existingMute = actions[key]?.isMutedAuthor
        let existingBlock = actions[key]?.isBlockedAuthor

        // Merge intelligently: preserve counts that weren't part of the action
        // If we have existing state, merge server state with existing state
        if var existing = actions[key] {
            // Update action-specific fields from server
            existing.isLiked = serverState.isLiked
            existing.isReposted = serverState.isReposted
            existing.likeCount = serverState.likeCount
            existing.repostCount = serverState.repostCount

            // Preserve replyCount and isReplied from existing state if server state has zero/missing
            // Only update if server state has a higher value (server is authoritative for increases)
            if serverState.replyCount > existing.replyCount {
                existing.replyCount = serverState.replyCount
            }
            // Preserve isReplied unless server explicitly says it's true
            if serverState.isReplied {
                existing.isReplied = true
            }

            // Preserve isQuoted similarly
            if serverState.isQuoted {
                existing.isQuoted = true
            }

            // Update author relationship fields
            existing.isFollowingAuthor = serverState.isFollowingAuthor
            existing.isMutedAuthor = serverState.isMutedAuthor
            existing.isBlockedAuthor = serverState.isBlockedAuthor

            existing.lastUpdatedAt = Date()
            actions[key] = existing
        } else {
            // No existing state, use server state as-is
            actions[key] = serverState.updated(with: Date())
        }

        // Propagate relationship changes to sibling posts by the same author
        if existingFollow != serverState.isFollowingAuthor {
            propagateFollowState(fromKey: key, shouldFollow: serverState.isFollowingAuthor)
        }
        if existingMute != serverState.isMutedAuthor {
            propagateMuteState(fromKey: key, shouldMute: serverState.isMutedAuthor)
        }
        if existingBlock != serverState.isBlockedAuthor {
            propagateBlockState(fromKey: key, shouldBlock: serverState.isBlockedAuthor)
        }

        pendingKeys.remove(key)
        inflightKeys.remove(key)
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

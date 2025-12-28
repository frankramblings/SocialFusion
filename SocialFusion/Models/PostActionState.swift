import Foundation

/// Lightweight representation of a post's interaction state used by the coordinator layer
public struct PostActionState: Codable, Equatable {
    public let stableId: String
    public let platform: SocialPlatform
    public var isLiked: Bool
    public var isReposted: Bool
    public var likeCount: Int
    public var repostCount: Int
    public var replyCount: Int
    public var isFollowingAuthor: Bool
    public var isMutedAuthor: Bool
    public var isBlockedAuthor: Bool
    public var lastUpdatedAt: Date

    public init(
        stableId: String,
        platform: SocialPlatform,
        isLiked: Bool,
        isReposted: Bool,
        likeCount: Int,
        repostCount: Int,
        replyCount: Int,
        isFollowingAuthor: Bool = false,
        isMutedAuthor: Bool = false,
        isBlockedAuthor: Bool = false,
        lastUpdatedAt: Date = Date()
    ) {
        self.stableId = stableId
        self.platform = platform
        self.isLiked = isLiked
        self.isReposted = isReposted
        self.likeCount = likeCount
        self.repostCount = repostCount
        self.replyCount = replyCount
        self.isFollowingAuthor = isFollowingAuthor
        self.isMutedAuthor = isMutedAuthor
        self.isBlockedAuthor = isBlockedAuthor
        self.lastUpdatedAt = lastUpdatedAt
    }
}

extension PostActionState {
    /// Creates an action state snapshot from a `Post`
    public init(post: Post, timestamp: Date = Date()) {
        self.init(
            stableId: post.stableId,
            platform: post.platform,
            isLiked: post.isLiked,
            isReposted: post.isReposted,
            likeCount: post.likeCount,
            repostCount: post.repostCount,
            replyCount: post.replyCount,
            isFollowingAuthor: post.isFollowingAuthor,
            isMutedAuthor: post.isMutedAuthor,
            isBlockedAuthor: post.isBlockedAuthor,
            lastUpdatedAt: timestamp
        )
    }

    /// Returns a copy updated with server state resolution timestamp
    public func updated(with timestamp: Date) -> PostActionState {
        var copy = self
        copy.lastUpdatedAt = timestamp
        return copy
    }
}

extension Post {
    /// Helper to derive a `PostActionState` from the current post instance
    public func makeActionState(timestamp: Date = Date()) -> PostActionState {
        PostActionState(post: self, timestamp: timestamp)
    }
}


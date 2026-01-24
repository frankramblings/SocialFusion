import Foundation
import SwiftUI

/// Normalized user data used for booster lists and cross-platform UI.
public struct User: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String?
    public let username: String
    public let avatarURL: URL?
    public let isFollowedByMe: Bool
    public let followsMe: Bool
    public let isBlocked: Bool
    public let boostedAt: Date?
    public let displayNameEmojiMap: [String: String]?  // Custom emoji in display name

    public init(
        id: String,
        displayName: String? = nil,
        username: String,
        avatarURL: URL? = nil,
        isFollowedByMe: Bool = false,
        followsMe: Bool = false,
        isBlocked: Bool = false,
        boostedAt: Date? = nil,
        displayNameEmojiMap: [String: String]? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.username = username
        self.avatarURL = avatarURL
        self.isFollowedByMe = isFollowedByMe
        self.followsMe = followsMe
        self.isBlocked = isBlocked
        self.boostedAt = boostedAt
        self.displayNameEmojiMap = displayNameEmojiMap
    }
}

/// Normalized user identifier that works across platforms
public struct UserID: Hashable, Codable {
    public let value: String  // @handle@instance (Mastodon) or handle.bsky.social (Bluesky)
    public let platform: SocialPlatform

    public init(value: String, platform: SocialPlatform) {
        self.value = value
        self.platform = platform
    }
}

/// Canonical user identity using stable IDs (DID/account ID) with handle fallback
/// This ensures reliable identity matching across platforms and prevents collisions
public struct CanonicalUserID: Hashable, Codable, Sendable {
    public let platform: SocialPlatform
    public let stableID: String?  // DID (Bluesky) or account ID (Mastodon)
    public let normalizedHandle: String  // Normalized handle as fallback
    
    public init(platform: SocialPlatform, stableID: String?, normalizedHandle: String) {
        self.platform = platform
        self.stableID = stableID
        self.normalizedHandle = normalizedHandle
    }
    
    /// Create from a Post's author information
    public static func from(post: Post) -> CanonicalUserID {
        let normalized = CanonicalUserID.normalizeHandle(post.authorUsername, platform: post.platform)
        let stableID = post.authorId.isEmpty ? nil : post.authorId
        return CanonicalUserID(platform: post.platform, stableID: stableID, normalizedHandle: normalized)
    }
    
    /// Normalize a handle for comparison (lowercase, trim, strip leading @, normalize host casing)
    public static func normalizeHandle(_ handle: String, platform: SocialPlatform) -> String {
        var s = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Strip leading @
        if s.hasPrefix("@") {
            s.removeFirst()
        }
        
        // Lowercase for case-insensitive comparison
        s = s.lowercased()
        
        // For federated handles (Mastodon), normalize host casing
        if platform == .mastodon, let atIndex = s.firstIndex(of: "@") {
            let beforeAt = String(s[..<atIndex])
            let afterAt = String(s[s.index(after: atIndex)...])
            s = "\(beforeAt)@\(afterAt.lowercased())"
        }
        
        return s
    }
    
    /// Check if two canonical IDs match (using stable ID if available, else handle)
    public func matches(_ other: CanonicalUserID) -> Bool {
        guard platform == other.platform else { return false }
        
        // Prefer stable ID matching if both have it
        if let myStableID = stableID, let otherStableID = other.stableID {
            return myStableID == otherStableID
        }
        
        // Fall back to normalized handle matching
        return normalizedHandle == other.normalizedHandle
    }
    
    /// Convert to ActorID for relationship operations
    public func toActorID() -> ActorID {
        return ActorID(from: self)
    }
}

/// Abstract interface for resolving thread participants
public protocol ThreadParticipantResolver: Sendable {
    func getThreadParticipants(for post: Post) async throws -> Set<UserID>
}

/// Resolves the canonical identity of the reply target for a post
/// This is the user being replied to, not the thread participants
public protocol ReplyTargetResolver: Sendable {
    /// Resolve the canonical ID of the reply target
    /// Returns nil if the target cannot be determined (fail-closed)
    func resolveReplyTarget(for post: Post) async -> CanonicalUserID?
}

/// Unified reply target resolver that works across platforms
private actor ParentPostCache {
    private var cache: [String: Post] = [:]

    func get(_ id: String) -> Post? {
        return cache[id]
    }

    func set(_ id: String, post: Post) {
        cache[id] = post
    }

    func clear() {
        cache.removeAll()
    }
}

public final class UnifiedReplyTargetResolver: ReplyTargetResolver, @unchecked Sendable {
    private let mastodonService: MastodonService?
    private let blueskyService: BlueskyService?
    private let accountProvider: @Sendable () async -> [SocialAccount]
    private let parentPostCache = ParentPostCache()
    
    public init(
        mastodonService: MastodonService?,
        blueskyService: BlueskyService?,
        accountProvider: @escaping @Sendable () async -> [SocialAccount]
    ) {
        self.mastodonService = mastodonService
        self.blueskyService = blueskyService
        self.accountProvider = accountProvider
    }
    
    public func resolveReplyTarget(for post: Post) async -> CanonicalUserID? {
        // Prefer embedded parent post if available (most reliable)
        if let parent = post.parent {
            return CanonicalUserID.from(post: parent)
        }
        
        // Try to resolve via inReplyToID if we have it
        guard let inReplyToID = post.inReplyToID else {
            // No reply indicators - this shouldn't be a reply, but fail-closed
            return nil
        }
        
        // Check cache first
        if let cached = await parentPostCache.get(inReplyToID) {
            return CanonicalUserID.from(post: cached)
        }
        
        // Fetch parent post based on platform
        let parentPost: Post?
        switch post.platform {
        case .mastodon:
            guard let service = mastodonService,
                  let account = await accountProvider().first(where: { $0.platform == .mastodon }) else {
                return nil
            }
            do {
                // Try fetchPostByID first, fall back to fetchStatus if needed
                if let post = try await service.fetchPostByID(inReplyToID, account: account) {
                    parentPost = post
                } else {
                    // Fallback to fetchStatus
                    parentPost = try await service.fetchStatus(id: inReplyToID, account: account)
                }
            } catch {
                // Fail-closed: if we can't fetch, exclude the reply
                return nil
            }
        case .bluesky:
            guard let service = blueskyService,
                  let account = await accountProvider().first(where: { $0.platform == .bluesky }) else {
                return nil
            }
            do {
                parentPost = try await service.fetchPostByID(inReplyToID, account: account)
            } catch {
                // Fail-closed: if we can't fetch, exclude the reply
                return nil
            }
        }
        
        guard let parent = parentPost else {
            return nil
        }
        
        // Cache for future use
        await parentPostCache.set(inReplyToID, post: parent)
        
        return CanonicalUserID.from(post: parent)
    }
    
    public func clearCache() {
        Task {
            await parentPostCache.clear()
        }
    }
}

/// Generic user profile information
public struct UserProfile: Codable, Sendable {
    public let id: String
    public let username: String
    public let displayName: String?
    public let avatarURL: String?
    public let headerURL: String?
    public let bio: String?
    public let followersCount: Int
    public let followingCount: Int
    public let statusesCount: Int
    public let platform: SocialPlatform
    public var following: Bool?
    public var followedBy: Bool?
    public var muting: Bool?
    public var blocking: Bool?

    public init(
        id: String,
        username: String,
        displayName: String? = nil,
        avatarURL: String? = nil,
        headerURL: String? = nil,
        bio: String? = nil,
        followersCount: Int = 0,
        followingCount: Int = 0,
        statusesCount: Int = 0,
        platform: SocialPlatform,
        following: Bool? = nil,
        followedBy: Bool? = nil,
        muting: Bool? = nil,
        blocking: Bool? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.headerURL = headerURL
        self.bio = bio
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.statusesCount = statusesCount
        self.platform = platform
        self.following = following
        self.followedBy = followedBy
        self.muting = muting
        self.blocking = blocking
    }
}

public struct SearchResult: Sendable {
    public let posts: [Post]
    public let users: [SearchUser]
    public let tags: [SearchTag]

    public init(posts: [Post] = [], users: [SearchUser] = [], tags: [SearchTag] = []) {
        self.posts = posts
        self.users = users
        self.tags = tags
    }
}

public struct SearchUser: Identifiable, Sendable {
    public let id: String
    public let username: String
    public let displayName: String?
    public let avatarURL: String?
    public let platform: SocialPlatform
    public let displayNameEmojiMap: [String: String]?

    public init(
        id: String, username: String, displayName: String? = nil, avatarURL: String? = nil,
        platform: SocialPlatform, displayNameEmojiMap: [String: String]? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.platform = platform
        self.displayNameEmojiMap = displayNameEmojiMap
    }
}

public struct SearchTag: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let platform: SocialPlatform

    public init(id: String, name: String, platform: SocialPlatform) {
        self.id = id
        self.name = name
        self.platform = platform
    }
}

public struct AppNotification: Identifiable, Sendable {
    public let id: String
    public let type: NotificationType
    public let createdAt: Date
    public let account: SocialAccount
    public let fromAccount: NotificationAccount
    public let post: Post?

    public enum NotificationType: String, Sendable {
        case mention
        case repost
        case like
        case follow
        case poll
        case update
    }

    public init(
        id: String, type: NotificationType, createdAt: Date, account: SocialAccount,
        fromAccount: NotificationAccount, post: Post? = nil
    ) {
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.account = account
        self.fromAccount = fromAccount
        self.post = post
    }
}

/// Coordinator for filtering posts in the feed based on reply logic
public class PostFeedFilter {
    private let replyTargetResolver: ReplyTargetResolver

    /// Feature flag to enable/disable filtering
    public var isReplyFilteringEnabled: Bool = true

    /// Keyword filtering
    public var blockedKeywords: [String] = []
    public var isKeywordFilteringEnabled: Bool = true

    public init(replyTargetResolver: ReplyTargetResolver) {
        self.replyTargetResolver = replyTargetResolver
    }
    
    // Legacy initializer for backward compatibility
    public convenience init(
        mastodonResolver: ThreadParticipantResolver?, blueskyResolver: ThreadParticipantResolver?
    ) {
        // Create a dummy resolver - this path should not be used with strict filtering
        let dummyResolver = UnifiedReplyTargetResolver(
            mastodonService: nil,
            blueskyService: nil,
            accountProvider: { [] }
        )
        self.init(replyTargetResolver: dummyResolver)
    }

    /// Determines if a post should be included in the feed
    public func shouldIncludePost(_ post: Post, followedAccounts: Set<CanonicalUserID>) async -> Bool {
        // Keyword filtering
        if isKeywordFilteringEnabled && !blockedKeywords.isEmpty {
            let lowercasedContent = post.content.lowercased()
            for keyword in blockedKeywords {
                if lowercasedContent.contains(keyword.lowercased()) {
                    DebugLog.verbose("🚫 Filtered out post \(post.id) - matched blocked keyword: \(keyword)")
                    return false
                }
            }
        }

        // Reply filtering
        return await shouldIncludeReply(post, followedAccounts: followedAccounts)
    }

    /// Strict reply filtering: only include replies if:
    /// 1. The reply target is followed, OR
    /// 2. It is a self-reply (author replying to themselves)
    /// Boosts are never filtered.
    /// Fails closed: if reply target cannot be determined, exclude the reply.
    public func shouldIncludeReply(_ post: Post, followedAccounts: Set<CanonicalUserID>) async -> Bool {
        // Rule: If filtering is disabled, always show
        guard isReplyFilteringEnabled else { return true }

        // Rule: NEVER filter boosts - they must always appear
        if post.boostedBy != nil || post.originalPost != nil {
            return true
        }

        // Rule: Always show top-level posts (not replies)
        guard post.isReply else { return true }

        // Get canonical identity of the post author
        let authorID = post.authorCanonicalID
        
        // Check if author is followed
        let isAuthorFollowed = followedAccounts.contains { $0.matches(authorID) }

        // Resolve the reply target (the user being replied to)
        guard let replyTargetID = await replyTargetResolver.resolveReplyTarget(for: post) else {
            // Fail-closed: if we can't determine the reply target, exclude the reply
            DebugLog.verbose("🚫 Filtered out reply \(post.id) - cannot determine reply target")
            return false
        }

        // Rule: Show self-replies (author replying to themselves) from followed users
        if authorID.matches(replyTargetID) && isAuthorFollowed {
            DebugLog.verbose("✅ Including self-reply from followed user: \(post.id)")
            return true
        }

        // Rule: Show replies to followed users
        let isReplyTargetFollowed = followedAccounts.contains { $0.matches(replyTargetID) }
        if isReplyTargetFollowed {
            DebugLog.verbose("✅ Including reply to followed user: \(post.id)")
            return true
        }

        // Rule: Exclude all other replies
        DebugLog.verbose("🚫 Filtered out reply \(post.id) - reply target not followed")
        return false
    }

    public func clearCache() {
        if let unifiedResolver = replyTargetResolver as? UnifiedReplyTargetResolver {
            unifiedResolver.clearCache()
        }
    }
}

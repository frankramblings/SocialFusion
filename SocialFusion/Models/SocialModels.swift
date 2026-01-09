import Foundation
import SwiftUI

/// Normalized user identifier that works across platforms
public struct UserID: Hashable, Codable {
    public let value: String  // @handle@instance (Mastodon) or handle.bsky.social (Bluesky)
    public let platform: SocialPlatform

    public init(value: String, platform: SocialPlatform) {
        self.value = value
        self.platform = platform
    }
}

/// Abstract interface for resolving thread participants
public protocol ThreadParticipantResolver: Sendable {
    func getThreadParticipants(for post: Post) async throws -> Set<UserID>
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

    public init(
        id: String, username: String, displayName: String? = nil, avatarURL: String? = nil,
        platform: SocialPlatform
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.platform = platform
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
    private let mastodonResolver: ThreadParticipantResolver?
    private let blueskyResolver: ThreadParticipantResolver?

    /// Feature flag to enable/disable filtering
    public var isReplyFilteringEnabled: Bool = true

    /// Keyword filtering
    public var blockedKeywords: [String] = []
    public var isKeywordFilteringEnabled: Bool = true

    /// Thread participant cache (normalized handle -> participants)
    private var participantCache: [String: (participants: Set<UserID>, timestamp: Date)] = [:]
    private let cacheLock = NSLock()
    private let cacheTTL: TimeInterval = 300  // 5 minutes

    public init(
        mastodonResolver: ThreadParticipantResolver?, blueskyResolver: ThreadParticipantResolver?
    ) {
        self.mastodonResolver = mastodonResolver
        self.blueskyResolver = blueskyResolver
    }

    private func getCachedParticipants(for key: String) -> Set<UserID>? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = participantCache[key],
            Date().timeIntervalSince(cached.timestamp) < cacheTTL
        {
            return cached.participants
        }
        return nil
    }

    private func updateCache(for key: String, participants: Set<UserID>) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        participantCache[key] = (participants, Date())
    }

    /// Determines if a post should be included in the feed
    public func shouldIncludePost(_ post: Post, followedAccounts: Set<UserID>) async -> Bool {
        // Keyword filtering
        if isKeywordFilteringEnabled && !blockedKeywords.isEmpty {
            let lowercasedContent = post.content.lowercased()
            for keyword in blockedKeywords {
                if lowercasedContent.contains(keyword.lowercased()) {
                    print("🚫 Filtered out post \(post.id) - matched blocked keyword: \(keyword)")
                    return false
                }
            }
        }

        // Reply filtering
        return await shouldIncludeReply(post, followedAccounts: followedAccounts)
    }

    /// Determines if a post should be included in the feed based on reply filtering rules
    public func shouldIncludeReply(_ post: Post, followedAccounts: Set<UserID>) async -> Bool {
        // Rule: If filtering is disabled, always show
        guard isReplyFilteringEnabled else { return true }

        // Rule: Always show top-level posts
        guard post.inReplyToID != nil else { return true }

        // Debug logging for reply filtering
        let authorID = UserID(value: post.authorUsername, platform: post.platform)
        let isAuthorFollowed = followedAccounts.contains(authorID)
        print("🔍 Filtering reply: @\(post.authorUsername) -> @\(post.inReplyToUsername ?? "unknown")")
        print("   Author followed: \(isAuthorFollowed)")

        // Rule: Show self-replies (author replying to themselves) from followed users
        if let inReplyToUsername = post.inReplyToUsername,
           inReplyToUsername == post.authorUsername,
           followedAccounts.contains(authorID) {
            print("   ✅ Showing self-reply from followed user")
            return true
        }

        // Rule: Show replies to followed users
        if let inReplyToUsername = post.inReplyToUsername {
            let repliedToID = UserID(value: inReplyToUsername, platform: post.platform)
            let isRepliedToFollowed = followedAccounts.contains(repliedToID)
            print("   Replied-to followed: \(isRepliedToFollowed)")
            if isRepliedToFollowed {
                print("   ✅ Showing reply to followed user")
                return true
            }
        }

        // Rule: For other replies, check thread participants
        do {
            let participants = try await getParticipants(for: post)

            // Check if at least two participants are in the followed accounts list
            let followedInThread = participants.filter { followedAccounts.contains($0) }

            // Log for debugging
            if followedInThread.count < 2 {
                print(
                    "🚫 Filtered out reply from \(post.authorUsername) - insufficient followed participants in thread (\(followedInThread.count))"
                )
                return false
            }

            return true
        } catch {
            // Fail-safe: if we can't resolve the thread, show the post
            print(
                "⚠️ PostFeedFilter: Error resolving thread participants for post \(post.id): \(error.localizedDescription)"
            )
            return true
        }
    }

    private func getParticipants(for post: Post) async throws -> Set<UserID> {
        let cacheKey = post.stableId

        // Check cache
        if let cached = getCachedParticipants(for: cacheKey) {
            return cached
        }

        // Resolve based on platform
        let participants: Set<UserID>
        switch post.platform {
        case .mastodon:
            guard let resolver = mastodonResolver else { return [] }
            participants = try await resolver.getThreadParticipants(for: post)
        case .bluesky:
            guard let resolver = blueskyResolver else { return [] }
            participants = try await resolver.getThreadParticipants(for: post)
        }

        // Update cache
        updateCache(for: cacheKey, participants: participants)

        return participants
    }

    public func clearCache() {
        cacheLock.lock()
        participantCache.removeAll()
        cacheLock.unlock()
    }
}

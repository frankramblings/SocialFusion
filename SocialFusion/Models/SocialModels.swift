import Foundation
import SwiftUI

/// Normalized user identifier that works across platforms
public struct UserID: Hashable, Codable {
    public let value: String      // @handle@instance (Mastodon) or handle.bsky.social (Bluesky)
    public let platform: SocialPlatform
    
    public init(value: String, platform: SocialPlatform) {
        self.value = value
        self.platform = platform
    }
}

/// Abstract interface for resolving thread participants
public protocol ThreadParticipantResolver {
    func getThreadParticipants(for post: Post) async throws -> Set<UserID>
}

/// Coordinator for filtering posts in the feed based on reply logic
public class PostFeedFilter {
    private let mastodonResolver: ThreadParticipantResolver?
    private let blueskyResolver: ThreadParticipantResolver?
    
    /// Feature flag to enable/disable filtering
    public var isReplyFilteringEnabled: Bool = true
    
    /// Thread participant cache (normalized handle -> participants)
    private var participantCache: [String: (participants: Set<UserID>, timestamp: Date)] = [:]
    private let cacheLock = NSLock()
    private let cacheTTL: TimeInterval = 300 // 5 minutes
    
    public init(mastodonResolver: ThreadParticipantResolver?, blueskyResolver: ThreadParticipantResolver?) {
        self.mastodonResolver = mastodonResolver
        self.blueskyResolver = blueskyResolver
    }
    
    /// Determines if a post should be included in the feed based on reply filtering rules
    public func shouldIncludeReply(_ post: Post, followedAccounts: Set<UserID>) async -> Bool {
        // Rule: If filtering is disabled, always show
        guard isReplyFilteringEnabled else { return true }
        
        // Rule: Always show top-level posts
        guard post.inReplyToID != nil else { return true }
        
        // Rule: Always show self-replies from followed users (thread continuation)
        let authorID = UserID(value: post.authorUsername, platform: post.platform)
        if followedAccounts.contains(authorID) {
            return true
        }
        
        // Rule: For other replies, check thread participants
        do {
            let participants = try await getParticipants(for: post)
            
            // Check if at least two participants are in the followed accounts list
            let followedInThread = participants.filter { followedAccounts.contains($0) }
            
            // Log for debugging
            if followedInThread.count < 2 {
                print("🚫 Filtered out reply from \(post.authorUsername) - insufficient followed participants in thread (\(followedInThread.count))")
                return false
            }
            
            return true
        } catch {
            // Fail-safe: if we can't resolve the thread, show the post
            print("⚠️ PostFeedFilter: Error resolving thread participants for post \(post.id): \(error.localizedDescription)")
            return true
        }
    }
    
    private func getParticipants(for post: Post) async throws -> Set<UserID> {
        let cacheKey = post.stableId
        
        // Check cache
        cacheLock.lock()
        if let cached = participantCache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            cacheLock.unlock()
            return cached.participants
        }
        cacheLock.unlock()
        
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
        cacheLock.lock()
        participantCache[cacheKey] = (participants, Date())
        cacheLock.unlock()
        
        return participants
    }
    
    public func clearCache() {
        cacheLock.lock()
        participantCache.removeAll()
        cacheLock.unlock()
    }
}

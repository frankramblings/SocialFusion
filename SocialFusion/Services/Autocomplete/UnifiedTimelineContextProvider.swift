import Foundation

/// Concrete implementation of TimelineContextProvider
/// Maintains compact snapshots of timeline context for autocomplete ranking
@MainActor
public class UnifiedTimelineContextProvider: TimelineContextProvider {
  
  // MARK: - Configuration
  
  private let maxAuthors = 50
  private let maxMentions = 30
  private let maxHashtags = 30
  private let maxPostsToAnalyze = 200 // Limit analysis to recent posts
  
  // MARK: - State
  
  private var snapshots: [AutocompleteTimelineScope: TimelineContextSnapshot] = [:]
  
  // MARK: - Initialization
  
  public init() {
    // Initialize with empty snapshots
  }
  
  // MARK: - TimelineContextProvider
  
  public func snapshot(for scope: AutocompleteTimelineScope) -> TimelineContextSnapshot {
    return snapshots[scope] ?? TimelineContextSnapshot()
  }
  
  public func updateSnapshot(posts: [Post], scope: AutocompleteTimelineScope) {
    // Limit to recent posts for performance
    let recentPosts = Array(posts.prefix(maxPostsToAnalyze))
    
    // Extract context from posts
    let authors = extractAuthors(from: recentPosts)
    let mentions = extractMentions(from: recentPosts)
    let hashtags = extractHashtags(from: recentPosts)
    
    // Extract conversation participants for thread scope
    var conversationParticipants: [AuthorContext] = []
    if case .thread(let postId) = scope {
      conversationParticipants = extractThreadParticipants(from: recentPosts, threadRootId: postId)
    }
    
    // Create snapshot
    let snapshot = TimelineContextSnapshot(
      recentAuthors: authors,
      recentMentions: mentions,
      recentHashtags: hashtags,
      conversationParticipants: conversationParticipants,
      snapshotTime: Date()
    )
    
    snapshots[scope] = snapshot
  }
  
  /// Extract conversation participants from a thread (for reply context)
  private func extractThreadParticipants(from posts: [Post], threadRootId: String) -> [AuthorContext] {
    // Find the thread root post
    guard let rootPost = posts.first(where: { $0.id == threadRootId }) else {
      return []
    }
    
    // Collect all unique authors from the thread (root + replies)
    var participantMap: [CanonicalUserID: AuthorContext] = [:]
    
    // Add root post author
    let rootAuthorID = rootPost.authorCanonicalID
    participantMap[rootAuthorID] = AuthorContext(
      canonicalID: rootAuthorID,
      displayName: rootPost.authorName.isEmpty ? nil : rootPost.authorName,
      username: rootPost.authorUsername,
      avatarURL: URL(string: rootPost.authorProfilePictureURL),
      isFollowed: rootPost.isFollowingAuthor,
      lastSeenAt: rootPost.createdAt,
      appearanceCount: 1
    )
    
    // Add authors from replies in the thread
    // Find replies by checking inReplyToID or parent relationships
    let threadReplies = posts.filter { post in
      post.inReplyToID == threadRootId || post.parent?.id == threadRootId || 
      (post.inReplyToID != nil && posts.contains(where: { $0.id == post.inReplyToID && ($0.id == threadRootId || $0.inReplyToID == threadRootId) }))
    }
    
    for reply in threadReplies {
      let authorID = reply.authorCanonicalID
      
      if var existing = participantMap[authorID] {
        // Update appearance count
        participantMap[authorID] = AuthorContext(
          canonicalID: authorID,
          displayName: reply.authorName.isEmpty ? nil : reply.authorName,
          username: reply.authorUsername,
          avatarURL: URL(string: reply.authorProfilePictureURL),
          isFollowed: reply.isFollowingAuthor,
          lastSeenAt: max(existing.lastSeenAt, reply.createdAt),
          appearanceCount: existing.appearanceCount + 1
        )
      } else {
        // New participant
        participantMap[authorID] = AuthorContext(
          canonicalID: authorID,
          displayName: reply.authorName.isEmpty ? nil : reply.authorName,
          username: reply.authorUsername,
          avatarURL: URL(string: reply.authorProfilePictureURL),
          isFollowed: reply.isFollowingAuthor,
          lastSeenAt: reply.createdAt,
          appearanceCount: 1
        )
      }
    }
    
    return Array(participantMap.values)
  }
  
  // MARK: - Private Extraction Methods
  
  private func extractAuthors(from posts: [Post]) -> [AuthorContext] {
    var authorMap: [CanonicalUserID: AuthorContext] = [:]
    
    for post in posts {
      let canonicalID = post.authorCanonicalID
      
      // Get or create author context
      if var context = authorMap[canonicalID] {
        // Update appearance count and recency
        let newCount = context.appearanceCount + 1
        let newLastSeen = max(context.lastSeenAt, post.createdAt)
        
        authorMap[canonicalID] = AuthorContext(
          canonicalID: canonicalID,
          displayName: post.authorName.isEmpty ? nil : post.authorName,
          username: post.authorUsername,
          avatarURL: URL(string: post.authorProfilePictureURL),
          isFollowed: post.isFollowingAuthor,
          lastSeenAt: newLastSeen,
          appearanceCount: newCount
        )
      } else {
        // Create new author context
        authorMap[canonicalID] = AuthorContext(
          canonicalID: canonicalID,
          displayName: post.authorName.isEmpty ? nil : post.authorName,
          username: post.authorUsername,
          avatarURL: URL(string: post.authorProfilePictureURL),
          isFollowed: post.isFollowingAuthor,
          lastSeenAt: post.createdAt,
          appearanceCount: 1
        )
      }
    }
    
    // Sort by recency and appearance count, then limit
    let sorted = Array(authorMap.values)
      .sorted { lhs, rhs in
        // More recent first
        if lhs.lastSeenAt != rhs.lastSeenAt {
          return lhs.lastSeenAt > rhs.lastSeenAt
        }
        // More appearances first
        if lhs.appearanceCount != rhs.appearanceCount {
          return lhs.appearanceCount > rhs.appearanceCount
        }
        // Followed accounts first
        if lhs.isFollowed != rhs.isFollowed {
          return lhs.isFollowed
        }
        return lhs.username < rhs.username
      }
    
    return Array(sorted.prefix(maxAuthors))
  }
  
  private func extractMentions(from posts: [Post]) -> [MentionContext] {
    var mentionMap: [String: MentionContext] = [:]
    
    for post in posts {
      // Extract mentions from post content and mentions array
      let allMentions = post.mentions
      
      for mention in allMentions {
        let normalized = mention.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let handle = normalized.hasPrefix("@") ? String(normalized.dropFirst()) : normalized
        
        if var context = mentionMap[handle] {
          // Update appearance count and recency
          let newCount = context.appearanceCount + 1
          let newLastSeen = max(context.lastSeenAt, post.createdAt)
          
          mentionMap[handle] = MentionContext(
            handle: mention,
            canonicalID: context.canonicalID, // Preserve if we had one
            lastSeenAt: newLastSeen,
            appearanceCount: newCount
          )
        } else {
          // Try to find canonical ID from post's author if mention matches
          // This is a best-effort match - we don't have full user lookup here
          let canonicalID: CanonicalUserID? = nil // Could be enhanced with user lookup
          
          mentionMap[handle] = MentionContext(
            handle: mention,
            canonicalID: canonicalID,
            lastSeenAt: post.createdAt,
            appearanceCount: 1
          )
        }
      }
    }
    
    // Sort by recency and appearance count, then limit
    let sorted = Array(mentionMap.values)
      .sorted { lhs, rhs in
        if lhs.lastSeenAt != rhs.lastSeenAt {
          return lhs.lastSeenAt > rhs.lastSeenAt
        }
        if lhs.appearanceCount != rhs.appearanceCount {
          return lhs.appearanceCount > rhs.appearanceCount
        }
        return lhs.handle < rhs.handle
      }
    
    return Array(sorted.prefix(maxMentions))
  }
  
  private func extractHashtags(from posts: [Post]) -> [HashtagContext] {
    var hashtagMap: [String: HashtagContext] = [:]
    
    for post in posts {
      // Extract hashtags from post tags array
      let tags = post.tags
      
      for tag in tags {
        let normalized = tag.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTag = normalized.hasPrefix("#") ? String(normalized.dropFirst()) : normalized
        
        if var context = hashtagMap[cleanTag] {
          // Update appearance count and recency
          let newCount = context.appearanceCount + 1
          let newLastSeen = max(context.lastSeenAt, post.createdAt)
          
          hashtagMap[cleanTag] = HashtagContext(
            tag: tag,
            lastSeenAt: newLastSeen,
            appearanceCount: newCount
          )
        } else {
          hashtagMap[cleanTag] = HashtagContext(
            tag: tag,
            lastSeenAt: post.createdAt,
            appearanceCount: 1
          )
        }
      }
    }
    
    // Sort by recency and appearance count, then limit
    let sorted = Array(hashtagMap.values)
      .sorted { lhs, rhs in
        if lhs.lastSeenAt != rhs.lastSeenAt {
          return lhs.lastSeenAt > rhs.lastSeenAt
        }
        if lhs.appearanceCount != rhs.appearanceCount {
          return lhs.appearanceCount > rhs.appearanceCount
        }
        return lhs.tag < rhs.tag
      }
    
    return Array(sorted.prefix(maxHashtags))
  }
}

import Foundation

/// Scope for timeline context (which timeline to query for autocomplete)
public enum AutocompleteTimelineScope: Hashable, Sendable {
  case unified
  case account(SocialAccount)
  case thread(String) // Post ID for reply context
  
  public func hash(into hasher: inout Hasher) {
    switch self {
    case .unified:
      hasher.combine("unified")
    case .account(let account):
      hasher.combine("account")
      hasher.combine(account.id)
    case .thread(let postId):
      hasher.combine("thread")
      hasher.combine(postId)
    }
  }
  
  public static func == (lhs: AutocompleteTimelineScope, rhs: AutocompleteTimelineScope) -> Bool {
    switch (lhs, rhs) {
    case (.unified, .unified):
      return true
    case (.account(let lhsAccount), .account(let rhsAccount)):
      return lhsAccount.id == rhsAccount.id
    case (.thread(let lhsId), .thread(let rhsId)):
      return lhsId == rhsId
    default:
      return false
    }
  }
}

/// Snapshot of timeline context for autocomplete ranking
public struct TimelineContextSnapshot: Sendable {
  /// Recent authors (last N posts, ordered by recency)
  public let recentAuthors: [AuthorContext]
  
  /// Recently seen mentions (from posts in timeline)
  public let recentMentions: [MentionContext]
  
  /// Recently seen hashtags (from posts in timeline)
  public let recentHashtags: [HashtagContext]
  
  /// Active conversation participants (if replying)
  public let conversationParticipants: [AuthorContext]
  
  /// Timestamp of snapshot (for recency weighting)
  public let snapshotTime: Date
  
  public init(
    recentAuthors: [AuthorContext] = [],
    recentMentions: [MentionContext] = [],
    recentHashtags: [HashtagContext] = [],
    conversationParticipants: [AuthorContext] = [],
    snapshotTime: Date = Date()
  ) {
    self.recentAuthors = recentAuthors
    self.recentMentions = recentMentions
    self.recentHashtags = recentHashtags
    self.conversationParticipants = conversationParticipants
    self.snapshotTime = snapshotTime
  }
}

/// Author context with stable ID and relationship state
public struct AuthorContext: Identifiable, Hashable, Sendable {
  public let id: String // Canonical ID string representation
  public let canonicalID: CanonicalUserID
  public let displayName: String?
  public let username: String
  public let avatarURL: URL?
  public let isFollowed: Bool
  public let lastSeenAt: Date
  public let appearanceCount: Int // How many times in recent timeline
  
  public init(
    canonicalID: CanonicalUserID,
    displayName: String?,
    username: String,
    avatarURL: URL?,
    isFollowed: Bool,
    lastSeenAt: Date,
    appearanceCount: Int
  ) {
    self.canonicalID = canonicalID
    self.displayName = displayName
    self.username = username
    self.avatarURL = avatarURL
    self.isFollowed = isFollowed
    self.lastSeenAt = lastSeenAt
    self.appearanceCount = appearanceCount
    // Use stable ID if available, else normalized handle
    self.id = canonicalID.stableID ?? canonicalID.normalizedHandle
  }
  
  public func hash(into hasher: inout Hasher) {
    hasher.combine(canonicalID)
  }
  
  public static func == (lhs: AuthorContext, rhs: AuthorContext) -> Bool {
    lhs.canonicalID == rhs.canonicalID
  }
}

/// Mention/hashtag context from timeline
public struct MentionContext: Identifiable, Hashable, Sendable {
  public let id: String // Normalized handle
  public let handle: String
  public let canonicalID: CanonicalUserID?
  public let lastSeenAt: Date
  public let appearanceCount: Int
  
  public init(
    handle: String,
    canonicalID: CanonicalUserID?,
    lastSeenAt: Date,
    appearanceCount: Int
  ) {
    self.handle = handle
    self.canonicalID = canonicalID
    self.lastSeenAt = lastSeenAt
    self.appearanceCount = appearanceCount
    // Normalize handle for ID
    let normalized = handle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    self.id = normalized.hasPrefix("@") ? String(normalized.dropFirst()) : normalized
  }
  
  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
  
  public static func == (lhs: MentionContext, rhs: MentionContext) -> Bool {
    lhs.id == rhs.id
  }
}

public struct HashtagContext: Identifiable, Hashable, Sendable {
  public let id: String // Normalized tag
  public let tag: String
  public let lastSeenAt: Date
  public let appearanceCount: Int
  
  public init(
    tag: String,
    lastSeenAt: Date,
    appearanceCount: Int
  ) {
    self.tag = tag
    self.lastSeenAt = lastSeenAt
    self.appearanceCount = appearanceCount
    // Normalize tag for ID (lowercase, strip #)
    let normalized = tag.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    self.id = normalized.hasPrefix("#") ? String(normalized.dropFirst()) : normalized
  }
  
  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
  
  public static func == (lhs: HashtagContext, rhs: HashtagContext) -> Bool {
    lhs.id == rhs.id
  }
}

import Foundation

/// Cross-platform actor identifier for relationship operations
/// Abstracts platform-specific ID formats (Mastodon account ID vs Bluesky DID)
public enum ActorID: Hashable, Codable, Sendable {
  case mastodon(String)  // account ID or acct URI
  case bluesky(String)   // DID
  
  public var platform: SocialPlatform {
    switch self {
    case .mastodon:
      return .mastodon
    case .bluesky:
      return .bluesky
    }
  }
  
  /// Create from a CanonicalUserID
  public init(from canonicalID: CanonicalUserID) {
    if let stableID = canonicalID.stableID, !stableID.isEmpty {
      // Prefer stable ID (DID for Bluesky, account ID for Mastodon)
      switch canonicalID.platform {
      case .mastodon:
        self = .mastodon(stableID)
      case .bluesky:
        self = .bluesky(stableID)
      }
    } else {
      // Fall back to normalized handle
      switch canonicalID.platform {
      case .mastodon:
        self = .mastodon(canonicalID.normalizedHandle)
      case .bluesky:
        self = .bluesky(canonicalID.normalizedHandle)
      }
    }
  }
  
  /// Create from a Post's author
  public init(from post: Post) {
    self.init(from: post.authorCanonicalID)
  }
  
  /// Create from a SearchUser
  public init(from user: SearchUser) {
    // For SearchUser, we have id which should be the stable ID
    switch user.platform {
    case .mastodon:
      self = .mastodon(user.id)
    case .bluesky:
      self = .bluesky(user.id)
    }
  }
}

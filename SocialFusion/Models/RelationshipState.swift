import Foundation

/// Unified relationship state model that works across Mastodon and Bluesky
/// Represents the current relationship between the authenticated user and another actor
public struct RelationshipState: Equatable, Sendable {
  /// Whether the authenticated user is following this actor
  public var isFollowing: Bool
  
  /// Whether this actor follows the authenticated user ("Follows you")
  public var isFollowedBy: Bool
  
  /// Whether the authenticated user is muting this actor
  public var isMuting: Bool
  
  /// Whether the authenticated user is blocking this actor
  public var isBlocking: Bool
  
  /// Whether a follow request is pending (for private accounts)
  public var followRequested: Bool
  
  public init(
    isFollowing: Bool = false,
    isFollowedBy: Bool = false,
    isMuting: Bool = false,
    isBlocking: Bool = false,
    followRequested: Bool = false
  ) {
    self.isFollowing = isFollowing
    self.isFollowedBy = isFollowedBy
    self.isMuting = isMuting
    self.isBlocking = isBlocking
    self.followRequested = followRequested
  }
  
  /// Whether this is a mutual follow relationship
  public var isMutual: Bool {
    return isFollowing && isFollowedBy
  }
  
  /// Whether follow actions should be disabled (e.g., when blocked)
  public var canFollow: Bool {
    return !isBlocking
  }
}

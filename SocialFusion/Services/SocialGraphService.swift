import Foundation

/// Protocol for cross-platform relationship operations
/// Abstracts Mastodon and Bluesky relationship APIs behind a unified interface
public protocol SocialGraphService {
  /// Fetch the current relationship state for an actor
  func relationship(for actor: ActorID, account: SocialAccount) async throws -> RelationshipState
  
  /// Follow an actor
  func follow(_ actor: ActorID, account: SocialAccount) async throws -> RelationshipState
  
  /// Unfollow an actor
  func unfollow(_ actor: ActorID, account: SocialAccount) async throws -> RelationshipState
  
  /// Mute an actor
  func mute(_ actor: ActorID, account: SocialAccount) async throws -> RelationshipState
  
  /// Unmute an actor
  func unmute(_ actor: ActorID, account: SocialAccount) async throws -> RelationshipState
  
  /// Block an actor
  func block(_ actor: ActorID, account: SocialAccount) async throws -> RelationshipState
  
  /// Unblock an actor
  func unblock(_ actor: ActorID, account: SocialAccount) async throws -> RelationshipState
}

import Foundation

/// Mastodon implementation of SocialGraphService
public final class MastodonGraphService: SocialGraphService {
  private let mastodonService: MastodonService
  
  public init(mastodonService: MastodonService) {
    self.mastodonService = mastodonService
  }
  
  public func relationship(for actor: ActorID, account: SocialAccount) async throws -> RelationshipState {
    guard case .mastodon(let userId) = actor else {
      throw ServiceError.invalidInput(reason: "Invalid actor ID for Mastodon")
    }
    
    // Fetch relationship from Mastodon API
    let relationships = try await mastodonService.fetchRelationships(accountIds: [userId], account: account)
    guard let relationship = relationships.first else {
      // Default state if not found
      return RelationshipState()
    }
    
    return RelationshipState(
      isFollowing: relationship.following,
      isFollowedBy: relationship.followedBy,
      isMuting: relationship.muting,
      isBlocking: relationship.blocking,
      followRequested: relationship.requested
    )
  }
  
  public func follow(_ actor: ActorID, account: SocialAccount) async throws -> RelationshipState {
    guard case .mastodon(let userId) = actor else {
      throw ServiceError.invalidInput(reason: "Invalid actor ID for Mastodon")
    }
    
    let relationship = try await mastodonService.followAccount(userId: userId, account: account)
    return RelationshipState(
      isFollowing: relationship.following,
      isFollowedBy: relationship.followedBy,
      isMuting: relationship.muting,
      isBlocking: relationship.blocking,
      followRequested: relationship.requested
    )
  }
  
  public func unfollow(_ actor: ActorID, account: SocialAccount) async throws -> RelationshipState {
    guard case .mastodon(let userId) = actor else {
      throw ServiceError.invalidInput(reason: "Invalid actor ID for Mastodon")
    }
    
    let relationship = try await mastodonService.unfollowAccount(userId: userId, account: account)
    return RelationshipState(
      isFollowing: relationship.following,
      isFollowedBy: relationship.followedBy,
      isMuting: relationship.muting,
      isBlocking: relationship.blocking,
      followRequested: relationship.requested
    )
  }
  
  public func mute(_ actor: ActorID, account: SocialAccount) async throws -> RelationshipState {
    guard case .mastodon(let userId) = actor else {
      throw ServiceError.invalidInput(reason: "Invalid actor ID for Mastodon")
    }
    
    let relationship = try await mastodonService.muteAccount(userId: userId, account: account)
    return RelationshipState(
      isFollowing: relationship.following,
      isFollowedBy: relationship.followedBy,
      isMuting: relationship.muting,
      isBlocking: relationship.blocking,
      followRequested: relationship.requested
    )
  }
  
  public func unmute(_ actor: ActorID, account: SocialAccount) async throws -> RelationshipState {
    guard case .mastodon(let userId) = actor else {
      throw ServiceError.invalidInput(reason: "Invalid actor ID for Mastodon")
    }
    
    let relationship = try await mastodonService.unmuteAccount(userId: userId, account: account)
    return RelationshipState(
      isFollowing: relationship.following,
      isFollowedBy: relationship.followedBy,
      isMuting: relationship.muting,
      isBlocking: relationship.blocking,
      followRequested: relationship.requested
    )
  }
  
  public func block(_ actor: ActorID, account: SocialAccount) async throws -> RelationshipState {
    guard case .mastodon(let userId) = actor else {
      throw ServiceError.invalidInput(reason: "Invalid actor ID for Mastodon")
    }
    
    let relationship = try await mastodonService.blockAccount(userId: userId, account: account)
    return RelationshipState(
      isFollowing: relationship.following,
      isFollowedBy: relationship.followedBy,
      isMuting: relationship.muting,
      isBlocking: relationship.blocking,
      followRequested: relationship.requested
    )
  }
  
  public func unblock(_ actor: ActorID, account: SocialAccount) async throws -> RelationshipState {
    guard case .mastodon(let userId) = actor else {
      throw ServiceError.invalidInput(reason: "Invalid actor ID for Mastodon")
    }
    
    let relationship = try await mastodonService.unblockAccount(userId: userId, account: account)
    return RelationshipState(
      isFollowing: relationship.following,
      isFollowedBy: relationship.followedBy,
      isMuting: relationship.muting,
      isBlocking: relationship.blocking,
      followRequested: relationship.requested
    )
  }
}

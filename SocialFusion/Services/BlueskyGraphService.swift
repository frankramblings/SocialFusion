import Foundation

/// Bluesky implementation of SocialGraphService
public final class BlueskyGraphService: SocialGraphService {
  private let blueskyService: BlueskyService
  
  public init(blueskyService: BlueskyService) {
    self.blueskyService = blueskyService
  }
  
  public func relationship(for actor: ActorID, account: SocialAccount) async throws -> RelationshipState {
    guard case .bluesky(let identifier) = actor else {
      throw ServiceError.invalidInput(reason: "Invalid actor ID for Bluesky")
    }
    
    // Fetch profile which includes viewer state (getProfile accepts both DID and handle)
    let profile = try await blueskyService.getProfile(actor: identifier, account: account)
    guard let viewer = profile.viewer else {
      // Default state if no viewer data
      return RelationshipState()
    }
    
    return RelationshipState(
      isFollowing: viewer.following != nil,
      isFollowedBy: viewer.followedBy != nil,
      isMuting: viewer.muted == true,
      isBlocking: viewer.blockedBy == true,  // Note: blockedBy means "blocked by viewer"
      followRequested: false  // Bluesky doesn't have follow requests in viewer state
    )
  }
  
  public func follow(_ actor: ActorID, account: SocialAccount) async throws -> RelationshipState {
    guard case .bluesky(let identifier) = actor else {
      throw ServiceError.invalidInput(reason: "Invalid actor ID for Bluesky")
    }
    
    print("🔵 [BlueskyGraphService] Follow called with identifier: \(identifier)")
    
    // Resolve to DID if we have a handle (getProfile accepts both)
    let did: String
    if identifier.hasPrefix("did:") {
      did = identifier
      print("   Using identifier as DID: \(did)")
    } else {
      // Fetch profile to get DID from handle
      print("   Identifier is handle, fetching profile to get DID...")
      let profile = try await blueskyService.getProfile(actor: identifier, account: account)
      did = profile.did
      print("   Resolved DID: \(did)")
    }
    
    print("   Calling followUser with DID: \(did), repo: \(account.platformSpecificId)")
    let followUri = try await blueskyService.followUser(did: did, account: account)
    print("   Follow succeeded, URI: \(followUri)")
    
    // Small delay to ensure Bluesky API has updated
    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    
    // Fetch updated relationship state using the resolved DID
    let profile = try await blueskyService.getProfile(actor: did, account: account)
    guard let viewer = profile.viewer else {
      print("   Warning: No viewer data in profile response")
      return RelationshipState(isFollowing: true) // Optimistic state
    }
    
    let newState = RelationshipState(
      isFollowing: viewer.following != nil,
      isFollowedBy: viewer.followedBy != nil,
      isMuting: viewer.muted == true,
      isBlocking: viewer.blockedBy == true,
      followRequested: false
    )
    print("   Relationship state after follow: following=\(newState.isFollowing), followUri=\(viewer.following ?? "nil")")
    return newState
  }
  
  public func unfollow(_ actor: ActorID, account: SocialAccount) async throws -> RelationshipState {
    guard case .bluesky(let identifier) = actor else {
      throw ServiceError.invalidInput(reason: "Invalid actor ID for Bluesky")
    }
    
    // First fetch current relationship to get followUri
    let currentState = try await relationship(for: actor, account: account)
    guard let followUri = try await getFollowUri(identifier: identifier, account: account) else {
      // Already not following
      return currentState
    }
    
    try await blueskyService.unfollowUser(followUri: followUri, account: account)
    // Fetch updated relationship state
    return try await relationship(for: actor, account: account)
  }
  
  public func mute(_ actor: ActorID, account: SocialAccount) async throws -> RelationshipState {
    guard case .bluesky(let identifier) = actor else {
      throw ServiceError.invalidInput(reason: "Invalid actor ID for Bluesky")
    }
    
    // Resolve to DID if we have a handle
    let did: String
    if identifier.hasPrefix("did:") {
      did = identifier
    } else {
      let profile = try await blueskyService.getProfile(actor: identifier, account: account)
      did = profile.did
    }
    
    try await blueskyService.muteActor(did: did, account: account)
    // Fetch updated relationship state
    return try await relationship(for: actor, account: account)
  }
  
  public func unmute(_ actor: ActorID, account: SocialAccount) async throws -> RelationshipState {
    guard case .bluesky(let identifier) = actor else {
      throw ServiceError.invalidInput(reason: "Invalid actor ID for Bluesky")
    }
    
    // Resolve to DID if we have a handle
    let did: String
    if identifier.hasPrefix("did:") {
      did = identifier
    } else {
      let profile = try await blueskyService.getProfile(actor: identifier, account: account)
      did = profile.did
    }
    
    try await blueskyService.unmuteActor(did: did, account: account)
    // Fetch updated relationship state
    return try await relationship(for: actor, account: account)
  }
  
  public func block(_ actor: ActorID, account: SocialAccount) async throws -> RelationshipState {
    guard case .bluesky(let identifier) = actor else {
      throw ServiceError.invalidInput(reason: "Invalid actor ID for Bluesky")
    }
    
    // Resolve to DID if we have a handle
    let did: String
    if identifier.hasPrefix("did:") {
      did = identifier
    } else {
      let profile = try await blueskyService.getProfile(actor: identifier, account: account)
      did = profile.did
    }
    
    _ = try await blueskyService.blockUser(did: did, account: account)
    // Fetch updated relationship state
    return try await relationship(for: actor, account: account)
  }
  
  public func unblock(_ actor: ActorID, account: SocialAccount) async throws -> RelationshipState {
    guard case .bluesky(let identifier) = actor else {
      throw ServiceError.invalidInput(reason: "Invalid actor ID for Bluesky")
    }
    
    // Resolve to DID if we have a handle
    let did: String
    if identifier.hasPrefix("did:") {
      did = identifier
    } else {
      let profile = try await blueskyService.getProfile(actor: identifier, account: account)
      did = profile.did
    }
    
    try await blueskyService.unblockUser(did: did, account: account)
    // Fetch updated relationship state
    return try await relationship(for: actor, account: account)
  }
  
  /// Helper to get the follow URI for a user (needed for unfollow)
  private func getFollowUri(identifier: String, account: SocialAccount) async throws -> String? {
    // Fetch profile to get viewer.following URI (getProfile accepts both DID and handle)
    let profile = try await blueskyService.getProfile(actor: identifier, account: account)
    return profile.viewer?.following
  }
}

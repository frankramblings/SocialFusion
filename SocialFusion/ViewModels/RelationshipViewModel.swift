import Combine
import Foundation
import SwiftUI

/// ViewModel for managing relationship state on profile screens
@MainActor
public final class RelationshipViewModel: ObservableObject {
  @Published public private(set) var state: RelationshipState = RelationshipState()
  @Published public private(set) var isLoading: Bool = false
  @Published public private(set) var error: Error? = nil
  
  private(set) var actorID: ActorID
  private(set) var account: SocialAccount
  private(set) var graphService: SocialGraphService
  private(set) var relationshipStore: RelationshipStore
  
  public init(
    actorID: ActorID,
    account: SocialAccount,
    graphService: SocialGraphService,
    relationshipStore: RelationshipStore
  ) {
    self.actorID = actorID
    self.account = account
    self.graphService = graphService
    self.relationshipStore = relationshipStore
    
    // Initialize state from store if available
    state = RelationshipState(
      isFollowing: false,  // Will be loaded from API
      isFollowedBy: false,  // Will be loaded from API
      isMuting: relationshipStore.isMuted(actorID),
      isBlocking: relationshipStore.isBlocked(actorID),
      followRequested: false
    )
  }
  
  /// Load relationship state from API
  public func loadState() async {
    isLoading = true
    error = nil
    
    do {
      let newState = try await graphService.relationship(for: actorID, account: account)
      state = newState
      
      // Sync store state (in case it was updated elsewhere)
      if newState.isBlocking {
        relationshipStore.setBlocked(actorID, true)
      }
      if newState.isMuting {
        relationshipStore.setMuted(actorID, true)
      }
    } catch {
      self.error = error
      ErrorHandler.shared.handleError(error)
    }
    
    isLoading = false
  }
  
  /// Follow the actor (optimistic update)
  public func follow() async {
    let previousState = state
    
    // Optimistic update
    state.isFollowing = true
    state.followRequested = false
    
    do {
      print("🔵 [RelationshipViewModel] Attempting to follow actor: \(actorID)")
      let newState = try await graphService.follow(actorID, account: account)
      print("✅ [RelationshipViewModel] Follow succeeded, new state: following=\(newState.isFollowing)")
      state = newState
    } catch {
      // Revert on failure
      print("❌ [RelationshipViewModel] Follow failed: \(error.localizedDescription)")
      if let serviceError = error as? ServiceError {
        print("   ServiceError details: \(serviceError)")
      }
      state = previousState
      self.error = error
      ErrorHandler.shared.handleError(error)
    }
  }
  
  /// Unfollow the actor (optimistic update)
  public func unfollow() async {
    let previousState = state
    
    // Optimistic update
    state.isFollowing = false
    state.followRequested = false
    
    do {
      let newState = try await graphService.unfollow(actorID, account: account)
      state = newState
    } catch {
      // Revert on failure
      state = previousState
      self.error = error
      ErrorHandler.shared.handleError(error)
    }
  }
  
  /// Mute the actor (optimistic update)
  public func mute() async {
    let previousState = state
    
    // Optimistic update
    state.isMuting = true
    relationshipStore.setMuted(actorID, true)
    
    do {
      let newState = try await graphService.mute(actorID, account: account)
      state = newState
      relationshipStore.setMuted(actorID, newState.isMuting)
    } catch {
      // Revert on failure
      state = previousState
      relationshipStore.setMuted(actorID, false)
      self.error = error
      ErrorHandler.shared.handleError(error)
    }
  }
  
  /// Unmute the actor (optimistic update)
  public func unmute() async {
    let previousState = state
    
    // Optimistic update
    state.isMuting = false
    relationshipStore.setMuted(actorID, false)
    
    do {
      let newState = try await graphService.unmute(actorID, account: account)
      state = newState
      relationshipStore.setMuted(actorID, newState.isMuting)
    } catch {
      // Revert on failure
      state = previousState
      relationshipStore.setMuted(actorID, true)
      self.error = error
      ErrorHandler.shared.handleError(error)
    }
  }
  
  /// Block the actor (optimistic update)
  public func block() async {
    let previousState = state
    
    // Optimistic update
    state.isBlocking = true
    state.isFollowing = false  // Can't follow while blocked
    relationshipStore.setBlocked(actorID, true)
    
    do {
      let newState = try await graphService.block(actorID, account: account)
      state = newState
      relationshipStore.setBlocked(actorID, newState.isBlocking)
    } catch {
      // Revert on failure
      state = previousState
      relationshipStore.setBlocked(actorID, false)
      self.error = error
      ErrorHandler.shared.handleError(error)
    }
  }
  
  /// Unblock the actor (optimistic update)
  public func unblock() async {
    let previousState = state
    
    // Optimistic update
    state.isBlocking = false
    relationshipStore.setBlocked(actorID, false)
    
    do {
      let newState = try await graphService.unblock(actorID, account: account)
      state = newState
      relationshipStore.setBlocked(actorID, newState.isBlocking)
    } catch {
      // Revert on failure
      state = previousState
      relationshipStore.setBlocked(actorID, true)
      self.error = error
      ErrorHandler.shared.handleError(error)
    }
  }
}

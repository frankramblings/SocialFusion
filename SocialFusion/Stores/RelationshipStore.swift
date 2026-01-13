import Combine
import Foundation

/// Centralized store for relationship state (blocked/muted actors)
/// Used for instant timeline filtering when users are blocked or muted
@MainActor
public final class RelationshipStore: ObservableObject {
  @Published public private(set) var blocked: Set<ActorID> = []
  @Published public private(set) var muted: Set<ActorID> = []
  
  private let persistenceKeyBlocked = "RelationshipStore.blocked"
  private let persistenceKeyMuted = "RelationshipStore.muted"
  
  public init() {
    loadPersistedState()
  }
  
  /// Set blocked state for an actor (optimistic update)
  public func setBlocked(_ id: ActorID, _ value: Bool) {
    if value {
      blocked.insert(id)
    } else {
      blocked.remove(id)
    }
    persistState()
  }
  
  /// Set muted state for an actor (optimistic update)
  public func setMuted(_ id: ActorID, _ value: Bool) {
    if value {
      muted.insert(id)
    } else {
      muted.remove(id)
    }
    persistState()
  }
  
  /// Check if an actor is blocked
  public func isBlocked(_ id: ActorID) -> Bool {
    return blocked.contains(id)
  }
  
  /// Check if an actor is muted
  public func isMuted(_ id: ActorID) -> Bool {
    return muted.contains(id)
  }
  
  /// Check if a post should be filtered (contains blocked or muted actors)
  public func shouldFilter(_ post: Post) -> Bool {
    for actorID in post.actorIDsInvolved {
      if isBlocked(actorID) || isMuted(actorID) {
        return true
      }
    }
    return false
  }
  
  // MARK: - Persistence
  
  private func loadPersistedState() {
    // Load blocked actors
    if let data = UserDefaults.standard.data(forKey: persistenceKeyBlocked),
       let decoded = try? JSONDecoder().decode([String].self, from: data) {
      blocked = Set(decoded.compactMap { decodeActorID(from: $0) })
    }
    
    // Load muted actors
    if let data = UserDefaults.standard.data(forKey: persistenceKeyMuted),
       let decoded = try? JSONDecoder().decode([String].self, from: data) {
      muted = Set(decoded.compactMap { decodeActorID(from: $0) })
    }
  }
  
  private func persistState() {
    // Persist blocked actors
    let blockedStrings = blocked.map { encodeActorID($0) }
    if let encoded = try? JSONEncoder().encode(blockedStrings) {
      UserDefaults.standard.set(encoded, forKey: persistenceKeyBlocked)
    }
    
    // Persist muted actors
    let mutedStrings = muted.map { encodeActorID($0) }
    if let encoded = try? JSONEncoder().encode(mutedStrings) {
      UserDefaults.standard.set(encoded, forKey: persistenceKeyMuted)
    }
  }
  
  /// Encode ActorID to string for persistence
  private func encodeActorID(_ id: ActorID) -> String {
    switch id {
    case .mastodon(let value):
      return "mastodon:\(value)"
    case .bluesky(let value):
      return "bluesky:\(value)"
    }
  }
  
  /// Decode ActorID from persisted string
  private func decodeActorID(from string: String) -> ActorID? {
    let components = string.split(separator: ":", maxSplits: 1)
    guard components.count == 2 else { return nil }
    
    let platform = String(components[0])
    let value = String(components[1])
    
    switch platform {
    case "mastodon":
      return .mastodon(value)
    case "bluesky":
      return .bluesky(value)
    default:
      return nil
    }
  }
}

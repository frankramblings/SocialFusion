import Foundation

/// Stable, cross-network key that anchors a canonical post.
public struct NativePostKey: Hashable, Codable {
  public let network: SocialPlatform
  public let key: String

  public var storageKey: String {
    "\(network.rawValue):\(key)"
  }

  public init(network: SocialPlatform, key: String) {
    self.network = network
    self.key = key
  }
}

/// Actor metadata for social events (boosts/reposts, etc.).
public struct SocialActor: Hashable, Codable {
  public let id: String
  public let handle: String
  public let displayName: String
  public let platform: SocialPlatform
  public let accountID: String?

  public init(
    id: String,
    handle: String,
    displayName: String,
    platform: SocialPlatform,
    accountID: String? = nil
  ) {
    self.id = id
    self.handle = handle
    self.displayName = displayName
    self.platform = platform
    self.accountID = accountID
  }
}

public enum SocialEventType: String, Codable {
  case repost
}

/// Social event referencing a canonical post.
public struct SocialEvent: Identifiable, Hashable, Codable {
  public let id: String
  public let type: SocialEventType
  public let canonicalPostID: String
  public let actor: SocialActor
  public let occurredAt: Date
  public let nativeEventKey: String?

  public init(
    id: String,
    type: SocialEventType,
    canonicalPostID: String,
    actor: SocialActor,
    occurredAt: Date,
    nativeEventKey: String? = nil
  ) {
    self.id = id
    self.type = type
    self.canonicalPostID = canonicalPostID
    self.actor = actor
    self.occurredAt = occurredAt
    self.nativeEventKey = nativeEventKey
  }
}

/// Aggregated social context for a canonical post.
public struct SocialContext: Equatable, Codable {
  public var repostActors: [SocialActor]
  public var latestRepostAt: Date?

  public init(repostActors: [SocialActor] = [], latestRepostAt: Date? = nil) {
    self.repostActors = repostActors
    self.latestRepostAt = latestRepostAt
  }

  public mutating func apply(_ event: SocialEvent) {
    guard event.type == .repost else { return }

    if let index = repostActors.firstIndex(where: { $0.id == event.actor.id }) {
      repostActors.remove(at: index)
    }
    repostActors.insert(event.actor, at: 0)
    if let currentLatest = latestRepostAt {
      latestRepostAt = max(currentLatest, event.occurredAt)
    } else {
      latestRepostAt = event.occurredAt
    }
  }

  public var repostActorCount: Int {
    repostActors.count
  }
}

/// Core canonical post representation.
public struct CanonicalPost: Identifiable, Equatable, Codable {
  public let id: String
  public let originNetwork: SocialPlatform
  public var nativeKeys: Set<NativePostKey>
  public var createdAt: Date
  public var lastSocialActivityAt: Date
  public var post: Post
  public var socialContext: SocialContext

  public init(
    id: String,
    originNetwork: SocialPlatform,
    nativeKeys: Set<NativePostKey>,
    createdAt: Date,
    lastSocialActivityAt: Date,
    post: Post,
    socialContext: SocialContext = SocialContext()
  ) {
    self.id = id
    self.originNetwork = originNetwork
    self.nativeKeys = nativeKeys
    self.createdAt = createdAt
    self.lastSocialActivityAt = lastSocialActivityAt
    self.post = post
    self.socialContext = socialContext
  }
}

public enum TimelineSource: String, Codable {
  case refresh
  case pagination
  case search
  case list
  case profile
  case pinned
  case system
}

/// Records where a timeline item came from to support deterministic aggregation.
public struct TimelineSourceContext: Hashable, Codable {
  public let source: TimelineSource
  public let platform: SocialPlatform?
  public let accountID: String?
  public let receivedAt: Date

  public init(
    source: TimelineSource,
    platform: SocialPlatform? = nil,
    accountID: String? = nil,
    receivedAt: Date = Date()
  ) {
    self.source = source
    self.platform = platform
    self.accountID = accountID
    self.receivedAt = receivedAt
  }
}

public enum TimelineSortKeyStrategy: String, Codable {
  case createdAt
  case lastSocialActivity
}

/// Controls whether social events bump ordering in timelines.
public struct TimelineOrderingConfiguration: Codable, Equatable {
  public var strategy: TimelineSortKeyStrategy
  public var bumpOnRepost: Bool

  public init(strategy: TimelineSortKeyStrategy = .lastSocialActivity, bumpOnRepost: Bool = true) {
    self.strategy = strategy
    self.bumpOnRepost = bumpOnRepost
  }
}

/// Timeline entry that references a canonical post ID only.
public struct CanonicalTimelineEntry: Identifiable, Hashable, Codable {
  public let id: String
  public let timelineID: String
  public let canonicalPostID: String
  public var sortKey: Date
  public var sourceContext: TimelineSourceContext
  public var updatedAt: Date

  public init(
    timelineID: String,
    canonicalPostID: String,
    sortKey: Date,
    sourceContext: TimelineSourceContext,
    updatedAt: Date = Date()
  ) {
    self.timelineID = timelineID
    self.canonicalPostID = canonicalPostID
    self.sortKey = sortKey
    self.sourceContext = sourceContext
    self.updatedAt = updatedAt
    self.id = "\(timelineID)|\(canonicalPostID)"
  }
}

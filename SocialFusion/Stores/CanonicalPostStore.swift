import Foundation

/// Canonical post repository with deterministic dedupe and timeline insertion.
@MainActor
public final class CanonicalPostStore {
  public static let unifiedTimelineID = "unified"

  private let orderingConfig: TimelineOrderingConfiguration
  // CanonicalPost is unique by canonicalPostID.
  private var postsByID: [String: CanonicalPost] = [:]
  private var canonicalIDByNativeKey: [String: String] = [:]
  // SocialEvent is unique by eventID.
  private var socialEventsByID: [String: SocialEvent] = [:]
  private var socialEventsByCanonicalID: [String: [SocialEvent]] = [:]
  // TimelineEntry is unique by (timelineID, canonicalPostID).
  private var timelineEntriesByTimelineID: [String: [CanonicalTimelineEntry]] = [:]
  private var timelineEntryIndexByTimelineID: [String: [String: Int]] = [:]

  public init(orderingConfig: TimelineOrderingConfiguration = TimelineOrderingConfiguration()) {
    self.orderingConfig = orderingConfig
  }

  public var canonicalPostCount: Int {
    postsByID.count
  }

  public func replaceTimeline(
    timelineID: String,
    posts: [Post],
    sourceContext: TimelineSourceContext
  ) {
    timelineEntriesByTimelineID[timelineID] = []
    timelineEntryIndexByTimelineID[timelineID] = [:]
    processIncomingPosts(posts, timelineID: timelineID, sourceContext: sourceContext)
  }

  public func processIncomingPosts(
    _ posts: [Post],
    timelineID: String,
    sourceContext: TimelineSourceContext
  ) {
    for post in posts {
      processIncomingPost(post, timelineID: timelineID, sourceContext: sourceContext)
    }
    sortTimeline(timelineID: timelineID)
  }

  public func processIncomingPost(
    _ post: Post,
    timelineID: String,
    sourceContext: TimelineSourceContext
  ) {
    let resolution = CanonicalPostResolver.resolve(post: post, sourceAccountID: sourceContext.accountID)
    let canonicalPostID = resolveCanonicalPostID(resolution)
    let canonicalPost = upsertCanonicalPost(resolution.canonicalPost, canonicalPostID: canonicalPostID)
    mapNativeKeys(resolution.nativeKeys, to: canonicalPostID)

    if !resolution.socialEvents.isEmpty {
      upsertSocialEvents(resolution.socialEvents, canonicalPostID: canonicalPostID)
    }

    let sortKey = sortKeyForCanonicalPost(canonicalPostID)
    insertOrUpdateTimelineEntry(
      timelineID: timelineID,
      canonicalPostID: canonicalPostID,
      sortKey: sortKey,
      sourceContext: sourceContext
    )
  }

  public func canonicalPost(for canonicalPostID: String) -> CanonicalPost? {
    postsByID[canonicalPostID]
  }

  public func timelineEntries(for timelineID: String) -> [CanonicalTimelineEntry] {
    timelineEntriesByTimelineID[timelineID] ?? []
  }

  public func timelineEntriesForUI(timelineID: String) -> [TimelineEntry] {
    let entries = timelineEntries(for: timelineID)
    return entries.compactMap { entry in
      guard let canonicalPost = postsByID[entry.canonicalPostID] else { return nil }
      let boostText = boostSummaryText(for: entry.canonicalPostID)
      let kind: TimelineEntryKind
      if let boostText = boostText {
        kind = .boost(boostedBy: boostText)
      } else if let parentId = canonicalPost.post.inReplyToID {
        kind = .reply(parentId: parentId)
      } else {
        kind = .normal
      }
      return TimelineEntry(
        id: entry.canonicalPostID,
        kind: kind,
        post: canonicalPost.post,
        createdAt: entry.sortKey
      )
    }
  }

  public func timelinePosts(for timelineID: String) -> [Post] {
    let entries = timelineEntries(for: timelineID)
    return entries.compactMap { entry in
      guard let canonicalPost = postsByID[entry.canonicalPostID] else { return nil }
      let summary = boostSummaryText(for: entry.canonicalPostID)
      if let summary = summary {
        canonicalPost.post.boostedBy = summary
        canonicalPost.post.boosterEmojiMap = boostEmojiMap(for: entry.canonicalPostID)
      }
      return canonicalPost.post
    }
  }

  public func socialEvents(for canonicalPostID: String) -> [SocialEvent] {
    socialEventsByCanonicalID[canonicalPostID] ?? []
  }

  public func boostSummaryText(for canonicalPostID: String) -> String? {
    guard let canonicalPost = postsByID[canonicalPostID] else { return nil }
    let actors = canonicalPost.socialContext.repostActors
    guard !actors.isEmpty else { return nil }

    if actors.count == 1 {
      return actors[0].displayName
    }
    if actors.count == 2 {
      return "\(actors[0].displayName) and \(actors[1].displayName)"
    }
    return "\(actors[0].displayName) and \(actors.count - 1) others"
  }

  private func boostEmojiMap(for canonicalPostID: String) -> [String: String]? {
    guard let canonicalPost = postsByID[canonicalPostID] else { return nil }
    let actors = canonicalPost.socialContext.repostActors
    guard !actors.isEmpty else { return nil }

    var merged: [String: String] = [:]
    for actor in actors {
      guard let emojiMap = actor.emojiMap else { continue }
      for (shortcode, url) in emojiMap where merged[shortcode] == nil {
        merged[shortcode] = url
      }
    }

    return merged.isEmpty ? nil : merged
  }

  public func sortKeyForCanonicalPost(_ canonicalPostID: String) -> Date {
    guard let canonicalPost = postsByID[canonicalPostID] else { return Date.distantPast }
    switch orderingConfig.strategy {
    case .createdAt:
      return canonicalPost.createdAt
    case .lastSocialActivity:
      if orderingConfig.bumpOnRepost, let latestRepost = canonicalPost.socialContext.latestRepostAt {
        return max(canonicalPost.createdAt, latestRepost)
      }
      return canonicalPost.createdAt
    }
  }

  private func resolveCanonicalPostID(_ resolution: CanonicalPostResolution) -> String {
    if let existing = resolution.nativeKeys.compactMap({ canonicalIDByNativeKey[$0.storageKey] }).first {
      return existing
    }
    return resolution.canonicalPostID
  }

  private func upsertCanonicalPost(_ post: CanonicalPost, canonicalPostID: String) -> CanonicalPost {
    if var existing = postsByID[canonicalPostID] {
      var incomingPost = post.post
      if incomingPost.poll == nil {
        incomingPost.poll = existing.post.poll
      }
      if let existingOriginal = existing.post.originalPost,
         let incomingOriginal = incomingPost.originalPost,
         incomingOriginal.poll == nil {
        incomingOriginal.poll = existingOriginal.poll
      }
      existing.nativeKeys.formUnion(post.nativeKeys)
      existing.post = incomingPost
      existing.createdAt = post.createdAt
      existing.lastSocialActivityAt = max(existing.lastSocialActivityAt, post.lastSocialActivityAt)
      postsByID[canonicalPostID] = existing
      return existing
    }
    postsByID[canonicalPostID] = post
    return post
  }

  private func mapNativeKeys(_ keys: Set<NativePostKey>, to canonicalPostID: String) {
    for key in keys {
      canonicalIDByNativeKey[key.storageKey] = canonicalPostID
    }
  }

  private func upsertSocialEvents(_ events: [SocialEvent], canonicalPostID: String) {
    for event in events {
      guard socialEventsByID[event.id] == nil else { continue }
      socialEventsByID[event.id] = event
      var list = socialEventsByCanonicalID[canonicalPostID] ?? []
      list.append(event)
      list.sort { $0.occurredAt > $1.occurredAt }
      socialEventsByCanonicalID[canonicalPostID] = list

      apply(event, to: canonicalPostID)
    }
  }

  private func apply(_ event: SocialEvent, to canonicalPostID: String) {
    guard var canonicalPost = postsByID[canonicalPostID] else { return }
    canonicalPost.socialContext.apply(event)
    canonicalPost.lastSocialActivityAt = max(canonicalPost.lastSocialActivityAt, event.occurredAt)
    postsByID[canonicalPostID] = canonicalPost
  }

  private func insertOrUpdateTimelineEntry(
    timelineID: String,
    canonicalPostID: String,
    sortKey: Date,
    sourceContext: TimelineSourceContext
  ) {
    var entries = timelineEntriesByTimelineID[timelineID] ?? []
    var indexMap = timelineEntryIndexByTimelineID[timelineID] ?? [:]

    if let existingIndex = indexMap[canonicalPostID] {
      var entry = entries[existingIndex]
      entry.sortKey = sortKey
      entry.sourceContext = sourceContext
      entry.updatedAt = Date()
      entries[existingIndex] = entry
    } else {
      let entry = CanonicalTimelineEntry(
        timelineID: timelineID,
        canonicalPostID: canonicalPostID,
        sortKey: sortKey,
        sourceContext: sourceContext
      )
      entries.append(entry)
      indexMap[canonicalPostID] = entries.count - 1
    }

    timelineEntriesByTimelineID[timelineID] = entries
    timelineEntryIndexByTimelineID[timelineID] = indexMap
  }

  private func sortTimeline(timelineID: String) {
    guard var entries = timelineEntriesByTimelineID[timelineID] else { return }
    entries.sort { lhs, rhs in
      if lhs.sortKey != rhs.sortKey {
        return lhs.sortKey > rhs.sortKey
      }
      return lhs.canonicalPostID < rhs.canonicalPostID
    }
    timelineEntriesByTimelineID[timelineID] = entries
    var indexMap: [String: Int] = [:]
    for (index, entry) in entries.enumerated() {
      indexMap[entry.canonicalPostID] = index
    }
    timelineEntryIndexByTimelineID[timelineID] = indexMap
  }
}

import Foundation

/// The kind of pinned timeline and its associated source references.
///
/// `sourceRefs` semantics by kind:
/// - `.mastodonList(accountId, listId)` — one Mastodon account + one list ID.
/// - `.blueskyList(accountId, listUri)` — one Bluesky account + one list AT-URI.
/// - `.blueskyFeed(accountId, feedUri)` — one Bluesky account + one feed AT-URI.
/// - `.accountGroup(accountIds)` — N account IDs across both networks; the
///   pin's timeline is the merged home timeline of those accounts only.
public enum PinnedTimelineKind: Hashable, Codable {
    case mastodonList(accountId: String, listId: String)
    case blueskyList(accountId: String, listUri: String)
    case blueskyFeed(accountId: String, feedUri: String)
    case accountGroup(accountIds: [String])

    /// Stable storage key for cache / pagination keying.
    public var storageKey: String {
        switch self {
        case .mastodonList(let acct, let id):
            return "mastodonList:\(acct):\(id)"
        case .blueskyList(let acct, let uri):
            return "blueskyList:\(acct):\(uri)"
        case .blueskyFeed(let acct, let uri):
            return "blueskyFeed:\(acct):\(uri)"
        case .accountGroup(let ids):
            return "accountGroup:\(ids.sorted().joined(separator: ","))"
        }
    }
}

/// A user-pinned timeline. Persists in `PinnedTimelineStore`.
public struct PinnedTimeline: Identifiable, Hashable, Codable {
    /// Stable UUID assigned at creation. Used as the persistence key and
    /// referenced by `TimelineFeedSelection.pinned(id:)`.
    public let id: String

    /// User-visible name. Defaults to the underlying list/feed/group label
    /// at creation time; editable via `PinnedTimelinesEditorView`.
    public var displayName: String

    public let kind: PinnedTimelineKind

    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        displayName: String,
        kind: PinnedTimelineKind,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.createdAt = createdAt
    }
}

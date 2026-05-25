import Foundation

enum TimelineScope: Hashable {
    case allAccounts
    case account(id: String)

    var storageKey: String {
        switch self {
        case .allAccounts:
            return "all"
        case .account(let id):
            return "account:\(id)"
        }
    }

    static func fromStorageKey(_ key: String) -> TimelineScope {
        if key == "all" {
            return .allAccounts
        }
        if key.hasPrefix("account:") {
            let id = String(key.dropFirst("account:".count))
            return .account(id: id)
        }
        return .allAccounts
    }
}

enum MastodonTimelineFeed: Hashable, Codable {
    case home
    case local
    case federated
    case list(id: String, title: String?)
    case instance(server: String)

    var cacheKey: String {
        switch self {
        case .home:
            return "home"
        case .local:
            return "local"
        case .federated:
            return "federated"
        case .list(let id, _):
            return "list:\(id)"
        case .instance(let server):
            return "instance:\(server)"
        }
    }
}

enum BlueskyTimelineFeed: Hashable, Codable {
    case following
    case custom(uri: String, name: String?)

    var cacheKey: String {
        switch self {
        case .following:
            return "following"
        case .custom(let uri, _):
            return "custom:\(uri)"
        }
    }
}

enum TimelineFeedSelection: Hashable, Codable {
    case unified
    case allMastodon
    case allBluesky
    case mastodon(accountId: String, feed: MastodonTimelineFeed)
    case bluesky(accountId: String, feed: BlueskyTimelineFeed)
    /// References a `PinnedTimeline` by id in `PinnedTimelineStore`. The
    /// resolution into concrete accounts + source URIs happens in
    /// `SocialServiceManager.resolveTimelineFetchPlan()` so call sites can
    /// stay agnostic about what's behind a pin.
    case pinned(id: String)
}

enum TimelineFetchPlan {
    case unified(accounts: [SocialAccount])
    case allMastodon(accounts: [SocialAccount])
    case allBluesky(accounts: [SocialAccount])
    case mastodon(account: SocialAccount, feed: MastodonTimelineFeed)
    case bluesky(account: SocialAccount, feed: BlueskyTimelineFeed)
    /// A pin paired with the runtime-resolved sources its kind expands into,
    /// so downstream fetch code never re-walks the pin store or the accounts
    /// list.
    case pinned(pin: PinnedTimeline, resolution: PinnedTimelineResolution)
}

/// The runtime-resolved sources a pinned timeline expands into. Mirrors
/// `PinnedTimelineKind` but carries fully-resolved `SocialAccount` values
/// rather than account IDs, so the fetch layer doesn't repeat that lookup.
enum PinnedTimelineResolution {
    case mastodonList(account: SocialAccount, listId: String)
    case blueskyList(account: SocialAccount, listUri: String)
    case blueskyFeed(account: SocialAccount, feedUri: String)
    case accountGroup(accounts: [SocialAccount])
}

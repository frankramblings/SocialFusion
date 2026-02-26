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
}

enum TimelineFetchPlan {
    case unified(accounts: [SocialAccount])
    case allMastodon(accounts: [SocialAccount])
    case allBluesky(accounts: [SocialAccount])
    case mastodon(account: SocialAccount, feed: MastodonTimelineFeed)
    case bluesky(account: SocialAccount, feed: BlueskyTimelineFeed)
}

import Foundation
import SwiftUI

@MainActor
final class TimelineFeedPickerViewModel: ObservableObject {
    @Published var mastodonListsByAccount: [String: [MastodonList]] = [:]
    @Published var blueskyFeedsByAccount: [String: [BlueskyFeedGenerator]] = [:]
    @Published var blueskyListsByAccount: [String: [BlueskyList]] = [:]
    @Published var recentInstances: [String] = []
    @Published var instanceSearchText: String = ""
    @Published var loadingListsForAccount: String? = nil
    @Published var loadingFeedsForAccount: String? = nil
    @Published var loadingBlueskyListsForAccount: String? = nil

    var mastodonLists: [MastodonList] { mastodonListsByAccount.values.flatMap { $0 } }
    var blueskyFeeds: [BlueskyFeedGenerator] { blueskyFeedsByAccount.values.flatMap { $0 } }
    var blueskyLists: [BlueskyList] { blueskyListsByAccount.values.flatMap { $0 } }

    private let serviceManager: SocialServiceManager
    private let recentInstancesKey = "recentMastodonInstancesV1"
    private let maxRecentInstances = 6

    init(serviceManager: SocialServiceManager) {
        self.serviceManager = serviceManager
        loadRecentInstances()
    }

    func loadMastodonLists(for account: SocialAccount) async {
        guard loadingListsForAccount != account.id else { return }
        guard mastodonListsByAccount[account.id] == nil else { return }
        loadingListsForAccount = account.id
        defer { loadingListsForAccount = nil }
        do {
            mastodonListsByAccount[account.id] = try await serviceManager.fetchMastodonLists(account: account)
        } catch {
            mastodonListsByAccount[account.id] = []
        }
    }

    func loadBlueskyFeeds(for account: SocialAccount) async {
        guard loadingFeedsForAccount != account.id else { return }
        guard blueskyFeedsByAccount[account.id] == nil else { return }
        loadingFeedsForAccount = account.id
        defer { loadingFeedsForAccount = nil }
        do {
            blueskyFeedsByAccount[account.id] = try await serviceManager.fetchBlueskySavedFeeds(account: account)
        } catch {
            blueskyFeedsByAccount[account.id] = []
        }
    }

    func loadBlueskyLists(for account: SocialAccount) async {
        guard loadingBlueskyListsForAccount != account.id else { return }
        guard blueskyListsByAccount[account.id] == nil else { return }
        loadingBlueskyListsForAccount = account.id
        defer { loadingBlueskyListsForAccount = nil }
        do {
            blueskyListsByAccount[account.id] = try await serviceManager.fetchBlueskyLists(account: account)
        } catch {
            blueskyListsByAccount[account.id] = []
        }
    }

    func isLoadingBlueskyLists(for accountId: String) -> Bool {
        return loadingBlueskyListsForAccount == accountId
    }

    func blueskyLists(for accountId: String) -> [BlueskyList] {
        return blueskyListsByAccount[accountId] ?? []
    }

    func isLoadingLists(for accountId: String) -> Bool {
        return loadingListsForAccount == accountId
    }

    func isLoadingFeeds(for accountId: String) -> Bool {
        return loadingFeedsForAccount == accountId
    }

    func lists(for accountId: String) -> [MastodonList] {
        return mastodonListsByAccount[accountId] ?? []
    }

    func feeds(for accountId: String) -> [BlueskyFeedGenerator] {
        return blueskyFeedsByAccount[accountId] ?? []
    }

    func normalizedInstance(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var server = trimmed
        if server.hasPrefix("https://") {
            server = String(server.dropFirst("https://".count))
        } else if server.hasPrefix("http://") {
            server = String(server.dropFirst("http://".count))
        }
        if let slashIndex = server.firstIndex(of: "/") {
            server = String(server[..<slashIndex])
        }
        server = server.lowercased()
        return server.isEmpty ? nil : server
    }

    func recordRecentInstance(_ server: String) {
        let normalized = normalizedInstance(from: server) ?? server
        var updated = recentInstances.filter { $0 != normalized }
        updated.insert(normalized, at: 0)
        if updated.count > maxRecentInstances {
            updated = Array(updated.prefix(maxRecentInstances))
        }
        recentInstances = updated
        persistRecentInstances()
    }

    private func loadRecentInstances() {
        let stored = UserDefaults.standard.stringArray(forKey: recentInstancesKey) ?? []
        recentInstances = stored
    }

    private func persistRecentInstances() {
        UserDefaults.standard.set(recentInstances, forKey: recentInstancesKey)
    }

    // MARK: - Pin capture

    /// Produces a sensible default `displayName` for a new pin captured from
    /// the picker. Returns nil if the selection isn't pinnable in v1.0
    /// (e.g. `.unified`, `.allMastodon`, `.allBluesky` — those are already
    /// top-level rows; home timelines aren't pinnable individually).
    func suggestedPinName(for selection: TimelineFeedSelection) -> String? {
        switch selection {
        case .unified, .allMastodon, .allBluesky:
            return nil
        case .mastodon(_, let feed):
            switch feed {
            case .list(_, let title):
                return title ?? "Mastodon list"
            case .home, .local, .federated:
                return nil
            case .instance(let server):
                return server
            }
        case .bluesky(_, let feed):
            switch feed {
            case .following:
                return nil
            case .custom(_, let name):
                return name ?? "Bluesky feed"
            }
        case .pinned:
            return nil
        }
    }

    /// Converts a pinnable `TimelineFeedSelection` into the matching
    /// `PinnedTimelineKind`. Returns nil for non-pinnable selections.
    /// (Bluesky lists don't appear in TimelineFeedSelection — they're
    /// pinned directly via `pinKindForBlueskyList(accountId:listURI:)`.)
    func pinKind(for selection: TimelineFeedSelection) -> PinnedTimelineKind? {
        switch selection {
        case .mastodon(let accountId, .list(let listId, _)):
            return .mastodonList(accountId: accountId, listId: listId)
        case .bluesky(let accountId, .custom(let uri, _)):
            return .blueskyFeed(accountId: accountId, feedUri: uri)
        default:
            return nil
        }
    }

    /// Direct helper used by the picker's "Pin this Bluesky list" row.
    /// Bluesky lists aren't reachable via the existing
    /// `TimelineFeedSelection` cases (the picker treats them as a separate
    /// pinnable surface), so this helper exists for direct capture.
    func pinKindForBlueskyList(accountId: String, listURI: String) -> PinnedTimelineKind {
        .blueskyList(accountId: accountId, listUri: listURI)
    }
}

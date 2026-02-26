import Foundation
import SwiftUI

@MainActor
final class TimelineFeedPickerViewModel: ObservableObject {
    @Published var mastodonListsByAccount: [String: [MastodonList]] = [:]
    @Published var blueskyFeedsByAccount: [String: [BlueskyFeedGenerator]] = [:]
    @Published var recentInstances: [String] = []
    @Published var instanceSearchText: String = ""
    @Published var loadingListsForAccount: String? = nil
    @Published var loadingFeedsForAccount: String? = nil

    var mastodonLists: [MastodonList] { mastodonListsByAccount.values.flatMap { $0 } }
    var blueskyFeeds: [BlueskyFeedGenerator] { blueskyFeedsByAccount.values.flatMap { $0 } }

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
}

import Foundation
import SwiftUI

@MainActor
final class TimelineFeedPickerViewModel: ObservableObject {
    @Published var mastodonLists: [MastodonList] = []
    @Published var blueskyFeeds: [BlueskyFeedGenerator] = []
    @Published var recentInstances: [String] = []
    @Published var instanceSearchText: String = ""
    @Published var isLoadingLists = false
    @Published var isLoadingFeeds = false

    private let serviceManager: SocialServiceManager
    private let recentInstancesKey = "recentMastodonInstancesV1"
    private let maxRecentInstances = 6

    init(serviceManager: SocialServiceManager) {
        self.serviceManager = serviceManager
        loadRecentInstances()
    }

    func loadMastodonLists(for account: SocialAccount) async {
        guard !isLoadingLists else { return }
        isLoadingLists = true
        defer { isLoadingLists = false }
        do {
            mastodonLists = try await serviceManager.fetchMastodonLists(account: account)
        } catch {
            mastodonLists = []
        }
    }

    func loadBlueskyFeeds(for account: SocialAccount) async {
        guard !isLoadingFeeds else { return }
        isLoadingFeeds = true
        defer { isLoadingFeeds = false }
        do {
            blueskyFeeds = try await serviceManager.fetchBlueskySavedFeeds(account: account)
        } catch {
            blueskyFeeds = []
        }
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

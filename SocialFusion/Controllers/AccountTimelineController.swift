import Combine
import Foundation
import SwiftUI

@MainActor
final class AccountTimelineController: ObservableObject {
    @Published private(set) var posts: [Post] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error? = nil
    @Published private(set) var hasNextPage = true
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var paginationToken: String?
    @Published private(set) var bufferCount: Int = 0
    @Published private(set) var bufferEarliestTimestamp: Date?
    @Published private(set) var bufferSources: Set<SocialPlatform> = []
    @Published private(set) var isNearTop: Bool = true
    @Published private(set) var isDeepHistory: Bool = false

    let account: SocialAccount
    private let serviceManager: SocialServiceManager
    private lazy var refreshCoordinator: TimelineRefreshCoordinator = {
        TimelineRefreshCoordinator(
            timelineID: "account-\(self.account.id)",
            platforms: [self.account.platform],
            isLoading: { [weak self] in self?.isLoading ?? false },
            fetchPostsForPlatform: { [weak serviceManager] platform in
#if DEBUG
                if UITestHooks.isEnabled {
                    return Self.makeTestPosts(count: 3, platform: platform)
                }
#endif
                guard let serviceManager = serviceManager else { return [] }
                do {
                    let result: TimelineResult
                    switch platform {
                    case .mastodon:
                        result = try await serviceManager.mastodonSvc.fetchHomeTimeline(
                            for: self.account,
                            maxId: nil
                        )
                    case .bluesky:
                        result = try await serviceManager.blueskySvc.fetchHomeTimeline(
                            for: self.account,
                            cursor: nil
                        )
                    }
                    return result.posts
                } catch {
                    return []
                }
            },
            mergeBufferedPosts: { [weak self] posts in
                self?.mergeBufferedPosts(posts)
            },
            refreshVisibleTimeline: { [weak self] _ in
                await self?.performManualRefresh()
            },
            visiblePostsProvider: { [weak self] in
                self?.posts ?? []
            },
            log: { message in
                DebugLog.verbose(message)
            }
        )
    }()
    private var cancellables = Set<AnyCancellable>()

    init(account: SocialAccount, serviceManager: SocialServiceManager) {
        self.account = account
        self.serviceManager = serviceManager
        setupBindings()
    }

    deinit {
        cancellables.removeAll()
    }

    func setTimelineVisible(_ isVisible: Bool) {
        refreshCoordinator.setTimelineVisible(isVisible)
    }

    func handleAppForegrounded() {
        refreshCoordinator.handleAppForegrounded()
    }

    func recordVisibleInteraction() {
        refreshCoordinator.recordVisibleInteraction()
    }

    func scrollInteractionBegan() {
        refreshCoordinator.scrollInteractionBegan()
    }

    func scrollInteractionEnded() {
        refreshCoordinator.scrollInteractionEnded()
    }

    func updateScrollState(isNearTop: Bool, isDeepHistory: Bool) {
        refreshCoordinator.updateScrollState(isNearTop: isNearTop, isDeepHistory: isDeepHistory)
    }

    func requestInitialPrefetch() {
        Task { await refreshCoordinator.requestPrefetch(trigger: .foreground) }
    }

    func manualRefresh() async {
        await refreshCoordinator.manualRefresh(intent: .manualRefresh)
    }

    func mergeBufferedPosts() {
        refreshCoordinator.mergeBufferedPostsIfNeeded()
    }

#if DEBUG
    func debugSeedTimeline() {
        guard UITestHooks.isEnabled else { return }
        let posts = Self.makeTestPosts(count: 8, platform: self.account.platform)
        self.posts = posts
        refreshCoordinator.handleVisibleTimelineUpdate(posts)
    }

    func debugTriggerIdlePrefetch() {
        guard UITestHooks.isEnabled else { return }
        Task { await refreshCoordinator.requestPrefetch(trigger: .idlePolling) }
    }

    private static func makeTestPosts(count: Int, platform: SocialPlatform) -> [Post] {
        let now = Date()
        return (0..<count).map { index in
            let id = "ui-test-\(platform.rawValue)-\(UUID().uuidString)-\(index)"
            return Post(
                id: id,
                content: "UI Test Post \(index)",
                authorName: "UI Test",
                authorUsername: "ui-test",
                authorProfilePictureURL: "",
                createdAt: now.addingTimeInterval(-Double(index)),
                platform: platform,
                originalURL: "https://example.com/\(id)",
                platformSpecificId: id
            )
        }
    }
#endif

    func loadMorePosts() async {
        guard hasNextPage && !isLoadingNextPage else { return }
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }

        do {
            let result = try await fetchTimelineForAccount(cursor: paginationToken)
            let existingIds = Set(posts.map { $0.stableId })
            let newPosts = result.posts.filter { !existingIds.contains($0.stableId) }
            posts.append(contentsOf: newPosts)
            posts.sort { $0.createdAt > $1.createdAt }
            hasNextPage = result.pagination.hasNextPage
            paginationToken = result.pagination.nextPageToken
            refreshCoordinator.handleVisibleTimelineUpdate(posts)
        } catch {
            DebugLog.verbose("❌ AccountTimelineController: Error loading more posts: \(error)")
        }
    }

    // MARK: - Private Helpers

    private func setupBindings() {
        serviceManager.$isComposing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isComposing in
                self?.refreshCoordinator.setComposing(isComposing)
            }
            .store(in: &cancellables)

        refreshCoordinator.$bufferCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.bufferCount = count
            }
            .store(in: &cancellables)

        refreshCoordinator.$bufferEarliestTimestamp
            .receive(on: DispatchQueue.main)
            .sink { [weak self] timestamp in
                self?.bufferEarliestTimestamp = timestamp
            }
            .store(in: &cancellables)

        refreshCoordinator.$bufferSources
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sources in
                self?.bufferSources = sources
            }
            .store(in: &cancellables)

        refreshCoordinator.$isNearTop
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isNearTop in
                self?.isNearTop = isNearTop
            }
            .store(in: &cancellables)

        refreshCoordinator.$isDeepHistory
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isDeepHistory in
                self?.isDeepHistory = isDeepHistory
            }
            .store(in: &cancellables)
    }

    private func performManualRefresh() async {
        isLoading = true
        error = nil
        paginationToken = nil
        hasNextPage = true

        do {
            let result = try await fetchTimelineForAccount()
            posts = result.posts
            hasNextPage = result.pagination.hasNextPage
            paginationToken = result.pagination.nextPageToken
        } catch {
            self.error = error
            posts = []
        }

        isLoading = false
        refreshCoordinator.handleVisibleTimelineUpdate(posts)
    }

    private func mergeBufferedPosts(_ newPosts: [Post]) {
        guard !newPosts.isEmpty else { return }
        let existingIds = Set(posts.map { $0.stableId })
        let deduped = newPosts.filter { !existingIds.contains($0.stableId) }
        guard !deduped.isEmpty else { return }
        posts.insert(contentsOf: deduped, at: 0)
        posts.sort { $0.createdAt > $1.createdAt }
        refreshCoordinator.handleVisibleTimelineUpdate(posts)
    }

    private func fetchTimelineForAccount(cursor: String? = nil) async throws -> TimelineResult {
        switch self.account.platform {
        case .mastodon:
            return try await serviceManager.mastodonSvc.fetchHomeTimeline(
                for: self.account,
                maxId: cursor
            )
        case .bluesky:
            return try await serviceManager.blueskySvc.fetchHomeTimeline(
                for: self.account,
                cursor: cursor
            )
        }
    }
}

import SwiftUI

struct AccountTimelineView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    let account: SocialAccount

    @StateObject private var navigationEnvironment = PostNavigationEnvironment()
    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var error: Error? = nil
    @State private var hasNextPage = true
    @State private var isLoadingNextPage = false
    @State private var paginationToken: String?

    // Scroll position persistence (per account)
    @State private var scrollAnchorId: String?
    @State private var pendingAnchorRestoreId: String?
    @State private var hasRestoredInitialAnchor = false
    @Environment(\.scenePhase) private var scenePhase

    private var anchorDefaultsKey: String { "accountTimeline.anchorId.\(account.id)" }
    private func persistedAnchor() -> String? { UserDefaults.standard.string(forKey: anchorDefaultsKey) }
    private func setPersistedAnchor(_ id: String?) {
        if let id = id {
            UserDefaults.standard.set(id, forKey: anchorDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: anchorDefaultsKey)
        }
    }

    private var timelineEntries: [TimelineEntry] {
        serviceManager.makeTimelineEntries(from: posts)
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            if isLoading && posts.isEmpty {
                ProgressView()
                    .scaleEffect(1.5)
            } else if posts.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 60))
                        .foregroundColor(Color(hex: account.platform.colorHex))

                    Text("No posts to display")
                        .font(.headline)

                    Text("Pull to refresh")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .foregroundColor(.secondary)
                }
            } else {
                if #available(iOS 17.0, *) {
                    ScrollViewReader { _ in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(Array(timelineEntries.enumerated()), id: \.element.id) { index, entry in
                                    PostCardView(
                                        entry: entry,
                                        postActionStore: serviceManager.postActionStore,
                                        postActionCoordinator: serviceManager.postActionCoordinator,
                                        onAuthorTap: { navigationEnvironment.navigateToUser(from: entry.post) }
                                    )
                                    .id(entry.id)
                                    .padding(.horizontal)
                                    .onAppear {
                                        if shouldLoadMorePosts(currentIndex: index) {
                                            Task { await loadMorePosts() }
                                        }
                                    }
                                }

                                if isLoadingNextPage {
                                    infiniteScrollLoadingView
                                        .padding(.vertical, 20)
                                }

                                if !hasNextPage && !posts.isEmpty {
                                    endOfTimelineView
                                        .padding(.vertical, 20)
                                }
                            }
                            .padding(.vertical)
                            .scrollTargetLayout()
                        }
                        .scrollPosition(id: $scrollAnchorId)
                        .onChange(of: scrollAnchorId) { newValue in
                            guard hasRestoredInitialAnchor, pendingAnchorRestoreId == nil else { return }
                            guard newValue != nil else { return }
                            setPersistedAnchor(newValue)
                        }
                        .refreshable {
                            let anchorBefore = scrollAnchorId ?? persistedAnchor()
                            pendingAnchorRestoreId = anchorBefore
                            await loadPosts()
                        }
                        .onAppear {
                            if pendingAnchorRestoreId == nil {
                                pendingAnchorRestoreId = persistedAnchor()
                            }
                            restorePendingAnchorIfPossible()
                        }
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(Array(timelineEntries.enumerated()), id: \.element.id) { index, entry in
                                    PostCardView(
                                        entry: entry,
                                        postActionStore: serviceManager.postActionStore,
                                        postActionCoordinator: serviceManager.postActionCoordinator,
                                        onAuthorTap: { navigationEnvironment.navigateToUser(from: entry.post) }
                                    )
                                    .id(entry.id)
                                    .padding(.horizontal)
                                    .onAppear {
                                        if shouldLoadMorePosts(currentIndex: index) {
                                            Task { await loadMorePosts() }
                                        }
                                    }
                                }

                                if isLoadingNextPage {
                                    infiniteScrollLoadingView
                                        .padding(.vertical, 20)
                                }

                                if !hasNextPage && !posts.isEmpty {
                                    endOfTimelineView
                                        .padding(.vertical, 20)
                                }
                            }
                            .padding(.vertical)
                        }
                        .refreshable { await loadPosts() }
                        .onAppear {
                            if let id = persistedAnchor() {
                                withAnimation(.none) { proxy.scrollTo(id, anchor: .top) }
                            }
                        }
                    }
                }
            }
        }
        .background(
            NavigationLink(
                destination: navigationEnvironment.selectedUser.map { user in
                    UserDetailView(user: user)
                        .environmentObject(serviceManager)
                },
                isActive: Binding(
                    get: { navigationEnvironment.selectedUser != nil },
                    set: { if !$0 { navigationEnvironment.clearNavigation() } }
                ),
                label: { EmptyView() }
            )
            .hidden()
        )
        .onAppear {
            if #available(iOS 17.0, *), pendingAnchorRestoreId == nil {
                pendingAnchorRestoreId = scrollAnchorId ?? persistedAnchor()
            }
            Task { await loadPosts() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                setPersistedAnchor(scrollAnchorId)
            }
        }
        .onChange(of: posts) { _ in
            restorePendingAnchorIfPossible()
        }
    }

    private var infiniteScrollLoadingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading more posts...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }

    private var endOfTimelineView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.green)
            Text("You're all caught up!")
                .font(.subheadline)
                .fontWeight(.medium)
            Text("No more posts to load")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }

    private func loadPosts() async {
        isLoading = true
        error = nil
        // Reset pagination for fresh load
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
    }

    private func restorePendingAnchorIfPossible() {
        guard #available(iOS 17.0, *) else { return }
        guard !posts.isEmpty else { return }
        guard let id = pendingAnchorRestoreId else {
            hasRestoredInitialAnchor = true
            return
        }
        if posts.contains(where: { $0.id == id }) {
            var t = Transaction()
            t.disablesAnimations = true
            if scrollAnchorId == id {
                withTransaction(t) { scrollAnchorId = nil }
                DispatchQueue.main.async {
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) { scrollAnchorId = id }
                }
            } else {
                withTransaction(t) { scrollAnchorId = id }
            }
        }
        pendingAnchorRestoreId = nil
        hasRestoredInitialAnchor = true
    }

    /// Determines if we should load more posts based on current scroll position
    private func shouldLoadMorePosts(currentIndex: Int) -> Bool {
        let totalPosts = timelineEntries.count
        let threshold = max(5, totalPosts / 4)  // Load when 25% from bottom, minimum 5 posts

        return currentIndex >= totalPosts - threshold && hasNextPage && !isLoadingNextPage
    }

    /// Load more posts for infinite scrolling
    private func loadMorePosts() async {
        guard hasNextPage && !isLoadingNextPage else {
            return
        }

        isLoadingNextPage = true

        do {
            let result = try await fetchTimelineForAccount(cursor: paginationToken)

            // Deduplicate new posts against existing ones
            let existingIds = Set(posts.map { $0.stableId })
            let newPosts = result.posts.filter { !existingIds.contains($0.stableId) }

            posts.append(contentsOf: newPosts)
            hasNextPage = result.pagination.hasNextPage
            paginationToken = result.pagination.nextPageToken

            print(
                "📊 AccountTimelineView: Loaded \(newPosts.count) more posts for \(account.username)"
            )
        } catch {
            print("❌ AccountTimelineView: Error loading more posts: \(error)")
            // Don't show error for pagination failures, just stop loading
        }

        isLoadingNextPage = false
    }

    /// Fetch timeline for the specific account with pagination support
    private func fetchTimelineForAccount(cursor: String? = nil) async throws -> TimelineResult {
        switch account.platform {
        case .mastodon:
            return try await serviceManager.mastodonSvc.fetchHomeTimeline(
                for: account,
                maxId: cursor
            )
        case .bluesky:
            return try await serviceManager.blueskySvc.fetchHomeTimeline(
                for: account,
                cursor: cursor
            )
        }
    }
}

extension SocialServiceManager {
    // Make these services accessible for individual account timelines (renamed to avoid collisions)
    var mastodonSvc: MastodonService { MastodonService() }
    var blueskySvc: BlueskyService { BlueskyService() }
}

struct AccountTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        let mastodonAccount = SocialAccount(
            id: "1",
            username: "user@mastodon.social",
            displayName: "Mastodon User",
            serverURL: "mastodon.social",
            platform: .mastodon
        )

        AccountTimelineView(account: mastodonAccount)
            .environmentObject(SocialServiceManager())
    }
}

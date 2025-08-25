import SwiftUI

struct AccountTimelineView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    let account: SocialAccount

    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var error: Error? = nil
    @State private var hasNextPage = true
    @State private var isLoadingNextPage = false
    @State private var paginationToken: String?

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
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(timelineEntries.enumerated()), id: \.element.id) {
                            index, entry in
                            PostCardView(entry: entry)
                                .id(entry.id)
                                .padding(.horizontal)
                                .onAppear {
                                    // Trigger infinite scroll when approaching the end
                                    if shouldLoadMorePosts(currentIndex: index) {
                                        Task {
                                            await loadMorePosts()
                                        }
                                    }
                                }
                        }

                        // Loading indicator at the bottom when fetching more posts
                        if isLoadingNextPage {
                            infiniteScrollLoadingView
                                .padding(.vertical, 20)
                        }

                        // End of timeline indicator
                        if !hasNextPage && !posts.isEmpty {
                            endOfTimelineView
                                .padding(.vertical, 20)
                        }
                    }
                    .padding(.vertical)
                }
                .refreshable {
                    await loadPosts()
                }
            }
        }
        .onAppear {
            Task {
                await loadPosts()
            }
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

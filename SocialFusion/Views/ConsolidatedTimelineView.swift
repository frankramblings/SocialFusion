import SwiftUI

/// Consolidated timeline view that serves as the single source of truth
/// Replaces all other timeline implementations to eliminate multiple instances
struct ConsolidatedTimelineView: View {
    @StateObject private var controller: UnifiedTimelineController
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @StateObject private var navigationEnvironment = PostNavigationEnvironment()
    @State private var isRefreshing = false

    init(serviceManager: SocialServiceManager? = nil) {
        // Handle the main actor isolation issue by creating controller on main thread
        if let serviceManager = serviceManager {
            self._controller = StateObject(
                wrappedValue: UnifiedTimelineController(serviceManager: serviceManager))
        } else {
            // Use a default initialization that will be handled properly
            self._controller = StateObject(wrappedValue: UnifiedTimelineController())
        }
    }

    var body: some View {
        contentView
            .environmentObject(navigationEnvironment)
            .background(
                NavigationLink(
                    destination: navigationEnvironment.selectedPost.map { post in
                        PostDetailNavigationView(
                            viewModel: PostViewModel(
                                post: post, serviceManager: serviceManager),
                            focusReplyComposer: false
                        )
                        .environmentObject(serviceManager)
                        .environmentObject(navigationEnvironment)
                    },
                    isActive: Binding(
                        get: { navigationEnvironment.selectedPost != nil },
                        set: { if !$0 { navigationEnvironment.selectedPost = nil } }
                    ),
                    label: { EmptyView() }
                )
                .hidden()
            )
            .task {
                await controller.ensureTimelineLoaded()
            }
            .alert("Error", isPresented: .constant(controller.error != nil)) {
                Button("OK") {
                    controller.clearError()
                }
            } message: {
                Text(controller.error?.localizedDescription ?? "Unknown error")
            }
    }

    @ViewBuilder
    private var contentView: some View {
        if controller.posts.isEmpty && controller.isLoading {
            loadingView
        } else if controller.posts.isEmpty && !controller.isLoading {
            emptyView
        } else {
            timelineView
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading timeline...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "timeline.selection")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No posts yet")
                .font(.title2)
                .fontWeight(.medium)
            Text("Pull to refresh or add some accounts to get started")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var timelineView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(controller.posts.enumerated()), id: \.element.id) { index, post in
                    postCard(for: post)
                        .onAppear {
                            // Trigger infinite scroll when approaching the end
                            if shouldLoadMorePosts(currentIndex: index) {
                                Task {
                                    await loadMorePosts()
                                }
                            }
                        }

                    // Divider between posts
                    if post.id != controller.posts.last?.id {
                        Divider()
                            .padding(.horizontal, 16)
                    }
                }

                // Loading indicator at the bottom when fetching more posts
                if serviceManager.isLoadingNextPage {
                    infiniteScrollLoadingView
                        .padding(.vertical, 20)
                }

                // End of timeline indicator
                if !serviceManager.hasNextPage && !controller.posts.isEmpty {
                    endOfTimelineView
                        .padding(.vertical, 20)
                }
            }
        }
        .refreshable {
            await refreshTimeline()
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

    private func postCard(for post: Post) -> some View {
        // Determine the correct TimelineEntry kind based on post properties
        let entryKind: TimelineEntryKind
        if let boostedBy = post.boostedBy {
            entryKind = .boost(boostedBy: boostedBy)
        } else if post.inReplyToID != nil {
            entryKind = .reply(parentId: post.inReplyToID!)
        } else {
            entryKind = .normal
        }

        return PostCardView(
            entry: TimelineEntry(
                id: post.stableId,
                kind: entryKind,
                post: post,
                createdAt: post.createdAt
            ),
            onPostTap: {
                navigationEnvironment.navigateToPost(post)
            },
            onParentPostTap: { parentPost in
                navigationEnvironment.navigateToPost(parentPost)
            },
            onRepost: {
                Task {
                    await controller.repostPost(post)
                }
            },
            onLike: {
                Task {
                    await controller.likePost(post)
                }
            }
        )
        .background(Color(.systemBackground))
    }

    private func refreshTimeline() async {
        isRefreshing = true
        // Reset pagination when doing a full refresh
        serviceManager.resetPagination()
        await controller.refreshTimeline(force: true)
        isRefreshing = false
    }

    /// Determines if we should load more posts based on current scroll position
    private func shouldLoadMorePosts(currentIndex: Int) -> Bool {
        let totalPosts = controller.posts.count
        let threshold = max(5, totalPosts / 4)  // Load when 25% from bottom, minimum 5 posts

        return currentIndex >= totalPosts - threshold && serviceManager.hasNextPage
            && !serviceManager.isLoadingNextPage
    }

    /// Load more posts for infinite scrolling
    private func loadMorePosts() async {
        guard serviceManager.hasNextPage && !serviceManager.isLoadingNextPage else {
            return
        }

        print("🔄 ConsolidatedTimelineView: Loading more posts...")
        await serviceManager.fetchNextPage()
        print("🔄 ConsolidatedTimelineView: Finished loading more posts")
    }
}

#Preview {
    ConsolidatedTimelineView()
}

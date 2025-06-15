import SwiftUI

/// Consolidated timeline view that serves as the single source of truth
/// Replaces all other timeline implementations to eliminate multiple instances
struct ConsolidatedTimelineView: View {
    @StateObject private var controller: UnifiedTimelineController
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
        NavigationView {
            contentView
        }
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
                ForEach(controller.posts, id: \.id) { post in
                    postCard(for: post)

                    // Divider between posts
                    if post.id != controller.posts.last?.id {
                        Divider()
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
        .refreshable {
            await refreshTimeline()
        }
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
        await controller.refreshTimeline(force: true)
        isRefreshing = false
    }
}

#Preview {
    ConsolidatedTimelineView()
}

import SwiftUI

/// Consolidated timeline view that serves as the single source of truth
/// Implements proper SwiftUI state management to prevent AttributeGraph cycles
struct ConsolidatedTimelineView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @StateObject private var controller: UnifiedTimelineController
    @StateObject private var navigationEnvironment = PostNavigationEnvironment()
    @State private var isRefreshing = false
    @State private var scrollVelocity: CGFloat = 0
    @State private var lastScrollTime = Date()
    @State private var scrollCancellationTimer: Timer?
    @State private var replyingToPost: Post? = nil

    init(serviceManager: SocialServiceManager) {
        // Use a factory pattern to create the controller with proper dependency injection
        _controller = StateObject(
            wrappedValue: UnifiedTimelineController(serviceManager: serviceManager))
    }

    var body: some View {
        contentView
            .environmentObject(navigationEnvironment)
            .background(
                NavigationLink(
                    destination: navigationEnvironment.selectedPost.map { post in
                        PostDetailView(
                            viewModel: PostViewModel(
                                post: post, serviceManager: serviceManager),
                            focusReplyComposer: false
                        )
                        .environmentObject(serviceManager)
                        .environmentObject(navigationEnvironment)
                    },
                    isActive: Binding(
                        get: { navigationEnvironment.selectedPost != nil },
                        set: { if !$0 { navigationEnvironment.clearNavigation() } }
                    ),
                    label: { EmptyView() }
                )
                .hidden()
            )
            .sheet(item: $replyingToPost) { post in
                FeedReplyComposer(post: post, onDismiss: { replyingToPost = nil })
            }
            .task {
                // Proper lifecycle management - only refresh if needed
                await ensureTimelineLoaded()
            }
            .alert("Error", isPresented: .constant(controller.error != nil)) {
                Button("Retry") {
                    controller.clearError()
                    controller.refreshTimeline()
                }
                Button("OK") {
                    controller.clearError()
                }
            } message: {
                if let error = controller.error {
                    Text(error.localizedDescription)
                    if let recoverySuggestion = (error as NSError).localizedRecoverySuggestion {
                        Text(recoverySuggestion)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Unknown error")
                }
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(controller.posts.enumerated()), id: \.element.id) {
                        index, post in
                        postCard(for: post)
                            .task {
                                // Proper async pattern for infinite scroll
                                await handleInfiniteScroll(currentIndex: index)
                            }

                        // Divider between posts
                        if post.id != controller.posts.last?.id {
                            Divider()
                                .padding(.horizontal, 16)
                        }
                    }

                    // Loading indicator at the bottom when fetching more posts
                    if controller.isLoadingNextPage {
                        infiniteScrollLoadingView
                            .padding(.vertical, 20)
                    }

                    // End of timeline indicator
                    if !controller.hasNextPage && !controller.posts.isEmpty {
                        endOfTimelineView
                            .padding(.vertical, 20)
                    }
                }
                .background(
                    // Invisible GeometryReader to detect scroll changes
                    GeometryReader { geometry in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geometry.frame(in: .named("scrollView")).origin.y)
                    }
                )
            }
            .coordinateSpace(name: "scrollView")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                handleScrollChange(offset: offset)
            }
            .refreshable {
                await refreshTimeline()
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

    private func postCard(for post: Post) -> some View {
        // Determine the correct TimelineEntry kind based on post properties
        let entryKind: TimelineEntryKind
        if let boostedBy = post.boostedBy {
            entryKind = .boost(boostedBy: boostedBy)
        } else if let parentId = post.inReplyToID {
            entryKind = .reply(parentId: parentId)
        } else {
            entryKind = .normal
        }

        let entry = TimelineEntry(
            id: post.id,
            kind: entryKind,
            post: post,
            createdAt: post.createdAt
        )

        return PostCardView(
            entry: entry,
            onPostTap: { navigationEnvironment.navigateToPost(post) },
            onParentPostTap: { parentPost in navigationEnvironment.navigateToPost(parentPost) },
            onReply: { replyingToPost = post },
            onRepost: { controller.repostPost(post) },
            onLike: { controller.likePost(post) },
            onShare: { /* TODO: Implement share functionality */  }
        )
        .id(post.id)
    }

    // MARK: - Private Helpers

    /// Ensure timeline is loaded - proper async pattern
    private func ensureTimelineLoaded() async {
        guard controller.posts.isEmpty && !controller.isLoading else { return }
        controller.refreshTimeline()
    }

    /// Refresh timeline - proper async pattern for user-initiated refresh
    private func refreshTimeline() async {
        print("🔄 ConsolidatedTimelineView: User-initiated refresh (pull-to-refresh)")
        await controller.refreshTimelineAsync()
    }

    /// Handle infinite scroll - proper async pattern
    private func handleInfiniteScroll(currentIndex: Int) async {
        guard shouldLoadMorePosts(currentIndex: currentIndex) else { return }
        await loadMorePosts()
    }

    /// Check if we should load more posts
    private func shouldLoadMorePosts(currentIndex: Int) -> Bool {
        let threshold = 3
        return currentIndex >= controller.posts.count - threshold
            && controller.hasNextPage
            && !controller.isLoadingNextPage
    }

    /// Load more posts for infinite scroll
    private func loadMorePosts() async {
        guard !controller.isLoadingNextPage else { return }
        await controller.loadNextPage()
    }

    /// Handle scroll changes - proper event-driven pattern
    private func handleScrollChange(offset: CGFloat) {
        let currentTime = Date()
        let timeDiff = currentTime.timeIntervalSince(lastScrollTime)

        guard timeDiff > 0.016 else { return }  // Throttle to ~60fps

        scrollVelocity = abs(offset) / timeDiff
        lastScrollTime = currentTime

        // Cancel previous timer and set new one
        scrollCancellationTimer?.invalidate()
        scrollCancellationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            scrollVelocity = 0
        }
    }
}

/// PreferenceKey for scroll offset detection
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    ConsolidatedTimelineView(serviceManager: SocialServiceManager())
}

// Add a simple reply composer view for the feed
struct FeedReplyComposer: View, Identifiable {
    let id = UUID()
    let post: Post
    let onDismiss: () -> Void
    @State private var replyText: String = ""
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @State private var isSending = false
    @State private var error: String? = nil

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Replying to @\(post.authorUsername)")
                    .font(.headline)
                TextEditor(text: $replyText)
                    .frame(minHeight: 100)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                if let error = error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                Spacer()
                HStack {
                    Button("Cancel") {
                        onDismiss()
                    }
                    Spacer()
                    Button("Send") {
                        sendReply()
                    }
                    .disabled(
                        replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isSending)
                }
            }
            .padding()
            .navigationTitle("Reply")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func sendReply() {
        guard !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSending = true
        error = nil
        Task {
            do {
                _ = try await serviceManager.replyToPost(post, content: replyText)
                // Update the post's isReplied state using proper async pattern
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                    post.isReplied = true
                }
                onDismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isSending = false
        }
    }
}

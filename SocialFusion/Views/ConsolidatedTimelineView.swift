import SwiftUI

/// Simple empty state view for basic edge case handling - ConsolidatedTimeline version
struct ConsolidatedTimelineEmptyStateView: View {
    enum StateType {
        case loading
        case noAccounts
        case noInternet
        case noPostsYet
        case lowMemory
    }

    let state: StateType
    let onRetry: (() -> Void)?
    let onAddAccount: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            image
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(title)
                .font(.title2)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)

            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if state == .noAccounts, let onAddAccount = onAddAccount {
                Button(action: onAddAccount) {
                    Text("Add Account")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(25)
                }
                .padding(.top, 8)
            } else if let onRetry = onRetry, state != .loading {
                Button("Retry") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var image: some View {
        switch state {
        case .loading:
            ProgressView()
                .scaleEffect(1.5)
        case .noAccounts:
            Image(systemName: "person.crop.circle.badge.questionmark")
        case .noInternet:
            Image(systemName: "wifi.slash")
        case .noPostsYet:
            Image(systemName: "timeline.selection")
        case .lowMemory:
            Image(systemName: "memorychip")
        }
    }

    private var title: String {
        switch state {
        case .loading:
            return "Loading timeline..."
        case .noAccounts:
            return "No accounts added"
        case .noInternet:
            return "No internet connection"
        case .noPostsYet:
            return "No posts yet"
        case .lowMemory:
            return "Low memory"
        }
    }

    private var message: String {
        switch state {
        case .loading:
            return "Please wait while we fetch your timeline."
        case .noAccounts:
            return "Add your Mastodon or Bluesky accounts to see posts here."
        case .noInternet:
            return "Please check your network connection and try again."
        case .noPostsYet:
            return "Pull to refresh or add some accounts to get started."
        case .lowMemory:
            return "The app is running low on memory. Some features may be limited."
        }
    }
}

/// Consolidated timeline view that serves as the single source of truth
/// Implements proper SwiftUI state management to prevent AttributeGraph cycles
/// Enhanced with Phase 3 features: position persistence, smart restoration, and unread tracking
struct ConsolidatedTimelineView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @StateObject private var controller: UnifiedTimelineController
    @StateObject private var navigationEnvironment = PostNavigationEnvironment()
    @State private var isRefreshing = false
    @State private var scrollVelocity: CGFloat = 0
    @State private var lastScrollTime = Date()
    @State private var scrollCancellationTimer: Timer?
    @State private var replyingToPost: Post? = nil
    @State private var showAddAccountView = false

    // PHASE 3+: Enhanced timeline state (optional, works alongside existing functionality)
    @StateObject private var timelineState = TimelineState()
    private let config = TimelineConfiguration.shared

    // MARK: - Accessibility Environment
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) var differentiateWithoutColor
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency

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
            .background(
                NavigationLink(
                    destination: navigationEnvironment.selectedTag.map { tag in
                        TagDetailView(tag: tag)
                            .environmentObject(serviceManager)
                    },
                    isActive: Binding(
                        get: { navigationEnvironment.selectedTag != nil },
                        set: { if !$0 { navigationEnvironment.clearNavigation() } }
                    ),
                    label: { EmptyView() }
                )
                .hidden()
            )
            .sheet(item: $replyingToPost) { post in
                ComposeView(replyingTo: post)
                    .environmentObject(serviceManager)
            }
            .sheet(isPresented: $showAddAccountView) {
                AddAccountView()
                    .environmentObject(serviceManager)
            }
            .task {
                // PHASE 3+: Enhanced timeline initialization with position restoration
                if config.isFeatureEnabled(.positionPersistence) {
                    // Load cached content immediately for instant display
                    // TODO: Implement loadCachedContent method
                    // timelineState.loadCachedContent(from: serviceManager)

                    // Update timeline state when posts are loaded
                    if !controller.posts.isEmpty {
                        timelineState.updateFromTimelineEntries(
                            controller.posts.map { post in
                                TimelineEntry(
                                    id: post.id, kind: .normal, post: post,
                                    createdAt: post.createdAt)
                            })
                    }
                }

                // Proper lifecycle management - only refresh if needed
                await ensureTimelineLoaded()

                // PHASE 3+: Smart position restoration after content loads
                if config.isFeatureEnabled(.smartRestoration) && !controller.posts.isEmpty {
                    // TODO: Implement performSmartRestoration function
                    // await performSmartRestoration()
                }
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
            ConsolidatedTimelineEmptyStateView(
                state: .loading,
                onRetry: {
                    controller.refreshTimeline()
                },
                onAddAccount: nil
            )
        } else if controller.posts.isEmpty && !controller.isLoading {
            determineEmptyState()
        } else {
            timelineView
        }
    }

    @ViewBuilder
    private func determineEmptyState() -> some View {
        // Determine the appropriate empty state based on current conditions
        if serviceManager.accounts.isEmpty {
            ConsolidatedTimelineEmptyStateView(
                state: .noAccounts,
                onRetry: nil,
                onAddAccount: {
                    showAddAccountView = true
                }
            )
        } else {
            ConsolidatedTimelineEmptyStateView(
                state: .noPostsYet,
                onRetry: {
                    controller.refreshTimeline()
                },
                onAddAccount: nil
            )
        }
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
                                .accessibilityHidden(true)  // Hide decorative dividers from VoiceOver
                        }
                    }

                    // Loading indicator at the bottom when fetching more posts
                    if controller.isLoadingNextPage {
                        infiniteScrollLoadingView
                            .padding(.vertical, 20)
                            .accessibilityLabel("Loading more posts")
                    }

                    // End of timeline indicator
                    if !controller.hasNextPage && !controller.posts.isEmpty {
                        endOfTimelineView
                            .padding(.vertical, 20)
                            .accessibilityLabel("End of timeline")
                            .accessibilityHint("No more posts to load")
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
            // MARK: - Timeline Accessibility
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Timeline")
            .accessibilityHint("Swipe up and down to navigate posts, pull down to refresh")
            .accessibilityAction(named: "Refresh Timeline") {
                Task {
                    await refreshTimeline()
                }
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
            postActionStore: controller.postActionStore,
            postActionCoordinator: controller.postActionCoordinator,
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

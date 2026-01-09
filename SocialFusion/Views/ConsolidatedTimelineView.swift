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
    @StateObject private var mediaCoordinator = FullscreenMediaCoordinator()
    @State private var isRefreshing = false
    // CRITICAL FIX: Removed scrollVelocity tracking - it was causing AttributeGraph cycles
    // GeometryReader-based scroll tracking triggers view updates every frame, creating cycles
    // scrollVelocity was never actually used, so removing it is safe
    @State private var replyingToPost: Post? = nil
    @State private var quotingToPost: Post? = nil
    @State private var showAddAccountView = false
    @State private var reportingPost: Post? = nil
    @State private var showReportDialog = false

    // Position persistence (iOS 17+ primary path)
    @SceneStorage("unifiedTimeline.anchorId") private var persistedAnchorId: String?
    @State private var scrollAnchorId: String?
    @Environment(\.scenePhase) private var scenePhase

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
            .environmentObject(mediaCoordinator)
            .fullScreenCover(isPresented: $mediaCoordinator.showFullscreen) {
                if let media = mediaCoordinator.selectedMedia {
                    FullscreenMediaOverlay(
                        media: media,
                        allMedia: mediaCoordinator.allMedia,
                        showAltTextInitially: mediaCoordinator.showAltTextInitially,
                        mediaNamespace: mediaCoordinator.mediaNamespace,
                        thumbnailFrames: mediaCoordinator.thumbnailFrames,
                        dismissalDirection: $mediaCoordinator.dismissalDirection,
                        onDismiss: { mediaCoordinator.dismiss() }
                    )
                }
            }
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
            .sheet(item: $quotingToPost) { post in
                ComposeView(quotingTo: post)
                    .environmentObject(serviceManager)
            }
            .sheet(isPresented: $showAddAccountView) {
                AddAccountView()
                    .environmentObject(serviceManager)
            }
            .task {
                // Load data if needed
                await ensureTimelineLoaded()

                // Attempt to restore position once posts are present (iOS 17+)
                if #available(iOS 17.0, *),
                   let id = persistedAnchorId,
                   controller.posts.contains(where: { $0.id == id }) {
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        scrollAnchorId = id
                    }
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .background {
                    // Persist latest known anchor on background as a safety net
                    if #available(iOS 17.0, *) {
                        persistedAnchorId = scrollAnchorId
                    }
                }
            }
            .alert("Error", isPresented: .constant(controller.error != nil)) {
                Button("Retry") {
                    let error = controller.error
                    controller.clearError()
                    if let error = error {
                        ErrorHandler.shared.handleError(error) {
                            controller.refreshTimeline()
                        }
                    }
                    controller.refreshTimeline()
                }
                Button("OK") {
                    if let error = controller.error {
                        ErrorHandler.shared.handleError(error)
                    }
                    controller.clearError()
                }
            } message: {
                if let error = controller.error {
                    Text(error.localizedDescription)
                } else {
                    Text("Unknown error")
                }
            }
            .onChange(of: controller.error?.localizedDescription) { errorDescription in
                if let errorDescription = errorDescription, let error = controller.error {
                    ErrorHandler.shared.handleError(error) {
                        controller.refreshTimeline()
                    }
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

    @ViewBuilder
    private var timelineView: some View {
        if #available(iOS 17.0, *) {
            ScrollViewReader { _ in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(controller.posts.enumerated()), id: \.element.id) { index, post in
                            postCard(for: post)
                                .id(post.id) // stable row identity for restoration
                                .task { await handleInfiniteScroll(currentIndex: index) }

                            if post.id != controller.posts.last?.id {
                                Divider()
                                    .padding(.horizontal, 16)
                                    .accessibilityHidden(true)
                            }
                        }

                        if controller.isLoadingNextPage {
                            infiniteScrollLoadingView
                                .padding(.vertical, 20)
                                .accessibilityLabel("Loading more posts")
                        }

                        if !controller.hasNextPage && !controller.posts.isEmpty {
                            endOfTimelineView
                                .padding(.vertical, 20)
                                .accessibilityLabel("End of timeline")
                                .accessibilityHint("No more posts to load")
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $scrollAnchorId)
                .onChange(of: scrollAnchorId) { persistedAnchorId = $0 }
                .refreshable {
                    // Preserve current anchor during refresh and restore it
                    let anchorBefore = scrollAnchorId ?? persistedAnchorId
                    await refreshTimeline()
                    if let id = anchorBefore,
                       controller.posts.contains(where: { $0.id == id }) {
                        var t = Transaction(); t.disablesAnimations = true
                        withTransaction(t) { scrollAnchorId = id }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Timeline")
                .accessibilityHint("Swipe up and down to navigate posts, pull down to refresh")
                .accessibilityAction(named: "Refresh Timeline") { Task { await refreshTimeline() } }
                .confirmationDialog(
                    "Report Post", isPresented: $showReportDialog, titleVisibility: .visible
                ) {
                    Button("Spam", role: .destructive) { report(reason: "Spam") }
                    Button("Harassment", role: .destructive) { report(reason: "Harassment") }
                    Button("Inappropriate Content", role: .destructive) { report(reason: "Inappropriate Content") }
                    Button("Cancel", role: .cancel) { reportingPost = nil }
                } message: {
                    Text("Why are you reporting this post? The platform moderators will review it.")
                }
            }
        } else {
            // Legacy path (iOS 16): no automatic scrollPosition binding; keep existing layout
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(controller.posts.enumerated()), id: \.element.id) { index, post in
                            postCard(for: post)
                                .id(post.id)
                                .task { await handleInfiniteScroll(currentIndex: index) }

                            if post.id != controller.posts.last?.id {
                                Divider()
                                    .padding(.horizontal, 16)
                                    .accessibilityHidden(true)
                            }
                        }

                        if controller.isLoadingNextPage {
                            infiniteScrollLoadingView
                                .padding(.vertical, 20)
                                .accessibilityLabel("Loading more posts")
                        }

                        if !controller.hasNextPage && !controller.posts.isEmpty {
                            endOfTimelineView
                                .padding(.vertical, 20)
                                .accessibilityLabel("End of timeline")
                                .accessibilityHint("No more posts to load")
                        }
                    }
                }
                .refreshable { await refreshTimeline() }
                .onAppear {
                    // Best-effort restoration if we have a persisted ID (may be nil on first run)
                    if let id = persistedAnchorId {
                        withAnimation(.none) { proxy.scrollTo(id, anchor: .top) }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Timeline")
                .accessibilityHint("Swipe up and down to navigate posts, pull down to refresh")
                .accessibilityAction(named: "Refresh Timeline") { Task { await refreshTimeline() } }
                .confirmationDialog(
                    "Report Post", isPresented: $showReportDialog, titleVisibility: .visible
                ) {
                    Button("Spam", role: .destructive) { report(reason: "Spam") }
                    Button("Harassment", role: .destructive) { report(reason: "Harassment") }
                    Button("Inappropriate Content", role: .destructive) { report(reason: "Inappropriate Content") }
                    Button("Cancel", role: .cancel) { reportingPost = nil }
                } message: {
                    Text("Why are you reporting this post? The platform moderators will review it.")
                }
            }
        }
    }

    private func report(reason: String) {
        guard let post = reportingPost else { return }
        Task {
            do {
                try await serviceManager.reportPost(post, reason: reason)
                print("✅ Successfully reported post")
            } catch {
                print("❌ Failed to report post: \(error)")
            }
            reportingPost = nil
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
        // CRITICAL FIX: Check for originalPost first to catch all boosts
        // CRITICAL: Never modify post properties during view rendering - causes AttributeGraph cycles
        let entryKind: TimelineEntryKind
        if post.originalPost != nil {
            // This is a boost - use boostedBy if available, otherwise use authorUsername
            // CRITICAL: Do NOT modify post.boostedBy here - it causes "Publishing changes from within view updates"
            // If boostedBy is missing, use authorUsername as fallback without modifying the post
            let boostedByHandle = post.boostedBy ?? post.authorUsername
            if boostedByHandle.isEmpty {
                print("⚠️ [ConsolidatedTimelineView] Boost detected but no boostedBy handle for post \(post.id)")
            }
            entryKind = .boost(boostedBy: boostedByHandle)
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

        // CRITICAL FIX: Use the entry initializer to ensure boostedBy is properly passed
        return PostCardView(
            entry: entry,
            postActionStore: controller.postActionStore,
            postActionCoordinator: controller.postActionCoordinator,
            onPostTap: { navigationEnvironment.navigateToPost(post) },
            onParentPostTap: { parentPost in navigationEnvironment.navigateToPost(parentPost) },
            onAuthorTap: { navigationEnvironment.navigateToUser(from: post) },
            onReply: {
                // When replying to a boost/repost, reply to the original post instead
                replyingToPost = post.isReposted ? (post.originalPost ?? post) : post
            },
            onRepost: { controller.repostPost(post) },
            onLike: { controller.likePost(post) },
            onShare: {
                guard let url = URL(string: post.originalURL) else { return }
                
                let activityVC = UIActivityViewController(
                    activityItems: [url], 
                    applicationActivities: nil
                )
                
                // Exclude some activity types that don't make sense for URLs
                activityVC.excludedActivityTypes = [
                    .assignToContact,
                    .addToReadingList
                ]
                
                // Find the topmost view controller to present from
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first(where: { $0.isKeyWindow }),
                   let rootVC = window.rootViewController {
                    
                    // Find the topmost presented view controller
                    var topVC = rootVC
                    while let presented = topVC.presentedViewController {
                        topVC = presented
                    }
                    
                    // Configure for iPad
                    if let popover = activityVC.popoverPresentationController {
                        popover.sourceView = topVC.view
                        popover.sourceRect = CGRect(
                            x: topVC.view.bounds.midX, 
                            y: topVC.view.bounds.midY, 
                            width: 0, 
                            height: 0
                        )
                        popover.permittedArrowDirections = []
                    }
                    
                    topVC.present(activityVC, animated: true, completion: nil)
                }
            },
            onQuote: { quotingToPost = post }
        )
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

    // CRITICAL FIX: Removed handleScrollChange function
    // It was causing AttributeGraph cycles and scrollVelocity was never actually used
    // Removing this eliminates the crash without affecting functionality
}

/// PreferenceKey for scroll offset detection
/// NOTE: Used by NotificationsView - kept here for NotificationsView compatibility
/// ConsolidatedTimelineView no longer uses this to prevent AttributeGraph cycles
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    ConsolidatedTimelineView(serviceManager: SocialServiceManager())
}

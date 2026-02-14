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
    @State private var showFeedPicker = false

    // Position persistence (iOS 17+ primary path)
    @SceneStorage("unifiedTimeline.anchorId") private var persistedAnchorId: String?
    @State private var scrollAnchorId: String?
    @State private var pendingAnchorRestoreId: String?
    @State private var hasRestoredInitialAnchor = false
    @State private var visibleAnchorId: String?
    @State private var anchorLockUntil: Date?
    @State private var lastVisiblePositions: [String: TimelineItemInfo] = [:]
    @State private var lastTopVisibleId: String?
    @State private var lastTopVisibleOffset: CGFloat = 0
    @Environment(\.scenePhase) private var scenePhase

    // PHASE 3+: Enhanced timeline state (optional, works alongside existing functionality)
    @StateObject private var timelineState = TimelineState()
    @StateObject private var feedPickerViewModel: TimelineFeedPickerViewModel
    private let config = TimelineConfiguration.shared
    
    // Layout snapshot system for stable media layout
    @State private var postSnapshots: [String: PostLayoutSnapshot] = [:]
    private let snapshotBuilder = PostLayoutSnapshotBuilder()
    // Computed property to access actor-isolated shared instance from MainActor context
    private var prefetcher: MediaPrefetcher {
      MediaPrefetcher.shared
    }
    @StateObject private var updateCoordinator = FeedUpdateCoordinator()

    // Cached screen height to avoid UIScreen queries on every scroll frame
    private let deepHistoryThreshold: CGFloat = UIScreen.main.bounds.height * 2.0

    // Read state tracking
    @State private var showJumpToLastRead = false
    @State private var lastReadPostId: String? = nil

    // MARK: - Accessibility Environment
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) var differentiateWithoutColor
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency

    init(serviceManager: SocialServiceManager) {
        // Use a factory pattern to create the controller with proper dependency injection
        _controller = StateObject(
            wrappedValue: UnifiedTimelineController(serviceManager: serviceManager))
        _feedPickerViewModel = StateObject(
            wrappedValue: TimelineFeedPickerViewModel(serviceManager: serviceManager))
    }

    var body: some View {
        mainContent
            .fullScreenCover(isPresented: $mediaCoordinator.showFullscreen) {
                if let media = mediaCoordinator.selectedMedia {
                    fullscreenMediaOverlay(media: media)
                }
            }
            .background(postDetailLink)
            .background(userDetailLink)
            .background(tagDetailLink)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavBarPillSelector(
                        title: currentFeedTitle,
                        isExpanded: showFeedPicker,
                        action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showFeedPicker.toggle()
                            }
                        }
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .top) {
                if showFeedPicker {
                    feedPickerOverlay
                }
            }
            .sheet(item: $replyingToPost) { post in
                ComposeView(
                    replyingTo: post,
                    timelineContextProvider: controller.autocompleteTimelineContextProvider
                )
                    .environmentObject(serviceManager)
            }
            .sheet(item: $quotingToPost) { post in
                ComposeView(
                    quotingTo: post,
                    timelineContextProvider: controller.autocompleteTimelineContextProvider
                )
                    .environmentObject(serviceManager)
            }
            .sheet(isPresented: $showAddAccountView) {
                AddAccountView()
                    .environmentObject(serviceManager)
            }
            .task {
                await ensureTimelineLoaded()
                if #available(iOS 17.0, *), pendingAnchorRestoreId == nil {
                    pendingAnchorRestoreId = persistedAnchorId
                    logAnchorState("initial queue")
                    restorePendingAnchorIfPossible()
                }
                // Prefetch dimensions for initial posts
                await prefetchInitialPosts()
                // Load last read post ID
                lastReadPostId = ViewTracker.shared.getLastReadPostId()
                updateJumpToLastReadVisibility()
            }
            .onAppear {
                serviceManager.markUnifiedTimelinePresented()
                controller.setTimelineVisible(true)
            }
            .onDisappear {
                controller.setTimelineVisible(false)
            }
            .onChange(of: scenePhase) { phase in
                if phase == .background {
                    if #available(iOS 17.0, *) {
                        persistedAnchorId = scrollAnchorId
                    }
                }
                if phase == .active {
                    controller.handleAppForegrounded()
                }
            }
            .onChange(of: controller.isLoading) { isLoading in
                guard #available(iOS 17.0, *), isLoading else { return }
                if !controller.posts.isEmpty {
                    pendingAnchorRestoreId = scrollAnchorId ?? persistedAnchorId
                    logAnchorState("loading started")
                }
            }
            .onChange(of: controller.posts) { newPosts in
                // Anchor + Compensate: Use the anchor captured by the controller
                // For pull-to-refresh, prefer the pendingAnchorRestoreId we set before refresh
                // Otherwise use the controller's restoration anchor
                if pendingAnchorRestoreId == nil, let restorationId = controller.restorationAnchor {
                    pendingAnchorRestoreId = restorationId
                }

                logAnchorState("posts updated count=\(newPosts.count) isRefreshing=\(isRefreshing)")

                // With buffer-then-merge, posts don't change during .refreshable
                // Restoration happens via offset compensation when buffer is merged
                if !isRefreshing {
                    restorePendingAnchorIfPossible()
                }

                // Update last read post ID and visibility
                lastReadPostId = ViewTracker.shared.getLastReadPostId()
                updateJumpToLastReadVisibility()

                // Build snapshots for new posts and prefetch dimensions
                Task {
                    await buildSnapshotsForPosts(newPosts)
                    prefetcher.prefetchDimensions(for: newPosts)
                }
            }
            .onChange(of: serviceManager.currentTimelineScope) { _ in
                controller.refreshTimeline()
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
            .onChange(of: controller.error?.localizedDescription) { _ in
                if let error = controller.error {
                    ErrorHandler.shared.handleError(error) {
                        controller.refreshTimeline()
                    }
                }
            }
            .overlay {
                if UITestHooks.isEnabled {
                    debugOverlay
                }
            }
    }

    private var mainContent: some View {
        contentView
            .environmentObject(navigationEnvironment)
            .environmentObject(mediaCoordinator)
    }

    private func fullscreenMediaOverlay(media: Post.Attachment) -> some View {
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

    private var postDetailLink: some View {
        EmptyView()
            .navigationDestination(
                isPresented: Binding(
                    get: { navigationEnvironment.selectedPost != nil },
                    set: { if !$0 { navigationEnvironment.clearNavigation() } }
                )
            ) {
                if let post = navigationEnvironment.selectedPost {
                    PostDetailView(
                        viewModel: PostViewModel(
                            post: post, serviceManager: serviceManager),
                        focusReplyComposer: false
                    )
                    .environmentObject(serviceManager)
                    .environmentObject(navigationEnvironment)
                }
            }
    }

    private var userDetailLink: some View {
        EmptyView()
            .navigationDestination(
                isPresented: Binding(
                    get: { navigationEnvironment.selectedUser != nil },
                    set: { if !$0 { navigationEnvironment.clearNavigation() } }
                )
            ) {
                if let user = navigationEnvironment.selectedUser {
                    UserDetailView(user: user)
                        .environmentObject(serviceManager)
                }
            }
    }

    private var tagDetailLink: some View {
        EmptyView()
            .navigationDestination(
                isPresented: Binding(
                    get: { navigationEnvironment.selectedTag != nil },
                    set: { if !$0 { navigationEnvironment.clearNavigation() } }
                )
            ) {
                if let tag = navigationEnvironment.selectedTag {
                    TagDetailView(tag: tag)
                        .environmentObject(serviceManager)
                }
            }
    }

    private var feedPickerOverlay: some View {
        ZStack {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showFeedPicker = false
                    }
                }

            VStack {
                HStack {
                    Spacer()

                    TimelineFeedPickerPopover(
                        viewModel: feedPickerViewModel,
                        isPresented: $showFeedPicker,
                        scope: serviceManager.currentTimelineScope,
                        selection: serviceManager.currentTimelineFeedSelection,
                        account: currentScopeAccount,
                        onSelect: handleFeedSelection(_:)
                    )

                    Spacer()
                }
                .padding(.top, 2)

                Spacer()
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var debugOverlay: some View {
        #if DEBUG
        VStack(spacing: 6) {
            Button("Seed Timeline") { controller.debugSeedTimeline() }
                .accessibilityIdentifier("SeedTimelineButton")
            Button("Trigger Foreground Prefetch") { controller.debugTriggerForegroundPrefetch() }
                .accessibilityIdentifier("TriggerForegroundPrefetchButton")
            Button("Trigger Idle Prefetch") { controller.debugTriggerIdlePrefetch() }
                .accessibilityIdentifier("TriggerIdlePrefetchButton")
            Button("Begin Scroll") { controller.scrollInteractionBegan() }
                .accessibilityIdentifier("BeginScrollButton")
            Button("End Scroll") { controller.scrollInteractionEnded() }
                .accessibilityIdentifier("EndScrollButton")
            Text("\(controller.bufferCount)")
                .accessibilityIdentifier("TimelineBufferCount")
            Text("\(controller.unreadAboveViewportCount)")
                .accessibilityIdentifier("TimelineUnreadCount")
            Text(lastTopVisibleId ?? "nil")
                .accessibilityIdentifier("TimelineTopAnchorId")
            Text(String(format: "%.2f", lastTopVisibleOffset))
                .accessibilityIdentifier("TimelineTopAnchorOffset")
        }
        .font(.caption2)
        .opacity(0.01)
        #else
        EmptyView()
        #endif
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

    private var currentScopeAccount: SocialAccount? {
        switch serviceManager.currentTimelineScope {
        case .allAccounts:
            return nil
        case .account(let id):
            return serviceManager.accounts.first(where: { $0.id == id })
        }
    }

    private var currentFeedTitle: String {
        switch serviceManager.currentTimelineScope {
        case .allAccounts:
            return "Unified"
        case .account:
            return feedTitle(for: serviceManager.currentTimelineFeedSelection)
        }
    }

    private func feedTitle(for selection: TimelineFeedSelection) -> String {
        switch selection {
        case .unified:
            return "Unified"
        case .mastodon(let feed):
            switch feed {
            case .home:
                return "Home"
            case .local:
                return "Local"
            case .federated:
                return "Federated"
            case .list(let id, let title):
                if let title = title {
                    return title
                }
                if let list = feedPickerViewModel.mastodonLists.first(where: { $0.id == id }) {
                    return list.title
                }
                return "List"
            case .instance(let server):
                return "Instance: \(server)"
            }
        case .bluesky(let feed):
            switch feed {
            case .following:
                return "Following"
            case .custom(let uri, let name):
                if let name = name {
                    return name
                }
                if let feed = feedPickerViewModel.blueskyFeeds.first(where: { $0.uri == uri }) {
                    return feed.displayName
                }
                return "Feed"
            }
        }
    }

    private func handleFeedSelection(_ selection: TimelineFeedSelection) {
        serviceManager.setTimelineFeedSelection(selection)
        controller.refreshTimeline()
    }

    @ViewBuilder
    private var timelineView: some View {
        if #available(iOS 17.0, *) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(controller.posts.enumerated()), id: \.element.stableId) { index, post in
                            postCard(for: post)
                                .id(scrollIdentifier(for: post))
                                .background(
                                    GeometryReader { geom in
                                        Color.clear.preference(
                                            key: TimelineVisibleItemPreferenceKey.self,
                                            value: [
                                                scrollIdentifier(for: post):
                                                    TimelineItemInfo(minY: geom.frame(in: .named("timelineScroll")).minY, index: index)
                                            ]
                                        )
                                    }
                                )

                            if post.id != controller.posts.last?.id {
                                Divider()
                                    .padding(.horizontal, 16)
                                    .accessibilityHidden(true)
                            }
                        }

                        if controller.hasNextPage && !controller.posts.isEmpty {
                            Color.clear
                                .frame(height: 1)
                                .task { await loadMorePostsFromTailIfNeeded() }
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
                .coordinateSpace(name: "timelineScroll")
                .onPreferenceChange(TimelineVisibleItemPreferenceKey.self) { positions in
                    lastVisiblePositions = positions

                    // Unread tracking — always runs, even during anchor lock
                    // This ensures the pill count ticks down as the user scrolls through new posts
                    if let topVisibleInfo = positions
                        .filter({ $0.value.minY >= -50 })
                        .min(by: { $0.value.minY < $1.value.minY }) {
                        controller.updateUnreadFromTopVisibleIndex(topVisibleInfo.value.index)
                    }
                    let visibleIds = Set(positions.filter { $0.value.minY >= 0 }.keys)
                    controller.markVisiblePostsAsRead(visibleIds)

                    // Anchor tracking — gated by locks to prevent position jumping
                    guard hasRestoredInitialAnchor, pendingAnchorRestoreId == nil else { return }
                    if let lockUntil = anchorLockUntil, Date() < lockUntil { return }
                    guard let nextId = positions
                        .filter({ $0.value.minY >= 0 })
                        .min(by: { $0.value.minY < $1.value.minY })?.key
                        ?? positions.min(by: { abs($0.value.minY) < abs($1.value.minY) })?.key
                    else { return }
                    if visibleAnchorId != nextId {
                        visibleAnchorId = nextId
                        persistedAnchorId = nextId
                        controller.updateCurrentAnchor(nextId)
                        logAnchorState("visible anchor -> \(nextId)")
                    }
                    let topId = controller.posts.first.map(scrollIdentifier(for:))
                    let isAtTop = topId.flatMap { positions[$0]?.minY }.map { $0 >= -12 } ?? false
                    if let topId = topId, let topInfo = positions[topId] {
                        lastTopVisibleId = topId
                        lastTopVisibleOffset = topInfo.minY
                    }
                    syncAnchorToTopIfNeeded(topId: topId, isAtTop: isAtTop)
                    let isDeepHistory = (topId.flatMap { positions[$0]?.minY }.map { $0 < -deepHistoryThreshold }) ?? false
                    controller.updateScrollState(isNearTop: isAtTop, isDeepHistory: isDeepHistory)
                }
                .scrollPosition(id: $scrollAnchorId)
                .onChange(of: scrollAnchorId) { newValue in
                    // During refresh, ignore scroll position changes - let onChange(of: posts) handle it
                    if isRefreshing {
                        return
                    }
                    // Normal scroll behavior when not refreshing
                    controller.recordVisibleInteraction()
                    controller.updateCurrentAnchor(newValue)
                    logAnchorState("scrollAnchorId changed -> \(newValue ?? "nil")")
                    updateJumpToLastReadVisibility()
                }
                .refreshable {
                    // BUFFER-THEN-MERGE: Fetch posts to buffer during .refreshable,
                    // then merge AFTER spinner dismisses. This prevents SwiftUI's
                    // built-in scroll-to-top behavior since content doesn't change.
                    //
                    // scrollPosition(id:) binding automatically preserves position when
                    // posts are inserted. As long as scrollAnchorId stays constant,
                    // the user stays at the same post visually.

                    isRefreshing = true
                    controller.prepareForRefresh(wasScrolledDown: !controller.isNearTop)
                    logAnchorState("refresh start (buffer) anchor=\(scrollAnchorId ?? "nil")")

                    // Fetch posts to buffer - timeline stays unchanged during fetch
                    let bufferedCount = await controller.fetchToBuffer()

                    logAnchorState("refresh fetch complete, buffer count=\(bufferedCount)")

                    // .refreshable ends here - spinner dismisses
                    isRefreshing = false
                    HapticEngine.refreshComplete(hasNewContent: bufferedCount > 0).trigger()
                    guard bufferedCount > 0 else { return }

                    logAnchorState("post-refresh merge starting, buffer=\(bufferedCount)")

                    // Small delay to ensure .refreshable animation is fully complete
                    Task {
                        try? await Task.sleep(nanoseconds: 100_000_000)

                        // Merge buffered posts - scrollPosition(id:) preserves position automatically
                        // No offset compensation needed - just trust the binding
                        controller.mergeBufferedPosts()

                        logAnchorState("post-refresh merge complete")
                    }
                }
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { _ in
                            controller.scrollInteractionBegan()
                        }
                        .onEnded { _ in
                            controller.scrollInteractionEnded()
                        }
                )
                .overlay(alignment: .top) {
                    VStack(spacing: 8) {
                        newPostsPill(proxy: proxy)
                        jumpToLastReadButton(proxy: proxy)
                    }
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.8),
                        value: newPostsAboveCount > 0 && !controller.isNearTop
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name.homeTabDoubleTapped))
                { _ in
                    HapticEngine.tap.trigger()
                    // Merge any buffered posts and scroll to top
                    if controller.bufferCount > 0 {
                        controller.scrollPolicy = .jumpToNow
                        controller.mergeBufferedPosts()
                    }
                    scrollToTop(using: proxy)
                    // Clear unread since user is going to top
                    controller.clearUnreadAboveViewport()
                    syncAnchorToTopIfNeeded(
                        topId: controller.posts.first.map(scrollIdentifier(for:)),
                        isAtTop: true
                    )
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
                        ForEach(controller.posts, id: \.stableId) { post in
                            postCard(for: post)
                                .id(scrollIdentifier(for: post))

                            if post.id != controller.posts.last?.id {
                                Divider()
                                    .padding(.horizontal, 16)
                                    .accessibilityHidden(true)
                            }
                        }

                        if controller.hasNextPage && !controller.posts.isEmpty {
                            Color.clear
                                .frame(height: 1)
                                .task { await loadMorePostsFromTailIfNeeded() }
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
                .refreshable {
                    // BUFFER-THEN-MERGE: Same approach as iOS 17+ path
                    isRefreshing = true
                    controller.prepareForRefresh(wasScrolledDown: true)
                    logAnchorState("refresh start (iOS 16, buffer)")

                    // Fetch posts to buffer - timeline stays unchanged
                    let bufferedCount = await controller.fetchToBuffer()

                    logAnchorState("refresh fetch complete (iOS 16), buffer count=\(bufferedCount)")

                    // .refreshable ends here - spinner dismisses
                    isRefreshing = false
                    HapticEngine.refreshComplete(hasNewContent: bufferedCount > 0).trigger()
                    guard bufferedCount > 0 else { return }

                    logAnchorState("post-refresh merge starting (iOS 16), buffer=\(bufferedCount)")

                    Task {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        controller.mergeBufferedPosts()
                        logAnchorState("post-refresh merge complete (iOS 16)")
                    }
                }
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { _ in
                            controller.scrollInteractionBegan()
                        }
                        .onEnded { _ in
                            controller.scrollInteractionEnded()
                        }
                )
                .overlay(alignment: .top) {
                    VStack(spacing: 8) {
                        newPostsPill(proxy: proxy)
                        jumpToLastReadButton(proxy: proxy)
                    }
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.8),
                        value: newPostsAboveCount > 0 && !controller.isNearTop
                    )
                }
                .onAppear {
                    // Best-effort restoration if we have a persisted ID (may be nil on first run)
                    if let id = persistedAnchorId {
                        withAnimation(.none) { proxy.scrollTo(id, anchor: .top) }
                    }
                    // Load last read post ID
                    lastReadPostId = ViewTracker.shared.getLastReadPostId()
                    updateJumpToLastReadVisibility()
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
                DebugLog.verbose("✅ Successfully reported post")
            } catch {
                DebugLog.verbose("❌ Failed to report post: \(error.localizedDescription)")
            }
            reportingPost = nil
        }
    }

    /// Count of new posts above viewport
    /// Priority: buffer count > pending merge bridge > unread count
    /// The pendingMergeCount bridges the async gap between buffer drain and unread count update,
    /// preventing the pill from flickering to 0 during the merge.
    private var newPostsAboveCount: Int {
        // If we have buffered posts waiting to merge, show that count
        if controller.bufferCount > 0 {
            return controller.bufferCount
        }
        // Bridge the gap: buffer just drained but updatePosts() hasn't fired yet
        if controller.pendingMergeCount > 0 && controller.unreadAboveViewportCount == 0 {
            return controller.pendingMergeCount
        }
        // Otherwise show the unread count (posts merged but above viewport)
        return controller.unreadAboveViewportCount
    }

    @ViewBuilder
    private func newPostsPill(proxy: ScrollViewProxy) -> some View {
        let count = newPostsAboveCount
        if count > 0 && !controller.isNearTop {
            Button(action: { handleNewPostsTap(proxy: proxy) }) {
                HStack(spacing: 8) {
                    Text("\(count) new post\(count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .contentTransition(.numericText())
                        .animation(
                            .spring(response: 0.3, dampingFraction: 0.8),
                            value: count
                        )
                    Image(systemName: "arrow.up.to.line")
                        .font(.caption)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
            }
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            .accessibilityIdentifier("NewPostsPill")
            .padding(.top, 8)
            .accessibilityLabel("\(count) new post\(count == 1 ? "" : "s")")
            .accessibilityHint("Tap to scroll to newest posts")
        }
    }
    
    private func handleNewPostsTap(proxy: ScrollViewProxy) {
        HapticEngine.tap.trigger()

        // If there are buffered posts, merge them first
        if controller.bufferCount > 0 {
            controller.scrollPolicy = .jumpToNow
            controller.mergeBufferedPosts()
        }

        // Scroll to top
        scrollToTop(using: proxy)

        // Clear unread tracking
        controller.clearUnreadAboveViewport()
    }
    
    @ViewBuilder
    private func jumpToLastReadButton(proxy: ScrollViewProxy) -> some View {
        if showJumpToLastRead, let lastReadId = lastReadPostId {
            Button(action: { handleJumpToLastRead(proxy: proxy, postId: lastReadId) }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                    Text("Jump to Last Read")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
            }
            .accessibilityIdentifier("JumpToLastReadButton")
            .accessibilityLabel("Jump to Last Read")
            .accessibilityHint("Tap to scroll to the last post you read")
        }
    }
    
    private func handleJumpToLastRead(proxy: ScrollViewProxy, postId: String) {
        guard let post = controller.posts.first(where: { $0.id == postId }) else { return }
        let identifier = scrollIdentifier(for: post)
        HapticEngine.tap.trigger()

        if #available(iOS 17.0, *) {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.35)) {
                scrollAnchorId = identifier
            }
        } else {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.35)) {
                proxy.scrollTo(identifier, anchor: .top)
            }
        }

        // Update visibility after scroll
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000) // Wait for scroll animation to complete
            updateJumpToLastReadVisibility()
        }
    }
    
    private func updateJumpToLastReadVisibility() {
        guard let lastReadId = lastReadPostId else {
            showJumpToLastRead = false
            return
        }
        
        // Check if last read post exists in current posts
        guard controller.posts.contains(where: { $0.id == lastReadId }) else {
            showJumpToLastRead = false
            return
        }
        
        // Don't show if merge pill is showing (to avoid clutter)
        if controller.bufferCount > 0 {
            showJumpToLastRead = false
            return
        }
        
        // Check if we're at the top (don't show if at top)
        if #available(iOS 17.0, *) {
            let topId = controller.posts.first.map(scrollIdentifier(for:))
            if let topId = topId, scrollAnchorId == topId {
                showJumpToLastRead = false
                return
            }
        }
        
        // Check if current position is below last read
        if let currentAnchorId = scrollAnchorId,
           let currentIndex = controller.posts.firstIndex(where: { scrollIdentifier(for: $0) == currentAnchorId }),
           let lastReadIndex = controller.posts.firstIndex(where: { $0.id == lastReadId }),
           currentIndex > lastReadIndex {
            showJumpToLastRead = true
        } else {
            // Also show if we don't have a current anchor but have posts and last read
            if scrollAnchorId == nil && !controller.posts.isEmpty {
                showJumpToLastRead = true
            } else {
                showJumpToLastRead = false
            }
        }
    }

    private func scrollToTop(using proxy: ScrollViewProxy) {
        guard let topId = controller.posts.first.map(scrollIdentifier(for:)) else { return }
        if #available(iOS 17.0, *) {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.35)) {
                scrollAnchorId = topId
            }
        } else {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.35)) {
                proxy.scrollTo(topId, anchor: .top)
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
        // CRITICAL FIX: Check for originalPost OR boostedBy metadata to catch all boosts
        // This is important because the canonical store may return the original post with boostedBy set
        let entryKind: TimelineEntryKind
        if post.originalPost != nil || post.boostedBy != nil {
            // This is a boost - use boostedBy if available, otherwise use authorUsername
            let boostedByHandle = post.boostedBy ?? post.authorUsername
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
        // Use snapshot if available for stable layout
        let snapshot = postSnapshots[post.id]
        return PostCardView(
            entry: entry,
            postActionStore: controller.postActionStore,
            postActionCoordinator: controller.postActionCoordinator,
            layoutSnapshot: snapshot,
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
                post.presentShareSheet()
            },
            onOpenInBrowser: { post.openInBrowser() },
            onCopyLink: { post.copyLink() },
            onReport: { reportingPost = post },
            onQuote: { quotingToPost = post }
        )
    }

    // MARK: - Private Helpers

    /// Ensure timeline is loaded - proper async pattern
    private func ensureTimelineLoaded() async {
        guard controller.posts.isEmpty && !controller.isLoading else { return }
        controller.requestInitialPrefetch()
    }

    /// Refresh timeline - proper async pattern for user-initiated refresh
    private func refreshTimeline() async {
        await controller.refreshTimelineAsync()
    }

    private func restorePendingAnchorIfPossible() {
        guard #available(iOS 17.0, *) else { return }
        guard !controller.posts.isEmpty else { return }
        // Don't restore if anchor is locked (e.g., during refresh)
        if let lockUntil = anchorLockUntil, Date() < lockUntil {
            logAnchorState("restore skipped - locked")
            return
        }
        guard let id = pendingAnchorRestoreId else {
            hasRestoredInitialAnchor = true
            return
        }
        logAnchorState("restore attempt id=\(id)")
        
        // Find the post with this identifier
        let matchingPost = controller.posts.first(where: { scrollIdentifier(for: $0) == id })
        guard matchingPost != nil else {
            // Anchor post not found - might have been filtered out or doesn't exist
            logAnchorState("restore failed - anchor not found")
            pendingAnchorRestoreId = nil
            hasRestoredInitialAnchor = true
            return
        }
        
        // Restore the anchor position
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            scrollAnchorId = id
        }
        persistedAnchorId = id
        // Lock anchor for a bit to prevent interference
        anchorLockUntil = Date().addingTimeInterval(0.8)
        pendingAnchorRestoreId = nil
        hasRestoredInitialAnchor = true
        logAnchorState("restore done")
    }

    private func scrollIdentifier(for post: Post) -> String {
        let stable = post.stableId
        return stable.hasSuffix("-") ? post.id : stable
    }

    private func logAnchorState(_ label: String) {
        guard UserDefaults.standard.bool(forKey: "debugScrollAnchor") else { return }
        let topId = controller.posts.first.map(scrollIdentifier(for:)) ?? "nil"
        let persisted = persistedAnchorId ?? "nil"
        let anchor = scrollAnchorId ?? "nil"
        let pending = pendingAnchorRestoreId ?? "nil"
        let visible = visibleAnchorId ?? "nil"
        let lock = anchorLockUntil?.timeIntervalSinceNow ?? -1
        print(
            "🧭 [ConsolidatedTimelineView] \(label) top=\(topId) persisted=\(persisted) anchor=\(anchor) pending=\(pending) visible=\(visible) lock=\(String(format: "%.2f", lock)) restored=\(hasRestoredInitialAnchor)"
        )
    }

    private func syncAnchorToTopIfNeeded(topId: String?, isAtTop: Bool) {
        guard #available(iOS 17.0, *), isAtTop, let topId = topId else { return }
        // Don't sync to top if we're in the middle of restoring an anchor (e.g., after pull-to-refresh)
        if let lockUntil = anchorLockUntil, Date() < lockUntil {
            logAnchorState("sync to top skipped - anchor locked")
            return
        }
        // Don't sync to top if we have a pending anchor restore (user was scrolled down)
        if pendingAnchorRestoreId != nil {
            logAnchorState("sync to top skipped - pending restore")
            return
        }
        if scrollAnchorId != topId {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { scrollAnchorId = topId }
            logAnchorState("sync to top")
        }
        persistedAnchorId = topId
        pendingAnchorRestoreId = nil
        // Clear unread when user reaches the top - they're viewing newest content
        controller.clearUnreadAboveViewport()
    }

    /// Trigger infinite scroll from tail sentinel only to avoid per-row task churn.
    private func loadMorePostsFromTailIfNeeded() async {
        guard !controller.posts.isEmpty else { return }
        guard shouldLoadMorePosts(currentIndex: controller.posts.count - 1) else { return }
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
    
    // MARK: - Layout Snapshot Management
    
    /// Build snapshots for posts (async, uses cache when available)
    private func buildSnapshotsForPosts(_ posts: [Post]) async {
        await withTaskGroup(of: (String, PostLayoutSnapshot).self) { group in
            for post in posts {
                group.addTask {
                    let snapshot = await snapshotBuilder.buildSnapshot(for: post)
                    return (post.id, snapshot)
                }
            }
            
            var newSnapshots: [String: PostLayoutSnapshot] = [:]
            for await (postId, snapshot) in group {
                newSnapshots[postId] = snapshot
            }
            
            // Update snapshots on main thread
            await MainActor.run {
                // Only update if snapshot changed (prevents unnecessary view updates)
                for (postId, snapshot) in newSnapshots {
                    if postSnapshots[postId] != snapshot {
                        postSnapshots[postId] = snapshot
                    }
                }
            }
        }
    }
    
    /// Prefetch dimensions for initial posts
    private func prefetchInitialPosts() async {
        let posts = controller.posts
        prefetcher.prefetchDimensions(for: posts)
        
        // Build initial snapshots synchronously (using cache only)
        var initialSnapshots: [String: PostLayoutSnapshot] = [:]
        for post in posts {
            let snapshot = snapshotBuilder.buildSnapshotSync(for: post)
            initialSnapshots[post.id] = snapshot
        }
        postSnapshots = initialSnapshots
        
        // Then build full snapshots async (with dimension fetching)
        await buildSnapshotsForPosts(posts)
    }
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

private struct TimelineItemInfo: Equatable {
    let minY: CGFloat
    let index: Int
}

private struct TimelineVisibleItemPreferenceKey: PreferenceKey {
    static var defaultValue: [String: TimelineItemInfo] = [:]

    static func reduce(value: inout [String: TimelineItemInfo], nextValue: () -> [String: TimelineItemInfo]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

#Preview {
    ConsolidatedTimelineView(serviceManager: SocialServiceManager())
}

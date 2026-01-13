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
    @State private var lastVisiblePositions: [String: CGFloat] = [:]
    @State private var lastTopVisibleId: String?
    @State private var lastTopVisibleOffset: CGFloat = 0
    @State private var pendingMergeAnchorId: String?
    @State private var pendingMergeAnchorOffset: CGFloat?
    @State private var mergeOffsetCompensation: CGFloat = 0
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
                
                // During refresh, don't let scrollPosition binding reset - maintain the anchor
                if isRefreshing, let anchorId = pendingAnchorRestoreId {
                    // Keep the scrollAnchorId set to prevent SwiftUI from resetting to top
                    if scrollAnchorId != anchorId {
                        scrollAnchorId = anchorId
                    }
                } else if !isRefreshing {
                    // Not refreshing, restore normally
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
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: TimelineVisibleItemPreferenceKey.self,
                                            value: [
                                                scrollIdentifier(for: post):
                                                    proxy.frame(in: .named("timelineScroll")).minY
                                            ]
                                        )
                                    }
                                )
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
                    .padding(.top, mergeOffsetCompensation)
                    .scrollTargetLayout()
                }
                .coordinateSpace(name: "timelineScroll")
                .onPreferenceChange(TimelineVisibleItemPreferenceKey.self) { positions in
                    lastVisiblePositions = positions
                    guard hasRestoredInitialAnchor, pendingAnchorRestoreId == nil else { return }
                    if let lockUntil = anchorLockUntil, Date() < lockUntil { return }
                    guard let nextId = positions
                        .filter({ $0.value >= 0 })
                        .min(by: { $0.value < $1.value })?.key
                        ?? positions.min(by: { abs($0.value) < abs($1.value) })?.key
                    else { return }
                    if visibleAnchorId != nextId {
                        visibleAnchorId = nextId
                        persistedAnchorId = nextId
                        controller.updateCurrentAnchor(nextId)
                        logAnchorState("visible anchor -> \(nextId)")
                    }
                    let topId = controller.posts.first.map(scrollIdentifier(for:))
                    let isAtTop = topId.flatMap { positions[$0] }.map { $0 >= -12 } ?? false
                    if let topId = topId, let topOffset = positions[topId] {
                        lastTopVisibleId = topId
                        lastTopVisibleOffset = topOffset
                    }
                    syncAnchorToTopIfNeeded(topId: topId, isAtTop: isAtTop)
                    let deepHistoryThreshold = UIScreen.main.bounds.height * 2.0
                    let isDeepHistory = (topId.flatMap { positions[$0] }.map { $0 < -deepHistoryThreshold }) ?? false
                    controller.updateScrollState(isNearTop: isAtTop, isDeepHistory: isDeepHistory)

                    if let mergeId = pendingMergeAnchorId,
                        let mergeOffset = pendingMergeAnchorOffset,
                        let currentOffset = positions[mergeId]
                    {
                        let delta = MergeOffsetCompensator.compensation(
                            previousOffset: mergeOffset,
                            currentOffset: currentOffset
                        )
                        if delta != 0 {
                            mergeOffsetCompensation = delta
                        }
                        pendingMergeAnchorId = nil
                        pendingMergeAnchorOffset = nil
                    }
                }
                .scrollPosition(id: $scrollAnchorId)
                .onChange(of: scrollAnchorId) { newValue in
                    // During refresh, prevent scrollPosition from resetting to top
                    if isRefreshing, let pendingId = pendingAnchorRestoreId {
                        // If scrollPosition is trying to change to the top post during refresh, prevent it
                        let topId = controller.posts.first.map(scrollIdentifier(for:))
                        if newValue == topId && newValue != pendingId {
                            // It's trying to jump to top - prevent it silently
                            // Don't log to avoid spam, just restore
                            scrollAnchorId = pendingId
                            return
                        }
                    }
                    controller.recordVisibleInteraction()
                    controller.updateCurrentAnchor(newValue)
                    logAnchorState("scrollAnchorId changed -> \(newValue ?? "nil")")
                    updateJumpToLastReadVisibility()
                }
                .refreshable {
                    // Preserve current anchor during refresh
                    // Capture the anchor BEFORE refresh starts
                    let anchorBeforeRefresh = visibleAnchorId ?? scrollAnchorId ?? persistedAnchorId
                    pendingAnchorRestoreId = anchorBeforeRefresh
                    isRefreshing = true
                    // Lock anchor restoration to prevent interference
                    anchorLockUntil = Date().addingTimeInterval(1.5)
                    logAnchorState("refresh start anchor=\(anchorBeforeRefresh ?? "nil")")
                    
                    // Perform the refresh
                    await refreshTimeline()
                    
                    // After refresh completes, wait for SwiftUI to finish updating
                    // Then restore scroll position smoothly using scrollPosition binding
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                    
                    // Restore using scrollPosition binding (smoother than proxy.scrollTo)
                    if let anchorId = anchorBeforeRefresh,
                       controller.posts.contains(where: { scrollIdentifier(for: $0) == anchorId }) {
                        logAnchorState("restoring scroll to anchor=\(anchorId)")
                        await MainActor.run {
                            // Use scrollPosition binding for smooth, non-jumpy restoration
                            scrollAnchorId = anchorId
                            persistedAnchorId = anchorId
                        }
                    }
                    
                    // Give it a moment to settle before allowing normal scroll behavior
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    isRefreshing = false
                    logAnchorState("refresh end")
                }
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { _ in
                            if mergeOffsetCompensation != 0 {
                                mergeOffsetCompensation = 0
                            }
                            controller.scrollInteractionBegan()
                        }
                        .onEnded { _ in
                            controller.scrollInteractionEnded()
                        }
                )
                .overlay(alignment: .top) {
                    VStack(spacing: 8) {
                        mergePill(proxy: proxy)
                        jumpToLastReadButton(proxy: proxy)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name.homeTabDoubleTapped))
                { _ in
                    scrollToTop(using: proxy)
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
                        ForEach(Array(controller.posts.enumerated()), id: \.element.stableId) { index, post in
                            postCard(for: post)
                                .id(scrollIdentifier(for: post))
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
                    .padding(.top, mergeOffsetCompensation)
                }
                .refreshable {
                    // For iOS 16, capture current scroll position before refresh
                    // Note: iOS 16 doesn't have scrollPosition API, so we rely on ScrollViewReader
                    // The restoration will happen via onAppear if persistedAnchorId is set
                    await refreshTimeline()
                }
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { _ in
                            if mergeOffsetCompensation != 0 {
                                mergeOffsetCompensation = 0
                            }
                            controller.scrollInteractionBegan()
                        }
                        .onEnded { _ in
                            controller.scrollInteractionEnded()
                        }
                )
                .overlay(alignment: .top) {
                    VStack(spacing: 8) {
                        mergePill(proxy: proxy)
                        jumpToLastReadButton(proxy: proxy)
                    }
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
                print("✅ Successfully reported post")
            } catch {
                print("❌ Failed to report post: \(error)")
            }
            reportingPost = nil
        }
    }

    @ViewBuilder
    private func mergePill(proxy: ScrollViewProxy) -> some View {
        if controller.bufferCount > 0 {
            Button(action: { handleMergeTap(proxy: proxy) }) {
                HStack(spacing: 8) {
                    Text("\(controller.bufferCount) new posts")
                        .font(.subheadline)
                        .fontWeight(.semibold)
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
            .accessibilityIdentifier("UnifiedMergePill")
            .padding(.top, 8)
            .accessibilityLabel("\(controller.bufferCount) new posts")
            .accessibilityHint("Tap to merge new posts into the timeline")
        }
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
        
        if #available(iOS 17.0, *) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                scrollAnchorId = identifier
            }
        } else {
            withAnimation(.none) {
                proxy.scrollTo(identifier, anchor: .top)
            }
        }
        
        // Update visibility after scroll
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000) // Wait for scroll to complete
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

    private func handleMergeTap(proxy: ScrollViewProxy) {
        if controller.isNearTop {
            controller.scrollPolicy = .jumpToNow
            controller.mergeBufferedPosts()
            return
        }
        scrollToTop(using: proxy)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            controller.scrollPolicy = .jumpToNow
            controller.mergeBufferedPosts()
        }
    }

    private func scrollToTop(using proxy: ScrollViewProxy) {
        guard let topId = controller.posts.first.map(scrollIdentifier(for:)) else { return }
        if #available(iOS 17.0, *) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { scrollAnchorId = topId }
        } else {
            withAnimation(.none) { proxy.scrollTo(topId, anchor: .top) }
        }
    }

    private func prepareMergeAnchorRestore() {
        guard #available(iOS 17.0, *) else { return }
        let anchorId = lastTopVisibleId ?? visibleAnchorId ?? scrollAnchorId ?? persistedAnchorId
        pendingMergeAnchorId = anchorId
        pendingMergeAnchorOffset = lastTopVisibleOffset
        pendingAnchorRestoreId = anchorId
        anchorLockUntil = Date().addingTimeInterval(0.6)
        logAnchorState("merge anchor set -> \(anchorId ?? "nil")")
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
        print("🔄 ConsolidatedTimelineView: User-initiated refresh (pull-to-refresh)")
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

private struct TimelineVisibleItemPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

#Preview {
    ConsolidatedTimelineView(serviceManager: SocialServiceManager())
}

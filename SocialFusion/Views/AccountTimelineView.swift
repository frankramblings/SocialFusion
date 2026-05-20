import SwiftUI

struct AccountTimelineView: View {
    private let serviceManager: SocialServiceManager
    let account: SocialAccount

    @StateObject private var navigationEnvironment = PostNavigationEnvironment()
    @StateObject private var controller: AccountTimelineController

    // Scroll position persistence (per account)
    @State private var scrollAnchorId: String?
    @State private var pendingAnchorRestoreId: String?
    @State private var hasRestoredInitialAnchor = false
    @State private var visibleAnchorId: String?
    @State private var anchorLockUntil: Date?
    @State private var lastVisiblePositions: [String: CGFloat] = [:]
    @State private var lastTopVisibleId: String?
    @State private var lastTopVisibleOffset: CGFloat = 0
    @State private var pendingMergeAnchorOffset: CGFloat?
    @State private var mergeOffsetCompensation: CGFloat = 0
    @State private var mergePillVisible = false
    @State private var scrollToTopOpacity: Double = 1.0
    @State private var pillBumpScale: CGFloat = 1.0
    @State private var lastSeenPillCount: Int = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var anchorDefaultsKey: String { "accountTimeline.anchorId.\(account.id)" }
    private func persistedAnchor() -> String? { UserDefaults.standard.string(forKey: anchorDefaultsKey) }
    private func setPersistedAnchor(_ id: String?) {
        if let id = id {
            UserDefaults.standard.set(id, forKey: anchorDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: anchorDefaultsKey)
        }
    }

    init(account: SocialAccount, serviceManager: SocialServiceManager) {
        self.account = account
        self.serviceManager = serviceManager
        _controller = StateObject(
            wrappedValue: AccountTimelineController(
                account: account,
                serviceManager: serviceManager
            )
        )
    }

    private var timelineEntries: [TimelineEntry] {
        serviceManager.makeTimelineEntries(from: controller.posts)
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            if controller.isLoading && controller.posts.isEmpty {
                loadingView
            } else if controller.posts.isEmpty {
                emptyStateView
            } else {
                contentView
            }
        }
        .navigationDestination(
            isPresented: Binding(
                get: { navigationEnvironment.selectedUser != nil },
                set: { if !$0 { navigationEnvironment.clearNavigation() } }
            )
        ) {
            if let user = navigationEnvironment.selectedUser {
                ProfileView(user: user, serviceManager: serviceManager)
                    .environmentObject(serviceManager)
            }
        }
        .onAppear {
            if #available(iOS 17.0, *), pendingAnchorRestoreId == nil {
                pendingAnchorRestoreId = scrollAnchorId ?? persistedAnchor()
            }
            controller.setTimelineVisible(true)
            controller.requestInitialPrefetch()
        }
        .onDisappear {
            controller.setTimelineVisible(false)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                setPersistedAnchor(visibleAnchorId ?? scrollAnchorId)
            }
            if phase == .active {
                controller.handleAppForegrounded()
            }
        }
        .onChange(of: controller.posts) {
            restorePendingAnchorIfPossible()
        }
        .toolbar {
            if controller.bufferCount > 0 {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Circle()
                        .fill(Color.secondary.opacity(0.7))
                        .frame(width: 8, height: 8)
                        .accessibilityIdentifier("AccountBufferedIndicator")
                        .accessibilityLabel("\(controller.bufferCount) new post\(controller.bufferCount == 1 ? "" : "s")")
                }
            }
        }
        .overlay {
            if UITestHooks.isEnabled {
                debugOverlay
            }
        }
    }

    private var loadingView: some View {
        ProgressView()
            .scaleEffect(1.5)
    }

    private var emptyStateView: some View {
        let platformColor = Color(hex: account.platform.colorHex)
        return VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [platformColor.opacity(0.18), platformColor.opacity(0.0)],
                            center: .center,
                            startRadius: 4,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                Image(systemName: "tray")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(platformColor.gradient)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(.top, 24)

            VStack(spacing: 6) {
                Text("No posts to display")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary.opacity(0.85))

                Text("Pull down to refresh.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var contentView: some View {
        if #available(iOS 17.0, *) {
            iOS17ScrollView
        } else {
            legacyScrollView
        }
    }

    private var debugOverlay: some View {
        #if DEBUG
        VStack(spacing: 6) {
            Button("Seed Timeline") { controller.debugSeedTimeline() }
                .accessibilityIdentifier("AccountSeedTimelineButton")
            Button("Trigger Idle Prefetch") { controller.debugTriggerIdlePrefetch() }
                .accessibilityIdentifier("AccountTriggerIdlePrefetchButton")
            Button("Begin Scroll") { controller.scrollInteractionBegan() }
                .accessibilityIdentifier("AccountBeginScrollButton")
            Button("End Scroll") { controller.scrollInteractionEnded() }
                .accessibilityIdentifier("AccountEndScrollButton")
            Text("\(controller.bufferCount)")
                .accessibilityIdentifier("AccountBufferCount")
            Text(lastTopVisibleId ?? "nil")
                .accessibilityIdentifier("AccountTopAnchorId")
            Text(String(format: "%.2f", lastTopVisibleOffset))
                .accessibilityIdentifier("AccountTopAnchorOffset")
        }
        .font(.caption2)
        .opacity(0.01)
        #else
        EmptyView()
        #endif
    }

    @available(iOS 17.0, *)
    private var iOS17ScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    postListContent
                }
                .padding(.top, mergeOffsetCompensation)
                .padding(.vertical)
                .scrollTargetLayout()
                // Same fade-and-snap mechanism as ConsolidatedTimelineView —
                // a brief opacity dip masks the index jump when the user
                // taps the merge pill or double-taps the tab while deep in
                // the timeline. See scrollToTop(using:).
                .opacity(scrollToTopOpacity)
            }
            .coordinateSpace(name: "accountTimelineScroll")
            .onPreferenceChange(AccountTimelineVisibleItemPreferenceKey.self) { positions in
                handleScrollPreferenceChange(positions)
            }
            .scrollPosition(id: $scrollAnchorId)
            .onChange(of: scrollAnchorId) {
                controller.recordVisibleInteraction()
            }
            .refreshable {
                let anchorBefore = visibleAnchorId ?? scrollAnchorId ?? persistedAnchor()
                pendingAnchorRestoreId = anchorBefore
                await controller.manualRefresh()
                HapticEngine.tap.trigger()
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
                mergePill(proxy: proxy)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name.homeTabDoubleTapped))
            { _ in
                HapticEngine.tap.trigger()
                scrollToTop(using: proxy)
                syncAnchorToTopIfNeeded(
                    topId: controller.posts.first?.id,
                    isAtTop: true
                )
            }
            .onAppear {
                if pendingAnchorRestoreId == nil {
                    pendingAnchorRestoreId = persistedAnchor()
                }
                restorePendingAnchorIfPossible()
            }
        }
    }

    private var legacyScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    postListContent
                }
                .padding(.top, mergeOffsetCompensation)
                .padding(.vertical)
            }
            .refreshable {
                await controller.manualRefresh()
                HapticEngine.tap.trigger()
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
                mergePill(proxy: proxy)
            }
            .onAppear {
                if let id = persistedAnchor() {
                    withAnimation(.none) { proxy.scrollTo(id, anchor: .top) }
                }
            }
        }
    }

    private var postListContent: some View {
        Group {
            ForEach(Array(timelineEntries.enumerated()), id: \.element.id) { index, entry in
                PostCardView(
                    entry: entry,
                    postActionStore: serviceManager.postActionStore,
                    postActionCoordinator: serviceManager.postActionCoordinator,
                    onAuthorTap: { navigationEnvironment.navigateToUser(from: entry.post) },
                    onShare: { entry.post.presentShareSheet() },
                    onOpenInBrowser: { entry.post.openInBrowser() },
                    onCopyLink: { entry.post.copyLink() },
                    onReport: { entry.post.report(via: serviceManager) }
                )
                .id(entry.id)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: AccountTimelineVisibleItemPreferenceKey.self,
                            value: [entry.id: proxy.frame(in: .named("accountTimelineScroll")).minY]
                        )
                    }
                )
                .padding(.horizontal)
                .onAppear {
                    if shouldLoadMorePosts(currentIndex: index) {
                        Task { await controller.loadMorePosts() }
                    }
                }
            }

            if controller.isLoadingNextPage {
                infiniteScrollLoadingView
                    .padding(.vertical, 20)
            }

            if !controller.hasNextPage && !controller.posts.isEmpty {
                endOfTimelineView
                    .padding(.vertical, 20)
            }
        }
    }

    private func handleScrollPreferenceChange(_ positions: [String: CGFloat]) {
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
            setPersistedAnchor(nextId)
        }
        let topId = controller.posts.first.map { $0.id }
        let isAtTop = topId.flatMap { positions[$0] }.map { $0 >= -12 } ?? false
        if let topId = topId, let topOffset = positions[topId] {
            lastTopVisibleId = topId
            lastTopVisibleOffset = topOffset
            syncAnchorToTopIfNeeded(topId: topId, isAtTop: isAtTop)
            let deepHistoryThreshold = UIScreen.main.bounds.height * 2.0
            let isDeepHistory = topOffset < -deepHistoryThreshold
            controller.updateScrollState(
                isNearTop: isAtTop,
                isDeepHistory: isDeepHistory
            )
        } else {
            controller.updateScrollState(isNearTop: isAtTop, isDeepHistory: false)
        }

        if let mergeId = pendingAnchorRestoreId,
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
            pendingMergeAnchorOffset = nil
        }
    }

    private var infiniteScrollLoadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.85)
            Text("Loading more posts")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading more posts")
    }

    private var endOfTimelineView: some View {
        VStack(spacing: 10) {
            // Two-layer palette: white checkmark on green circle —
            // matches ConsolidatedTimelineView's end-of-timeline marker.
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.white, Color.green)
                .symbolRenderingMode(.palette)
            Text("You're all caught up")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary.opacity(0.85))
            Text("No more posts to load")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You're all caught up, no more posts to load")
        .padding(.horizontal)
    }

    private func restorePendingAnchorIfPossible() {
        guard #available(iOS 17.0, *) else { return }
        guard !controller.posts.isEmpty else { return }
        guard let id = pendingAnchorRestoreId else {
            hasRestoredInitialAnchor = true
            return
        }
        if controller.posts.contains(where: { $0.id == id }) {
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
            setPersistedAnchor(id)
            anchorLockUntil = Date().addingTimeInterval(0.6)
        }
        pendingAnchorRestoreId = nil
        hasRestoredInitialAnchor = true
    }

    /// Determines if we should load more posts based on current scroll position
    private func shouldLoadMorePosts(currentIndex: Int) -> Bool {
        let totalPosts = timelineEntries.count
        let threshold = max(5, totalPosts / 4)  // Load when 25% from bottom, minimum 5 posts

        return currentIndex >= totalPosts - threshold
            && controller.hasNextPage
            && !controller.isLoadingNextPage
    }

    @ViewBuilder
    private func mergePill(proxy: ScrollViewProxy) -> some View {
        let count = controller.bufferCount
        if count > 0 {
            Button {
                HapticEngine.tap.trigger()
                handleMergeTap(proxy: proxy)
            } label: {
                HStack(spacing: 8) {
                    Text("\(count) new post\(count == 1 ? "" : "s")")
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.numericText())
                        .animation(
                            .spring(response: 0.3, dampingFraction: 0.8),
                            value: count
                        )
                    Image(systemName: "arrow.up.to.line")
                        .font(.caption.weight(.semibold))
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
            .buttonStyle(MergePillPressStyle())
            // Matching the entrance choreography ConsolidatedTimelineView's
            // newPostsPill received in iter 202 — spring scale + fade so
            // the pill lands rather than slides. Settles after one beat;
            // no perpetual pulse.
            //
            // pillBumpScale composes multiplicatively for the count-increase
            // bump (iter 207, mirrored here for parity across timelines).
            .scaleEffect((mergePillVisible ? 1.0 : 0.96) * pillBumpScale)
            .opacity(mergePillVisible ? 1.0 : 0.0)
            .onAppear {
                lastSeenPillCount = count
                if reduceMotion {
                    mergePillVisible = true
                } else {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.7)) {
                        mergePillVisible = true
                    }
                }
            }
            .onDisappear {
                mergePillVisible = false
                pillBumpScale = 1.0
                lastSeenPillCount = 0
            }
            .onChange(of: count) { _, newValue in
                guard !reduceMotion, newValue > lastSeenPillCount, lastSeenPillCount > 0 else {
                    lastSeenPillCount = newValue
                    return
                }
                lastSeenPillCount = newValue
                withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                    pillBumpScale = 1.06
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 160_000_000)
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                        pillBumpScale = 1.0
                    }
                }
            }
            .accessibilityIdentifier("AccountMergePill")
            .padding(.top, 8)
            .accessibilityLabel("\(count) new post\(count == 1 ? "" : "s")")
            .accessibilityHint("Merges new posts into the timeline")
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        }
    }

    private func handleMergeTap(proxy: ScrollViewProxy) {
        if controller.isNearTop {
            prepareMergeAnchorRestore()
            controller.mergeBufferedPosts()
            return
        }
        scrollToTop(using: proxy)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            prepareMergeAnchorRestore()
            controller.mergeBufferedPosts()
        }
    }

    /// Scroll the timeline back to the top. Callers fire the tap haptic
    /// at the moment of intent — this method intentionally fires none of
    /// its own so the gesture feels like one crisp action, not two
    /// (matches ConsolidatedTimelineView.scrollToTop, iter 202).
    private func scrollToTop(using proxy: ScrollViewProxy) {
        guard let topId = controller.posts.first?.id else { return }
        let isFarFromTop = !controller.isNearTop

        if isFarFromTop && !reduceMotion {
            // Brief crossfade masks the scroll-position teleport so the
            // jump reads as 'whoosh to the top' rather than a snap.
            withAnimation(.easeOut(duration: 0.12)) {
                scrollToTopOpacity = 0.65
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                if #available(iOS 17.0, *) {
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) { scrollAnchorId = topId }
                } else {
                    withAnimation(.none) { proxy.scrollTo(topId, anchor: .top) }
                }
                withAnimation(.easeOut(duration: 0.18)) {
                    scrollToTopOpacity = 1.0
                }
            }
        } else {
            if #available(iOS 17.0, *) {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { scrollAnchorId = topId }
            } else {
                withAnimation(.none) { proxy.scrollTo(topId, anchor: .top) }
            }
        }
    }

    private func prepareMergeAnchorRestore() {
        guard #available(iOS 17.0, *) else { return }
        let anchorId = lastTopVisibleId ?? visibleAnchorId ?? scrollAnchorId ?? persistedAnchor()
        pendingMergeAnchorOffset = lastTopVisibleOffset
        pendingAnchorRestoreId = anchorId
        anchorLockUntil = Date().addingTimeInterval(0.6)
    }

    private func syncAnchorToTopIfNeeded(topId: String?, isAtTop: Bool) {
        guard #available(iOS 17.0, *), isAtTop, let topId = topId else { return }
        if scrollAnchorId != topId {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { scrollAnchorId = topId }
        }
        setPersistedAnchor(topId)
        pendingAnchorRestoreId = nil
    }
}

private struct AccountTimelineVisibleItemPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
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

        AccountTimelineView(account: mastodonAccount, serviceManager: SocialServiceManager())
    }
}

/// Subtle press feedback for the floating "new posts" pill — scales down and
/// dims to acknowledge the tap, without overpowering the gentle reveal.
private struct MergePillPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

import Combine
import SwiftUI
import UIKit

// PostDetailView import resolution

// MARK: - PostItem for sheet presentation
struct PostItem: Identifiable {
    let id: String
    let post: Post

    init(post: Post) {
        self.id = post.id
        self.post = post
    }
}

// MARK: - UnifiedTimelineView
struct UnifiedTimelineView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @State private var showingAuthError = false
    @State private var authErrorMessage = ""
    @State private var showingErrorAlert = false
    @State private var errorMessage: String? = nil
    @State private var isRefreshing = false

    // PHASE 3+: Enhanced TimelineState with smart restoration
    @StateObject private var timelineState = TimelineState()

    @State private var isLoading = false
    @State private var entries: [TimelineEntry] = []  // Keep for compatibility during transition
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: TimelineViewModel

    // Navigation state
    @State private var selectedPostForDetail: Post? = nil
    @State private var selectedPostForReply: Post? = nil
    @State private var showingComposeSheet = false
    @State private var showingDetailView = false
    @State private var showingReplyView = false

    // Enhanced scroll state with smart restoration
    @State private var scrollPosition: TimelineEntry? = nil
    @State private var savedScrollPosition: TimelineEntry? = nil
    @State private var isScrolling = false
    @State private var hasInitiallyLoaded = false
    @State private var lastScrollOffset: CGFloat = 0
    @State private var shouldShowRestorationBanner = false

    // Store accounts for filtering
    private let accounts: [SocialAccount]

    init(accounts: [SocialAccount]) {
        self.accounts = accounts
        let viewModel = TimelineViewModel(accounts: accounts)
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    // PHASE 3+: Enhanced computed property that uses TimelineState
    private var displayEntries: [TimelineEntry] {
        // Use TimelineState if it has content, otherwise fallback to existing entries
        let timelineEntries = timelineState.entries.map { entry in
            let kind: TimelineEntryKind
            if let boostedBy = entry.post.boostedBy {
                kind = .boost(boostedBy: boostedBy)
            } else {
                kind = .normal
            }

            return TimelineEntry(
                id: entry.id,
                kind: kind,
                post: entry.post,
                createdAt: entry.post.createdAt
            )
        }
        return timelineEntries.isEmpty ? entries : timelineEntries
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // PHASE 3+: Restoration suggestions banner (only show as fallback)
                if timelineState.showRestoreOptions && hasInitiallyLoaded
                    && shouldShowRestorationBanner
                {
                    restorationSuggestionsBanner
                }

                // PHASE 3+: Sync status indicator
                if case .syncing = timelineState.syncStatus {
                    syncStatusBanner
                }

                // Timeline Content
                if isLoading && displayEntries.isEmpty {
                    loadingView
                } else if displayEntries.isEmpty {
                    emptyView
                } else {
                    timelineContent
                }
            }
            .onAppear {
                // PHASE 3+: Enhanced onAppear with smart restoration
                Task {
                    // Load cached content immediately for instant display
                    // TODO: Implement loadCachedContent method or remove this call
                    timelineState.updateLastVisitDate()

                    // Perform cross-session sync - DISABLED to prevent hangs
                    // await timelineState.syncAcrossDevices()

                    // Same: Existing network loading logic preserved
                    if !hasInitiallyLoaded
                        && (!serviceManager.mastodonAccounts.isEmpty
                            || !serviceManager.blueskyAccounts.isEmpty)
                    {
                        hasInitiallyLoaded = true
                        // Load timeline when view appears for the first time
                        if let account = serviceManager.mastodonAccounts.first
                            ?? serviceManager.blueskyAccounts.first
                        {
                            viewModel.refreshTimeline(for: account)
                        }
                    }
                }
            }
            .refreshable {
                await refreshTimeline()
            }
            .alert("Error", isPresented: $showingErrorAlert) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }

            // PHASE 3+: Enhanced unread count indicator with sync status
            if timelineState.unreadCount > 0 {
                unreadCountIndicator
            }

            // Debug UI removed to prevent AttributeGraph cycles
        }
        // Navigation Links - iOS 16 compatible
        .background(
            Group {
                NavigationLink(
                    destination: Group {
                        if let post = selectedPostForDetail {
                            let viewModel = PostViewModel(
                                post: post, serviceManager: serviceManager)
                            PostDetailNavigationView(
                                viewModel: viewModel,
                                focusReplyComposer: false
                            )
                        }
                    },
                    isActive: $showingDetailView
                ) { EmptyView() }

                NavigationLink(
                    destination: Group {
                        if let post = selectedPostForReply {
                            let viewModel = PostViewModel(
                                post: post, serviceManager: serviceManager)
                            PostDetailNavigationView(
                                viewModel: viewModel,
                                focusReplyComposer: true
                            )
                        }
                    },
                    isActive: $showingReplyView
                ) { EmptyView() }
            }
            .opacity(0)
        )
        .sheet(isPresented: $showingComposeSheet) {
            ComposeView(replyingTo: nil)
                .environmentObject(serviceManager)
        }
        .onReceive(viewModel.$state) { state in
            // PHASE 3+: Update both existing entries and TimelineState
            // Use Task to avoid "Modifying state during view update" warnings
            Task { @MainActor in
                // Small delay to ensure we're not in the middle of a view update
                try? await Task.sleep(nanoseconds: 1_000_000)  // 1ms

                let posts = state.posts
                self.entries = self.serviceManager.makeTimelineEntries(from: posts)  // Keep existing for compatibility
                self.isLoading = state.isLoading

                // Update TimelineState with new posts (preserves scroll position)
                if !posts.isEmpty {
                    let wasFirstLoad = !timelineState.isInitialized
                    timelineState.updateFromPosts(
                        posts, preservePosition: timelineState.isInitialized)

                    // If this was the first load, we'll handle position restoration in the ScrollViewReader
                    if wasFirstLoad {
                        NSLog(
                            "🎯 First load detected, position restoration will be handled in timeline content"
                        )
                    }
                }
            }
        }
    }

    // PHASE 3+: Restoration suggestions banner
    private var restorationSuggestionsBanner: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Continue Reading?")
                        .font(.headline)
                        .foregroundColor(.primary)

                    if let suggestion = timelineState.restorationSuggestions.first {
                        Text(suggestion.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    Button("Continue") {
                        if let suggestion = timelineState.restorationSuggestions.first {
                            applyRestorationSuggestion(suggestion)
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .clipShape(Capsule())

                    Button("Dismiss") {
                        timelineState.dismissRestorationSuggestions()
                        shouldShowRestorationBanner = false
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(.separator)),
                alignment: .bottom
            )
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // PHASE 3+: Sync status banner
    private var syncStatusBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)

            Text("Syncing position across devices...")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            if let lastSyncTime = timelineState.lastSyncTime {
                Text("Last: \(lastSyncTime.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .transition(.opacity)
    }

    private var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading timeline...")
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Posts")
                .font(.title2)
                .bold()

            Text("Connect your accounts to see posts in your timeline")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var timelineContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("scroll")).minY)
                }
                .frame(height: 0)

                LazyVStack(spacing: 0) {
                    ForEach(displayEntries, id: \.id) { entry in
                        let index = displayEntries.firstIndex(where: { $0.id == entry.id }) ?? 0

                        ResponsivePostCardView(
                            entry: entry,
                            onReply: { handleReplyTap(entry.post) },
                            onRepost: { Task { await handleBoostTap(entry.post) } },
                            onLike: { Task { await handleLikeTap(entry.post) } },
                            onShare: { handleShareTap(entry.post) },
                            onPostTap: { handlePostTap(entry.post) },
                            viewModel: nil
                        )
                        .padding(.horizontal, 4)  // Reduced padding for tighter layout
                        .padding(.vertical, 4)  // Reduced padding for tighter layout
                        .onAppear {
                            // PHASE 3+: Enhanced read tracking and position saving
                            // Use DispatchQueue to defer state updates and avoid AttributeGraph cycles
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                timelineState.markPostAsRead(entry.post.id)
                            }

                            // Save position as user scrolls through - with longer delay to ensure it's intentional scrolling
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                timelineState.saveScrollPosition(entry.post.id)
                            }

                            // Clear unread count if user has scrolled to the top (first few posts)
                            if index <= 2 && timelineState.unreadCount > 0 {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    timelineState.clearAllUnread()
                                    print("📱 Cleared unread count - user reached top of timeline")
                                }
                            }
                        }

                        // Add divider between posts (but not after the last one)
                        if entry.id != displayEntries.last?.id {
                            Divider()
                                .background(Color.gray.opacity(0.2))
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.bottom, 100)  // Extra padding for better scroll experience
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                // Clear unread count when user scrolls to the top
                if value >= -10 && timelineState.unreadCount > 0 {  // Allow small tolerance for "at top"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        timelineState.clearAllUnread()
                        print("📱 Cleared unread count - user scrolled to top (offset: \(value))")
                    }
                }
            }
            .refreshable {
                await refreshTimeline()
            }
            .onReceive(NotificationCenter.default.publisher(for: .scrollToTop)) { _ in
                // Same: Existing scroll to top functionality with safety checks
                guard let firstEntry = displayEntries.first else { return }

                // Use DispatchQueue to avoid ScrollViewProxy access during view updates
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        proxy.scrollTo(firstEntry.id, anchor: .top)
                    }
                }
                // Clear unread state separately to avoid AttributeGraph cycles
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    timelineState.clearAllUnread()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .scrollToPosition)) {
                notification in
                // Handle scroll to specific position for Continue Reading
                guard let userInfo = notification.userInfo,
                    let postId = userInfo["postId"] as? String,
                    let targetEntry = displayEntries.first(where: { $0.post.id == postId })
                else {
                    let unknownId = notification.userInfo?["postId"] as? String ?? "unknown"
                    print("🎯 Failed to find target post \(unknownId) for position restoration")
                    return
                }

                print("🎯 Scrolling to position: \(postId)")

                // Use DispatchQueue to avoid "Modifying state during view update"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 1.0)) {
                        proxy.scrollTo(targetEntry.id, anchor: .top)
                    }

                    print(
                        "🎯 Position restoration completed - unread indicator should now work properly"
                    )
                }
            }
        }
    }

    // PHASE 3+: Enhanced unread count indicator with sync status
    private var unreadCountIndicator: some View {
        VStack {
            HStack {
                Spacer()

                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))

                        Text("\(timelineState.unreadCount)")
                            .font(.system(size: 18, weight: .bold))
                            .monospacedDigit()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color.blue.opacity(0.4), radius: 8, x: 0, y: 4)
                    .scaleEffect(1.1)  // Make it slightly larger
                    .overlay(
                        // Pulse animation for attention
                        Circle()
                            .stroke(Color.blue.opacity(0.6), lineWidth: 2)
                            .scaleEffect(timelineState.unreadCount > 0 ? 1.5 : 1.0)
                            .opacity(timelineState.unreadCount > 0 ? 0.0 : 1.0)
                            .animation(
                                timelineState.unreadCount > 0
                                    ? Animation.easeInOut(duration: 1.5).repeatForever(
                                        autoreverses: false) : .default,
                                value: timelineState.unreadCount
                            )
                    )
                    .onTapGesture {
                        // Add haptic feedback
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()

                        NotificationCenter.default.post(name: .scrollToTop, object: nil)
                    }

                    // Sync status indicator
                    if case .success = timelineState.syncStatus {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.icloud")
                                .font(.system(size: 10, weight: .medium))
                            Text("Synced")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
                .padding(.trailing, 16)
            }
            Spacer()
        }
        .padding(.top, 8)
        .transition(.opacity)
        .allowsHitTesting(true)
    }

    // MARK: - Smart Restoration Methods

    /// Apply a restoration suggestion from the banner
    private func applyRestorationSuggestion(_ suggestion: RestorationSuggestion) {
        timelineState.applyRestorationSuggestion(suggestion)
        shouldShowRestorationBanner = false

        // Trigger scroll to the suggested position using async Task
        Task { @MainActor in
            // Small delay for safety
            try? await Task.sleep(nanoseconds: 10_000_000)  // 0.01 seconds

            NotificationCenter.default.post(
                name: .scrollToPosition,
                object: nil,
                userInfo: ["postId": suggestion.postId]
            )
        }

        print("✅ Applied suggestion: \(suggestion.title)")
    }

    // MARK: - Action Handlers
    private func handlePostTap(_ post: Post) {
        selectedPostForDetail = post
        showingDetailView = true
    }

    private func handleReplyTap(_ post: Post) {
        selectedPostForReply = post
        showingReplyView = true
    }

    private func handleLikeTap(_ post: Post) async {
        // Avoid modifying Post @Published properties to prevent AttributeGraph cycles
        // Instead, let the service manager handle the state updates
        do {
            if post.isLiked {
                _ = try await serviceManager.unlikePost(post)
            } else {
                _ = try await serviceManager.likePost(post)
            }
            print("✅ Like operation completed successfully")
        } catch {
            print("❌ Like failed: \(error.localizedDescription)")

            // Show user-friendly error for auth issues
            if error.localizedDescription.contains("authentication")
                || error.localizedDescription.contains("expired")
            {
                // You could trigger a banner/alert here
                print("🔄 Please refresh your account authentication in settings")
            }
        }
    }

    private func handleBoostTap(_ post: Post) async {
        // Avoid modifying Post @Published properties to prevent AttributeGraph cycles
        // Instead, let the service manager handle the state updates
        do {
            if post.isReposted {
                _ = try await serviceManager.unrepostPost(post)
            } else {
                _ = try await serviceManager.repostPost(post)
            }
            print("✅ Repost operation completed successfully")
        } catch {
            print("❌ Repost failed: \(error.localizedDescription)")
        }
    }

    private func handleShareTap(_ post: Post) {
        // Share functionality - placeholder
        print("Share tapped for post: \(post.id)")
    }

    @MainActor
    private func refreshTimeline() async {
        // PHASE 3+: Enhanced refresh that updates TimelineState with smart position preservation
        isRefreshing = true

        // Save current scroll position with enhanced tracking
        if let firstVisibleEntry = displayEntries.first {
            timelineState.saveScrollPositionWithOffset(
                firstVisibleEntry.id, offset: lastScrollOffset)
        }

        viewModel.refreshUnifiedTimeline()

        // Wait for the refresh to complete
        while viewModel.isRefreshing {
            try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
        }

        // Trigger cross-session sync after refresh
        await timelineState.syncAcrossDevices()

        // Perform maintenance to clean up old data
        timelineState.performMaintenance()

        isRefreshing = false
    }
}

// MARK: - ResponsivePostCardView
/// A wrapper that automatically updates when post interaction states change
struct ResponsivePostCardView: View {
    let entry: TimelineEntry
    let onReply: () -> Void
    let onRepost: () -> Void
    let onLike: () -> Void
    let onShare: () -> Void
    let onPostTap: () -> Void
    let viewModel: PostViewModel?

    var body: some View {
        PostCardView(
            entry: entry,
            viewModel: viewModel,
            onPostTap: onPostTap,
            onReply: onReply,
            onRepost: onRepost,
            onLike: onLike,
            onShare: onShare
        )
        .id(entry.id)  // Use stable entry ID without like state to prevent AttributeGraph cycles
    }
}

// PHASE 3+: Extension for scroll to top notification
extension Notification.Name {
    static let scrollToTop = Notification.Name("scrollToTop")
    static let scrollToPosition = Notification.Name("scrollToPosition")
}

// Add the preference key for scroll offset detection
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

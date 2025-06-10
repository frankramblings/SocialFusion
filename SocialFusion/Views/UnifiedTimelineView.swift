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
    @State private var timelineState = TimelineState()
    
    @State private var isLoading = false
    @State private var entries: [TimelineEntry] = [] // Keep for compatibility during transition
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
    @State private var scrollReader: ScrollViewReader? = nil

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
        let timelineEntries = timelineState.compatibleTimelineEntries
        return timelineEntries.isEmpty ? entries : timelineEntries
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // PHASE 3+: Restoration suggestions banner
                if timelineState.showRestoreOptions {
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
                    timelineState.loadCachedContent(from: serviceManager)
                    timelineState.updateLastVisitDate()
                    
                    // Perform cross-session sync
                    await timelineState.syncAcrossDevices()
                    
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
            let posts = state.posts
            self.entries = self.serviceManager.makeTimelineEntries(from: posts) // Keep existing for compatibility
            self.isLoading = state.isLoading
            
            // Update TimelineState with new posts (preserves scroll position)
            if !posts.isEmpty {
                timelineState.updateFromServiceManagerWithExistingLogic(serviceManager, isRefresh: timelineState.isInitialized)
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
                    .foregroundColor(.tertiary)
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
                        .padding(.horizontal, 8)  // Apple standard: 8pt for timeline separation
                        .padding(.vertical, 6)  // Apple standard: 6pt between posts
                        .onAppear {
                            // PHASE 3+: Enhanced read tracking and position saving
                            timelineState.markPostAsRead(entry.post.id)
                            
                            // Save position as user scrolls through
                            timelineState.saveScrollPosition(entry.post.id)
                        }

                        // Add divider between posts (but not after the last one)
                        if index < displayEntries.count - 1 {
                            Divider()
                                .background(
                                    colorScheme == .dark
                                        ? Color.white.opacity(0.12)
                                        : Color.gray.opacity(0.25)
                                )
                                .padding(.horizontal, 24)  // Apple standard: 24pt for divider insets
                        }
                    }
                }
                .padding(.vertical, 8)  // Apple standard: 8pt top/bottom timeline padding
            }
            .scrollDismissesKeyboard(.immediately)
            .onAppear {
                // PHASE 3+: Smart position restoration on appear
                Task {
                    await restoreScrollPositionIntelligently(using: proxy)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .scrollToTop)) { _ in
                // Same: Existing scroll to top functionality
                if let firstEntry = displayEntries.first {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        proxy.scrollTo(firstEntry.id, anchor: .top)
                    }
                    // Clear unread when scrolling to top
                    timelineState.clearAllUnread()
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
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                        
                        Text("\(timelineState.unreadCount)")
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                        
                        Text(timelineState.unreadCount == 1 ? "new post" : "new posts")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.9))
                    .clipShape(Capsule())
                    .onTapGesture {
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
    
    /// PHASE 3+: Smart position restoration with multiple strategies
    private func restoreScrollPositionIntelligently(using proxy: ScrollViewReader) async {
        // Give a moment for the content to load
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        let restoration = timelineState.restorePositionIntelligently()
        
        await MainActor.run {
            if let index = restoration.index, index < displayEntries.count {
                let targetEntry = displayEntries[index]
                
                withAnimation(.easeInOut(duration: 0.8)) {
                    if restoration.offset > 0 {
                        // Use offset-based restoration if available
                        proxy.scrollTo(targetEntry.id, anchor: .top)
                    } else {
                        // Center-based restoration for better UX
                        proxy.scrollTo(targetEntry.id, anchor: .center)
                    }
                }
                
                print("🎯 Restored to position: \(targetEntry.id) at index \(index)")
            } else if restoration.offset > 0 {
                // Fallback to offset-based restoration
                // Note: ScrollView doesn't support direct offset, so we approximate
                print("📍 Using offset-based fallback: \(restoration.offset)")
            }
        }
    }
    
    /// Apply a restoration suggestion from the banner
    private func applyRestorationSuggestion(_ suggestion: RestorationSuggestion) {
        timelineState.applyRestorationSuggestion(suggestion)
        
        // Scroll to the suggested position
        if let entry = displayEntries.first(where: { $0.id == suggestion.postId }) {
            // This would need a ScrollViewReader reference
            // For now, we'll save the position and let the next onAppear handle it
            print("✅ Applied suggestion: \(suggestion.title)")
        }
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
        // Find the post in our entries array and get its index
        guard let entryIndex = displayEntries.firstIndex(where: { $0.post.id == post.id }) else {
            print("❌ Could not find post in entries array")
            return
        }

        // Get a reference to the current post for optimistic updates
        let currentPost = displayEntries[entryIndex].post

        // Store original values for potential revert
        let originalLiked = currentPost.isLiked
        let originalCount = currentPost.likeCount

        // Create updated values
        let newLikedState = !originalLiked
        let newLikeCount = originalCount + (newLikedState ? 1 : -1)

        // Optimistically update the post and trigger UI update
        await MainActor.run {
            currentPost.isLiked = newLikedState
            currentPost.likeCount = newLikeCount
            // Force UI update by triggering objectWillChange on the Post
            currentPost.objectWillChange.send()
        }

        // Perform the actual like operation
        do {
            let updatedPost: Post
            if newLikedState {
                updatedPost = try await serviceManager.likePost(currentPost)
            } else {
                updatedPost = try await serviceManager.unlikePost(currentPost)
            }

            // Update with server response
            await MainActor.run {
                currentPost.isLiked = updatedPost.isLiked
                currentPost.likeCount = updatedPost.likeCount
                // Force UI update again with final server state
                currentPost.objectWillChange.send()
            }
        } catch {
            // Revert on error
            await MainActor.run {
                currentPost.isLiked = originalLiked
                currentPost.likeCount = originalCount
                // Force UI update for revert
                currentPost.objectWillChange.send()
            }
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
        // Find the post in our entries array
        guard let entryIndex = displayEntries.firstIndex(where: { $0.post.id == post.id }) else {
            print("❌ Could not find post in entries array")
            return
        }

        // Get a reference to the current post
        let currentPost = displayEntries[entryIndex].post

        // Store original values for potential revert
        let originalReposted = currentPost.isReposted
        let originalCount = currentPost.repostCount

        // Update the post object and trigger UI update
        let newRepostedState = !originalReposted
        let newRepostCount = originalCount + (newRepostedState ? 1 : -1)

        await MainActor.run {
            currentPost.isReposted = newRepostedState
            currentPost.repostCount = newRepostCount
            // Force UI update
            currentPost.objectWillChange.send()
        }

        // Perform the actual repost operation
        do {
            let updatedPost: Post
            if newRepostedState {
                updatedPost = try await serviceManager.repostPost(currentPost)
            } else {
                updatedPost = try await serviceManager.unrepostPost(currentPost)
            }

            // Update with server response
            await MainActor.run {
                currentPost.isReposted = updatedPost.isReposted
                currentPost.repostCount = updatedPost.repostCount
                currentPost.objectWillChange.send()
            }
        } catch {
            // Revert on error
            await MainActor.run {
                currentPost.isReposted = originalReposted
                currentPost.repostCount = originalCount
                currentPost.objectWillChange.send()
            }
            print("Repost failed: \(error)")
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
            timelineState.saveScrollPositionWithOffset(firstVisibleEntry.id, offset: lastScrollOffset)
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
}

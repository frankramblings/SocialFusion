import SwiftUI

// MARK: - UnifiedTimelineViewV2

struct UnifiedTimelineViewV2: View {

    let serviceManager: SocialServiceManager
    @StateObject private var viewModel: TimelineViewModel

    // Add navigation state
    @State private var selectedPost: Post?
    @State private var showingDetailView = false
    @State private var showingReplyComposer = false

    // Enhanced position and unread tracking
    @State private var readPostIds = Set<String>()
    @State private var lastReadPostId: String?  // The last post the user actually read
    @State private var savedScrollPosition: String?  // Position to restore to
    @State private var hasRestoredPosition = false
    @State private var hasLoadedStoredState = false  // Track if we've loaded state
    @State private var lastVisitDate = Date()

    // Track visible posts for real-time unread counting
    @State private var visiblePostIds = Set<String>()

    // Timer for batched updates to prevent bouncing
    @State private var updateTimer: Timer?
    @State private var savePositionTimer: Timer?

    // Cache unread count to avoid expensive computation during view updates
    @State private var cachedUnreadCount: Int = 0
    @State private var cachedFirstUnreadPost: Post? = nil

    // Computed property for unread count (posts above last read position)
    private var unreadCount: Int {
        return cachedUnreadCount
    }

    // Find the first unread post for scroll-to functionality
    private var firstUnreadPost: Post? {
        return cachedFirstUnreadPost
    }

    // MARK: - Initialization

    init(serviceManager: SocialServiceManager) {
        self.serviceManager = serviceManager
        self._viewModel = StateObject(
            wrappedValue: TimelineViewModel(accounts: serviceManager.accounts))

        // Don't load stored state here - do it in onAppear to avoid race conditions
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    // Status header - simplified to reduce updates
                    HStack {
                        Text("Timeline V2")
                            .font(.headline)
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                    // Timeline content
                    if viewModel.isLoading && viewModel.posts.isEmpty {
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("Loading timeline...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.posts.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("No posts available")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            Text("Pull to refresh")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Posts list using existing PostCardView
                        ScrollViewReader { proxy in
                            ZStack {
                                ScrollView {
                                    LazyVStack(spacing: 0) {
                                        ForEach(viewModel.posts, id: \.id) { post in
                                            VStack(spacing: 0) {
                                                PostCardView(
                                                    entry: createTimelineEntry(for: post),
                                                    viewModel: nil,
                                                    onPostTap: {
                                                        selectedPost = post
                                                        showingDetailView = true
                                                    },
                                                    onReply: {
                                                        selectedPost = post
                                                        showingReplyComposer = true
                                                    },
                                                    onRepost: {
                                                        Task { @MainActor in
                                                            await handleRepostTap(post)
                                                        }
                                                    },
                                                    onLike: {
                                                        Task { @MainActor in
                                                            await handleLikeTap(post)
                                                        }
                                                    },
                                                    onShare: {
                                                        sharePost(post)
                                                    }
                                                )
                                                .onAppear {
                                                    handlePostAppear(post.id)
                                                }
                                                .onDisappear {
                                                    handlePostDisappear(post.id)
                                                }
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 6)
                                                .id(post.id)  // Important for ScrollViewReader

                                                // Divider between posts
                                                if post.id != viewModel.posts.last?.id {
                                                    Divider()
                                                        .background(Color.gray.opacity(0.2))
                                                        .padding(.horizontal, 16)
                                                }
                                            }
                                        }
                                    }
                                }

                                // Enhanced unread count indicator - only show when there are unread posts
                                if unreadCount > 0 {
                                    VStack {
                                        HStack {
                                            Spacer()
                                            Button(action: {
                                                handleUnreadCounterTap(proxy: proxy)
                                            }) {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "arrow.up.circle.fill")
                                                        .font(.system(size: 16, weight: .bold))

                                                    Text("\(unreadCount)")
                                                        .font(.system(size: 18, weight: .bold))
                                                        .monospacedDigit()

                                                    Text("new")
                                                        .font(.system(size: 12, weight: .medium))
                                                }
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 10)
                                                .background(
                                                    Capsule()
                                                        .fill(Color.blue)
                                                        .shadow(
                                                            color: .black.opacity(0.2), radius: 4,
                                                            x: 0, y: 2)
                                                )
                                            }
                                            .padding(.trailing, 20)
                                        }
                                        .padding(.top, 10)

                                        Spacer()
                                    }
                                }
                            }
                            .task {
                                if !viewModel.posts.isEmpty && !hasRestoredPosition
                                    && hasLoadedStoredState
                                {
                                    restoreScrollPosition(proxy: proxy)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            viewModel.refreshUnifiedTimeline()

            // Only load stored state once per app session
            if !hasLoadedStoredState {
                loadStoredState()
            }

            // Update unread cache after loading
            updateUnreadCache()
        }
        .onDisappear {
            updateTimer?.invalidate()
            savePositionTimer?.invalidate()
            saveCurrentState()
        }
        .refreshable {
            viewModel.refreshUnifiedTimeline()
            // Update cache after refresh
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                updateUnreadCache()
            }
        }
        .sheet(isPresented: $showingDetailView) {
            if let post = selectedPost {
                NavigationView {
                    PostDetailNavigationView(
                        viewModel: PostViewModel(post: post, serviceManager: serviceManager),
                        focusReplyComposer: false
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarItems(
                        trailing: Button("Done") {
                            showingDetailView = false
                        })
                }
            }
        }
        .sheet(isPresented: $showingReplyComposer) {
            if let post = selectedPost {
                ComposeView(replyingTo: post)
                    .environmentObject(serviceManager)
            }
        }
    }

    // MARK: - Helper Methods

    private func loadStoredState() {
        // Load read posts
        if let savedReadPosts = UserDefaults.standard.array(forKey: "readPostIds") as? [String] {
            readPostIds = Set(savedReadPosts)
        }

        // Load last read post ID (most important for position tracking)
        lastReadPostId = UserDefaults.standard.string(forKey: "lastReadPostId")

        // Load last visit date
        if let savedLastVisit = UserDefaults.standard.object(forKey: "lastVisitDate") as? Date {
            lastVisitDate = savedLastVisit
        } else {
            // First launch: set to 1 hour ago so some posts appear as unread for testing
            lastVisitDate = Date().addingTimeInterval(-60 * 60)
        }

        // Load saved scroll position (for immediate restoration)
        savedScrollPosition = UserDefaults.standard.string(forKey: "savedScrollPosition")

        hasLoadedStoredState = true
    }

    private func saveCurrentState() {
        // Save read posts
        UserDefaults.standard.set(Array(readPostIds), forKey: "readPostIds")

        // Save the first visible post as the primary scroll position
        if let firstVisible = getFirstVisiblePost() {
            savedScrollPosition = firstVisible
            UserDefaults.standard.set(firstVisible, forKey: "savedScrollPosition")
        }

        // Also save the most recently read post as the last read position
        if let mostRecentRead = getMostRecentReadPost() {
            lastReadPostId = mostRecentRead
            UserDefaults.standard.set(mostRecentRead, forKey: "lastReadPostId")
        }

        // Update last visit date
        UserDefaults.standard.set(Date(), forKey: "lastVisitDate")
    }

    private func getMostRecentReadPost() -> String? {
        // Find the first (most recent) post in the timeline that has been read
        return viewModel.posts.first { post in
            readPostIds.contains(post.id)
        }?.id
    }

    private func getFirstVisiblePost() -> String? {
        // Find the first visible post in timeline order (not just first in set)
        for post in viewModel.posts {
            if visiblePostIds.contains(post.id) {
                return post.id
            }
        }

        // Fallback: return the first post in the timeline
        return viewModel.posts.first?.id
    }

    // Batched post appearance handling to prevent UI bouncing
    private func handlePostAppear(_ postId: String) {
        // Defer state updates to avoid AttributeGraph cycles
        DispatchQueue.main.async {
            self.visiblePostIds.insert(postId)

            // Save scroll position periodically during scrolling
            self.saveScrollPositionPeriodically()

            // Don't auto-mark posts as read if this is first launch or we haven't restored position yet
            guard self.hasRestoredPosition else { return }

            // Check if user has scrolled to the top and clear unread count
            if let firstPost = self.viewModel.posts.first,
                firstPost.id == postId && self.unreadCount > 0
            {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Mark all current posts as read
                    for post in self.viewModel.posts {
                        self.readPostIds.insert(post.id)
                    }

                    // Update reading position to the first post
                    self.lastReadPostId = firstPost.id

                    // Update cache
                    self.updateUnreadCache()

                    print("📱 Timeline v2: Cleared unread count - user reached top of timeline")
                }
            }

            // Invalidate existing timer and create new one for batched updates
            self.updateTimer?.invalidate()
            self.updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                // Only mark posts as read if they've been visible for a while
                // and user has scrolled (indicating they're actively reading)
                let postsToMarkRead = Array(self.visiblePostIds)
                for id in postsToMarkRead {
                    // Only mark as read if still visible (user is actually reading)
                    if self.visiblePostIds.contains(id) {
                        self.markPostAsRead(id)
                    }
                }
            }
        }
    }

    private func saveScrollPositionPeriodically() {
        // Invalidate existing timer and create new one
        savePositionTimer?.invalidate()
        savePositionTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            // Save the current scroll position
            if let firstVisible = getFirstVisiblePost() {
                savedScrollPosition = firstVisible
                UserDefaults.standard.set(firstVisible, forKey: "savedScrollPosition")
            }
        }
    }

    private func handlePostDisappear(_ postId: String) {
        DispatchQueue.main.async {
            self.visiblePostIds.remove(postId)
        }
    }

    private func markPostAsRead(_ postId: String) {
        guard !readPostIds.contains(postId) else { return }

        readPostIds.insert(postId)

        // Update last read position to the most recent post we've read
        if let postIndex = viewModel.posts.firstIndex(where: { $0.id == postId }),
            let currentLastReadIndex = lastReadPostId.flatMap({ id in
                viewModel.posts.firstIndex(where: { $0.id == id })
            })
        {
            // Only update if this post is more recent (earlier in timeline) than current last read
            if postIndex < currentLastReadIndex {
                lastReadPostId = postId
            }
        } else if lastReadPostId == nil {
            // No previous position, set this as last read
            lastReadPostId = postId
        }

        // Update unread cache when read state changes
        updateUnreadCache()
    }

    private func restoreScrollPosition(proxy: ScrollViewProxy, retryCount: Int = 0) {
        guard !hasRestoredPosition else { return }
        let maxRetries = 10
        let retryDelay: Double = 0.3

        // Use savedScrollPosition as primary target, fallback to lastReadPostId
        let targetId = savedScrollPosition ?? lastReadPostId

        // If no saved position, don't restore - start at top
        guard let targetId = targetId else {
            hasRestoredPosition = true
            return
        }

        // Check if target post exists in current timeline
        guard viewModel.posts.contains(where: { $0.id == targetId }) else {
            if retryCount < maxRetries {
                DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                    restoreScrollPosition(proxy: proxy, retryCount: retryCount + 1)
                }
            } else {
                hasRestoredPosition = true  // Give up after max retries
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.4)) {
                proxy.scrollTo(targetId, anchor: .top)
            }
            hasRestoredPosition = true
        }
    }

    private func handleUnreadCounterTap(proxy: ScrollViewProxy) {
        if let firstUnread = firstUnreadPost {
            // Scroll to first unread post
            withAnimation(.easeInOut(duration: 0.5)) {
                proxy.scrollTo(firstUnread.id, anchor: .top)
            }
        } else {
            // No specific unread post, scroll to top and mark all as read
            if let firstPost = viewModel.posts.first {
                withAnimation(.easeInOut(duration: 0.5)) {
                    proxy.scrollTo(firstPost.id, anchor: .top)
                }
            }

            // Mark all current posts as read
            for post in viewModel.posts {
                readPostIds.insert(post.id)
            }

            // Update reading position to the first post
            if let firstPost = viewModel.posts.first {
                lastReadPostId = firstPost.id
            }

            // Clear saved position since we're at top
            savedScrollPosition = nil
            UserDefaults.standard.removeObject(forKey: "savedScrollPosition")
        }
    }

    private func createTimelineEntry(for post: Post) -> TimelineEntry {
        // Match the same logic as SocialServiceManager.makeTimelineEntries
        if let original = post.originalPost {
            // This is a boost/repost - pass the wrapper post so PostCardView can access boostedBy
            return TimelineEntry(
                id: "boost-\(post.authorUsername)-\(original.id)",
                kind: .boost(boostedBy: post.authorUsername),
                post: post,  // Pass the wrapper post, not the original
                createdAt: post.createdAt
            )
        } else if let parentId = post.inReplyToID {
            // This is a reply
            return TimelineEntry(
                id: "reply-\(post.id)",
                kind: .reply(parentId: parentId),
                post: post,
                createdAt: post.createdAt
            )
        } else {
            // Normal post
            return TimelineEntry(
                id: post.id,
                kind: .normal,
                post: post,
                createdAt: post.createdAt
            )
        }
    }

    private func sharePost(_ post: Post) {
        guard let url = URL(string: post.originalURL) else { return }

        let activityViewController = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first
        {
            window.rootViewController?.present(activityViewController, animated: true)
        }
    }

    private func handleRepostTap(_ post: Post) async {
        // Find the post in our posts array
        guard let postIndex = viewModel.posts.firstIndex(where: { $0.id == post.id }) else {
            print("❌ Could not find post in posts array")
            return
        }

        // Get a reference to the current post
        let currentPost = viewModel.posts[postIndex]

        // Store original values for potential revert
        let originalReposted = currentPost.isReposted
        let originalCount = currentPost.repostCount

        // Calculate new state
        let newRepostedState = !originalReposted
        let newRepostCount = max(0, originalCount + (newRepostedState ? 1 : -1))

        // Defer state updates to avoid "Modifying state during view update" warnings
        await MainActor.run {
            currentPost.isReposted = newRepostedState
            currentPost.repostCount = newRepostCount
        }

        // Perform the actual repost operation using service manager
        do {
            let updatedPost: Post
            if newRepostedState {
                updatedPost = try await serviceManager.repostPost(currentPost)
            } else {
                updatedPost = try await serviceManager.unrepostPost(currentPost)
            }

            // Update with server response on main thread
            await MainActor.run {
                currentPost.isReposted = updatedPost.isReposted
                currentPost.repostCount = updatedPost.repostCount
            }
        } catch {
            // Revert on error
            await MainActor.run {
                currentPost.isReposted = originalReposted
                currentPost.repostCount = originalCount
            }
            print("❌ Repost failed: \(error.localizedDescription)")
        }
    }

    private func handleLikeTap(_ post: Post) async {
        // Find the post in our posts array
        guard let postIndex = viewModel.posts.firstIndex(where: { $0.id == post.id }) else {
            print("❌ Could not find post in posts array")
            return
        }

        // Get a reference to the current post for optimistic updates
        let currentPost = viewModel.posts[postIndex]

        // Store original values for potential revert
        let originalLiked = currentPost.isLiked
        let originalCount = currentPost.likeCount

        // Calculate new state (avoiding negative counts)
        let newLikedState = !originalLiked
        let newLikeCount = max(0, originalCount + (newLikedState ? 1 : -1))

        // Defer state updates to avoid "Modifying state during view update" warnings
        await MainActor.run {
            currentPost.isLiked = newLikedState
            currentPost.likeCount = newLikeCount
        }

        // Perform the actual like operation using service manager
        do {
            let updatedPost: Post
            if newLikedState {
                updatedPost = try await serviceManager.likePost(currentPost)
            } else {
                updatedPost = try await serviceManager.unlikePost(currentPost)
            }

            // Update with server response on main thread
            await MainActor.run {
                currentPost.isLiked = updatedPost.isLiked
                currentPost.likeCount = updatedPost.likeCount
            }
        } catch {
            // Revert on error
            await MainActor.run {
                currentPost.isLiked = originalLiked
                currentPost.likeCount = originalCount
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

    // Update cached values when posts or read state changes
    private func updateUnreadCache() {
        // Use direct assignment since we're in a struct, not a class
        let unreadPosts = viewModel.posts.filter { post in
            post.createdAt > lastVisitDate && !readPostIds.contains(post.id)
        }
        cachedUnreadCount = unreadPosts.count
        cachedFirstUnreadPost = unreadPosts.first
    }
}

// MARK: - Preview

#if DEBUG
    struct UnifiedTimelineViewV2_Previews: PreviewProvider {
        static var previews: some View {
            UnifiedTimelineViewV2(serviceManager: SocialServiceManager.shared)
                .environmentObject(SocialServiceManager.shared)
        }
    }
#endif

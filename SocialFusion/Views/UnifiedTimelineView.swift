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

    @State private var isLoading = false
    @State private var posts: [Post] = []
    @Environment(\.colorScheme) private var colorScheme
    @State private var navigateToParentPost = false
    @ObservedObject var postStore = PostStore.shared
    @StateObject private var viewModel: TimelineViewModel

    // Scroll position tracking for double-tap functionality
    @State private var savedScrollPosition: String? = nil
    @State private var isAtTop = true

    // Published properties to allow external scroll control
    @State private var shouldScrollToTop = false
    @State private var shouldScrollToSaved = false
    @State private var refreshDebounceTimer: Timer? = nil
    @State private var selectedPost: Post? = nil
    @State private var replyingToPost: Post? = nil
    @State private var postViewModels: [String: PostViewModel] = [:]

    init(accounts: [SocialAccount]) {
        _viewModel = StateObject(wrappedValue: TimelineViewModel(accounts: accounts))
    }

    // Public methods to trigger scroll actions
    @MainActor
    func scrollToTop() {
        shouldScrollToTop = true
    }

    @MainActor
    func scrollToSavedPosition() {
        shouldScrollToSaved = true
    }

    // Handle double-tap on Home tab
    @MainActor
    private func handleHomeTabDoubleTap() {
        if isAtTop && savedScrollPosition != nil {
            // If we're at the top and have a saved position, scroll back to it
            scrollToSavedPosition()
        } else {
            // Otherwise, scroll to the top
            scrollToTop()
        }
    }

    private var hasAccounts: Bool {
        return !serviceManager.mastodonAccounts.isEmpty || !serviceManager.blueskyAccounts.isEmpty
    }

    private var displayPosts: [Post] {
        return serviceManager.unifiedTimeline.filter { post in
            if serviceManager.selectedAccountIds.contains("all") {
                // When "All" is selected, show posts from all accounts
                return true
            } else {
                // For specific account selection, match the post author
                let username = post.authorUsername
                let selectedAccounts = serviceManager.selectedAccountIds
                return selectedAccounts.contains(where: { $0.contains(username) })
            }
        }
    }

    private var displayTitle: String {
        if !hasAccounts {
            return "Home"
        } else if serviceManager.selectedAccountIds.contains("all") {
            return "All Accounts"
        } else if serviceManager.selectedAccountIds.count == 1,
            let id = serviceManager.selectedAccountIds.first,
            let account = getCurrentAccountById(id)
        {
            // Safe unwrapping of displayName, using username as fallback
            return account.displayName ?? account.username
        } else {
            return "Selected Accounts"
        }
    }

    private func getCurrentAccountById(_ id: String) -> SocialAccount? {
        // Find in Mastodon accounts
        if let account = serviceManager.mastodonAccounts.first(where: { $0.id == id }) {
            return account
        }

        // Find in Bluesky accounts
        if let account = serviceManager.blueskyAccounts.first(where: { $0.id == id }) {
            return account
        }

        return nil
    }

    private var timelineEntries: [TimelineEntry] {
        serviceManager.makeTimelineEntries(from: serviceManager.unifiedTimeline)
    }

    private var allAccounts: [SocialAccount] {
        serviceManager.mastodonAccounts + serviceManager.blueskyAccounts
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            if serviceManager.isLoadingTimeline && serviceManager.unifiedTimeline.isEmpty {
                ProgressView()
                    .scaleEffect(1.5)
            } else if serviceManager.unifiedTimeline.isEmpty {
                // Completely empty state with pull-to-refresh
                ScrollView {
                    EmptyTimelineView(hasAccounts: hasAccounts)
                        .padding()
                }
                .background(Color(.systemBackground))
                .refreshable {
                    // Refresh timeline on pull
                    await refreshTimelineAsync()
                }
                .onAppear {
                    if hasAccounts {
                        Task {
                            do {
                                try await serviceManager.refreshTimeline()
                            } catch {
                                print(
                                    "Error refreshing timeline: \(error.localizedDescription)")
                            }
                        }
                    } else {
                        // No accounts - don't load anything, let the empty state show
                    }
                }
            } else {
                // Show the timeline when we have posts
                VStack(spacing: 0) {
                    // Header at the top with an elegant design
                    HStack {
                        Text(displayTitle)
                            .font(.headline)
                            .fontWeight(.semibold)

                        Spacer()

                        // Refresh button
                        Button(action: {
                            refreshTimeline()
                        }) {
                            if isRefreshing {
                                ProgressView()
                                    .frame(width: 20, height: 20)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 16))
                                    .foregroundColor(.primary)
                            }
                        }
                        .disabled(isRefreshing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    // Post list
                    ScrollViewReader { proxy in
                        ScrollView {
                            postListView
                                .padding(.top, 0)
                        }
                        .background(Color(.systemBackground))
                        .refreshable {
                            await refreshTimelineAsync()
                        }
                        .onAppear {
                            // Reset pagination when view appears
                            serviceManager.resetPagination()
                        }
                        .onChange(of: shouldScrollToTop) { newValue in
                            if newValue {
                                // Save current position before scrolling to top
                                if !isAtTop && timelineEntries.count > 5 {
                                    // Save the 5th post as our return position (reasonable scroll-back point)
                                    savedScrollPosition = timelineEntries[4].id
                                }

                                withAnimation(.easeInOut(duration: 0.5)) {
                                    proxy.scrollTo("top", anchor: .top)
                                }
                                isAtTop = true
                                shouldScrollToTop = false
                            }
                        }
                        .onChange(of: shouldScrollToSaved) { newValue in
                            if newValue, let savedId = savedScrollPosition {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    proxy.scrollTo(savedId, anchor: .top)
                                }
                                isAtTop = false
                                shouldScrollToSaved = false
                                savedScrollPosition = nil
                            }
                        }
                    }
                }
                .background(Color(.systemBackground))
            }

            if let error = postStore.error {
                VStack {
                    Text(error.message)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.red)
                        .cornerRadius(8)
                    Spacer()
                }
                .padding()
                .transition(.move(edge: .top))
            }
        }
        .alert("Error", isPresented: $showingAuthError) {
            Button("OK") {}
        }
        .alert("Timeline Error", isPresented: $showingErrorAlert) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .onChange(of: hasAccounts) { newValue in
            // When accounts status changes, refresh the appropriate content
            // Only trigger if we have accounts and no timeline data
            if newValue && serviceManager.unifiedTimeline.isEmpty {
                // Debounce this to prevent rapid successive calls
                refreshDebounceTimer?.invalidate()
                refreshDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) {
                    _ in
                    Task {
                        print("Account status changed to hasAccounts: \(newValue)")
                        await refreshTimelineAsync()
                    }
                }
            }
        }
        .onChange(of: serviceManager.selectedAccountIds) { newIds in
            // When selected accounts change, refresh the timeline
            // Only trigger if we have accounts and this is a meaningful change
            if hasAccounts && !newIds.isEmpty && !isRefreshing {
                print("📱 UnifiedTimelineView: Selected accounts changed, refreshing timeline")
                // Debounce to prevent rapid successive calls during account selection
                refreshDebounceTimer?.invalidate()
                refreshDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) {
                    _ in
                    Task {
                        await refreshTimelineAsync(force: true)
                    }
                }
            }
        }
        .onReceive(serviceManager.$error) { newError in
            // Show auth error banner if applicable
            handleServiceError(newError)
        }
        .onAppear {
            // Prevent infinite onAppear loops by only running when necessary
            let currentTimelineCount = serviceManager.unifiedTimeline.count

            // Only print once to reduce console spam
            if !isLoading {
                print(
                    "📱 UnifiedTimelineView: onAppear - hasAccounts: \(hasAccounts), timeline count: \(currentTimelineCount)"
                )
            }

            // Only load timeline if we have accounts, no posts, and aren't already loading
            if hasAccounts && currentTimelineCount == 0 && !serviceManager.isLoadingTimeline
                && !isLoading
            {
                print("📱 UnifiedTimelineView: Initial timeline load")
                isLoading = true
                Task {
                    do {
                        try await serviceManager.refreshTimeline(force: false)
                    } catch {
                        print(
                            "❌ UnifiedTimelineView: Error loading timeline: \(error.localizedDescription)"
                        )
                    }
                    await MainActor.run {
                        isLoading = false
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .homeTabDoubleTapped)) { _ in
            DispatchQueue.main.async {
                handleHomeTabDoubleTap()
            }
        }
        .sheet(
            item: Binding<PostItem?>(
                get: { selectedPost.map(PostItem.init) },
                set: { _ in selectedPost = nil }
            )
        ) { postItem in
            NavigationView {
                PostDetailModalView(
                    viewModel: PostViewModel(post: postItem.post, serviceManager: serviceManager),
                    focusReplyComposer: .constant(false)
                )
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarTitle("")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            selectedPost = nil
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(
            item: Binding<PostItem?>(
                get: { replyingToPost.map(PostItem.init) },
                set: { _ in replyingToPost = nil }
            )
        ) { postItem in
            NavigationView {
                PostDetailModalView(
                    viewModel: PostViewModel(post: postItem.post, serviceManager: serviceManager),
                    focusReplyComposer: .constant(true)
                )
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarTitle("Reply")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            replyingToPost = nil
                        }
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func getPostViewModel(for entry: TimelineEntry) -> PostViewModel {
        let postId = entry.post.id
        if let existingViewModel = postViewModels[postId] {
            // Update the existing view model with the latest post data
            existingViewModel.post = entry.post
            return existingViewModel
        } else {
            // Create a new view model
            let viewModel = PostViewModel(post: entry.post, serviceManager: serviceManager)
            postViewModels[postId] = viewModel
            return viewModel
        }
    }

    private func refreshTimeline() {
        guard !isRefreshing else { return }

        isRefreshing = true
        Task {
            await refreshTimelineAsync()
            _ = await MainActor.run {
                isRefreshing = false
            }
        }
    }

    private func refreshTimelineAsync(force: Bool = false) async {
        do {
            try await serviceManager.refreshTimeline(force: force)
        } catch {
            _ = await MainActor.run {
                errorMessage = "Failed to refresh timeline: \(error.localizedDescription)"
                showingErrorAlert = true
            }
        }
    }

    private func handleServiceError(_ error: Error?) {
        guard let error = error else { return }

        // Process the error
        if let socialError = error as? ServiceError {
            switch socialError {
            case .authenticationFailed:
                authErrorMessage = "Authentication failed. Please check your account settings."
                showingAuthError = true
            case .rateLimitError:
                authErrorMessage = "Rate limited. Please try again later."
                showingAuthError = true
            default:
                errorMessage = socialError.localizedDescription
                showingErrorAlert = true
            }
        } else {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
    }

    // Extracted post list view
    @ViewBuilder
    private var postListView: some View {
        LazyVStack(spacing: 0) {
            // Top anchor for scroll-to-top functionality
            Color.clear
                .frame(height: 1)
                .id("top")

            // Display error alert if there's an authentication issue
            if showingAuthError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(authErrorMessage)
                        .font(.footnote)
                        .foregroundColor(.primary)
                    Spacer()
                    Button(action: {
                        showingAuthError = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 8)
            }
            ForEach(timelineEntries, id: \.id) { entry in
                VStack(spacing: 0) {
                    let viewModel = getPostViewModel(for: entry)
                    PostCardView(
                        entry: entry,
                        viewModel: viewModel,
                        onPostTap: {
                            selectedPost = entry.post
                        },
                        onReply: {
                            replyingToPost = entry.post
                        },
                        onRepost: {
                            Task {
                                await viewModel.repost()
                            }
                        },
                        onLike: {
                            Task {
                                await viewModel.like()
                            }
                        },
                        onShare: {
                            viewModel.share()
                        }
                    )

                    // Subtle divider between posts
                    if entry.id != timelineEntries.last?.id {
                        Divider()
                            .padding(.horizontal, 16)
                    }
                }
                .id(entry.id)  // Important: ensure each post has an ID for scrollTo
                .onAppear {
                    // Track scroll position - if this is one of the first few posts, we're near the top
                    if let firstEntryIndex = timelineEntries.firstIndex(where: {
                        $0.id == entry.id
                    }),
                        firstEntryIndex <= 2
                    {
                        isAtTop = true
                    } else {
                        isAtTop = false
                    }

                    // Check if this is one of the last few posts and trigger loading more
                    if entry.id == timelineEntries.suffix(3).first?.id {
                        Task {
                            await serviceManager.fetchNextPage()
                        }
                    }
                }
            }
            if serviceManager.isLoadingNextPage {
                ProgressView("Loading more posts...")
                    .padding()
            }
            Color.clear.frame(height: 60)
        }
    }
}

// MARK: - Empty Timeline View
struct EmptyTimelineView: View {
    let hasAccounts: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "newspaper")
                .font(.system(size: 50))
                .foregroundColor(.gray)

            Text(hasAccounts ? "No posts available" : "No accounts added")
                .font(.title2)
                .fontWeight(.semibold)

            Text(
                hasAccounts
                    ? "Try refreshing, or check back later for new content."
                    : "Add a Mastodon or Bluesky account to get started."
            )
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)

            if !hasAccounts {
                NavigationLink(destination: AccountsView()) {
                    Text("Add Account")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color("PrimaryColor"))
                        .cornerRadius(8)
                }
                .padding(.top, 10)
            }
        }
        .padding()
    }
}

// MARK: - Custom Tab Bar
struct CustomTabBar: View {
    @Binding var selectedTab: Tab

    // Purple accent color from the screenshot
    private let accentPurple = Color(red: 102 / 255, green: 51 / 255, blue: 204 / 255)

    enum Tab: String, CaseIterable {
        case home = "Home"
        case notifications = "Notifications"
        case search = "Search"
        case profile = "Profile"

        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .notifications: return "bell.fill"
            case .search: return "magnifyingglass"
            case .profile: return "person.circle.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20))
                            .foregroundColor(selectedTab == tab ? accentPurple : .gray)

                        Text(tab.rawValue)
                            .font(.system(size: 12))
                            .foregroundColor(selectedTab == tab ? accentPurple : .gray)
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(tab.rawValue)
                Spacer()
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 16)  // Add extra padding for bottom safe area
        .background(
            Rectangle()
                .fill(Color(UIColor.systemBackground).opacity(0.95))
                .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: -1)
        )
    }
}

// Helper for Bluesky DID-based username
private func shortenUsername(_ username: String) -> String {
    if username.hasPrefix("did:plc:") {
        let shortened = String(username.prefix(16)) + "..."
        return shortened
    }
    return username
}

// Parent post preview view
// Using shared ParentPostPreview component from PostCardView.swift

// Cache for parent posts to avoid duplicate fetches
@MainActor
class PostParentCache: ObservableObject {
    static let shared = PostParentCache()
    @Published var cache = [String: Post]()
    private var fetching = Set<String>()
    private var preloadQueue = Set<String>()

    func getCachedPost(id: String) -> Post? {
        return cache[id]
    }

    func isFetching(id: String) -> Bool {
        return fetching.contains(id)
    }

    func isPreloading(id: String) -> Bool {
        return preloadQueue.contains(id)
    }

    func fetchRealPost(
        id: String, username: String, platform: SocialPlatform,
        serviceManager: SocialServiceManager, allAccounts: [SocialAccount]
    ) {
        guard !fetching.contains(id) else {
            return
        }

        fetching.insert(id)

        Task(priority: .userInitiated) {
            defer {
                Task { @MainActor in
                    self.fetching.remove(id)
                }
            }

            do {
                let post = try await self.fetchParentPost(
                    id: id, platform: platform,
                    serviceManager: serviceManager, allAccounts: allAccounts
                )

                await MainActor.run {
                    if let post = post {
                        self.cache[id] = post
                    }
                }
            } catch {
                print("❌ PostParentCache: Failed to fetch parent post \(id): \(error)")
            }
        }
    }

    /// Preload parent post in background for smooth animations
    func preloadParentPost(
        id: String, username: String, platform: SocialPlatform,
        serviceManager: SocialServiceManager, allAccounts: [SocialAccount]
    ) {
        // Skip if already cached, fetching, or in preload queue
        guard !cache.keys.contains(id) && !fetching.contains(id) && !preloadQueue.contains(id)
        else {
            return
        }

        preloadQueue.insert(id)

        Task(priority: .background) {
            defer {
                Task { @MainActor in
                    self.preloadQueue.remove(id)
                }
            }

            do {
                let post = try await self.fetchParentPost(
                    id: id, platform: platform,
                    serviceManager: serviceManager, allAccounts: allAccounts
                )

                await MainActor.run {
                    if let post = post {
                        self.cache[id] = post
                        print("📱 PostParentCache: Preloaded parent post: \(id)")
                    }
                }
            } catch {
                print("❌ PostParentCache: Failed to preload parent post \(id): \(error)")
            }
        }
    }

    // MARK: - Private Helpers

    private func fetchParentPost(
        id: String, platform: SocialPlatform,
        serviceManager: SocialServiceManager, allAccounts: [SocialAccount]
    ) async throws -> Post? {
        switch platform {
        case .mastodon:
            if let account = allAccounts.first(where: { $0.platform == .mastodon }) {
                return try await serviceManager.fetchMastodonStatus(id: id, account: account)
            }
            return nil
        case .bluesky:
            return try await serviceManager.fetchBlueskyPostByID(id)
        }
    }
}

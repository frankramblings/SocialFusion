import Combine
import SwiftUI
import UIKit

// MARK: - UnifiedTimelineView
struct UnifiedTimelineView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @State private var showingAuthError = false
    @State private var authErrorMessage = ""
    @State private var showingErrorAlert = false
    @State private var errorMessage: String? = nil
    @State private var isRefreshing = false
    @State private var isLoadingMorePosts = false
    @State private var isLoading = false
    @State private var posts: [Post] = []
    @Environment(\.colorScheme) private var colorScheme
    @State private var navigateToParentPost = false

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
        if serviceManager.selectedAccountIds.contains("all") {
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

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            if serviceManager.isLoadingTimeline && serviceManager.unifiedTimeline.isEmpty {
                ProgressView()
                    .scaleEffect(1.5)
            } else if serviceManager.unifiedTimeline.isEmpty {
                // Completely empty state
                EmptyTimelineView(hasAccounts: hasAccounts)
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
                            // Load sample data for testing if no accounts
                            serviceManager.loadSamplePosts()
                        }
                    }
            } else {
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
                    ScrollView {
                        LazyVStack(spacing: 0) {
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

                            ForEach(displayPosts) { post in
                                VStack {
                                    // Use the proper view for displaying posts
                                    if #available(iOS 16.0, *) {
                                        PostCardView(post: post)
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 8)
                                    } else {
                                        // Fallback for older iOS versions
                                        Text(post.content)
                                            .padding()
                                            .background(Color(.secondarySystemBackground))
                                            .cornerRadius(8)
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 8)
                                    }
                                }
                            }

                            // Show loading indicator at the bottom when more posts are loading
                            if isLoadingMorePosts {
                                ProgressView("Loading more posts...")
                                    .padding()
                                    .onAppear {
                                        Task {
                                            isLoadingMorePosts = false
                                        }
                                    }
                            }

                            // Add spacing at bottom to prevent content being hidden behind tab bar
                            Color.clear.frame(height: 60)
                        }
                        .padding(.top, 0)
                    }
                    .background(Color(.systemBackground))
                    .refreshable {
                        await refreshTimelineAsync()
                    }
                }
                .background(Color(.systemBackground))
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
            if newValue {
                Task {
                    print("Account status changed to hasAccounts: \(newValue)")
                    await refreshTimelineAsync()
                }
            }
        }
        .onChange(of: serviceManager.selectedAccountIds) { _ in
            // When selected accounts change, refresh the timeline
            if hasAccounts {
                Task {
                    print("Selected accounts changed, refreshing timeline")
                    await refreshTimelineAsync(force: true)
                }
            }
        }
        .onReceive(serviceManager.$error) { newError in
            // Show auth error banner if applicable
            handleServiceError(newError)
        }
        .onAppear {
            // Load actual timeline data instead of sample posts when view appears
            if serviceManager.unifiedTimeline.isEmpty {
                Task {
                    if hasAccounts {
                        // Use refreshTimeline to fetch real posts from API
                        do {
                            try await serviceManager.refreshTimeline(force: true)
                        } catch {
                            print("Error loading timeline: \(error.localizedDescription)")
                        }
                    } else {
                        // Only use sample posts if there are no accounts
                        serviceManager.loadSamplePosts()
                    }
                }
            }
        }
    }

    private func refreshTimeline() {
        guard !isRefreshing else { return }

        isRefreshing = true
        Task {
            await refreshTimelineAsync()
            await MainActor.run {
                isRefreshing = false
            }
        }
    }

    private func refreshTimelineAsync(force: Bool = false) async {
        do {
            try await serviceManager.refreshTimeline(force: force)
        } catch {
            await MainActor.run {
                if let serviceError = error as? ServiceError,
                    case let .rateLimitError(reason, _) = serviceError
                {
                    // Show rate limit error
                    errorMessage = "Rate limit hit: \(reason). Try again later."
                } else {
                    // Show general error
                    errorMessage = "Error: \(error.localizedDescription)"
                }
                showingErrorAlert = true
            }
        }
    }

    private func handleServiceError(_ error: Error?) {
        guard let error = error else { return }

        if let serviceError = error as? ServiceError {
            // Handle auth errors specifically
            if case .authenticationFailed(let message) = serviceError {
                self.authErrorMessage = message
                self.showingAuthError = true
            }
        }
    }

    // Load timeline posts
    private func loadPosts() async {
        isLoadingMorePosts = true

        // This would be replaced with actual API calls to Mastodon and Bluesky
        // For now, we'll just simulate loading with some sample data
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000)  // Simulate network delay

            // Use the serviceManager to load sample posts including replies
            serviceManager.loadSamplePosts()

            // Posts are now available through serviceManager.unifiedTimeline
            isLoadingMorePosts = false
        } catch {
            isLoadingMorePosts = false
            print("Error loading posts: \(error)")
        }
    }
}

// Empty timeline view - shown when no posts are available
struct EmptyTimelineView: View {
    let hasAccounts: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            // Different content based on whether user has accounts
            if hasAccounts {
                // User has accounts but no posts
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 70))
                    .foregroundColor(.gray.opacity(0.3))

                Text("No Posts Yet")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Add some accounts or check back later")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
                // User has no accounts
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 70))
                    .foregroundColor(.gray.opacity(0.3))

                Text("Welcome to SocialFusion")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Add your social accounts to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                NavigationLink(destination: AccountsView()) {
                    Text("Add Account")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
}

enum BadgeSize {
    case small
    case regular
}

struct UnifiedTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        UnifiedTimelineView()
            .environmentObject(SocialServiceManager())
    }
}

// Bottom navigation tab bar
struct TabBarView: View {
    @Binding var selectedTab: Tab

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
            case .profile: return "person.crop.circle"
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
                            .foregroundColor(selectedTab == tab ? Color("PrimaryColor") : .gray)

                        Text(tab.rawValue)
                            .font(.caption2)
                            .foregroundColor(selectedTab == tab ? Color("PrimaryColor") : .gray)
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(tab.rawValue)
                Spacer()
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            Rectangle()
                .fill(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: -2)
        )
    }
}

// Temporary PostCardView definition to avoid import issues
// Will be replaced by the actual view once module structure is fixed
struct PostCardView: View {
    let post: Post
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @State private var replyToDisplayName: String?
    @State private var navigateToDetail: Bool = false  // Add state for navigation
    @State private var parentPost: Post? = nil
    @State private var isLoadingParentPost: Bool = false
    @State private var showParentPost: Bool = false
    @State private var navigateToParentPost: Bool = false  // Navigation state for parent post

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Reply indicator
            if post.isReply, let replyToUsername = post.replyToUsername {
                // Modern reply indicator styling similar to Twitter/X/Bluesky
                HStack {
                    HStack(spacing: 6) {
                        // Reply arrow icon
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.system(size: 11))
                            .foregroundColor(post.platform == .bluesky ? Color.blue : Color.purple)
                            .padding(4)
                            .background(
                                Circle()
                                    .fill(
                                        (post.platform == .bluesky ? Color.blue : Color.purple)
                                            .opacity(0.12))
                            )

                        // Display username with proper formatting
                        Text(
                            "Replying to @\(replyToDisplayName ?? shortenUsername(replyToUsername))"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)

                        Spacer()

                        // Chevron indicator with rotation based on expansion state
                        Image(systemName: showParentPost ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.gray.opacity(0.6))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showParentPost.toggle()
                        if showParentPost && parentPost == nil && !isLoadingParentPost {
                            loadParentPost(
                                replyToUsername: replyToUsername, platform: post.platform)
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(UIColor.systemGray6).opacity(0.4))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                )
                .padding(.bottom, showParentPost ? 0 : 4)
                .onAppear {
                    // Try to load the actual username for Bluesky replies
                    if post.platform == .bluesky,
                        replyToUsername.hasPrefix("did:plc:"),
                        let replyToId = post.replyToId
                    {
                        // For Bluesky, we need to look up the post to get the author
                        Task {
                            await lookupReplyUsername(replyToId)
                        }
                    } else if !replyToUsername.hasPrefix("did:plc:") {
                        // For Mastodon or if we already have a username without DID
                        replyToDisplayName = replyToUsername
                    }
                }

                // Parent post preview when expanded
                if showParentPost {
                    if let parent = parentPost {
                        ParentPostPreview(
                            post: parent,
                            onTap: {
                                // Navigate to parent post detail view
                                navigateToParentPost = true
                            }
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                        .background(
                            NavigationLink(
                                destination: PostDetailView(post: parent),
                                isActive: $navigateToParentPost,
                                label: { EmptyView() }
                            )
                        )
                    } else if isLoadingParentPost {
                        // Loading placeholder
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding()
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                    } else {
                        // Message when parent post couldn't be loaded
                        Text("Couldn't fetch the parent post.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                    }
                }
            }

            // Boost/Repost indicator
            if post.isReposted {
                // Use same styling as reply indicator for consistency
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.2.squarepath.fill")
                            .font(.system(size: 11))
                            .foregroundColor(post.platform == .bluesky ? Color.blue : Color.purple)
                            .padding(4)
                            .background(
                                Circle()
                                    .fill(
                                        (post.platform == .bluesky ? Color.blue : Color.purple)
                                            .opacity(0.12))
                            )

                        Text("\(post.authorName) boosted")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        Spacer()
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(UIColor.systemGray6).opacity(0.4))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                )
                .padding(.bottom, 4)
            }

            // Author info
            HStack {
                // Avatar
                AsyncImage(url: URL(string: post.authorProfilePictureURL)) { phase in
                    if let image = phase.image {
                        image.resizable()
                    } else {
                        Circle().fill(Color.gray.opacity(0.3))
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())

                // Author name and username
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName)
                        .font(.headline)
                    Text("@\(post.authorUsername)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Platform indicator and time
                HStack(spacing: 4) {
                    Text(formattedDate(post.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Circle()
                        .fill(post.platform == .bluesky ? Color.blue : Color.purple)
                        .frame(width: 8, height: 8)
                }
            }

            // Post content
            Text(post.content)
                .font(.body)
                .multilineTextAlignment(.leading)

            // Interaction buttons
            HStack(spacing: 20) {
                Button(action: {}) {
                    Image(systemName: "bubble.left")
                        .foregroundColor(.secondary)
                }

                Button(action: {}) {
                    Image(systemName: "arrow.2.squarepath")
                        .foregroundColor(.secondary)
                }

                Button(action: {}) {
                    Image(systemName: "heart")
                        .foregroundColor(.secondary)
                }

                Button(action: {}) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.secondary)
                }
            }
            .font(.system(size: 16))
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture {
            // Only navigate to post detail when tapping on the main post area
            // (not the reply indicator or parent post preview)
            navigateToDetail = true
        }
        .background(
            // Only use the parent post if showing parent post details, otherwise use the current post
            NavigationLink(
                destination: PostDetailView(post: post),
                isActive: $navigateToDetail,
                label: { EmptyView() }
            )
        )
    }

    // Helper to look up a username from a reply ID
    private func lookupReplyUsername(_ replyId: String) async {
        // For Bluesky replies, try to fetch the original post to get the author's username
        do {
            if let parentPost = try await serviceManager.fetchBlueskyPostByID(replyId) {
                // Update the display name with the actual username
                await MainActor.run {
                    replyToDisplayName = parentPost.authorUsername
                }
            }
        } catch {
            print("Error loading reply author: \(error)")
        }
    }

    // Helper function to load parent post
    private func loadParentPost(replyToUsername: String, platform: SocialPlatform) {
        isLoadingParentPost = true

        // Cache key for looking up parent post
        let cacheKey = "parent-\(platform.rawValue)-\(replyToUsername)"

        // Check cache first
        if let cachedPost = PostParentCache.shared.getCachedPost(id: cacheKey) {
            parentPost = cachedPost
            isLoadingParentPost = false
            return
        }

        // Set up observers for parent post cache updates
        NotificationCenter.default.addObserver(
            forName: .parentPostUpdated,
            object: nil,
            queue: .main
        ) { notification in
            // Check if this notification is for our post
            if let notificationId = notification.object as? String,
                notificationId == cacheKey,
                let updatedPost = PostParentCache.shared.getCachedPost(id: cacheKey)
            {
                // Update our post
                self.parentPost = updatedPost
                self.isLoadingParentPost = false
            }
        }

        // Initiate fetch if not already being fetched
        if !PostParentCache.shared.isFetching(id: cacheKey) {
            PostParentCache.shared.fetchRealPost(
                id: cacheKey,
                username: replyToUsername,
                platform: platform,
                serviceManager: serviceManager
            )
        }

        // Set a timeout to avoid showing loading spinner indefinitely
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if self.isLoadingParentPost {
                // Check once more before giving up
                if let cachedPost = PostParentCache.shared.getCachedPost(id: cacheKey) {
                    self.parentPost = cachedPost
                }
                self.isLoadingParentPost = false
            }
        }
    }

    // For showing a shorter, more readable version of DIDs while loading
    private func shortenUsername(_ username: String) -> String {
        if username.hasPrefix("did:plc:") {
            let parts = username.components(separatedBy: ":")
            if parts.count >= 3 {
                let lastPart = parts[2]
                // Further shorten if too long
                if lastPart.count > 12 {
                    return String(lastPart.prefix(12)) + "..."
                }
                return lastPart
            }
        }
        return username
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

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

    private var timelineEntries: [TimelineEntry] {
        serviceManager.makeTimelineEntries(from: serviceManager.unifiedTimeline)
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
                            // Load trending posts for testing if no accounts
                            Task {
                                await serviceManager.fetchTrendingPosts()
                            }
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
                        postListView
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
                        // Use trending posts if there are no accounts
                        await serviceManager.fetchTrendingPosts()
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
            ForEach(timelineEntries) { entry in
                PostCardView(
                    viewModel: PostViewModel(
                        post: entry.post,
                        serviceManager: serviceManager,
                        kind: {
                            switch entry.kind {
                            case .normal: return .normal
                            case .boost(let boostedBy): return .boost(boostedBy: boostedBy)
                            case .reply(let parentId): return .reply(parentId: parentId)
                            }
                        }()
                    )
                )
            }
            if isLoadingMorePosts {
                ProgressView("Loading more posts...")
                    .padding()
                    .onAppear {
                        Task {
                            isLoadingMorePosts = false
                        }
                    }
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

// Cache for parent posts to avoid duplicate fetches
class PostParentCache {
    static let shared = PostParentCache()
    private var cache = [String: Post]()
    private var fetching = Set<String>()

    func getCachedPost(id: String) -> Post? {
        return cache[id]
    }

    func isFetching(id: String) -> Bool {
        return fetching.contains(id)
    }

    func fetchRealPost(
        id: String, username: String, platform: SocialPlatform, serviceManager: SocialServiceManager
    ) {
        fetching.insert(id)

        Task {
            do {
                var post: Post?

                if platform == .mastodon {
                    // Implementation for Mastodon parent post fetching
                } else if platform == .bluesky {
                    if username.hasPrefix("did:plc:"),
                        let postId = username.split(separator: "/").last
                    {
                        post = try await serviceManager.fetchBlueskyPostByID(String(postId))
                    }
                }

                if let post = post {
                    await MainActor.run {
                        cache[id] = post
                        fetching.remove(id)
                        NotificationCenter.default.post(name: .parentPostUpdated, object: id)
                    }
                } else {
                    await MainActor.run {
                        fetching.remove(id)
                    }
                }
            } catch {
                print("Error fetching parent post: \(error)")
                await MainActor.run {
                    fetching.remove(id)
                }
            }
        }
    }
}

// Notification name for parent post updates
extension Notification.Name {
    static let parentPostUpdated = Notification.Name("parentPostUpdated")
}

// Parent post preview view
// Using shared ParentPostPreview component from PostCardView.swift

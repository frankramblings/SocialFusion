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

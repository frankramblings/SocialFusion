import Combine
import SwiftUI
import UIKit

struct UnifiedTimelineView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @State private var showingAuthError = false
    @State private var authErrorMessage = ""
    @State private var showingErrorAlert = false
    @State private var errorMessage: String? = nil
    @State private var isRefreshing = false
    @State private var isLoadingMorePosts = false
    @Environment(\.colorScheme) private var colorScheme

    private var hasAccounts: Bool {
        !serviceManager.mastodonAccounts.isEmpty || !serviceManager.blueskyAccounts.isEmpty
    }

    private var displayPosts: [Post] {
        return serviceManager.unifiedTimeline
    }

    private var displayTitle: String {
        if !hasAccounts {
            return "Trending"
        } else if serviceManager.selectedAccountIds.contains("all")
            || serviceManager.selectedAccountIds.isEmpty
        {
            return "All Accounts"
        } else if let accountId = serviceManager.selectedAccountIds.first,
            let account = getCurrentAccountById(accountId)
        {
            return account.displayName ?? account.username
        } else {
            return "Home"
        }
    }

    private func getCurrentAccountById(_ id: String) -> SocialAccount? {
        return serviceManager.mastodonAccounts.first(where: { $0.id == id })
            ?? serviceManager.blueskyAccounts.first(where: { $0.id == id })
    }

    var body: some View {
        TimelineContentView(
            displayTitle: displayTitle,
            hasAccounts: hasAccounts,
            displayPosts: displayPosts,
            isRefreshing: $isRefreshing,
            isLoadingMorePosts: $isLoadingMorePosts,
            showingAuthError: $showingAuthError,
            authErrorMessage: $authErrorMessage,
            showingErrorAlert: $showingErrorAlert,
            errorMessage: $errorMessage
        )
        .environmentObject(serviceManager)
    }
}

// Helper view to split up the complex body
struct TimelineContentView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    let displayTitle: String
    let hasAccounts: Bool
    let displayPosts: [Post]
    @Binding var isRefreshing: Bool
    @Binding var isLoadingMorePosts: Bool
    @Binding var showingAuthError: Bool
    @Binding var authErrorMessage: String
    @Binding var showingErrorAlert: Bool
    @Binding var errorMessage: String?
    @Environment(\.colorScheme) private var colorScheme

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
                        }
                    }
            } else {
                TimelineListView(
                    displayTitle: displayTitle,
                    displayPosts: displayPosts,
                    isRefreshing: $isRefreshing,
                    isLoadingMorePosts: $isLoadingMorePosts,
                    showingAuthError: $showingAuthError,
                    authErrorMessage: $authErrorMessage,
                    showingErrorAlert: $showingErrorAlert,
                    errorMessage: $errorMessage
                )
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
            Task {
                print("Account status changed to hasAccounts: \(newValue)")
                if newValue {
                    do {
                        try await serviceManager.refreshTimeline()
                    } catch {
                        // Just log errors, don't display alert on automatic refresh
                        print(
                            "Error refreshing timeline after account status change: \(error.localizedDescription)"
                        )
                    }
                }
            }
        }
        .onChange(of: serviceManager.selectedAccountIds) { _ in
            // When selected accounts change, refresh the timeline
            Task {
                print("Selected accounts changed, refreshing timeline")
                if hasAccounts {
                    do {
                        try await serviceManager.refreshTimeline(force: true)
                    } catch {
                        // Just log errors, don't display alert on automatic refresh
                        print(
                            "Error refreshing timeline after account selection change: \(error.localizedDescription)"
                        )
                    }
                }
            }
        }
        .onReceive(serviceManager.$error) { newError in
            // Show auth error banner if applicable
            if let error = newError as? NSError,
                error.domain == "BlueskyService" || error.domain == "MastodonService",
                error.code == 401
            {
                authErrorMessage =
                    "Authentication issue detected. Please check your account settings."
                showingAuthError = true
            } else if let error = newError {
                errorMessage = error.localizedDescription
                showingErrorAlert = true
            } else {
                showingAuthError = false
                showingErrorAlert = false
            }
        }
    }
}

// Further splitting the view to reduce complexity
struct TimelineListView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    let displayTitle: String
    let displayPosts: [Post]
    @Binding var isRefreshing: Bool
    @Binding var isLoadingMorePosts: Bool
    @Binding var showingAuthError: Bool
    @Binding var authErrorMessage: String
    @Binding var showingErrorAlert: Bool
    @Binding var errorMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header at the top with an elegant design
            HStack {
                Text(displayTitle)
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                // Refresh button
                Button(action: {
                    isRefreshing = true
                    Task {
                        do {
                            try await serviceManager.refreshTimeline(force: true)
                            isRefreshing = false
                        } catch {
                            isRefreshing = false
                            if let serviceError = error as? ServiceError,
                                case let .rateLimitError(reason, _) = serviceError
                            {
                                errorMessage = "\(reason) Please try again later."
                                showingErrorAlert = true
                            } else {
                                errorMessage = error.localizedDescription
                                showingErrorAlert = true
                            }
                        }
                    }
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
            .background(
                colorScheme == .dark
                    ? Color(UIColor.secondarySystemBackground) : Color.white
            )
            .overlay(
                Divider()
                    .opacity(0.5)
                    .background(Color.gray.opacity(0.2))
                    .offset(y: 12),
                alignment: .bottom
            )

            PostListView(
                displayPosts: displayPosts,
                showingAuthError: showingAuthError,
                authErrorMessage: authErrorMessage,
                isLoadingMorePosts: $isLoadingMorePosts
            )
        }
    }
}

// Final view component for the post list
struct PostListView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    let displayPosts: [Post]
    let showingAuthError: Bool
    let authErrorMessage: String
    @Binding var isLoadingMorePosts: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
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
                            // Since we can't directly modify the binding here,
                            // we'll need to handle this at a higher level
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
                    PostCardView(post: post)
                }

                // Show loading indicator at the bottom when more posts are loading
                if isLoadingMorePosts {
                    ProgressView("Loading more posts...")
                        .padding()
                        .onAppear {
                            Task {
                                // Instead of directly using serviceManager.loadMorePosts
                                // We'll set a flag to handle loading more posts
                                isLoadingMorePosts = false
                            }
                        }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .refreshable {
            do {
                if !serviceManager.mastodonAccounts.isEmpty
                    || !serviceManager.blueskyAccounts.isEmpty
                {
                    try await serviceManager.refreshTimeline(force: true)
                }
            } catch {
                // Error handling happens at a higher level
                print("Error refreshing: \(error.localizedDescription)")
            }
        }
    }
}

// A reusable empty state view
struct EmptyTimelineView: View {
    let hasAccounts: Bool
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @State private var showAddAccountView = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        colorScheme == .dark
                            ? Color(UIColor.tertiarySystemBackground)
                            : Color(UIColor.secondarySystemBackground)
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 44))
                    .foregroundColor(Color("AccentColor"))
            }

            Text("No posts to display")
                .font(.title3)
                .fontWeight(.medium)

            if hasAccounts {
                Text("Pull down to refresh your timeline")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .foregroundColor(.secondary)
            } else {
                Text("Add accounts to view your personal timeline")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .foregroundColor(.secondary)

                Button(action: {
                    // Show the add account view
                    showAddAccountView = true
                }) {
                    Text("Add Account")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(25)
                }
                .padding(.top, 12)
            }

            Spacer()
        }
        .sheet(isPresented: $showAddAccountView) {
            AddAccountView()
                .environmentObject(serviceManager)
        }
    }
}

struct UnifiedTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        UnifiedTimelineView()
            .environmentObject(SocialServiceManager())
    }
}

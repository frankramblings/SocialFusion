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
    @Environment(\.colorScheme) private var colorScheme

    private var hasAccounts: Bool {
        !serviceManager.mastodonAccounts.isEmpty || !serviceManager.blueskyAccounts.isEmpty
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

                    ScrollView {
                        LazyVStack(spacing: 14) {
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

                            ForEach(serviceManager.unifiedTimeline) { post in
                                PostCardView(post: post)
                                    .padding(.horizontal)
                            }

                            // Add a bottom padding to ensure there's space at the end of the list
                            Color.clear
                                .frame(height: 50)
                        }
                        .padding(.vertical, 10)
                    }
                    .refreshable {
                        do {
                            if hasAccounts {
                                try await serviceManager.refreshTimeline(force: true)
                            }
                        } catch {
                            // Handle authentication errors specifically
                            if (error as NSError).domain == "BlueskyService"
                                || (error as NSError).domain == "MastodonService",
                                (error as NSError).code == 401
                            {
                                authErrorMessage =
                                    "Authentication issue detected. Please check your account settings."
                                showingAuthError = true
                            }
                            // Handle rate limit errors with specific message
                            else if let serviceError = error as? ServiceError,
                                case let .rateLimitError(reason, _) = serviceError
                            {
                                errorMessage = "\(reason) Please try again later."
                                showingErrorAlert = true
                            }
                            // Handle other errors
                            else {
                                errorMessage = error.localizedDescription
                                showingErrorAlert = true
                            }
                        }
                    }
                }
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

// A reusable empty state view
struct EmptyTimelineView: View {
    let hasAccounts: Bool
    @Environment(\.colorScheme) private var colorScheme

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
                    // Navigate to accounts view or show account picker
                    // This would need to be implemented based on your navigation structure
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
    }
}

struct UnifiedTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        UnifiedTimelineView()
            .environmentObject(SocialServiceManager())
    }
}

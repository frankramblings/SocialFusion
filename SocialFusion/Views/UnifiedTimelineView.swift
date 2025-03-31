import SwiftUI
import UIKit

struct UnifiedTimelineView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager

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
                        if !hasAccounts {
                            Task {
                                await serviceManager.fetchTrendingPosts()
                            }
                        } else {
                            Task {
                                await serviceManager.refreshTimeline()
                            }
                        }
                    }
            } else {
                VStack(spacing: 0) {
                    // Show the header text based on the current selection
                    HStack {
                        Text(displayTitle)
                            .font(.headline)
                            .padding(.horizontal)
                            .padding(.top, 8)
                            .padding(.bottom, 4)

                        Spacer()
                    }

                    Divider()

                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(serviceManager.unifiedTimeline) { post in
                                PostCardView(post: post)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                    .refreshable {
                        if hasAccounts {
                            print("User triggered refresh - has accounts")
                            await serviceManager.refreshTimeline()
                        } else {
                            print("User triggered refresh - logged out")
                            await serviceManager.fetchTrendingPosts()
                        }
                    }
                }
            }
        }
        .onAppear {
            Task {
                print("Timeline view appeared - hasAccounts: \(hasAccounts)")
                if hasAccounts {
                    await serviceManager.refreshTimeline()
                } else {
                    await serviceManager.fetchTrendingPosts()
                }
            }
        }
        .onChange(of: hasAccounts) { newValue in
            // When accounts status changes, refresh the appropriate content
            Task {
                print("Account status changed to hasAccounts: \(newValue)")
                if newValue {
                    await serviceManager.refreshTimeline()
                } else {
                    await serviceManager.fetchTrendingPosts()
                }
            }
        }
        .onChange(of: serviceManager.selectedAccountIds) { _ in
            // When selected accounts change, refresh the timeline
            Task {
                print("Selected accounts changed, refreshing timeline")
                if hasAccounts {
                    await serviceManager.refreshTimeline(force: true)
                }
            }
        }
    }
}

// A reusable empty state view
struct EmptyTimelineView: View {
    let hasAccounts: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundColor(Color("AccentColor"))

            Text("No posts to display")
                .font(.headline)

            if hasAccounts {
                Text("Pull to refresh your timeline")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .foregroundColor(.secondary)
            } else {
                Text("Add accounts to view your personal timeline")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct UnifiedTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        UnifiedTimelineView()
            .environmentObject(SocialServiceManager())
    }
}

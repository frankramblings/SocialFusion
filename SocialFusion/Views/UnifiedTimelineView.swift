import SwiftUI
import UIKit

struct UnifiedTimelineView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager

    private var hasAccounts: Bool {
        !serviceManager.mastodonAccounts.isEmpty || !serviceManager.blueskyAccounts.isEmpty
    }

    private var displayTitle: String {
        hasAccounts ? "Home" : "Trending"
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
                        }
                    }
            } else {
                VStack(spacing: 0) {
                    // Show the "Trending" header text if we're in the logged-out state
                    if !hasAccounts {
                        HStack {
                            Text("Trending")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top, 8)
                                .padding(.bottom, 4)

                            Spacer()
                        }

                        Divider()
                    }

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
                            await serviceManager.refreshTimeline()
                        } else {
                            await serviceManager.fetchTrendingPosts()
                        }
                    }
                }
            }
        }
        .onAppear {
            Task {
                if hasAccounts {
                    await serviceManager.refreshTimeline()
                } else {
                    await serviceManager.fetchTrendingPosts()
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

import SwiftUI

struct AccountTimelineView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    let account: SocialAccount

    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var error: Error? = nil

    private var timelineEntries: [TimelineEntry] {
        serviceManager.makeTimelineEntries(from: posts)
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            if isLoading && posts.isEmpty {
                ProgressView()
                    .scaleEffect(1.5)
            } else if posts.isEmpty {
                VStack(spacing: 20) {
                    Image(
                        systemName: account.platform == .mastodon
                            ? "bubble.left.fill" : "cloud.fill"
                    )
                    .font(.system(size: 60))
                    .foregroundColor(Color(account.platform.color))

                    Text("No posts to display")
                        .font(.headline)

                    Text("Pull to refresh")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(timelineEntries) { entry in
                            PostCardView(entry: entry)
                                .id(entry.id)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
                .refreshable {
                    await loadPosts()
                }
            }
        }
        .onAppear {
            Task {
                await loadPosts()
            }
        }
    }

    private func loadPosts() async {
        isLoading = true

        do {
            switch account.platform {
            case .mastodon:
                posts = try await serviceManager.mastodonService.fetchHomeTimeline(for: account)
            case .bluesky:
                posts = try await serviceManager.blueskyService.fetchHomeTimeline(for: account)
            }

            // Sort by date, newest first
            posts.sort { $0.createdAt > $1.createdAt }
        } catch {
            self.error = error
            print("Error loading posts: \(error)")

            // For testing, fallback to some sample data
            if posts.isEmpty {
                posts = Post.samplePosts.filter { $0.platform == account.platform }
            }
        }

        isLoading = false
    }
}

extension SocialServiceManager {
    // Make these services accessible for individual account timelines
    var mastodonService: MastodonService {
        // In a real app, this would be properly injected
        // For now, we're creating a new instance here
        MastodonService()
    }

    var blueskyService: BlueskyService {
        // In a real app, this would be properly injected
        // For now, we're creating a new instance here
        BlueskyService()
    }
}

struct AccountTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        let mastodonAccount = SocialAccount(
            id: "1",
            username: "user@mastodon.social",
            displayName: "Mastodon User",
            serverURL: "mastodon.social",
            platform: .mastodon
        )

        AccountTimelineView(account: mastodonAccount)
            .environmentObject(SocialServiceManager())
    }
}

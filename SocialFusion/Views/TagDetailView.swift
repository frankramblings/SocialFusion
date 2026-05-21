import SwiftUI

struct TagDetailView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    let tag: SearchTag
    @StateObject private var navigationEnvironment = PostNavigationEnvironment()
    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var error: Error? = nil
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header — tinted halo + large hashtag + post count
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.0)],
                                    center: .center,
                                    startRadius: 4,
                                    endRadius: 70
                                )
                            )
                            .frame(width: 140, height: 140)

                        Image(systemName: "number")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(Color.accentColor.gradient)
                            .symbolRenderingMode(.hierarchical)
                    }

                    Text("#\(tag.name)")
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    if let count = tag.formattedUsageCount {
                        Text("\(count) post\(count == "1" ? "" : "s")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .background(
                    LinearGradient(
                        colors: [
                            Color(.secondarySystemBackground),
                            Color(.secondarySystemBackground).opacity(0.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Posts Feed
                if isLoading && posts.isEmpty {
                    ProgressView()
                        .padding(.top, 40)
                        .accessibilityLabel("Loading tagged posts")
                } else if error != nil {
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.14))
                                .frame(width: 64, height: 64)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(Color.orange.gradient)
                                .symbolRenderingMode(.hierarchical)
                        }
                        Text("Couldn't load posts")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary.opacity(0.8))
                            .accessibilityAddTraits(.isHeader)
                        Button {
                            HapticEngine.tap.trigger()
                            Task { await fetchPosts() }
                        } label: {
                            Text("Try Again")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor.gradient)
                                        .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 3)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 40)
                } else if posts.isEmpty {
                    VStack(spacing: 14) {
                        // Tinted-halo composition matching other empty
                        // states across the app.
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [Color.accentColor.opacity(0.14), Color.accentColor.opacity(0.0)],
                                        center: .center,
                                        startRadius: 4,
                                        endRadius: 60
                                    )
                                )
                                .frame(width: 120, height: 120)
                            Image(systemName: "tray")
                                .font(.system(size: 36, weight: .light))
                                .foregroundStyle(Color.accentColor.gradient)
                                .symbolRenderingMode(.hierarchical)
                        }
                        VStack(spacing: 6) {
                            Text("No posts yet")
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.primary.opacity(0.85))
                            Text("Be the first — try this hashtag from your timeline.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 40)
                    .accessibilityElement(children: .combine)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(posts) { post in
                            PostCardView(
                                entry: TimelineEntry(
                                    id: post.id,
                                    kind: .normal,
                                    post: post,
                                    createdAt: post.createdAt
                                ),
                                postActionStore: serviceManager.postActionStore,
                                onAuthorTap: { navigationEnvironment.navigateToUser(from: post) },
                                onShare: { post.presentShareSheet() },
                                onOpenInBrowser: { post.openInBrowser() },
                                onCopyLink: { post.copyLink() },
                                onReport: { post.report(via: serviceManager) }
                            )
                            Divider().padding(.horizontal)
                        }
                    }
                }
            }
        }
        .navigationDestination(
            isPresented: Binding(
                get: { navigationEnvironment.selectedUser != nil },
                set: { if !$0 { navigationEnvironment.clearNavigation() } }
            )
        ) {
            if let user = navigationEnvironment.selectedUser {
                ProfileView(user: user, serviceManager: serviceManager)
                    .environmentObject(serviceManager)
            }
        }
        .navigationTitle("#\(tag.name)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await fetchPosts()
            }
        }
    }
    
    private func fetchPosts() async {
        isLoading = true
        error = nil
        do {
            // We need a search for posts by tag
            let result = try await serviceManager.search(query: "#\(tag.name)")
            posts = result.posts
        } catch {
            #if DEBUG
            print("Failed to fetch tag posts: \(error)")
            #endif
            self.error = error
        }
        isLoading = false
    }
}

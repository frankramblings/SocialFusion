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
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "number")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                        .padding(.top, 20)
                    
                    Text("#\(tag.name)")
                        .font(.title)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)
                .background(Color(.secondarySystemBackground))

                // Posts Feed
                if isLoading && posts.isEmpty {
                    ProgressView()
                        .padding(.top, 40)
                } else if error != nil {
                    VStack(spacing: 12) {
                        Text("Failed to load posts")
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task {
                                await fetchPosts()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 40)
                } else if posts.isEmpty {
                    Text("No posts found for this tag")
                        .foregroundColor(.secondary)
                        .padding(.top, 40)
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
                                onReport: {
                                    Task {
                                        do {
                                            try await serviceManager.reportPost(post)
                                        } catch {
                                            ErrorHandler.shared.handleError(error)
                                        }
                                    }
                                }
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
                UserDetailView(user: user)
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
            print("Failed to fetch tag posts: \(error)")
            self.error = error
        }
        isLoading = false
    }
}

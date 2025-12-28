import SwiftUI

struct UserDetailView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    let user: SearchUser
    @State private var posts: [Post] = []
    @State private var profile: BlueskyProfile? = nil // Only for Bluesky
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var error: Error? = nil
    @State private var cursor: String? = nil
    @State private var canLoadMore = true
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Profile Header
                VStack(spacing: 16) {
                    if let avatarURL = user.avatarURL, let url = URL(string: avatarURL) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(Color.gray.opacity(0.3))
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1))
                        .padding(.top, 20)
                    } else {
                        Circle().fill(Color.gray.opacity(0.3))
                            .frame(width: 80, height: 80)
                            .padding(.top, 20)
                    }

                    VStack(spacing: 4) {
                        Text(user.displayName ?? user.username)
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("@\(user.username)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if let profile = profile {
                            Text(profile.description ?? "")
                                .font(.body)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .padding(.top, 8)
                            
                            HStack(spacing: 20) {
                                VStack {
                                    Text("\(profile.followersCount)")
                                        .fontWeight(.bold)
                                    Text("Followers")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                VStack {
                                    Text("\(profile.followsCount)")
                                        .fontWeight(.bold)
                                    Text("Following")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)
                .background(Color(.secondarySystemBackground))

                // Posts Feed
                if isLoading && posts.isEmpty {
                    ProgressView()
                        .padding(.top, 40)
                } else if let error = error {
                    VStack(spacing: 12) {
                        Text("Failed to load posts")
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task {
                                await fetchData()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 40)
                } else if posts.isEmpty {
                    Text("No posts yet")
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
                                postActionStore: serviceManager.postActionStore
                            )
                            .onAppear {
                                if post.id == posts.last?.id && canLoadMore && !isLoadingMore {
                                    Task {
                                        await fetchMorePosts()
                                    }
                                }
                            }
                            Divider().padding(.horizontal)
                        }
                        
                        if isLoadingMore {
                            ProgressView()
                                .padding()
                        }
                    }
                }
            }
        }
        .navigationTitle(user.displayName ?? user.username)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if posts.isEmpty {
                Task {
                    await fetchData()
                }
            }
        }
    }
    
    private func fetchData() async {
        isLoading = true
        error = nil
        do {
            // Determine which account to use for fetching
            guard let account = serviceManager.accounts.first(where: { $0.platform == user.platform }) else {
                isLoading = false
                return
            }
            
            // Fetch posts
            let (newPosts, nextCursor) = try await serviceManager.fetchUserPosts(user: user, account: account)
            posts = newPosts
            cursor = nextCursor
            canLoadMore = nextCursor != nil && !newPosts.isEmpty
            
            // Fetch extra profile info for Bluesky
            if user.platform == .bluesky {
                // We might need a service method for this
                // For now just keep existing info
            }
        } catch {
            print("Failed to fetch user data: \(error)")
            self.error = error
        }
        isLoading = false
    }
    
    private func fetchMorePosts() async {
        guard let currentCursor = cursor, canLoadMore else { return }
        
        isLoadingMore = true
        do {
            guard let account = serviceManager.accounts.first(where: { $0.platform == user.platform }) else {
                isLoadingMore = false
                return
            }
            
            let (newPosts, nextCursor) = try await serviceManager.fetchUserPosts(user: user, account: account, cursor: currentCursor)
            
            if newPosts.isEmpty {
                canLoadMore = false
            } else {
                posts.append(contentsOf: newPosts)
                cursor = nextCursor
                canLoadMore = nextCursor != nil
            }
        } catch {
            print("Failed to fetch more user posts: \(error)")
        }
        isLoadingMore = false
    }
}


import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    let account: SocialAccount
    @State private var posts: [Post] = []
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
                    ProfileImageView(account: account)
                        .frame(width: 80, height: 80)
                        .overlay(
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .padding(.top, 20)

                    VStack(spacing: 4) {
                        Text(account.displayName ?? account.username)
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("@\(account.username)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
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
                                await fetchPosts()
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
        .navigationTitle(account.displayName ?? account.username)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if posts.isEmpty {
                Task {
                    await fetchPosts()
                }
            }
        }
    }
    
    private func fetchPosts() async {
        isLoading = true
        error = nil
        do {
            let searchUser = SearchUser(
                id: account.platformSpecificId,
                username: account.username,
                displayName: account.displayName,
                avatarURL: account.profileImageURL?.absoluteString,
                platform: account.platform
            )
            let (newPosts, nextCursor) = try await serviceManager.fetchUserPosts(user: searchUser, account: account)
            posts = newPosts
            cursor = nextCursor
            canLoadMore = nextCursor != nil && !newPosts.isEmpty
        } catch {
            print("Failed to fetch user posts: \(error)")
            self.error = error
        }
        isLoading = false
    }
    
    private func fetchMorePosts() async {
        guard let currentCursor = cursor, canLoadMore else { return }
        
        isLoadingMore = true
        do {
            let searchUser = SearchUser(
                id: account.platformSpecificId,
                username: account.username,
                displayName: account.displayName,
                avatarURL: account.profileImageURL?.absoluteString,
                platform: account.platform
            )
            let (newPosts, nextCursor) = try await serviceManager.fetchUserPosts(user: searchUser, account: account, cursor: currentCursor)
            
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


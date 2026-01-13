import SwiftUI

struct UserDetailView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    let user: SearchUser
    @StateObject private var navigationEnvironment = PostNavigationEnvironment()
    @State private var posts: [Post] = []
    @State private var profile: BlueskyProfile? = nil // Only for Bluesky
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var error: Error? = nil
    @State private var cursor: String? = nil
    @State private var canLoadMore = true
    
    // Relationship management
    @State private var relationshipViewModel: RelationshipViewModel?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Profile Header
                VStack(spacing: 16) {
                    if let avatarURL = user.avatarURL, let url = URL(string: avatarURL) {
                        CachedAsyncImage(url: url, priority: .high) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(Color.gray.opacity(0.3))
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.6)
                                )
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
                
                // Relationship Bar
                if let viewModel = relationshipViewModel {
                    RelationshipBarView(viewModel: viewModel)
                        .padding(.vertical, 8)
                        .background(Color(.systemBackground))
                }

                // Posts Feed
                if let viewModel = relationshipViewModel, viewModel.state.isBlocking {
                    // Blocked state: show placeholder
                    VStack(spacing: 12) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("You blocked this account")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("You won't see their posts in your timeline.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
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
        }
        .navigationDestination(
            isPresented: Binding(
                get: { navigationEnvironment.selectedUser != nil },
                set: { if !$0 { navigationEnvironment.clearNavigation() } }
            )
        ) {
            if let selectedUser = navigationEnvironment.selectedUser {
                UserDetailView(user: selectedUser)
                    .environmentObject(serviceManager)
            }
        }
        .navigationTitle(user.displayName ?? user.username)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Initialize relationship view model with proper account and service
            if relationshipViewModel == nil {
                let actorID = ActorID(from: user)
                if let account = serviceManager.accounts.first(where: { $0.platform == user.platform }) {
                    let graphService = serviceManager.graphService(for: user.platform)
                    let store = serviceManager.relationshipStore
                    
                    // Create new view model with correct dependencies
                    let newViewModel = RelationshipViewModel(
                        actorID: actorID,
                        account: account,
                        graphService: graphService,
                        relationshipStore: store
                    )
                    
                    relationshipViewModel = newViewModel
                    
                    // Load relationship state
                    Task {
                        await newViewModel.loadState()
                    }
                }
            }
            
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

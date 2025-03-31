import SwiftUI

struct UnifiedTimelineView: View {
    @State private var posts: [Post] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()
                
                if isLoading && posts.isEmpty {
                    ProgressView()
                        .scaleEffect(1.5)
                } else if posts.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 60))
                            .foregroundColor(Color("AccentColor"))
                        
                        Text("No posts to display")
                            .font(.headline)
                        
                        Text("Add accounts in the Accounts tab to get started")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(posts) { post in
                                PostCardView(post: post)
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
            .navigationTitle("Timeline")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await loadPosts()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
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
        
        // This would be replaced with actual API calls to Mastodon and Bluesky
        // For now, we'll just simulate loading with some sample data
        do {
            try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            posts = Post.samplePosts
        } catch {
            print("Error loading posts: \(error)")
        }
        
        isLoading = false
    }
}

struct UnifiedTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        UnifiedTimelineView()
    }
}
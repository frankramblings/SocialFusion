import Foundation
import Combine

class SocialServiceManager: ObservableObject {
    // Services
    private let mastodonService = MastodonService()
    private let blueskyService = BlueskyService()
    
    // Published properties
    @Published var mastodonAccounts: [SocialAccount] = []
    @Published var blueskyAccounts: [SocialAccount] = []
    @Published var unifiedTimeline: [Post] = []
    @Published var isLoadingTimeline = false
    @Published var error: Error? = nil
    
    // MARK: - Initialization
    
    init() {
        loadAccounts()
    }
    
    // MARK: - Account Management
    
    private func loadAccounts() {
        // In a real app, this would load accounts from secure storage
        // For now, we'll just use sample data
        mastodonAccounts = [
            SocialAccount(id: "1", username: "user1", displayName: "User One", serverURL: "mastodon.social", platform: .mastodon),
        ]
        
        blueskyAccounts = [
            SocialAccount(id: "2", username: "user2.bsky.social", displayName: "User Two", serverURL: "bsky.social", platform: .bluesky),
        ]
    }
    
    func addMastodonAccount(server: String, username: String, password: String) async throws -> SocialAccount {
        let account = try await mastodonService.authenticate(server: server, username: username, password: password)
        
        // Add to accounts list
        DispatchQueue.main.async {
            self.mastodonAccounts.append(account)
        }
        
        // In a real app, save to secure storage
        
        return account
    }
    
    func addBlueskyAccount(username: String, password: String) async throws -> SocialAccount {
        let account = try await blueskyService.authenticate(username: username, password: password)
        
        // Add to accounts list
        DispatchQueue.main.async {
            self.blueskyAccounts.append(account)
        }
        
        // In a real app, save to secure storage
        
        return account
    }
    
    func removeAccount(_ account: SocialAccount) {
        // Remove from accounts list
        DispatchQueue.main.async {
            if account.platform == .mastodon {
                self.mastodonAccounts.removeAll { $0.id == account.id }
            } else {
                self.blueskyAccounts.removeAll { $0.id == account.id }
            }
        }
        
        // In a real app, remove from secure storage
    }
    
    // MARK: - Timeline
    
    func refreshTimeline() async {
        guard !mastodonAccounts.isEmpty || !blueskyAccounts.isEmpty else {
            // No accounts to fetch timeline for
            return
        }
        
        DispatchQueue.main.async {
            self.isLoadingTimeline = true
            self.error = nil
        }
        
        do {
            var allPosts: [Post] = []
            
            // Fetch Mastodon timeline for all accounts
            for account in mastodonAccounts {
                let posts = try await mastodonService.fetchHomeTimeline(for: account)
                allPosts.append(contentsOf: posts)
            }
            
            // Fetch Bluesky timeline for all accounts
            for account in blueskyAccounts {
                let posts = try await blueskyService.fetchHomeTimeline(for: account)
                allPosts.append(contentsOf: posts)
            }
            
            // Sort by date, newest first
            let sortedPosts = allPosts.sorted { $0.createdAt > $1.createdAt }
            
            DispatchQueue.main.async {
                self.unifiedTimeline = sortedPosts
                self.isLoadingTimeline = false
            }
        } catch {
            DispatchQueue.main.async {
                self.error = error
                self.isLoadingTimeline = false
            }
        }
    }
    
    // MARK: - Post Actions
    
    func createPost(content: String, mediaAttachments: [Data] = [], platforms: Set<SocialPlatform>, visibility: PostVisibility = .public) async throws {
        var createdPosts: [Post] = []
        
        // Post to Mastodon if selected
        if platforms.contains(.mastodon) {
            for account in mastodonAccounts {
                let post = try await mastodonService.createPost(
                    content: content,
                    mediaAttachments: mediaAttachments,
                    visibility: visibility,
                    account: account
                )
                createdPosts.append(post)
            }
        }
        
        // Post to Bluesky if selected
        if platforms.contains(.bluesky) {
            for account in blueskyAccounts {
                let post = try await blueskyService.createPost(
                    content: content,
                    mediaAttachments: mediaAttachments,
                    account: account
                )
                createdPosts.append(post)
            }
        }
        
        // Add created posts to timeline
        DispatchQueue.main.async {
            self.unifiedTimeline.insert(contentsOf: createdPosts, at: 0)
        }
    }
    
    func likePost(_ post: Post) async throws {
        var updatedPost: Post
        
        if post.platform == .mastodon {
            // Get the first Mastodon account (in a real app, use the account that's viewing the post)
            guard let account = mastodonAccounts.first else { return }
            updatedPost = try await mastodonService.likePost(post, account: account)
        } else {
            // Get the first Bluesky account (in a real app, use the account that's viewing the post)
            guard let account = blueskyAccounts.first else { return }
            updatedPost = try await blueskyService.likePost(post, account: account)
        }
        
        // Update post in timeline
        DispatchQueue.main.async {
            if let index = self.unifiedTimeline.firstIndex(where: { $0.id == post.id }) {
                self.unifiedTimeline[index] = updatedPost
            }
        }
    }
    
    func repostPost(_ post: Post) async throws {
        var updatedPost: Post
        
        if post.platform == .mastodon {
            // Get the first Mastodon account (in a real app, use the account that's viewing the post)
            guard let account = mastodonAccounts.first else { return }
            updatedPost = try await mastodonService.repostPost(post, account: account)
        } else {
            // Get the first Bluesky account (in a real app, use the account that's viewing the post)
            guard let account = blueskyAccounts.first else { return }
            updatedPost = try await blueskyService.repostPost(post, account: account)
        }
        
        // Update post in timeline
        DispatchQueue.main.async {
            if let index = self.unifiedTimeline.firstIndex(where: { $0.id == post.id }) {
                self.unifiedTimeline[index] = updatedPost
            }
        }
    }
    
    func replyToPost(_ post: Post, content: String) async throws {
        var replyPost: Post
        
        if post.platform == .mastodon {
            // Get the first Mastodon account (in a real app, use the account that's viewing the post)
            guard let account = mastodonAccounts.first else { return }
            replyPost = try await mastodonService.replyToPost(post, content: content, account: account)
        } else {
            // Get the first Bluesky account (in a real app, use the account that's viewing the post)
            guard let account = blueskyAccounts.first else { return }
            replyPost = try await blueskyService.replyToPost(post, content: content, account: account)
        }
        
        // Add reply to timeline
        DispatchQueue.main.async {
            self.unifiedTimeline.insert(replyPost, at: 0)
            
            // Update reply count on original post
            if let index = self.unifiedTimeline.firstIndex(where: { $0.id == post.id }) {
                var updatedPost = self.unifiedTimeline[index]
                updatedPost.replyCount += 1
                self.unifiedTimeline[index] = updatedPost
            }
        }
    }
}
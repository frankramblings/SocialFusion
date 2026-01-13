import SwiftUI

/// Environment object to handle post navigation throughout the app
class PostNavigationEnvironment: ObservableObject {
    @Published var selectedPost: Post? = nil
    @Published var boostInfo: (boostedBy: String, boostedAt: Date)? = nil

    @Published var selectedUser: SearchUser? = nil
    @Published var selectedTag: SearchTag? = nil

    func navigateToPost(_ post: Post) {
        print("🧭 [PostNavigationEnvironment] Navigating to post: \(post.id) by \(post.authorName)")

        // Defer state updates to prevent AttributeGraph cycles
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds

            // If this is a boost post, navigate to the original post but preserve boost info
            if let originalPost = post.originalPost, let boostedBy = post.boostedBy {
                print(
                    "🧭 [PostNavigationEnvironment] Boost detected - navigating to original post: \(originalPost.id)"
                )
                selectedPost = originalPost
                boostInfo = (boostedBy: boostedBy, boostedAt: post.createdAt)
            } else {
                selectedPost = post
                boostInfo = nil
            }
        }
    }
    
    /// Navigate to a user's profile from a Post
    func navigateToUser(from post: Post) {
        // CRITICAL FIX: For boosted posts, navigate to the original author, not the booster
        let targetPost = post.originalPost ?? post
        print("🧭 [PostNavigationEnvironment] Navigating to user profile: \(targetPost.authorUsername) on \(targetPost.platform) (from post \(post.id), isBoost: \(post.originalPost != nil))")
        
        // Defer state updates to prevent AttributeGraph cycles
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
            
            // CRITICAL FIX: Use authorId instead of authorUsername for SearchUser.id
            // The API needs the actual user ID (numeric for Mastodon, DID for Bluesky), not the username
            let userId = targetPost.authorId.isEmpty ? targetPost.authorUsername : targetPost.authorId
            
            let user = SearchUser(
                id: userId,
                username: targetPost.authorUsername,
                displayName: targetPost.authorName,
                avatarURL: targetPost.authorProfilePictureURL.isEmpty ? nil : targetPost.authorProfilePictureURL,
                platform: targetPost.platform,
                displayNameEmojiMap: targetPost.authorEmojiMap
            )
            selectedUser = user
        }
    }

    /// Navigate to a user's profile from a SearchUser
    func navigateToUser(from user: SearchUser) {
        print("🧭 [PostNavigationEnvironment] Navigating to user profile: \(user.username) on \(user.platform)")
        
        // Defer state updates to prevent AttributeGraph cycles
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
            selectedUser = user
        }
    }
    
    /// Navigate to a tag timeline
    func navigateToTag(_ tag: SearchTag) {
        print("🧭 [PostNavigationEnvironment] Navigating to tag: \(tag.name) on \(tag.platform)")
        
        // Defer state updates to prevent AttributeGraph cycles
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
            selectedTag = tag
        }
    }
    
    /// Clear navigation state
    func clearNavigation() {
        // Defer state updates to prevent AttributeGraph cycles
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
            selectedPost = nil
            selectedUser = nil
            selectedTag = nil
            boostInfo = nil
        }
    }

    /// Check if this URL can be handled by our deep link logic
    func canHandle(_ url: URL) -> Bool {
        if url.scheme == "socialfusion" {
            return true
        }
        
        let host = url.host?.lowercased() ?? ""
        if host == "bsky.app" {
            return true
        }
        
        // Mastodon patterns: /@{user}/{id}
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        if pathComponents.count >= 2 && pathComponents[0].hasPrefix("@") {
            return true
        }
        
        return false
    }

    func handleDeepLink(_ url: URL, serviceManager: SocialServiceManager) {
        if url.scheme == "socialfusion" {
            handleCustomScheme(url, serviceManager: serviceManager)
        } else if url.scheme == "http" || url.scheme == "https" {
            handleUniversalLink(url, serviceManager: serviceManager)
        }
    }

    private func handleCustomScheme(_ url: URL, serviceManager: SocialServiceManager) {
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 2 else { return }
        let type = components[0] // "post", "user", or "tag"
        
        Task { @MainActor in
            do {
                switch type {
                case "post":
                    guard components.count >= 3 else { return }
                    let platformStr = components[1]
                    let id = components[2]
                    let platform: SocialPlatform = platformStr == "mastodon" ? .mastodon : .bluesky
                    
                    let post: Post?
                    if platform == .mastodon {
                        guard let account = serviceManager.mastodonAccounts.first else { return }
                        post = try await serviceManager.fetchMastodonStatus(id: id, account: account)
                    } else {
                        post = try await serviceManager.fetchBlueskyPostByID(id)
                    }
                    
                    if let post = post {
                        navigateToPost(post)
                    }
                    
                case "user":
                    guard components.count >= 3 else { return }
                    let platformStr = components[1]
                    let handle = components[2]
                    let platform: SocialPlatform = platformStr == "mastodon" ? .mastodon : .bluesky
                    
                    selectedUser = SearchUser(id: handle, username: handle, displayName: nil, avatarURL: nil, platform: platform)
                    
                case "tag":
                    let tag = components[1]
                    selectedTag = SearchTag(id: tag, name: tag, platform: .mastodon)
                    
                default:
                    break
                }
            } catch {
                print("Failed to handle custom scheme link \(url): \(error)")
            }
        }
    }

    private func handleUniversalLink(_ url: URL, serviceManager: SocialServiceManager) {
        let host = url.host?.lowercased() ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        if host == "bsky.app" {
            // Bluesky: /profile/{handle}/post/{id}
            if pathComponents.count >= 4 && pathComponents[0] == "profile" && pathComponents[2] == "post" {
                let handle = pathComponents[1]
                let postId = pathComponents[3]
                // Construct full AT Protocol URI - the API requires this format
                let atUri = "at://\(handle)/app.bsky.feed.post/\(postId)"
                Task { @MainActor in
                    do {
                        if let post = try await serviceManager.fetchBlueskyPostByID(atUri) {
                            navigateToPost(post)
                        }
                    } catch {
                        print("Failed to fetch Bluesky post from universal link: \(error)")
                    }
                }
            } else if pathComponents.count >= 2 && pathComponents[0] == "profile" {
                let handle = pathComponents[1]
                selectedUser = SearchUser(id: handle, username: handle, displayName: nil, avatarURL: nil, platform: .bluesky)
            }
        } else {
            // Mastodon-like: /@{user}/{id}
            if pathComponents.count >= 2 && pathComponents[0].hasPrefix("@") {
                let statusId = pathComponents[1]
                
                Task { @MainActor in
                    do {
                        // Try to find an account matching this host
                        let matchingAccount = serviceManager.mastodonAccounts.first { account in
                            account.serverURL?.host?.lowercased() == host
                        }
                        
                        // Fallback to first Mastodon account if no direct match
                        let account = matchingAccount ?? serviceManager.mastodonAccounts.first
                        
                        guard let account = account else { return }
                        
                        if let post = try await serviceManager.mastodonService.fetchPostByID(statusId, account: account) {
                            navigateToPost(post)
                        }
                    } catch {
                        print("Failed to fetch Mastodon post from universal link: \(error)")
                    }
                }
            }
        }
    }
}

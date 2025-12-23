import Combine
import Foundation
import os.log

/// A store for managing posts across different platforms
public class UnifiedPostStore {
    // MARK: - Properties

    private let logger = Logger(subsystem: "com.socialfusion", category: "UnifiedPostStore")
    private let blueskyService: BlueskyService
    private let mastodonService: MastodonService
    private let postNormalizer: PostNormalizer

    @Published private(set) var posts: [Post] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        blueskyService: BlueskyService,
        mastodonService: MastodonService,
        postNormalizer: PostNormalizer
    ) {
        self.blueskyService = blueskyService
        self.mastodonService = mastodonService
        self.postNormalizer = postNormalizer
    }

    // MARK: - Public Methods

    /// Fetch posts for the given accounts
    public func fetchPosts(for accounts: [SocialAccount]) async throws -> [Post] {
        isLoading = true
        error = nil

        do {
            var allPosts: [Post] = []

            // Fetch posts from each account
            for account in accounts {
                let accountPosts = try await fetchPostsForAccount(account)
                allPosts.append(contentsOf: accountPosts)
            }

            // Sort posts by date
            allPosts.sort { $0.createdAt > $1.createdAt }
            let postsSnapshot = allPosts

            // Update state
            await MainActor.run {
                self.posts = postsSnapshot
                self.isLoading = false
            }

            return allPosts
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
            throw error
        }
    }

    /// Like a post
    public func likePost(_ post: Post) async throws {
        do {
            switch post.platform {
            case .bluesky:
                _ = try await blueskyService.likePost(
                    post, account: try await resolveAccount(for: post))
            case .mastodon:
                _ = try await mastodonService.likePost(
                    post, account: try await resolveAccount(for: post))
            }

            // Update local state
            await MainActor.run {
                if let index = posts.firstIndex(where: { $0.id == post.id }) {
                    let updatedPost = posts[index]
                    var modifiedPost = updatedPost
                    modifiedPost.isLiked = true
                    modifiedPost.likeCount += 1
                    posts[index] = modifiedPost
                }
            }
        } catch {
            logger.error("Failed to like post: \(error.localizedDescription)")
            throw error
        }
    }

    /// Unlike a post
    public func unlikePost(_ post: Post) async throws {
        do {
            switch post.platform {
            case .bluesky:
                _ = try await blueskyService.unlikePost(
                    post, account: try await resolveAccount(for: post))
            case .mastodon:
                _ = try await mastodonService.unlikePost(
                    post, account: try await resolveAccount(for: post))
            }

            // Update local state
            await MainActor.run {
                if let index = posts.firstIndex(where: { $0.id == post.id }) {
                    let updatedPost = posts[index]
                    var modifiedPost = updatedPost
                    modifiedPost.isLiked = false
                    modifiedPost.likeCount -= 1
                    posts[index] = modifiedPost
                }
            }
        } catch {
            logger.error("Failed to unlike post: \(error.localizedDescription)")
            throw error
        }
    }

    /// Repost a post
    public func repostPost(_ post: Post) async throws {
        do {
            switch post.platform {
            case .bluesky:
                _ = try await blueskyService.repostPost(
                    post, account: try await resolveAccount(for: post))
            case .mastodon:
                _ = try await mastodonService.repostPost(
                    post, account: try await resolveAccount(for: post))
            }

            // Update local state
            await MainActor.run {
                if let index = posts.firstIndex(where: { $0.id == post.id }) {
                    let updatedPost = posts[index]
                    var modifiedPost = updatedPost
                    modifiedPost.isReposted = true
                    modifiedPost.repostCount += 1
                    posts[index] = modifiedPost
                }
            }
        } catch {
            logger.error("Failed to repost: \(error.localizedDescription)")
            throw error
        }
    }

    /// Unrepost a post
    public func unrepostPost(_ post: Post) async throws {
        do {
            switch post.platform {
            case .bluesky:
                _ = try await blueskyService.unrepostPost(
                    post, account: try await resolveAccount(for: post))
            case .mastodon:
                _ = try await mastodonService.unrepostPost(
                    post, account: try await resolveAccount(for: post))
            }

            // Update local state
            await MainActor.run {
                if let index = posts.firstIndex(where: { $0.id == post.id }) {
                    let updatedPost = posts[index]
                    var modifiedPost = updatedPost
                    modifiedPost.isReposted = false
                    modifiedPost.repostCount -= 1
                    posts[index] = modifiedPost
                }
            }
        } catch {
            logger.error("Failed to unrepost: \(error.localizedDescription)")
            throw error
        }
    }

    /// Reply to a post
    public func replyToPost(_ post: Post, content: String) async throws -> Post {
        do {
            let reply: Post

            switch post.platform {
            case .bluesky:
                reply = try await blueskyService.replyToPost(
                    post, content: content, account: try await resolveAccount(for: post))
            case .mastodon:
                reply = try await mastodonService.replyToPost(
                    post, content: content, account: try await resolveAccount(for: post))
            }

            // Update local state
            await MainActor.run {
                if let index = posts.firstIndex(where: { $0.id == post.id }) {
                    let updatedPost = posts[index]
                    var modifiedPost = updatedPost
                    modifiedPost.replyCount += 1
                    posts[index] = modifiedPost
                }
                posts.insert(reply, at: 0)
            }

            return reply
        } catch {
            logger.error("Failed to reply to post: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Private Methods

    private func fetchPostsForAccount(_ account: SocialAccount) async throws -> [Post] {
        switch account.platform {
        case .bluesky:
            // Use timeline API result to return posts
            return try await blueskyService.fetchHomeTimeline(for: account).posts
        case .mastodon:
            return try await mastodonService.fetchHomeTimeline(for: account).posts
        }
    }

    private func resolveAccount(for post: Post) async throws -> SocialAccount {
        // Placeholder resolution; in this store we may need an injected account source
        throw ServiceError.invalidAccount(
            reason: "Account resolution not configured in UnifiedPostStore")
    }
}

// MARK: - Preview Helper
extension UnifiedPostStore {
    static var preview: UnifiedPostStore {
        UnifiedPostStore(
            blueskyService: BlueskyService(),
            mastodonService: MastodonService(),
            postNormalizer: PostNormalizerImpl.shared
        )
    }
}

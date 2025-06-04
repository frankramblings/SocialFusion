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

    public init(
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

            // Update state
            await MainActor.run {
                self.posts = allPosts
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
                try await blueskyService.likePost(post.platformSpecificId, account: post.account)
            case .mastodon:
                try await mastodonService.likePost(post.platformSpecificId, account: post.account)
            }

            // Update local state
            await MainActor.run {
                if let index = posts.firstIndex(where: { $0.id == post.id }) {
                    var updatedPost = posts[index]
                    updatedPost.isLiked = true
                    updatedPost.likeCount += 1
                    posts[index] = updatedPost
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
                try await blueskyService.unlikePost(post.platformSpecificId, account: post.account)
            case .mastodon:
                try await mastodonService.unlikePost(post.platformSpecificId, account: post.account)
            }

            // Update local state
            await MainActor.run {
                if let index = posts.firstIndex(where: { $0.id == post.id }) {
                    var updatedPost = posts[index]
                    updatedPost.isLiked = false
                    updatedPost.likeCount -= 1
                    posts[index] = updatedPost
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
                try await blueskyService.repostPost(post.platformSpecificId, account: post.account)
            case .mastodon:
                try await mastodonService.repostPost(post.platformSpecificId, account: post.account)
            }

            // Update local state
            await MainActor.run {
                if let index = posts.firstIndex(where: { $0.id == post.id }) {
                    var updatedPost = posts[index]
                    updatedPost.isReposted = true
                    updatedPost.repostCount += 1
                    posts[index] = updatedPost
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
                try await blueskyService.unrepostPost(
                    post.platformSpecificId, account: post.account)
            case .mastodon:
                try await mastodonService.unrepostPost(
                    post.platformSpecificId, account: post.account)
            }

            // Update local state
            await MainActor.run {
                if let index = posts.firstIndex(where: { $0.id == post.id }) {
                    var updatedPost = posts[index]
                    updatedPost.isReposted = false
                    updatedPost.repostCount -= 1
                    posts[index] = updatedPost
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
                let blueskyReply = try await blueskyService.replyToPost(
                    post.platformSpecificId,
                    content: content,
                    account: post.account
                )
                reply = postNormalizer.normalizeBlueskyPost(blueskyReply)
            case .mastodon:
                let mastodonReply = try await mastodonService.replyToPost(
                    post.platformSpecificId,
                    content: content,
                    account: post.account
                )
                reply = postNormalizer.normalizeMastodonPost(mastodonReply)
            }

            // Update local state
            await MainActor.run {
                if let index = posts.firstIndex(where: { $0.id == post.id }) {
                    var updatedPost = posts[index]
                    updatedPost.replyCount += 1
                    posts[index] = updatedPost
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
            let blueskyPosts = try await blueskyService.fetchTimeline(for: account)
            return blueskyPosts.map { postNormalizer.normalizeBlueskyPost($0) }
        case .mastodon:
            let mastodonPosts = try await mastodonService.fetchTimeline(for: account)
            return mastodonPosts.map { postNormalizer.normalizeMastodonPost($0) }
        }
    }
}

// MARK: - Preview Helper
extension UnifiedPostStore {
    static var preview: UnifiedPostStore {
        UnifiedPostStore(
            blueskyService: BlueskyService.preview,
            mastodonService: MastodonService.preview,
            postNormalizer: PostNormalizer.preview
        )
    }
}

import Combine
import Foundation
import SwiftUI
import UIKit

@MainActor
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
        // For development, we'll load sample posts for logged-out users
        // instead of trying to fetch from real accounts
        loadAccounts()

        // Start fetching trending posts immediately for users who aren't logged in
        Task {
            await fetchTrendingPosts()

            // Set up periodic refresh of trending posts when not logged in
            if mastodonAccounts.isEmpty && blueskyAccounts.isEmpty {
                // Continue refreshing every 5 minutes in the background
                while true {
                    do {
                        try await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)  // 5 minutes
                        if !Task.isCancelled {
                            await fetchTrendingPosts()
                        }
                    } catch {
                        break  // Exit if task is cancelled or interrupted
                    }
                }
            }
        }
    }

    // MARK: - Account Management

    private func loadAccounts() {
        // For development, don't actually load any accounts
        // This would load accounts from secure storage in a real app
        #if DEBUG
            // In debug mode, we'll avoid loading accounts to show the sample feed
            mastodonAccounts = []
            blueskyAccounts = []
        #else
            do {
                // In a real app, this would load accounts from secure storage
                // For now, we'll just use sample data, but with validation
                let sampleMastodonAccount = SocialAccount(
                    id: "1",
                    username: "user1",
                    displayName: "User One",
                    serverURL: "mastodon.social",
                    platform: .mastodon
                )

                let sampleBlueskyAccount = SocialAccount(
                    id: "2",
                    username: "user2.bsky.social",
                    displayName: "User Two",
                    serverURL: "bsky.social",
                    platform: .bluesky
                )

                // Validate accounts before adding
                if validateAccount(sampleMastodonAccount) {
                    mastodonAccounts = [sampleMastodonAccount]
                }

                if validateAccount(sampleBlueskyAccount) {
                    blueskyAccounts = [sampleBlueskyAccount]
                }
            }
        #endif
    }

    private func validateAccount(_ account: SocialAccount) -> Bool {
        guard !account.id.isEmpty,
            !account.username.isEmpty,
            account.serverURL != nil
        else {
            return false
        }

        // For serverURL validation, handle Bluesky and Mastodon differently
        if account.platform == .bluesky {
            // Bluesky always uses bsky.social as serverURL, so just check it's not empty
            return account.serverURL != nil
        } else {
            // For Mastodon, we need to ensure the server URL can be parsed properly
            // Try adding https:// if needed
            let serverUrlString = account.serverURL?.absoluteString ?? ""
            let serverWithScheme =
                serverUrlString.contains("://")
                ? serverUrlString : "https://" + serverUrlString

            return URL(string: serverWithScheme) != nil
        }
    }

    func addMastodonAccount(server: String, username: String, password: String) async throws
        -> SocialAccount
    {
        // Validate input
        guard !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalidInput(reason: "Server URL cannot be empty")
        }

        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalidInput(reason: "Username cannot be empty")
        }

        guard !password.isEmpty else {
            throw ServiceError.invalidInput(reason: "Password cannot be empty")
        }

        // Validate server URL format
        guard let url = URL(string: server),
            url.scheme != nil,
            url.host != nil
        else {
            throw ServiceError.invalidInput(reason: "Invalid server URL format")
        }

        let account = try await mastodonService.authenticate(
            server: URL(string: server),
            username: username,
            password: password
        )

        // Validate returned account
        guard validateAccount(account) else {
            throw ServiceError.invalidAccount(reason: "Invalid account data received from server")
        }

        // Check for duplicate accounts
        guard !mastodonAccounts.contains(where: { $0.id == account.id }) else {
            throw ServiceError.duplicateAccount
        }

        mastodonAccounts.append(account)
        return account
    }

    /// Add a Mastodon account using OAuth authentication (recommended)
    func addMastodonAccountWithOAuth(server: String) async throws -> SocialAccount {
        // Validate input
        guard !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalidInput(reason: "Server URL cannot be empty")
        }

        // Ensure server URL has proper scheme
        let formattedServer = server.lowercased()
        let serverWithScheme =
            formattedServer.hasPrefix("https://") ? formattedServer : "https://" + formattedServer

        // Validate server URL format
        guard let url = URL(string: serverWithScheme),
            url.scheme == "https",
            url.host != nil
        else {
            throw ServiceError.invalidInput(
                reason: "Invalid server URL format. Must be a valid domain.")
        }

        // Temporarily return a fake account to allow compilation
        // In the real implementation, we would use the OAuth flow
        let account = SocialAccount(
            id: UUID().uuidString,
            username: "placeholder_user@\(url.host ?? "")",
            displayName: "Placeholder User",
            serverURL: serverWithScheme,
            platform: .mastodon,
            accessToken: "placeholder_token",
            refreshToken: nil,
            accountDetails: [:]
        )

        // Add to accounts list
        if !self.mastodonAccounts.contains(where: { $0.id == account.id }) {
            self.mastodonAccounts.append(account)
        }

        return account
    }

    func addBlueskyAccount(username: String, password: String) async throws -> SocialAccount {
        // Validate input
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalidInput(reason: "Username cannot be empty")
        }

        guard !password.isEmpty else {
            throw ServiceError.invalidInput(reason: "Password cannot be empty")
        }

        let account = try await blueskyService.authenticate(
            username: username,
            password: password
        )

        // Validate returned account
        guard validateAccount(account) else {
            throw ServiceError.invalidAccount(reason: "Invalid account data received from server")
        }

        // Check for duplicate accounts
        guard !blueskyAccounts.contains(where: { $0.id == account.id }) else {
            throw ServiceError.duplicateAccount
        }

        blueskyAccounts.append(account)
        return account
    }

    func removeAccount(_ account: SocialAccount) {
        // Validate account before removal
        guard validateAccount(account) else {
            return
        }

        switch account.platform {
        case .mastodon:
            mastodonAccounts.removeAll { $0.id == account.id }
        case .bluesky:
            blueskyAccounts.removeAll { $0.id == account.id }
        }
    }

    // MARK: - Timeline

    func refreshTimeline() async {
        guard !mastodonAccounts.isEmpty || !blueskyAccounts.isEmpty else {
            return
        }

        isLoadingTimeline = true
        error = nil

        do {
            var allPosts: [Post] = []
            var errors: [Error] = []

            // Fetch Mastodon timeline for all accounts
            await withTaskGroup(of: (Result<[Post], Error>).self) { group in
                for account in mastodonAccounts {
                    group.addTask {
                        do {
                            let posts = try await self.mastodonService.fetchHomeTimeline(
                                for: account)
                            return .success(posts)
                        } catch {
                            return .failure(error)
                        }
                    }
                }

                // Collect results
                for await result in group {
                    switch result {
                    case .success(let posts):
                        allPosts.append(contentsOf: posts)
                    case .failure(let error):
                        errors.append(error)
                    }
                }
            }

            // Fetch Bluesky timeline for all accounts
            await withTaskGroup(of: (Result<[Post], Error>).self) { group in
                for account in blueskyAccounts {
                    group.addTask {
                        do {
                            let posts = try await self.blueskyService.fetchHomeTimeline(
                                for: account)
                            return .success(posts)
                        } catch {
                            return .failure(error)
                        }
                    }
                }

                // Collect results
                for await result in group {
                    switch result {
                    case .success(let posts):
                        allPosts.append(contentsOf: posts)
                    case .failure(let error):
                        errors.append(error)
                    }
                }
            }

            // If we have any posts, show them even if some requests failed
            if !allPosts.isEmpty {
                // Sort by date, newest first (strictly chronological for logged-in view)
                let sortedPosts = allPosts.sorted { $0.createdAt > $1.createdAt }
                unifiedTimeline = sortedPosts
            }

            // If we had any errors, set the last error
            if let lastError = errors.last {
                error = ServiceError.timelineError(underlying: lastError)
            }

            isLoadingTimeline = false
        } catch {
            self.error = ServiceError.timelineError(underlying: error)
            isLoadingTimeline = false
        }
    }

    // MARK: - Post Actions

    func createPost(
        content: String,
        mediaAttachments: [Data] = [],
        platforms: Set<SocialPlatform>,
        visibility: PostVisibilityType = .public_
    ) async throws {
        // Validate content
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            throw ServiceError.invalidContent(reason: "Content cannot be empty")
        }

        // Validate content length for each platform
        if platforms.contains(.mastodon) {
            guard trimmedContent.count <= 500 else {
                throw ServiceError.invalidContent(
                    reason: "Content exceeds Mastodon's 500 character limit")
            }
        }

        if platforms.contains(.bluesky) {
            guard trimmedContent.count <= 300 else {
                throw ServiceError.invalidContent(
                    reason: "Content exceeds Bluesky's 300 character limit")
            }
        }

        guard !platforms.isEmpty else {
            throw ServiceError.noPlatformsSelected
        }

        // Validate media attachments
        guard mediaAttachments.count <= 4 else {
            throw ServiceError.invalidContent(reason: "Maximum of 4 media attachments allowed")
        }

        for (index, data) in mediaAttachments.enumerated() {
            guard !data.isEmpty else {
                throw ServiceError.invalidContent(reason: "Media attachment \(index + 1) is empty")
            }

            guard data.count <= 40 * 1024 * 1024 else {  // 40MB limit
                throw ServiceError.invalidContent(
                    reason: "Media attachment \(index + 1) exceeds size limit of 40MB")
            }
        }

        var createdPosts: [Post] = []
        var errors: [Error] = []

        // Post to Mastodon if selected
        if platforms.contains(.mastodon) {
            await withTaskGroup(of: (Result<Post, Error>).self) { group in
                for account in mastodonAccounts {
                    group.addTask {
                        do {
                            let post = try await self.mastodonService.createPost(
                                content: content,
                                mediaAttachments: mediaAttachments,
                                visibility: visibility,
                                account: account
                            )
                            return .success(post)
                        } catch {
                            return .failure(error)
                        }
                    }
                }

                // Collect results
                for await result in group {
                    switch result {
                    case .success(let post):
                        createdPosts.append(post)
                    case .failure(let error):
                        errors.append(error)
                    }
                }
            }
        }

        // Post to Bluesky if selected
        if platforms.contains(.bluesky) {
            await withTaskGroup(of: (Result<Post, Error>).self) { group in
                for account in blueskyAccounts {
                    group.addTask {
                        do {
                            let post = try await self.blueskyService.createPost(
                                content: content,
                                mediaAttachments: mediaAttachments,
                                account: account
                            )
                            return .success(post)
                        } catch {
                            return .failure(error)
                        }
                    }
                }

                // Collect results
                for await result in group {
                    switch result {
                    case .success(let post):
                        createdPosts.append(post)
                    case .failure(let error):
                        errors.append(error)
                    }
                }
            }
        }

        // If we have any successful posts, add them to the timeline
        if !createdPosts.isEmpty {
            unifiedTimeline.insert(contentsOf: createdPosts, at: 0)
        }

        // If we had any errors, throw the last one
        if let lastError = errors.last {
            throw ServiceError.createPostError(underlying: lastError)
        }
    }

    func likePost(_ post: Post) async throws {
        // Create a local copy to ensure thread safety
        let postToLike = post
        let platform = postToLike.platform

        let updatedPost: Post

        do {
            switch platform {
            case .mastodon:
                guard let account = mastodonAccounts.first else {
                    throw ServiceError.noAccount(platform: .mastodon)
                }
                updatedPost = try await mastodonService.likePost(postToLike, account: account)

            case .bluesky:
                guard let account = blueskyAccounts.first else {
                    throw ServiceError.noAccount(platform: .bluesky)
                }
                updatedPost = try await blueskyService.likePost(postToLike, account: account)
            }

            // Update timeline on success
            if let index = unifiedTimeline.firstIndex(where: { $0.id == postToLike.id }) {
                unifiedTimeline[index] = updatedPost
            }
        } catch {
            throw ServiceError.likeError(underlying: error)
        }
    }

    func repostPost(_ post: Post) async throws {
        // Create a local copy to ensure thread safety
        let postToRepost = post
        let platform = postToRepost.platform

        let updatedPost: Post

        do {
            switch platform {
            case .mastodon:
                guard let account = mastodonAccounts.first else {
                    throw ServiceError.noAccount(platform: .mastodon)
                }
                updatedPost = try await mastodonService.repostPost(postToRepost, account: account)

            case .bluesky:
                guard let account = blueskyAccounts.first else {
                    throw ServiceError.noAccount(platform: .bluesky)
                }
                updatedPost = try await blueskyService.repostPost(postToRepost, account: account)
            }

            // Update timeline on success
            if let index = unifiedTimeline.firstIndex(where: { $0.id == postToRepost.id }) {
                unifiedTimeline[index] = updatedPost
            }
        } catch {
            throw ServiceError.repostError(underlying: error)
        }
    }

    func replyToPost(_ post: Post, content: String) async throws {
        // Create a local copy to ensure thread safety
        let postToReply = post
        let platform = postToReply.platform

        let replyPost: Post

        do {
            switch platform {
            case .mastodon:
                guard let account = mastodonAccounts.first else {
                    throw ServiceError.noAccount(platform: .mastodon)
                }
                replyPost = try await mastodonService.replyToPost(
                    postToReply,
                    content: content,
                    account: account
                )

            case .bluesky:
                guard let account = blueskyAccounts.first else {
                    throw ServiceError.noAccount(platform: .bluesky)
                }
                replyPost = try await blueskyService.replyToPost(
                    postToReply,
                    content: content,
                    account: account
                )
            }

            // Add reply to timeline and update reply count atomically
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    self.unifiedTimeline.insert(replyPost, at: 0)
                }

                group.addTask { @MainActor in
                    if let index = self.unifiedTimeline.firstIndex(where: {
                        $0.id == postToReply.id
                    }) {
                        var updatedPost = self.unifiedTimeline[index]
                        updatedPost.replyCount += 1
                        self.unifiedTimeline[index] = updatedPost
                    }
                }
            }
        } catch {
            throw ServiceError.replyError(underlying: error)
        }
    }

    // MARK: - Trending Content

    /// Fetch trending posts from Mastodon and Bluesky when no accounts are connected
    @MainActor
    func fetchTrendingPosts() async {
        isLoadingTimeline = true
        error = nil

        print("Fetching trending posts for logged-out users...")

        do {
            var mastodonPosts: [Post] = []
            var blueskyPosts: [Post] = []
            var errors: [Error] = []

            // Fetch trending posts from Mastodon
            await withTaskGroup(of: Result<[Post], Error>.self) { group in
                group.addTask {
                    do {
                        let posts = try await self.mastodonService.fetchTrendingPosts()
                        print("Got \(posts.count) Mastodon trending posts")
                        return .success(posts)
                    } catch {
                        print(
                            "Failed to fetch Mastodon trending posts: \(error.localizedDescription)"
                        )
                        return .failure(error)
                    }
                }

                // Collect Mastodon results
                for await result in group {
                    switch result {
                    case .success(let posts):
                        mastodonPosts = posts
                    case .failure(let error):
                        errors.append(error)
                    }
                }
            }

            // Fetch trending posts from Bluesky in a separate task group
            await withTaskGroup(of: Result<[Post], Error>.self) { group in
                group.addTask {
                    do {
                        // Try the standard timeline
                        let posts = try await self.blueskyService.fetchTrendingPosts()
                        return .success(posts)
                    } catch {
                        print(
                            "Failed to fetch Bluesky trending posts: \(error.localizedDescription)")
                        return .failure(error)
                    }
                }

                // Collect Bluesky results
                for await result in group {
                    switch result {
                    case .success(let posts):
                        blueskyPosts = posts
                    case .failure(let error):
                        errors.append(error)
                    }
                }
            }

            // Fallback Bluesky content if none retrieved
            if blueskyPosts.isEmpty {
                print("No Bluesky posts fetched - using fallback content")
                // Create fallback Bluesky posts
                blueskyPosts = createFallbackBlueskyPosts()
            }

            print("Got \(mastodonPosts.count) Mastodon posts, \(blueskyPosts.count) Bluesky posts")

            // Create an interleaved timeline with posts from each platform
            var combinedTimeline: [Post] = []

            // Sort each platform's posts by popularity
            let sortedMastodonPosts = mastodonPosts.sorted {
                ($0.likeCount + $0.repostCount) > ($1.likeCount + $1.repostCount)
            }

            let sortedBlueskyPosts = blueskyPosts.sorted {
                ($0.likeCount + $0.repostCount) > ($1.likeCount + $1.repostCount)
            }

            // If we have both types of content, interleave them
            if !sortedMastodonPosts.isEmpty && !sortedBlueskyPosts.isEmpty {
                // Interleave the posts to create a balanced feed
                let maxCount = max(sortedMastodonPosts.count, sortedBlueskyPosts.count)
                for i in 0..<maxCount {
                    if i < sortedBlueskyPosts.count {
                        combinedTimeline.append(sortedBlueskyPosts[i])
                    }
                    if i < sortedMastodonPosts.count {
                        combinedTimeline.append(sortedMastodonPosts[i])
                    }
                }
            } else if !sortedMastodonPosts.isEmpty {
                // Insert Bluesky post every third Mastodon post
                for (index, post) in sortedMastodonPosts.enumerated() {
                    combinedTimeline.append(post)

                    // After every third Mastodon post, insert a Bluesky post if available
                    if (index + 1) % 3 == 0 && !sortedBlueskyPosts.isEmpty {
                        let blueskyIndex = (index / 3) % sortedBlueskyPosts.count
                        combinedTimeline.append(sortedBlueskyPosts[blueskyIndex])
                    }
                }
            } else {
                // Use whatever content we have
                combinedTimeline = sortedBlueskyPosts + sortedMastodonPosts
            }

            // Update the timeline with our mixed content
            if !combinedTimeline.isEmpty {
                unifiedTimeline = combinedTimeline
                print("Updated timeline with \(combinedTimeline.count) combined posts")
            } else {
                print("Warning: No posts to display in timeline")
            }

            // If we had any errors, set the last error
            if let lastError = errors.last {
                self.error = ServiceError.timelineError(underlying: lastError)
            }
        } catch {
            self.error = ServiceError.timelineError(underlying: error)
            print("Error in fetchTrendingPosts: \(error.localizedDescription)")
        }

        isLoadingTimeline = false
    }

    /// Create fallback Bluesky posts when none can be retrieved from the API
    private func createFallbackBlueskyPosts() -> [Post] {
        let fallbackAuthor = Author(
            id: "bluesky-sample",
            username: "sample.bsky.social",
            displayName: "Bluesky Sample",
            profileImageURL: nil,
            platform: .bluesky,
            platformSpecificId: "bluesky-sample"
        )

        // Sample content for fallback posts
        let contents = [
            "Excited to explore the decentralized social web with Bluesky! #BlueSky #ATProtocol",
            "The AT Protocol will revolutionize how we think about social media ownership and data portability.",
            "Just set up my Bluesky account and loving the clean interface and growing community!",
            "Bluesky's approach to content moderation through labeling is a fascinating experiment in community governance.",
            "Open source, open protocols, and user choice - that's what makes Bluesky special.",
            "Building a timeline that I control is refreshing after years of algorithmic feeds.",
            "Anyone else excited about custom feeds and the ability to bring your social graph between services?",
            "Bluesky feels like the early days of Twitter, but with a focus on openness and interoperability.",
        ]

        // Create posts with varied engagement metrics
        return contents.enumerated().map { index, content in
            Post(
                id: "bluesky-fallback-\(index)",
                platform: .bluesky,
                author: fallbackAuthor,
                content: content,
                mediaAttachments: [],
                createdAt: Date().addingTimeInterval(-Double(index * 3600)),
                likeCount: Int.random(in: 15...150),
                repostCount: Int.random(in: 5...50),
                replyCount: Int.random(in: 2...30),
                isLiked: false,
                isReposted: false,
                platformSpecificId: "at://did:plc:sample/app.bsky.feed.post/\(UUID().uuidString)"
            )
        }
    }

    // MARK: - Errors

    enum ServiceError: LocalizedError {
        case noAccount(platform: SocialPlatform)
        case likeError(underlying: Error)
        case repostError(underlying: Error)
        case replyError(underlying: Error)
        case createPostError(underlying: Error)
        case timelineError(underlying: Error)
        case invalidContent(reason: String)
        case invalidInput(reason: String)
        case invalidAccount(reason: String)
        case duplicateAccount
        case noPlatformsSelected
        case authenticationError(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .noAccount(let platform):
                return "No \(platform) account available"
            case .likeError(let error):
                return "Failed to like post: \(error.localizedDescription)"
            case .repostError(let error):
                return "Failed to repost: \(error.localizedDescription)"
            case .replyError(let error):
                return "Failed to reply: \(error.localizedDescription)"
            case .createPostError(let error):
                return "Failed to create post: \(error.localizedDescription)"
            case .timelineError(let error):
                return "Failed to refresh timeline: \(error.localizedDescription)"
            case .invalidContent(let reason):
                return "Invalid content: \(reason)"
            case .invalidInput(let reason):
                return "Invalid input: \(reason)"
            case .invalidAccount(let reason):
                return "Invalid account: \(reason)"
            case .duplicateAccount:
                return "Account already exists"
            case .noPlatformsSelected:
                return "No platforms selected for posting"
            case .authenticationError(let error):
                return "Authentication error: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - URL Helper Extensions
extension Optional where Wrapped == URL {
    func formatServerUrl() -> String {
        guard let url = self else { return "" }

        let urlString = url.absoluteString
        if urlString.contains("://") {
            return urlString
        } else {
            return "https://" + urlString
        }
    }
}

private func formatServerURL(for account: SocialAccount) -> String {
    return account.serverURL.formatServerUrl()
}

/// Check if an account contains the minimum required information
func isAccountValid(_ account: SocialAccount) -> Bool {
    return !account.username.isEmpty && !account.id.isEmpty && account.serverURL != nil
}

/// Check if a platform-specific account is valid for the given platform
func isPlatformValid(_ account: SocialAccount, for platform: SocialPlatform) -> Bool {
    if account.platform == .bluesky {
        // For Bluesky, we need a server URL
        return account.serverURL != nil
    } else {
        // For Mastodon, we need a server URL that's not empty
        return account.serverURL != nil
    }
}

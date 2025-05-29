import AuthenticationServices  // For authentication-related functionality
import Combine
import Foundation
import SwiftUI
import UIKit
import os.log

// Define notification names
extension Notification.Name {
    static let profileImageUpdated = Notification.Name("AccountProfileImageUpdated")
    static let accountUpdated = Notification.Name("AccountUpdated")
}

// Define service errors
public enum ServiceError: Error, LocalizedError {
    case invalidInput(reason: String)
    case invalidAccount(reason: String)
    case duplicateAccount
    case authenticationFailed(reason: String)
    case networkError(underlying: Error)
    case rateLimitError(reason: String, retryAfter: TimeInterval = 60)
    case timelineError(underlying: Error)
    case invalidContent(reason: String)
    case noPlatformsSelected
    case postFailed(reason: String)
    case unsupportedPlatform
    case apiError(String)
    case unauthorized(String)
    case emptyResponse
    case dataFormatError(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let reason):
            return "Invalid input: \(reason)"
        case .invalidAccount(let reason):
            return "Invalid account: \(reason)"
        case .duplicateAccount:
            return "This account has already been added"
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .rateLimitError(let reason, _):
            return "Rate limit exceeded: \(reason)"
        case .timelineError(let underlying):
            return "Timeline error: \(underlying.localizedDescription)"
        case .invalidContent(let reason):
            return "Invalid content: \(reason)"
        case .noPlatformsSelected:
            return "No platforms selected for post"
        case .postFailed(let reason):
            return "Failed to post: \(reason)"
        case .unsupportedPlatform:
            return "Unsupported platform"
        case .apiError(let message):
            return "API error: \(message)"
        case .unauthorized(let reason):
            return "Unauthorized: \(reason)"
        case .emptyResponse:
            return "Empty response"
        case .dataFormatError(let reason):
            return "Data format error: \(reason)"
        case .unknown(let reason):
            return "Unknown error: \(reason)"
        }
    }
}

// Rate limit tracking structure
struct RateLimitInfo {
    var platformName: String
    var lastHit: Date
    var retryAfter: TimeInterval
    var consecutiveHits: Int

    var canMakeRequest: Bool {
        Date() > lastHit.addingTimeInterval(retryAfter)
    }

    var nextAllowedRequestTime: Date {
        lastHit.addingTimeInterval(retryAfter)
    }
}

/// Manages the social services and accounts
final class SocialServiceManager: ObservableObject {
    static let shared = SocialServiceManager()

    @Published var accounts: [SocialAccount] = []
    @Published var isLoading: Bool = false
    @Published var error: Error?

    // Selected account IDs (Set to store unique IDs)
    @Published var selectedAccountIds: Set<String> = ["all"]

    // Filtered account lists
    @Published var mastodonAccounts: [SocialAccount] = []
    @Published var blueskyAccounts: [SocialAccount] = []

    // Timeline data
    @Published var unifiedTimeline: [Post] = []
    @Published var isLoadingTimeline: Bool = false
    @Published var timelineError: Error?

    // Services for each platform
    private let mastodonService = MastodonService()
    private let blueskyService = BlueskyService()

    // Cache for Mastodon parent posts to avoid redundant fetches
    private var mastodonPostCache: [String: (post: Post, timestamp: Date)] = [:]
    // Cache for Bluesky parent posts to avoid redundant fetches
    private var blueskyPostCache: [String: Post] = [:]
    // Track in-progress parent fetches to avoid redundant network calls
    private var parentFetchInProgress: Set<String> = []

    // MARK: - Initialization

    // Make initializer public so it can be used in SocialFusionApp
    public init() {
        // Load saved accounts
        loadAccounts()

        // Register for app termination notification to save accounts
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveAccountsBeforeTermination),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func saveAccountsBeforeTermination() {
        saveAccounts()
    }

    // MARK: - Account Management

    /// Load saved accounts from UserDefaults
    private func loadAccounts() {
        let logger = Logger(subsystem: "com.socialfusion", category: "AccountPersistence")
        logger.info("Loading saved accounts")

        guard let data = UserDefaults.standard.data(forKey: "savedAccounts") else {
            logger.info("No saved accounts found")
            updateAccountLists()
            return
        }

        do {
            let decoder = JSONDecoder()
            let decodedAccounts = try decoder.decode([SocialAccount].self, from: data)
            accounts = decodedAccounts

            logger.info("Successfully loaded \(decodedAccounts.count) accounts")

            // Load tokens for each account from keychain
            for account in accounts {
                account.loadTokensFromKeychain()
                logger.debug("Loaded tokens for account: \(account.username, privacy: .public)")
            }
        } catch {
            logger.error(
                "Failed to decode saved accounts: \(error.localizedDescription, privacy: .public)")
        }

        // After loading accounts, separate them by platform
        updateAccountLists()
    }

    /// Save accounts to UserDefaults
    public func saveAccounts() {
        let logger = Logger(subsystem: "com.socialfusion", category: "AccountPersistence")
        logger.info("Saving \(self.accounts.count) accounts")

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(self.accounts)
            UserDefaults.standard.set(data, forKey: "savedAccounts")
            logger.info("Successfully saved accounts")
        } catch {
            logger.error(
                "Failed to encode accounts: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Update the platform-specific account lists
    private func updateAccountLists() {
        // Separate accounts by platform
        mastodonAccounts = accounts.filter { $0.platform == .mastodon }
        blueskyAccounts = accounts.filter { $0.platform == .bluesky }
    }

    /// Add a new account
    func addAccount(_ account: SocialAccount) {
        accounts.append(account)
        // Save to UserDefaults
        saveAccounts()

        // Update platform-specific lists
        updateAccountLists()
    }

    /// Add a Mastodon account
    func addMastodonAccount(server: String, username: String, password: String) async throws
        -> SocialAccount
    {
        let account = try await mastodonService.authenticate(
            server: URL(string: server),
            username: username,
            password: password
        )

        // Add the account to our collection
        await MainActor.run {
            addAccount(account)
        }

        return account
    }

    /// Add a Mastodon account using an access token
    func addMastodonAccountWithToken(serverURL: String, accessToken: String) async throws
        -> SocialAccount
    {
        // Format the server URL properly
        let serverUrlString = serverURL.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let formattedURL =
            serverUrlString.hasPrefix("http") ? serverUrlString : "https://\(serverUrlString)"

        guard let url = URL(string: formattedURL) else {
            throw ServiceError.invalidInput(reason: "Invalid server URL")
        }

        // Use the MastodonService to authenticate with the token
        let account = try await mastodonService.authenticateWithToken(
            server: url,
            accessToken: accessToken
        )

        // Add the account to our collection
        await MainActor.run {
            addAccount(account)
        }

        return account
    }

    /// Add a Bluesky account
    func addBlueskyAccount(username: String, password: String) async throws -> SocialAccount {
        let account = try await blueskyService.authenticate(
            username: username,
            password: password
        )

        // Add the account to our collection
        await MainActor.run {
            addAccount(account)
        }

        return account
    }

    /// Remove an account
    func removeAccount(_ account: SocialAccount) {
        accounts.removeAll { $0.id == account.id }
        // Would normally remove from UserDefaults or Keychain

        // Update platform-specific lists
        updateAccountLists()
    }

    // MARK: - Timeline

    /// Fetch posts for a specific account
    private func fetchPostsForAccount(_ account: SocialAccount) async throws -> [Post] {
        // Based on the platform, use the appropriate service
        switch account.platform {
        case .mastodon:
            return try await mastodonService.fetchHomeTimeline(for: account)
        case .bluesky:
            return try await blueskyService.fetchTimeline(for: account)
        }
    }

    /// Refresh timeline, with option to force refresh
    func refreshTimeline(force: Bool = false) async throws {
        try await fetchTimeline()
    }

    /// Refresh timeline for specific accounts
    func refreshTimeline(accounts: [SocialAccount]) async throws -> [Post] {
        var allPosts: [Post] = []

        // Fetch posts from each account and combine
        for account in accounts {
            do {
                let posts = try await fetchPostsForAccount(account)
                allPosts.append(contentsOf: posts)
            } catch {
                print("Error fetching posts for \(account.username): \(error)")
                // Continue with other accounts even if one fails
            }
        }

        // Patch: Ensure all posts have unique IDs, especially for boosts/reposts
        let uniquePosts = allPosts.map { post -> Post in
            if let original = post.originalPost {
                // Synthesize a unique id for the boost/repost wrapper
                let boostId = "boost-\(post.authorUsername)-\(original.id)"
                // Only patch if the id is not already unique
                if post.id == original.id {
                    // Create a copy with the new id
                    let patched = post.copy(with: boostId)
                    patched.originalPost = original  // preserve reference
                    return patched
                }
            }
            return post
        }
        let sortedPosts = uniquePosts.sorted(by: { $0.createdAt > $1.createdAt })

        // Hydrate parent posts for replies
        for post in sortedPosts {
            if let parent = post.parent, parent.content == "..." {
                // Schedule hydration for Mastodon or Bluesky
                Task {
                    print(
                        "[Hydration] Triggering parent fetch for post id=\(post.id), parent id=\(parent.id), platform=\(post.platform)"
                    )
                    if post.platform == .mastodon, let parentId = post.inReplyToID,
                        let account = mastodonAccounts.first
                    {
                        if let cached = mastodonPostCache[parentId]?.post {
                            print(
                                "[Hydration] Using cached Mastodon parent for id=\(parentId): username=\(cached.authorUsername), content=\(cached.content.prefix(20))..."
                            )
                            post.parent = cached
                            post.inReplyToUsername = cached.authorUsername
                        } else {
                            do {
                                let realParentOpt = try await self.fetchMastodonStatus(
                                    id: parentId, account: account)
                                if let realParent = realParentOpt {
                                    print(
                                        "[Hydration] Fetched Mastodon parent for id=\(parentId): username=\(realParent.authorUsername), content=\(realParent.content.prefix(20))..."
                                    )
                                    mastodonPostCache[parentId] = (realParent, Date())
                                    post.parent = realParent
                                    post.inReplyToUsername = realParent.authorUsername
                                } else {
                                    print(
                                        "[Hydration] Fetched Mastodon parent for id=\(parentId): result was nil"
                                    )
                                }
                            } catch {
                                print(
                                    "[Hydration] Failed to fetch Mastodon parent for id=\(parentId): \(error)"
                                )
                            }
                        }
                    } else if post.platform == .bluesky, let parentId = post.inReplyToID {
                        if let cached = blueskyPostCache[parentId] {
                            print(
                                "[Hydration] Using cached Bluesky parent for id=\(parentId): username=\(cached.authorUsername), content=\(cached.content.prefix(20))..."
                            )
                            post.parent = cached
                            post.inReplyToUsername = cached.authorUsername
                        } else {
                            do {
                                let realParentOpt = try await self.fetchBlueskyPostByID(parentId)
                                if let realParent = realParentOpt {
                                    print(
                                        "[Hydration] Fetched Bluesky parent for id=\(parentId): username=\(realParent.authorUsername), content=\(realParent.content.prefix(20))..."
                                    )
                                    blueskyPostCache[parentId] = realParent
                                    post.parent = realParent
                                    post.inReplyToUsername = realParent.authorUsername
                                } else {
                                    print(
                                        "[Hydration] Fetched Bluesky parent for id=\(parentId): result was nil"
                                    )
                                }
                            } catch {
                                print(
                                    "[Hydration] Failed to fetch Bluesky parent for id=\(parentId): \(error)"
                                )
                            }
                        }
                    }
                }
            }
        }

        // Update unified timeline on main thread
        DispatchQueue.main.async {
            self.unifiedTimeline = sortedPosts
            self.isLoadingTimeline = false
            // Wire up timeline debug singleton for Bluesky
            if let debug = SocialFusionTimelineDebug.shared as SocialFusionTimelineDebug? {
                debug.setBlueskyPosts(sortedPosts.filter { $0.platform == .bluesky })
            }
        }

        return sortedPosts
    }

    /// Fetch the unified timeline for all accounts
    private func fetchTimeline() async throws {
        // Check if we're already loading
        guard !isLoadingTimeline else {
            return
        }

        // Update loading state on main thread
        await MainActor.run {
            isLoadingTimeline = true
            timelineError = nil
        }

        do {
            // Determine which accounts to fetch based on selection
            var accountsToFetch: [SocialAccount] = []

            if selectedAccountIds.contains("all") {
                // Fetch from all accounts
                accountsToFetch = accounts
            } else {
                // Fetch only from selected accounts
                accountsToFetch = accounts.filter { selectedAccountIds.contains($0.id) }
            }

            guard !accountsToFetch.isEmpty else {
                await MainActor.run {
                    isLoadingTimeline = false
                }
                return
            }

            // Use our other method to fetch and process the posts
            let _ = try await refreshTimeline(accounts: accountsToFetch)

            await MainActor.run {
                isLoadingTimeline = false
            }
        } catch {
            await MainActor.run {
                timelineError = error
                isLoadingTimeline = false
            }
            throw error
        }
    }

    /// Fetch trending posts from public sources
    @MainActor
    func fetchTrendingPosts() async {
        isLoadingTimeline = true
        defer { isLoadingTimeline = false }

        do {
            // Try to fetch trending posts from Mastodon
            let posts = try await mastodonService.fetchTrendingPosts()
            self.unifiedTimeline = posts
        } catch {
            // If that fails, use sample posts
            self.unifiedTimeline = Post.samplePosts
            self.error = error
        }
    }

    /// Fetch a specific post by ID from Bluesky
    func fetchBlueskyPostByID(_ postId: String) async throws -> Post? {
        // Find a Bluesky account to use for the API call
        guard let account = blueskyAccounts.first else {
            throw ServiceError.invalidAccount(reason: "No Bluesky account available")
        }

        return try await blueskyService.fetchPostByID(postId, account: account)
    }

    /// Fetch a specific post by ID from Mastodon with caching
    func fetchMastodonStatus(id: String, account: SocialAccount) async throws -> Post? {
        print("📊 SocialServiceManager: Fetching Mastodon status with ID: \(id)")

        // Check cache first (valid for 5 minutes)
        if let cached = mastodonPostCache[id],
            Date().timeIntervalSince(cached.timestamp) < 300
        {  // 5 minutes
            print("📊 SocialServiceManager: Using cached Mastodon post for ID: \(id)")
            return cached.post
        }

        guard account.platform == .mastodon else {
            print(
                "📊 SocialServiceManager: Invalid account platform - expected Mastodon but got \(account.platform)"
            )
            throw ServiceError.invalidAccount(
                reason: "The provided account is not a Mastodon account")
        }

        do {
            // Use a task with higher priority for better UI responsiveness
            return try await Task.detached(priority: .userInitiated) {
                let result = try await self.mastodonService.fetchStatus(id: id, account: account)
                if let post = result {
                    print(
                        "📊 SocialServiceManager: Successfully fetched Mastodon post \(post.id), inReplyToID: \(post.inReplyToID ?? "nil")"
                    )

                    // Store in cache
                    await MainActor.run {
                        self.mastodonPostCache[id] = (post: post, timestamp: Date())
                    }
                } else {
                    print(
                        "📊 SocialServiceManager: Mastodon service returned nil post for ID: \(id)")
                }
                return result
            }.value
        } catch {
            print("📊 SocialServiceManager: Error fetching Mastodon status: \(error)")
            throw error
        }
    }

    /// Fetch posts for the specified account
    func fetchPosts(for account: SocialAccount? = nil) async throws -> [Post] {
        await MainActor.run {
            isLoading = true
            error = nil
        }

        do {
            var posts: [Post] = []

            if let account = account {
                // Fetch for specific account
                posts = try await fetchPostsForAccount(account)
            } else {
                // Fetch for all accounts
                for account in accounts {
                    do {
                        let accountPosts = try await fetchPostsForAccount(account)
                        posts.append(contentsOf: accountPosts)
                    } catch {
                        print("Error fetching posts for \(account.username): \(error)")
                        // Continue with other accounts even if one fails
                    }
                }
            }

            // Use sample posts if no real posts available
            if posts.isEmpty {
                posts = Post.samplePosts
            }

            await MainActor.run {
                isLoading = false
            }

            return posts
        } catch {
            await MainActor.run {
                self.error = error
                isLoading = false
            }
            throw error
        }
    }

    // MARK: - TimelineEntry Construction

    /// Converts an array of Post objects into TimelineEntry objects for robust SwiftUI rendering
    func makeTimelineEntries(from posts: [Post]) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []
        for post in posts {
            if let original = post.originalPost {
                // This is a boost/repost
                let entry = TimelineEntry(
                    id: "boost-\(post.authorUsername)-\(original.id)",
                    kind: .boost(boostedBy: post.authorUsername),
                    post: original,
                    createdAt: post.createdAt
                )
                entries.append(entry)
            } else if let parentId = post.inReplyToID {
                // This is a reply
                let entry = TimelineEntry(
                    id: "reply-\(post.id)",
                    kind: .reply(parentId: parentId),
                    post: post,
                    createdAt: post.createdAt
                )
                entries.append(entry)
            } else {
                // Normal post
                let entry = TimelineEntry(
                    id: post.id,
                    kind: .normal,
                    post: post,
                    createdAt: post.createdAt
                )
                entries.append(entry)
            }
        }
        // Sort by date, newest first
        return entries.sorted(by: { $0.createdAt > $1.createdAt })
    }

    /// Reply to a post (Mastodon or Bluesky)
    func replyToPost(_ post: Post, content: String) async throws -> Post {
        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            return try await mastodonService.replyToPost(post, content: content, account: account)
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            return try await blueskyService.replyToPost(post, content: content, account: account)
        }
    }

    /// Like a post (Mastodon or Bluesky)
    func likePost(_ post: Post) async throws -> Post {
        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            return try await mastodonService.likePost(post, account: account)
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            return try await blueskyService.likePost(post, account: account)
        }
    }

    /// Repost a post (Mastodon or Bluesky)
    func repostPost(_ post: Post) async throws -> Post {
        switch post.platform {
        case .mastodon:
            guard let account = mastodonAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Mastodon account available")
            }
            return try await mastodonService.repostPost(post, account: account)
        case .bluesky:
            guard let account = blueskyAccounts.first else {
                throw ServiceError.invalidAccount(reason: "No Bluesky account available")
            }
            return try await blueskyService.repostPost(post, account: account)
        }
    }
}

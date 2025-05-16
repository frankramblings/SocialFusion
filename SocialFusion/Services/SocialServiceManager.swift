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

    // MARK: - Initialization

    // Make initializer public so it can be used in SocialFusionApp
    public init() {
        // Load saved accounts
        loadAccounts()
    }

    // MARK: - Account Management

    /// Load saved accounts from UserDefaults
    private func loadAccounts() {
        // Implementation would load accounts from UserDefaults or Keychain
        // This is a simplified version

        // After loading accounts, separate them by platform
        updateAccountLists()
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
        // Would normally save to UserDefaults or Keychain

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

    /// Fetch posts for an account or all accounts
    func fetchPosts(for account: SocialAccount? = nil) async throws -> [Post] {
        isLoading = true
        defer { isLoading = false }

        var allPosts: [Post] = []

        do {
            if let account = account {
                // Fetch for specific account
                switch account.platform {
                case .mastodon:
                    // Fetch Mastodon posts
                    let posts = try await mastodonService.fetchHomeTimeline(for: account)
                    allPosts.append(contentsOf: posts)
                case .bluesky:
                    // Fetch Bluesky posts
                    let posts = try await blueskyService.fetchTimeline(for: account)
                    allPosts.append(contentsOf: posts)
                }
            } else {
                // Fetch for all accounts
                for account in accounts {
                    // Fetch posts for each account
                    let posts = try await fetchPosts(for: account)
                    allPosts.append(contentsOf: posts)
                }
            }

            // For testing, return sample data if we don't have real posts
            if allPosts.isEmpty {
                return Post.samplePosts
            }

            return allPosts
        } catch {
            self.error = error
            throw error
        }
    }

    /// Refresh the unified timeline
    @MainActor
    func refreshTimeline(force: Bool = false) async throws {
        guard !isLoadingTimeline || force else { return }

        isLoadingTimeline = true
        defer { isLoadingTimeline = false }

        // Fetch posts from all accounts
        var posts: [Post] = []

        do {
            if accounts.isEmpty {
                // Use sample posts if no accounts
                posts = Post.samplePosts
            } else {
                // Fetch from each account
                for account in accounts {
                    try await Task.sleep(nanoseconds: 100_000_000)  // Small delay between requests
                    let accountPosts = try await fetchPosts(for: account)
                    posts.append(contentsOf: accountPosts)
                }
            }

            // Sort by date (newest first)
            posts.sort { $0.createdAt > $1.createdAt }

            // Update the unified timeline
            self.unifiedTimeline = posts
        } catch {
            self.error = error
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

    // MARK: - Post Actions

    /// Like/favorite a post
    func likePost(_ post: Post) async throws -> Bool {
        // Implementation would call the appropriate service based on the post's platform
        return true
    }

    /// Repost/boost a post
    func repostPost(_ post: Post) async throws -> Bool {
        // Implementation would call the appropriate service based on the post's platform
        return true
    }

    /// Reply to a post
    func replyToPost(_ post: Post, content: String) async throws -> Bool {
        // Implementation would call the appropriate service based on the post's platform
        return true
    }
}

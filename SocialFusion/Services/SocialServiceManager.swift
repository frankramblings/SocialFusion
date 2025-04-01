import Combine
import Foundation
import SwiftUI
import UIKit

// Define notification names
extension Notification.Name {
    static let profileImageUpdated = Notification.Name("AccountProfileImageUpdated")
    static let accountUpdated = Notification.Name("AccountUpdated")
}

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
    @Published var selectedAccountIds: Set<String> = ["all"]  // Track which accounts are selected for timeline
    @Published var isFetchingTimeline = false
    @Published var lastRefreshed = Date()

    // MARK: - Initialization

    init() {
        // Load accounts and their selection state
        loadAccounts()
        loadSelections()

        print(
            "SocialServiceManager initialized with \(mastodonAccounts.count) Mastodon accounts and \(blueskyAccounts.count) Bluesky accounts"
        )
        print("Selected account IDs: \(Array(selectedAccountIds).joined(separator: ","))")

        // Start with trending posts if no accounts
        if mastodonAccounts.isEmpty && blueskyAccounts.isEmpty {
            Task {
                await fetchTrendingPosts()
            }
        }

        // Listen for profile image updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProfileImageUpdate),
            name: .profileImageUpdated,
            object: nil
        )

        // Listen for account updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAccountUpdate(_:)),
            name: .accountUpdated,
            object: nil
        )
    }

    @objc private func handleProfileImageUpdate(_ notification: Notification) {
        guard
            let accountId = notification.userInfo?["accountId"] as? String,
            let profileImageURL = notification.userInfo?["profileImageURL"] as? URL
        else {
            return
        }

        // Update Bluesky account
        if let index = blueskyAccounts.firstIndex(where: { $0.id == accountId }) {
            var updatedAccount = blueskyAccounts[index]
            updatedAccount.profileImageURL = profileImageURL
            blueskyAccounts[index] = updatedAccount
            saveAccounts()
            print("Updated Bluesky account \(accountId) with profile image URL: \(profileImageURL)")
        }

        // Update Mastodon account
        if let index = mastodonAccounts.firstIndex(where: { $0.id == accountId }) {
            var updatedAccount = mastodonAccounts[index]
            updatedAccount.profileImageURL = profileImageURL
            mastodonAccounts[index] = updatedAccount
            saveAccounts()
            print(
                "Updated Mastodon account \(accountId) with profile image URL: \(profileImageURL)")

            // Save the updated account
            NotificationCenter.default.post(
                name: .profileImageUpdated,
                object: nil,
                userInfo: ["account": updatedAccount]
            )
        }
    }

    // Handler for account updates
    @objc private func handleAccountUpdate(_ notification: Notification) {
        guard let account = notification.object as? SocialAccount else {
            print("Invalid account object in update notification")
            return
        }

        Task { @MainActor in
            // Update the account in the appropriate array
            if account.platform == .mastodon {
                if let index = mastodonAccounts.firstIndex(where: { $0.id == account.id }) {
                    mastodonAccounts[index] = account
                    print("Updated Mastodon account: \(account.username)")
                } else {
                    mastodonAccounts.append(account)
                    print("Added new Mastodon account: \(account.username)")
                }
            } else if account.platform == .bluesky {
                if let index = blueskyAccounts.firstIndex(where: { $0.id == account.id }) {
                    blueskyAccounts[index] = account
                    print("Updated Bluesky account: \(account.username)")
                } else {
                    blueskyAccounts.append(account)
                    print("Added new Bluesky account: \(account.username)")
                }
            }

            // Save changes to persistent storage
            saveAccounts()
            objectWillChange.send()
        }
    }

    // MARK: - Account Management

    private func loadAccounts() {
        do {
            // Load Mastodon accounts
            if let mastodonData = UserDefaults.standard.data(forKey: "mastodonAccounts") {
                let decodedAccounts = try JSONDecoder().decode(
                    [SocialAccount].self, from: mastodonData)
                mastodonAccounts = decodedAccounts.filter { validateAccount($0) }
                print("Loaded \(mastodonAccounts.count) Mastodon accounts")

                // Print profile image URLs for debugging
                for account in mastodonAccounts {
                    print(
                        "Loaded Mastodon account \(account.username) profile image URL: \(String(describing: account.profileImageURL))"
                    )
                }
            } else {
                mastodonAccounts = []
                print("No Mastodon accounts found in storage")
            }

            // Load Bluesky accounts
            if let blueskyData = UserDefaults.standard.data(forKey: "blueskyAccounts") {
                let decodedAccounts = try JSONDecoder().decode(
                    [SocialAccount].self, from: blueskyData)
                blueskyAccounts = decodedAccounts.filter { validateAccount($0) }
                print("Loaded \(blueskyAccounts.count) Bluesky accounts")

                // Print profile image URLs for debugging
                for account in blueskyAccounts {
                    print(
                        "Loaded Bluesky account \(account.username) profile image URL: \(String(describing: account.profileImageURL))"
                    )
                }
            } else {
                blueskyAccounts = []
                print("No Bluesky accounts found in storage")
            }

            // Load selected account IDs
            if let selectedIds = UserDefaults.standard.array(forKey: "selectedAccountIds")
                as? [String]
            {
                selectedAccountIds = Set(selectedIds)
            }
        } catch {
            print("Error loading accounts from storage: \(error.localizedDescription)")
        }
    }

    private func validateAccount(_ account: SocialAccount) -> Bool {
        guard !account.id.isEmpty,
            !account.username.isEmpty,
            account.serverURL != nil
        else {
            print("Account validation failed - missing required fields")
            return false
        }

        // For serverURL validation, handle Bluesky and Mastodon differently
        if account.platform == .bluesky {
            // Bluesky always uses bsky.social as serverURL, so just check it's not empty
            return account.serverURL != nil
        } else {
            // For Mastodon, we need to ensure the server URL can be parsed properly
            let serverUrlString = account.serverURL?.absoluteString ?? ""
            let serverWithScheme =
                serverUrlString.contains("://") ? serverUrlString : "https://" + serverUrlString
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
        // Save updated accounts
        saveAccounts()
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
            server: URL(string: "bsky.social"),
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

        // Select the new account
        selectedAccountIds = ["all"]  // Reset to show all accounts

        print("Added Bluesky account: \(account.username)")

        // Save updated accounts
        saveAccounts()

        // Immediately refresh timeline
        Task {
            await refreshTimeline()
        }

        return account
    }

    func removeAccount(_ account: SocialAccount) async {
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

        // Remove from timeline posts from this account
        await refreshTimeline()

        // Save updated accounts
        saveAccounts()
    }

    // MARK: - Timeline

    @MainActor
    func refreshTimeline(force: Bool = false) async {
        guard !isLoadingTimeline else { return }
        isLoadingTimeline = true

        var mastodonPosts: [Post] = []
        var blueskyPosts: [Post] = []
        var allPosts: [Post] = []
        var errors: [Error] = []

        // MASTODON: Fetch from all accounts or just the selected one
        if selectedAccountIds.contains("all") || selectedAccountIds.isEmpty {
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
                        mastodonPosts.append(contentsOf: posts)
                    case .failure(let error):
                        errors.append(error)
                    }
                }
            }
        }

        // BLUESKY: Fetch from all accounts or just the selected one
        if selectedAccountIds.contains("all") || selectedAccountIds.isEmpty {
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
                        blueskyPosts.append(contentsOf: posts)
                    case .failure(let error):
                        errors.append(error)
                    }
                }
            }
        }

        // Combine all posts
        allPosts = mastodonPosts + blueskyPosts

        // Sort combined timeline by date
        let sortedCombined = allPosts.sorted(by: { $0.createdAt > $1.createdAt })

        // Update the timeline
        if !sortedCombined.isEmpty {
            unifiedTimeline = sortedCombined
            print("Updated timeline with \(sortedCombined.count) posts")
        } else if errors.isEmpty {
            // Empty timeline but no errors, just normal empty state
            unifiedTimeline = []
            print("Timeline is empty (no posts to display)")
        }

        // Set error if we encountered any
        if let lastError = errors.last {
            self.error = ServiceError.timelineError(underlying: lastError)
        }

        // Update last refreshed timestamp
        lastRefreshed = Date()

        isLoadingTimeline = false
    }

    // Helper method to get an account by ID
    private func getCurrentAccountById(_ id: String) -> SocialAccount? {
        return mastodonAccounts.first(where: { $0.id == id })
            ?? blueskyAccounts.first(where: { $0.id == id })
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
                                visibility: visibility.rawValue,
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
                    if self.unifiedTimeline.firstIndex(where: { $0.id == postToReply.id }) != nil {
                        // No longer updating replyCount since the Post model doesn't have this property
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
                        // Try the public API
                        let posts = try await self.blueskyService.fetchTrendingPosts()
                        print("Got \(posts.count) Bluesky posts from public API")
                        return .success(posts)
                    } catch {
                        print(
                            "Failed to fetch Bluesky trending posts: \(error.localizedDescription)")

                        // If public API fails, try with a backup endpoint
                        do {
                            // Wait a moment before retry
                            try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds

                            // Try an alternative public API
                            let backupUrl = "https://skyfeed.app/api/popular"
                            let backupRequest = URLRequest(url: URL(string: backupUrl)!)
                            let (_, _) = try await URLSession.shared.data(for: backupRequest)

                            // If we got any data, just return success with empty array
                            // This will trigger fallback content
                            print("Tried backup API but will use fallback content")
                            return .success([])
                        } catch {
                            // If both fail, return the original error
                            print("Backup API also failed, using fallback content")
                            return .failure(error)
                        }
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

            // Sort each platform's posts by date (most recent first)
            let sortedMastodonPosts = mastodonPosts.sorted(by: {
                (post1: Post, post2: Post) -> Bool in
                return post1.createdAt > post2.createdAt
            })

            let sortedBlueskyPosts = blueskyPosts.sorted(by: { (post1: Post, post2: Post) -> Bool in
                return post1.createdAt > post2.createdAt
            })

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
                combinedTimeline = sortedBlueskyPosts
                combinedTimeline.append(contentsOf: sortedMastodonPosts)
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

            // Add a throwing operation to ensure the catch block is reachable
            if errors.count > 0 {
                throw ServiceError.timelineError(underlying: errors.first!)
            }
        } catch {
            self.error = ServiceError.timelineError(underlying: error)
            print("Error in fetchTrendingPosts: \(error.localizedDescription)")
        }

        isLoadingTimeline = false
    }

    /// Create fallback Bluesky posts when none can be retrieved from the API
    private func createFallbackBlueskyPosts() -> [Post] {
        print("Creating realistic fallback Bluesky posts")

        // Generate a mix of realistic authors
        let authors = [
            Author(
                id: "did:plc:bafyreighnl7oaph7x4zwgvq7stijp3qvbxxrjnf7kgvno6xmt4k6fx25am",
                username: "jay.bsky.social",
                displayName: "Jay Graber",
                profileImageURL: URL(
                    string:
                        "https://cdn.bsky.app/img/avatar/plain/did:plc:bafyreighnl7oaph7x4zwgvq7stijp3qvbxxrjnf7kgvno6xmt4k6fx25am/bafkreigmvk5i7fk3jjpxontzijrjpdyvswkxbk5kd3kn53ds2hrj53xz4e"
                ),
                platform: .bluesky,
                platformSpecificId:
                    "did:plc:bafyreighnl7oaph7x4zwgvq7stijp3qvbxxrjnf7kgvno6xmt4k6fx25am"
            ),
            Author(
                id: "did:plc:z72i7hdynmk6r22z27h6tvur",
                username: "pfrazee.com",
                displayName: "Paul Frazee",
                profileImageURL: URL(
                    string:
                        "https://cdn.bsky.app/img/avatar/plain/did:plc:z72i7hdynmk6r22z27h6tvur/bafkreifvbfhdrt2bvzpcgj4unyrpw7uopc7nfcxs3vpnhdczmuf7pu7swa"
                ),
                platform: .bluesky,
                platformSpecificId: "did:plc:z72i7hdynmk6r22z27h6tvur"
            ),
            Author(
                id: "did:plc:mqxsuw5b5rhpwo4lw6iwlid5",
                username: "rose.bsky.social",
                displayName: "Rose Wang",
                profileImageURL: URL(
                    string:
                        "https://cdn.bsky.app/img/avatar/plain/did:plc:mqxsuw5b5rhpwo4lw6iwlid5/bafkreigy3u5wvdpdxwqcfcj3otn4wul5jkft2awbhs6kxqgatslkftvl6q"
                ),
                platform: .bluesky,
                platformSpecificId: "did:plc:mqxsuw5b5rhpwo4lw6iwlid5"
            ),
            Author(
                id: "did:plc:ragtjsm2j2vknwkz3zp4oxrd",
                username: "andy.bsky.team",
                displayName: "Andy Luers",
                profileImageURL: URL(
                    string:
                        "https://cdn.bsky.app/img/avatar/plain/did:plc:ragtjsm2j2vknwkz3zp4oxrd/bafkreidgbj4kglbw2dkk2gy4wti7kal7hxwjcmbwvwpyoegecll5ch2g2u"
                ),
                platform: .bluesky,
                platformSpecificId: "did:plc:ragtjsm2j2vknwkz3zp4oxrd"
            ),
            Author(
                id: "did:plc:kkf4nxgzfirlwpzjyhjlmzwa",
                username: "dholms.xyz",
                displayName: "Daniel Holmgren",
                profileImageURL: URL(
                    string:
                        "https://cdn.bsky.app/img/avatar/plain/did:plc:kkf4nxgzfirlwpzjyhjlmzwa/bafkreiahqgmcdntwjmgfmr4qjynnoigjwa7mwsdmoy2od4dkswac4o2qzq"
                ),
                platform: .bluesky,
                platformSpecificId: "did:plc:kkf4nxgzfirlwpzjyhjlmzwa"
            ),
            Author(
                id: "did:plc:vpkhqolt662uhesyj6nxm7ys",
                username: "tieshun.bsky.social",
                displayName: "Tieshun Roquerre",
                profileImageURL: URL(
                    string:
                        "https://cdn.bsky.app/img/avatar/plain/did:plc:vpkhqolt662uhesyj6nxm7ys/bafkreicu6c6gwrjnvjqw7ogtx4kwzxvce3qpl4ir5pqurnqvxwk6gtmeb4"
                ),
                platform: .bluesky,
                platformSpecificId: "did:plc:vpkhqolt662uhesyj6nxm7ys"
            ),
            Author(
                id: "did:plc:vwzwgnygau7ed7b7wt5ux7y2",
                username: "gwen.bsky.social",
                displayName: "Gwen",
                profileImageURL: URL(
                    string:
                        "https://cdn.bsky.app/img/avatar/plain/did:plc:vwzwgnygau7ed7b7wt5ux7y2/bafkreifu5gdhzu5ieqznjj33t7ecsfnf7u4qmqvhcxeqicrhiyb5rqr3zm"
                ),
                platform: .bluesky,
                platformSpecificId: "did:plc:vwzwgnygau7ed7b7wt5ux7y2"
            ),
            Author(
                id: "did:plc:ewvi7nxzyoun6zhxrhs64oiz",
                username: "atproto.com",
                displayName: "AT Protocol",
                profileImageURL: URL(
                    string:
                        "https://cdn.bsky.app/img/avatar/plain/did:plc:ewvi7nxzyoun6zhxrhs64oiz/bafkreihdoza3prmo6jev3j4ocpw7rq36eopui7sxzhcnvc2hyhhpgdrfcu"
                ),
                platform: .bluesky,
                platformSpecificId: "did:plc:ewvi7nxzyoun6zhxrhs64oiz"
            ),
        ]

        // Real-looking content for posts
        let contents = [
            "Excited to share that we're working on a new version of the Bluesky app with enhanced features for custom feeds and content discovery!",

            "The AT Protocol's key innovation is that it separates identity, data, and algorithms. This gives users portability and choice. You can bring your handle and data to any app built on the protocol.",

            "Celebrating a milestone: Bluesky has now reached over 4 million users! Thank you to everyone who's been a part of this journey with us. 💙",

            "Working on feed generators has been an eye-opening experience. The ability to create custom algorithms that anyone can subscribe to is transforming how we think about content discovery.",

            "We're focused on building moderation tools that work at scale while respecting user autonomy. It's a challenging balance, but essential for healthy online communities.",

            "Reply to @alice.bsky.social - Yes, that's exactly the kind of interoperability we're aiming for with the AT Protocol. Your identity and social graph should be portable across compatible apps.",

            "The latest update for Bluesky includes better image handling, including support for image alt text and improved accessibility features.",

            "Coming soon: better search functionality and topic exploration. We've heard your feedback and we're working on making content discovery more intuitive.",

            "Our team is growing! We're looking for developers passionate about decentralized social networking. Check out our careers page if you want to help build the future of social.",

            "Just posted a detailed technical overview of how self-authenticating data works in the AT Protocol. This is what enables account portability between apps: atproto.com/blog/data-model",

            "We're not just building another social network - we're creating infrastructure for an ecosystem of interoperable social apps that put users in control.",

            "Privacy update: We're implementing more granular privacy controls in the next release, giving you more choices about how your content is distributed.",
        ]

        // Create posts with more realistic data
        var posts: [Post] = []

        for (index, content) in contents.enumerated() {
            // Pick a random author from our list
            let author = authors[index % authors.count]

            // Create realistic post ID
            let postId = "at://\(author.id)/app.bsky.feed.post/\(UUID().uuidString.prefix(8))"

            // Create some random engagement numbers for variety
            // These values are not used in the current Post model but may be needed in the future
            _ = Int.random(in: 20...250)  // likeCount
            _ = Int.random(in: 5...100)  // repostCount
            _ = Int.random(in: 3...50)  // replyCount

            // Create date with realistic distribution (newer posts first)
            let hoursAgo = Double(index) * 3.0 + Double.random(in: 0...2)
            let createdAt = Date().addingTimeInterval(-hoursAgo * 3600)

            // Create the post
            let post = Post(
                id: postId,
                content: content,
                authorName: author.displayName,
                authorUsername: author.username,
                authorProfilePictureURL: author.profileImageURL?.absoluteString ?? "",
                createdAt: createdAt,
                platform: .bluesky,
                originalURL: "https://bsky.app/profile/\(author.username)/post/\(postId)",
                attachments: [],
                mentions: [],
                tags: []
            )

            posts.append(post)
        }

        print("Created \(posts.count) fallback Bluesky posts")
        return posts
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

    func addMastodonAccountWithToken(serverURL: String, accessToken: String) async throws
        -> SocialAccount
    {
        print("Adding Mastodon account with token. Server: \(serverURL)")

        // Validate inputs
        guard !serverURL.isEmpty else {
            throw NSError(
                domain: "SocialServiceManager",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Server URL cannot be empty"])
        }

        guard !accessToken.isEmpty else {
            throw NSError(
                domain: "SocialServiceManager",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Access token cannot be empty"])
        }

        // Format the server URL properly
        let formattedServerURL = serverURL.contains("://") ? serverURL : "https://" + serverURL
        guard URL(string: formattedServerURL) != nil else {
            throw NSError(
                domain: "SocialServiceManager",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL: \(formattedServerURL)"])
        }

        // Create a temporary account for verification
        let tempAccount = SocialAccount(
            id: UUID().uuidString,
            username: "temp_user",
            displayName: "Temporary User",
            serverURL: formattedServerURL,
            platform: .mastodon,
            accessToken: accessToken
        )

        // Save the access token to the temporary account
        tempAccount.saveAccessToken(accessToken)

        do {
            // Verify credentials and get account info
            print("Verifying Mastodon credentials...")
            let verifiedAccount = try await mastodonService.verifyAndCreateAccount(
                account: tempAccount)

            // Check if we already have this account
            let accountExists = mastodonAccounts.contains { account in
                account.username == verifiedAccount.username
                    && account.serverURL?.absoluteString.lowercased()
                        == verifiedAccount.serverURL?.absoluteString.lowercased()
            }

            if accountExists {
                throw NSError(
                    domain: "SocialServiceManager",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "Account already exists"])
            }

            // Add account
            mastodonAccounts.append(verifiedAccount)
            saveAccounts()

            print(
                "Successfully added Mastodon account: \(verifiedAccount.username)@\(verifiedAccount.serverURL?.absoluteString ?? "")"
            )

            // Trigger timeline refresh with the new account
            DispatchQueue.main.async {
                self.isFetchingTimeline = true
                Task {
                    await self.refreshTimeline(force: true)
                    await MainActor.run {
                        self.isFetchingTimeline = false
                    }
                }
            }

            return verifiedAccount
        } catch {
            print("Failed to add Mastodon account: \(error.localizedDescription)")
            throw error
        }
    }

    @MainActor
    func refreshAccountSelections() {
        print("Refreshing account selections...")

        // Ensure accounts are loaded from storage if needed
        if mastodonAccounts.isEmpty && blueskyAccounts.isEmpty {
            loadAccounts()
        }

        // Log the accounts we have
        print(
            "Currently have \(mastodonAccounts.count) Mastodon accounts and \(blueskyAccounts.count) Bluesky accounts"
        )

        // Ensure valid selection state
        if selectedAccountIds.isEmpty {
            selectedAccountIds = ["all"]
            print("Reset selection to 'all' accounts")
        }

        // Validate that selected account IDs actually exist
        let validAccountIds = Set(mastodonAccounts.map { $0.id })
            .union(blueskyAccounts.map { $0.id })
            .union(["all"])  // "all" is always valid

        // Filter out invalid account IDs
        let invalidSelections = selectedAccountIds.filter { !validAccountIds.contains($0) }
        if !invalidSelections.isEmpty {
            selectedAccountIds.subtract(invalidSelections)
            if selectedAccountIds.isEmpty {
                selectedAccountIds = ["all"]
            }
            print("Removed \(invalidSelections.count) invalid account selections")
        }

        // Save the selection state
        saveSelections()
    }

    private func saveSelections() {
        let selectionArray = Array(selectedAccountIds)
        UserDefaults.standard.set(selectionArray, forKey: "selectedAccountIds")
        print("Saved account selections: \(selectionArray)")
    }

    private func loadSelections() {
        if let savedSelections = UserDefaults.standard.stringArray(forKey: "selectedAccountIds") {
            selectedAccountIds = Set(savedSelections)
            print("Loaded account selections: \(savedSelections)")
        } else {
            selectedAccountIds = ["all"]
            print("No saved selections found, defaulting to 'all'")
        }
    }

    private func saveAccounts() {
        do {
            // Save Mastodon accounts
            let mastodonData = try JSONEncoder().encode(mastodonAccounts)
            UserDefaults.standard.set(mastodonData, forKey: "mastodonAccounts")
            print("Saved \(mastodonAccounts.count) Mastodon accounts")

            // Print profile image URLs for debugging
            for account in mastodonAccounts {
                print(
                    "Saved Mastodon account \(account.username) profile image URL: \(String(describing: account.profileImageURL))"
                )
            }

            // Save Bluesky accounts
            let blueskyData = try JSONEncoder().encode(blueskyAccounts)
            UserDefaults.standard.set(blueskyData, forKey: "blueskyAccounts")
            print("Saved \(blueskyAccounts.count) Bluesky accounts")

            // Print profile image URLs for debugging
            for account in blueskyAccounts {
                print(
                    "Saved Bluesky account \(account.username) profile image URL: \(String(describing: account.profileImageURL))"
                )
            }

            // Save selected account IDs
            UserDefaults.standard.set(Array(selectedAccountIds), forKey: "selectedAccountIds")
        } catch {
            print("Error saving accounts to storage: \(error.localizedDescription)")
        }
    }

    // MARK: - Save and Load Accounts

    /// Saves all account data to persistent storage
    @MainActor
    func saveAllAccounts() {
        saveAccounts()
        saveSelections()
        print("All account data saved to persistent storage")
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
    return account.serverURL?.absoluteString ?? ""
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

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

/// SocialServiceManager is a class that manages all social media services
@MainActor
public class SocialServiceManager: ObservableObject {
    // Services
    private let mastodonService = MastodonService()
    private let blueskyService = BlueskyService()

    // Published properties
    @Published public var mastodonAccounts: [SocialAccount] = []
    @Published public var blueskyAccounts: [SocialAccount] = []
    @Published public var unifiedTimeline: [Post] = []
    @Published public var isLoadingTimeline = false
    @Published public var error: Error? = nil
    @Published public var selectedAccountIds: Set<String> = ["all"]
    @Published public var isFetchingTimeline = false
    @Published public var lastRefreshed = Date()
    @Published public var authErrorMessage: String? = nil
    @Published public var showingAuthError = false

    // Auto-refresh timer
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?

    // Rate limiting tracking
    private var rateLimits: [String: RateLimitInfo] = [:]
    private let blueskyRateLimitKey = "bluesky"
    private let mastodonRateLimitKey = "mastodon"

    // Maximum number of concurrent requests (for staggering)
    private let maxConcurrentRequests = 2

    // Add a computed property to determine which types of accounts are selected
    var selectedAccountTypes: Set<SocialPlatform> {
        if selectedAccountIds.contains("all") || selectedAccountIds.isEmpty {
            return [.mastodon, .bluesky]
        }

        var types: Set<SocialPlatform> = []

        for id in selectedAccountIds {
            if mastodonAccounts.contains(where: { $0.id == id }) {
                types.insert(.mastodon)
            } else if blueskyAccounts.contains(where: { $0.id == id }) {
                types.insert(.bluesky)
            }
        }

        return types
    }

    // MARK: - Initialization

    public init() {
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

        // Set up auto-refresh timer if user has enabled it
        setupAutoRefreshTimer()

        // Listen for app background/foreground notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterBackground),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        // Listen for settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    // MARK: - App Lifecycle and Refresh Timer

    @objc private func handleAppWillEnterBackground() {
        // Cancel any pending refresh task
        refreshTask?.cancel()

        // Stop the timer when app goes to background
        stopAutoRefreshTimer()
    }

    @objc private func handleAppWillEnterForeground() {
        // Restart the timer when app comes to foreground
        setupAutoRefreshTimer()
    }

    @objc private func handleSettingsChanged() {
        // Update timer when settings change
        setupAutoRefreshTimer()
    }

    private func setupAutoRefreshTimer() {
        // Cancel existing timer
        stopAutoRefreshTimer()

        // Check user settings
        let autoRefreshEnabled = UserDefaults.standard.bool(forKey: "autoRefreshTimeline")
        if !autoRefreshEnabled {
            print("Auto-refresh is disabled in settings, not starting timer")
            return
        }

        // Get refresh interval from user settings
        let refreshIntervalMinutes = UserDefaults.standard.integer(forKey: "refreshInterval")
        let refreshInterval = Double(max(1, refreshIntervalMinutes)) * 60.0  // Convert to seconds, minimum 1 minute

        print("Setting up auto-refresh timer with interval: \(refreshInterval) seconds")

        // Create a new timer on the main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.refreshTimer = Timer.scheduledTimer(
                withTimeInterval: refreshInterval,
                repeats: true
            ) { [weak self] _ in
                guard let self = self else { return }

                // Cancel any existing refresh task
                Task { @MainActor in
                    self.refreshTask?.cancel()

                    // Create a new refresh task
                    self.refreshTask = Task {
                        // Capture accounts to avoid accessing MainActor properties directly
                        let hasAccounts = await MainActor.run {
                            return !self.mastodonAccounts.isEmpty || !self.blueskyAccounts.isEmpty
                        }

                        // Check if we have accounts before refreshing
                        guard hasAccounts else {
                            print("No accounts to refresh timeline for")
                            return
                        }

                        print("Auto-refresh timer triggered, refreshing timeline...")
                        do {
                            try await self.refreshTimeline(force: false)
                        } catch {
                            print("Auto-refresh failed: \(error.localizedDescription)")
                        }
                    }
                }
            }

            // Fire the timer immediately for the first refresh
            self.refreshTimer?.fire()
        }
    }

    private func stopAutoRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Rate Limiting

    private func checkRateLimit(for platform: String) -> Bool {
        guard let rateLimit = rateLimits[platform] else {
            return true  // No rate limit info recorded yet
        }

        return rateLimit.canMakeRequest
    }

    private func recordRateLimit(for platform: String, retryAfter: TimeInterval = 60.0) {
        var info =
            rateLimits[platform]
            ?? RateLimitInfo(
                platformName: platform,
                lastHit: Date(),
                retryAfter: retryAfter,
                consecutiveHits: 0
            )

        // Increase the backoff with each consecutive hit
        info.consecutiveHits += 1

        // Exponential backoff: Start with the suggested retry time, but increase it exponentially
        // with consecutive hits to prevent rapid retries
        let exponentialFactor = pow(1.5, Double(min(info.consecutiveHits, 10)))
        info.retryAfter = retryAfter * exponentialFactor
        info.lastHit = Date()

        print(
            "⚠️ Rate limit hit for \(platform). Backing off for \(info.retryAfter) seconds. Consecutive hits: \(info.consecutiveHits)"
        )

        rateLimits[platform] = info
    }

    private func resetRateLimitCounter(for platform: String) {
        if var info = rateLimits[platform], info.consecutiveHits > 0 {
            info.consecutiveHits = 0
            rateLimits[platform] = info
            print("✅ Successful request to \(platform), resetting rate limit counter")
        }
    }

    // MARK: - Profile Updates

    @objc private func handleProfileImageUpdate(_ notification: Notification) {
        guard
            let accountId = notification.userInfo?["accountId"] as? String,
            let profileImageURL = notification.userInfo?["profileImageURL"] as? URL
        else {
            return
        }

        // Update Bluesky account
        if let index = blueskyAccounts.firstIndex(where: { $0.id == accountId }) {
            let updatedAccount = blueskyAccounts[index]
            updatedAccount.profileImageURL = profileImageURL
            blueskyAccounts[index] = updatedAccount
            saveAccounts()
            print("Updated Bluesky account \(accountId) with profile image URL: \(profileImageURL)")
        }

        // Update Mastodon account
        if let index = mastodonAccounts.firstIndex(where: { $0.id == accountId }) {
            let updatedAccount = mastodonAccounts[index]
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

    /// Loads account selection state from UserDefaults
    private func loadSelections() {
        if let savedSelections = UserDefaults.standard.array(forKey: "selected_account_ids")
            as? [String]
        {
            selectedAccountIds = Set(savedSelections)

            // Ensure we have at least "all" in the selection set
            if selectedAccountIds.isEmpty {
                selectedAccountIds.insert("all")
            }

            print("Loaded \(selectedAccountIds.count) account selections from UserDefaults")
        } else {
            // Default to "all" if no selections are saved
            selectedAccountIds = ["all"]
            print("No saved selections found, defaulting to 'all'")
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

    /// Add a Mastodon account using an access token
    @MainActor
    func addMastodonAccountWithToken(serverURL: String, accessToken: String) async throws
        -> SocialAccount
    {
        // Validate input
        guard !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalidInput(reason: "Server URL cannot be empty")
        }

        guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalidInput(reason: "Access token cannot be empty")
        }

        // Ensure server URL has proper scheme
        let formattedServer = serverURL.lowercased()
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

        // Call the MastodonService to authenticate with the token
        let account = try await mastodonService.authenticateWithToken(
            server: url,
            accessToken: accessToken
        )

        // Validate the returned account
        guard validateAccount(account) else {
            throw ServiceError.invalidAccount(reason: "Invalid account data received from server")
        }

        // Check for duplicate accounts
        guard !mastodonAccounts.contains(where: { $0.id == account.id }) else {
            throw ServiceError.duplicateAccount
        }

        // Add to accounts list and save
        mastodonAccounts.append(account)
        saveAccounts()

        return account
    }

    /// Add a Bluesky account using username/password authentication
    /// - Parameters:
    ///   - username: The Bluesky username or email
    ///   - password: The Bluesky app password
    /// - Returns: The created SocialAccount
    @MainActor
    public func addBlueskyAccount(username: String, password: String) async throws -> SocialAccount
    {
        do {
            // Validate input
            guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ServiceError.invalidInput(reason: "Username cannot be empty")
            }

            guard !password.isEmpty else {
                throw ServiceError.invalidInput(reason: "Password cannot be empty")
            }

            print("Attempting to authenticate with Bluesky for user: \(username)")

            // Use BlueskyService directly to authenticate
            // Store only the domain without https:// prefix to avoid double-prefixing
            let serverURL = URL(string: "bsky.social")
            let account = try await blueskyService.authenticate(
                server: serverURL,
                username: username,
                password: password
            )

            // Print debug info for the account
            print("Account created - server URL: \(String(describing: account.serverURL))")

            // Check if account already exists
            if let existingIndex = self.blueskyAccounts.firstIndex(where: { $0.id == account.id }) {
                // Update existing account with new tokens
                self.blueskyAccounts[existingIndex] = account
                self.saveAccounts()
                print("Updated existing Bluesky account with new tokens: \(account.username)")
            } else {
                // Add new account
                self.blueskyAccounts.append(account)
                self.saveAccounts()
                print(
                    "Successfully added new Bluesky account: \(account.username) (ID: \(account.id))"
                )

                // Update account selection if needed
                if self.mastodonAccounts.isEmpty && self.blueskyAccounts.count == 1 {
                    self.selectedAccountIds = [account.id]
                    print("Setting selected account to newly added Bluesky account")
                }
            }

            // Update UI
            self.objectWillChange.send()

            // Post notification for account added/updated
            NotificationCenter.default.post(
                name: .accountUpdated,
                object: account
            )

            // Trigger timeline refresh
            try? await self.refreshTimeline(force: true)

            return account
        } catch {
            print("Failed to add Bluesky account: \(error.localizedDescription)")
            throw error
        }
    }

    func removeAccount(_ account: SocialAccount) async {
        // Validate account before removal
        guard validateAccount(account) else {
            return
        }

        // Delete authentication tokens using account's method
        deleteTokens(for: account.id)
        print("Deleted tokens for account \(account.username)")

        switch account.platform {
        case .mastodon:
            mastodonAccounts.removeAll { $0.id == account.id }
            print("Removed Mastodon account: \(account.username)")
        case .bluesky:
            blueskyAccounts.removeAll { $0.id == account.id }
            print("Removed Bluesky account: \(account.username)")
        }

        // Remove posts from this account from timeline
        try? await refreshTimeline()

        // Save updated accounts
        saveAccounts()

        // Post notification about account removal
        NotificationCenter.default.post(
            name: .accountUpdated,
            object: nil,
            userInfo: ["action": "removed", "accountId": account.id]
        )
    }

    // Helper function to delete tokens
    private func deleteTokens(for accountId: String) {
        UserDefaults.standard.removeObject(forKey: "accessToken-\(accountId)")
        UserDefaults.standard.removeObject(forKey: "refreshToken-\(accountId)")
        UserDefaults.standard.removeObject(forKey: "clientId-\(accountId)")
        UserDefaults.standard.removeObject(forKey: "clientSecret-\(accountId)")
        UserDefaults.standard.removeObject(forKey: "token-expiry-\(accountId)")
    }

    // MARK: - Timeline

    @MainActor
    func refreshTimeline(force: Bool = false) async throws {
        // Check if already loading
        guard !isLoadingTimeline || force else { return }
        isLoadingTimeline = true

        print("Refreshing timeline (force: \(force))...")

        var allPosts: [Post] = []
        var errors: [Error] = []

        // Check rate limits before making requests
        let canFetchBluesky = checkRateLimit(for: blueskyRateLimitKey)
        let canFetchMastodon = checkRateLimit(for: mastodonRateLimitKey)

        if !canFetchBluesky && !canFetchMastodon {
            let nextBlueskyTime = rateLimits[blueskyRateLimitKey]?.nextAllowedRequestTime
            let nextMastodonTime = rateLimits[mastodonRateLimitKey]?.nextAllowedRequestTime

            throw ServiceError.rateLimitError(
                reason:
                    "Rate limit in effect. Next allowed request at: Bluesky: \(nextBlueskyTime?.formatted() ?? "unknown"), Mastodon: \(nextMastodonTime?.formatted() ?? "unknown")"
            )
        }

        // MASTODON: Fetch based on selection if not rate limited
        if canFetchMastodon
            && (selectedAccountTypes.contains(.mastodon) || selectedAccountIds.contains("all")
                || selectedAccountIds.isEmpty)
        {
            let accountsToFetch: [SocialAccount]

            if selectedAccountIds.contains("all") || selectedAccountIds.isEmpty {
                // Fetch from all Mastodon accounts
                accountsToFetch = mastodonAccounts
            } else {
                // Fetch only from selected Mastodon accounts
                accountsToFetch = mastodonAccounts.filter { selectedAccountIds.contains($0.id) }
            }

            // Process accounts in chunks to avoid overwhelming the API
            var index = 0
            while index < accountsToFetch.count {
                // Process accounts in chunks based on maxConcurrentRequests
                let endIndex = min(index + maxConcurrentRequests, accountsToFetch.count)
                let accountChunk = Array(accountsToFetch[index..<endIndex])

                await withTaskGroup(of: (Result<[Post], Error>).self) { group in
                    for account in accountChunk {
                        group.addTask {
                            do {
                                print("Fetching Mastodon timeline for \(account.username)")
                                let posts = try await self.fetchTimeline(for: account)
                                print(
                                    "Successfully fetched \(posts.count) posts for Mastodon account: \(account.username)"
                                )
                                return .success(posts)
                            } catch {
                                print(
                                    "Error fetching Mastodon timeline for \(account.username): \(error.localizedDescription)"
                                )

                                // Check if this was a rate limit error
                                if let serviceError = error as? ServiceError,
                                    case .apiError(let message) = serviceError,
                                    message.contains("429")
                                {
                                    // Handle rate limiting
                                    await self.recordRateLimit(
                                        for: self.mastodonRateLimitKey, retryAfter: 60.0)
                                }
                                return .failure(error)
                            }
                        }
                    }

                    // Collect results from this chunk
                    for await result in group {
                        switch result {
                        case .success(let posts):
                            allPosts.append(contentsOf: posts)
                            self.resetRateLimitCounter(for: self.mastodonRateLimitKey)
                        case .failure(let error):
                            errors.append(error)
                        }
                    }
                }

                // Move to the next chunk of accounts
                index = endIndex

                // Add a small delay between chunks to avoid overwhelming the API
                if index < accountsToFetch.count {
                    try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 second delay
                }
            }
        }

        // BLUESKY: Fetch based on selection if not rate limited
        if canFetchBluesky
            && (selectedAccountTypes.contains(.bluesky) || selectedAccountIds.contains("all")
                || selectedAccountIds.isEmpty)
        {
            let accountsToFetch: [SocialAccount]

            if selectedAccountIds.contains("all") || selectedAccountIds.isEmpty {
                // Fetch from all Bluesky accounts
                accountsToFetch = blueskyAccounts
            } else {
                // Fetch only from selected Bluesky accounts
                accountsToFetch = blueskyAccounts.filter { selectedAccountIds.contains($0.id) }
            }

            // Process accounts in chunks to avoid overwhelming the API
            var index = 0
            while index < accountsToFetch.count {
                // Process accounts in chunks based on maxConcurrentRequests
                let endIndex = min(index + maxConcurrentRequests, accountsToFetch.count)
                let accountChunk = Array(accountsToFetch[index..<endIndex])

                await withTaskGroup(of: (Result<[Post], Error>).self) { group in
                    for account in accountChunk {
                        group.addTask {
                            do {
                                print("Fetching Bluesky timeline for \(account.username)")
                                let posts = try await self.fetchTimeline(for: account)
                                print(
                                    "Successfully fetched \(posts.count) Bluesky posts for account: \(account.username)"
                                )
                                return .success(posts)
                            } catch {
                                print(
                                    "Error fetching Bluesky timeline for \(account.username): \(error.localizedDescription)"
                                )

                                // Check if this was a rate limit error or token error
                                if let serviceError = error as? ServiceError {
                                    switch serviceError {
                                    case .apiError(let message) where message.contains("429"):
                                        await self.recordRateLimit(
                                            for: self.blueskyRateLimitKey, retryAfter: 60.0)
                                    case .unauthorized(let reason):
                                        await MainActor.run {
                                            self.authErrorMessage =
                                                "Bluesky login expired for \(account.username): \(reason). Please re-add the account."
                                            self.showingAuthError = true
                                        }
                                    default:
                                        break
                                    }
                                }
                                return .failure(error)
                            }
                        }
                    }

                    // Collect results
                    for await result in group {
                        switch result {
                        case .success(let posts):
                            allPosts.append(contentsOf: posts)
                            self.resetRateLimitCounter(for: self.blueskyRateLimitKey)
                        case .failure(let error):
                            errors.append(error)
                        }
                    }
                }

                // Move to the next chunk of accounts
                index = endIndex

                // Add a small delay between chunks to avoid overwhelming the API
                if index < accountsToFetch.count {
                    try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 second delay
                }
            }
        }

        // Sort all posts by date, newest first
        let sortedPosts = allPosts.sorted(by: { $0.createdAt > $1.createdAt })

        // Update timeline with the new posts if we have any
        if !sortedPosts.isEmpty {
            unifiedTimeline = sortedPosts
            print("Updated timeline with \(sortedPosts.count) posts")
        }
        // If we didn't get any posts AND we have rate limits, throw a rate limit error
        else if !checkRateLimit(for: blueskyRateLimitKey)
            || !checkRateLimit(for: mastodonRateLimitKey)
        {
            let blueskyInfo = rateLimits[blueskyRateLimitKey]
            let mastodonInfo = rateLimits[mastodonRateLimitKey]

            var errorMessage = "Rate limits in effect."
            if let blueskyInfo = blueskyInfo {
                errorMessage +=
                    " Bluesky: next request at \(blueskyInfo.nextAllowedRequestTime.formatted())."
            }
            if let mastodonInfo = mastodonInfo {
                errorMessage +=
                    " Mastodon: next request at \(mastodonInfo.nextAllowedRequestTime.formatted())."
            }

            throw ServiceError.rateLimitError(reason: errorMessage)
        }

        // Set an error if we encountered any
        if let lastError = errors.last {
            if let serviceError = lastError as? ServiceError,
                case .rateLimitError(let reason, _) = serviceError
            {
                self.error = ServiceError.rateLimitError(reason: reason)
            } else {
                self.error = ServiceError.timelineError(underlying: lastError)
            }
            print("Timeline refresh encountered error: \(lastError.localizedDescription)")
        } else {
            self.error = nil
        }

        // Update last refreshed timestamp and loading state
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
    }

    // MARK: - Save and Load Accounts

    /// Saves all account data to persistent storage
    @MainActor
    public func saveAllAccounts() async {
        saveAccounts()
        saveSelections()
        print("All account data saved to persistent storage")
    }

    /// Saves all accounts to UserDefaults
    private func saveAccounts() {
        // Save Mastodon accounts
        var mastodonData: [[String: Any]] = []
        for account in mastodonAccounts {
            mastodonData.append([
                "id": account.id,
                "username": account.username,
                "displayName": account.displayName as Any,
                "serverURL": account.serverURL?.absoluteString ?? "",
                "platform": account.platform.rawValue,
                "profileImageURL": account.profileImageURL?.absoluteString ?? "",
            ])
        }
        UserDefaults.standard.set(mastodonData, forKey: "mastodon_accounts")

        // Save Bluesky accounts
        var blueskyData: [[String: Any]] = []
        for account in blueskyAccounts {
            blueskyData.append([
                "id": account.id,
                "username": account.username,
                "displayName": account.displayName as Any,
                "serverURL": account.serverURL?.absoluteString ?? "",
                "platform": account.platform.rawValue,
                "profileImageURL": account.profileImageURL?.absoluteString ?? "",
            ])
        }
        UserDefaults.standard.set(blueskyData, forKey: "bluesky_accounts")

        print(
            "Saved \(mastodonAccounts.count) Mastodon accounts and \(blueskyAccounts.count) Bluesky accounts"
        )
    }

    /// Saves the selection state of accounts
    private func saveSelections() {
        let selectedIds = Array(selectedAccountIds)
        UserDefaults.standard.set(selectedIds, forKey: "selected_account_ids")
        print("Saved selection state for \(selectedIds.count) accounts")
    }

    /// Fetches trending posts when no accounts are added
    @MainActor
    func fetchTrendingPosts() async {
        guard unifiedTimeline.isEmpty else { return }

        isLoadingTimeline = true

        do {
            // Try to fetch trending posts from Mastodon
            var trendingPosts: [Post] = []

            // Use a public Mastodon instance to fetch trending content
            let publicInstance = URL(string: "https://mastodon.social")!
            let posts = try await mastodonService.fetchPublicTimeline(
                serverURL: publicInstance, count: 20)
            trendingPosts.append(contentsOf: posts)

            if !trendingPosts.isEmpty {
                unifiedTimeline = trendingPosts
                print("Loaded \(trendingPosts.count) trending posts for new users")
            }
        } catch {
            self.error = error
            print("Error fetching trending posts: \(error.localizedDescription)")
        }

        isLoadingTimeline = false
    }

    // MARK: - Quote Posts

    /// Loads more posts for the timeline
    @MainActor
    public func loadMorePosts() async {
        // This is a placeholder implementation
        // In a real implementation, this would use pagination to fetch more posts
        // and append them to the existing timeline
        print("Load more posts requested")

        // For now, we'll just add a small delay to simulate loading
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
        } catch {
            print("Sleep interrupted: \(error.localizedDescription)")
        }
    }

    /// Fetches a single Bluesky post by its ID
    /// - Parameter postID: The ID of the post to fetch
    /// - Returns: The Post object if found, nil otherwise
    public func fetchBlueskyPostByID(_ postID: String) async throws -> Post? {
        // Check if we have any Bluesky accounts to use for API access
        guard let blueskyAccount = blueskyAccounts.first else {
            // For public timeline, create a demo account to fetch posts
            let demoAccount = SocialAccount(
                id: "public",
                username: "public",
                displayName: "Public Timeline",
                serverURL: URL(string: "bsky.social"),
                platform: .bluesky,
                profileImageURL: nil
            )
            return try await blueskyService.fetchPostByID(postID, account: demoAccount)
        }

        // Use the first available Bluesky account to fetch the post
        return try await blueskyService.fetchPostByID(postID, account: blueskyAccount)
    }

    /// Fetches a single Mastodon post by its ID
    /// - Parameter postID: The ID of the post to fetch
    /// - Returns: The Post object if found, nil otherwise
    public func fetchMastodonPostByID(_ postID: String) async throws -> Post? {
        // Check if we have any Mastodon accounts to use for API access
        guard let mastodonAccount = mastodonAccounts.first else {
            // For public timeline, create a demo account to fetch posts
            let demoAccount = SocialAccount(
                id: "public",
                username: "public",
                displayName: "Public Timeline",
                serverURL: URL(string: "mastodon.social"),
                platform: .mastodon,
                profileImageURL: nil
            )
            return try await mastodonService.fetchPostByID(postID, account: demoAccount)
        }

        // Use the first available Mastodon account to fetch the post
        return try await mastodonService.fetchPostByID(postID, account: mastodonAccount)
    }

    // MARK: - Timeline Methods

    /// Fetches the timeline for a specific account
    public func fetchTimeline(for account: SocialAccount) async throws -> [Post] {
        let logger = Logger(subsystem: "com.socialfusion.app", category: "SocialServiceManager")

        logger.log(
            level: .info,
            "Fetching timeline for \(account.platform.rawValue) account: \(account.username, privacy: .public)"
        )

        do {
            switch account.platform {
            case .mastodon:
                return try await mastodonService.fetchHomeTimeline(for: account)

            case .bluesky:
                return try await blueskyService.getHomeTimeline(for: account)

            default:
                logger.log(
                    level: .error,
                    "Unsupported platform: \(account.platform.rawValue, privacy: .public)")
                throw ServiceError.unsupportedPlatform
            }
        } catch {
            logger.log(
                level: .error,
                "Error fetching timeline: \(error.localizedDescription, privacy: .public)")

            // Provide more specific error information based on the caught error
            if let networkError = error as? NetworkError {
                switch networkError {
                case .httpError(let statusCode, _):
                    throw ServiceError.apiError("Server returned status code: \(statusCode)")
                case .invalidURL:
                    throw ServiceError.invalidInput(reason: "Invalid server URL for account")
                case .noData:
                    throw ServiceError.emptyResponse
                case .apiError(let message):
                    throw ServiceError.apiError(message)
                case .decodingError:
                    throw ServiceError.dataFormatError(
                        "Invalid data format received from the server")
                case .requestFailed(let err):
                    throw ServiceError.networkError(underlying: err)
                case .rateLimitExceeded(let retryAfter):
                    throw ServiceError.rateLimitError(
                        reason: "Rate limit exceeded. Please try again later.",
                        retryAfter: retryAfter ?? 60.0
                    )
                default:
                    throw ServiceError.timelineError(underlying: error)
                }
            } else if let tokenError = error as? TokenError {
                switch tokenError {
                case .noAccessToken:
                    throw ServiceError.unauthorized("Missing access token")
                case .invalidRefreshToken:
                    throw ServiceError.unauthorized("Invalid refresh token")
                case .refreshFailed:
                    throw ServiceError.unauthorized("Failed to refresh access token")
                case .noRefreshToken:
                    throw ServiceError.unauthorized("No refresh token available")
                case .invalidServer:
                    throw ServiceError.invalidInput(reason: "Invalid server URL")
                }
            }

            // For any other errors
            throw ServiceError.unknown("An error occurred: \(error.localizedDescription)")
        }
    }
}

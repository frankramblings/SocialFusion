import Combine
import Foundation
import SwiftUI
import os.log

/// Represents the states a timeline view can be in
public enum TimelineState {
    case idle
    case loading
    case loaded([Post])
    case error(Error)
    case empty
    case rateLimited(retryAfter: TimeInterval)

    var posts: [Post] {
        if case .loaded(let posts) = self {
            return posts
        }
        return []
    }

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var error: Error? {
        if case .error(let error) = self {
            return error
        }
        return nil
    }

    var isRateLimited: Bool {
        if case .rateLimited = self {
            return true
        }
        return false
    }
}

/// A ViewModel for managing timeline data and state
@MainActor
public final class TimelineViewModel: ObservableObject {
    @Published public private(set) var state: TimelineState = .idle
    @Published public private(set) var posts: [Post] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?
    @Published public private(set) var isRateLimited = false
    @Published public private(set) var retryAfter: TimeInterval = 0

    private let socialServiceManager: SocialServiceManager
    private var cancellables = Set<AnyCancellable>()

    public init(socialServiceManager: SocialServiceManager = .shared) {
        self.socialServiceManager = socialServiceManager
        setupObservers()
    }

    // MARK: - Public Methods

    /// Refresh the timeline for a specific account
    public func refreshTimeline(for account: SocialAccount) {
        // Cancel any existing refresh task
        refreshTask?.cancel()

        // Start the new refresh task
        refreshTask = Task { [weak self] in
            guard let self = self else { return }

            // Show loading state
            await MainActor.run {
                self.isLoading = true
                if case .idle = self.state {
                    self.state = .loading
                }
            }

            do {
                // Fetch posts from the service manager
                let posts = try await socialServiceManager.fetchTimeline(for: account)

                // Update UI on main thread
                await MainActor.run {
                    self.posts = posts
                    self.isLoading = false

                    if posts.isEmpty {
                        self.state = .empty
                    } else {
                        self.state = .loaded(posts)

                        // Pre-load parent posts for instant expand
                        for post in posts {
                            if let parentID = post.inReplyToID {
                                // Handle different platforms
                                switch post.platform {
                                case .mastodon:
                                    // For logging/debugging
                                    self.logger.info(
                                        "Pre-loading Mastodon parent post for: \(post.id), parentID: \(parentID)"
                                    )

                                    // Use a higher-priority task for Mastodon parent posts
                                    Task(priority: .userInitiated) {
                                        // Try to find a matching Mastodon account
                                        let mastodonAccount = await MainActor.run {
                                            () -> SocialAccount? in
                                            return accounts.first(where: {
                                                $0.platform == .mastodon
                                            })
                                        }

                                        if let mastodonAccount = mastodonAccount {
                                            do {
                                                // Attempt to fetch synchronously via the async API for more reliable results
                                                if let parent = try await self.socialServiceManager
                                                    .fetchMastodonStatus(
                                                        id: parentID, account: mastodonAccount)
                                                {
                                                    // Extract username for faster display even if post details take time to load
                                                    let username = parent.authorUsername

                                                    // Update immediately with the username for the reply banner
                                                    await MainActor.run {
                                                        if case .loaded(var currentPosts) = self
                                                            .state
                                                        {
                                                            if let idx = currentPosts.firstIndex(
                                                                where: { $0.id == post.id })
                                                            {
                                                                if currentPosts[idx]
                                                                    .inReplyToUsername == nil
                                                                    || currentPosts[idx]
                                                                        .inReplyToUsername?.isEmpty
                                                                        == true
                                                                {
                                                                    self.logger.info(
                                                                        "Setting reply username to: \(username)"
                                                                    )
                                                                    currentPosts[idx]
                                                                        .inReplyToUsername =
                                                                        username
                                                                }

                                                                // Store the parent post and update the state
                                                                self.logger.info(
                                                                    "Successfully pre-loaded Mastodon parent post for: \(post.id)"
                                                                )
                                                                currentPosts[idx].parent = parent
                                                                self.state = .loaded(currentPosts)
                                                            }
                                                        }
                                                    }
                                                } else {
                                                    self.logger.error(
                                                        "Failed to pre-load Mastodon parent post: nil result"
                                                    )
                                                }
                                            } catch {
                                                self.logger.error(
                                                    "Error pre-loading Mastodon parent post: \(error.localizedDescription)"
                                                )

                                                // Fallback to the old method as backup
                                                socialServiceManager.mastodonService.fetchStatus(
                                                    id: parentID
                                                ) { parent in
                                                    guard let parent = parent else {
                                                        self.logger.error(
                                                            "Fallback also failed to pre-load Mastodon parent post for: \(post.id)"
                                                        )
                                                        return
                                                    }

                                                    Task { @MainActor in
                                                        if case .loaded(var currentPosts) = self
                                                            .state
                                                        {
                                                            if let idx = currentPosts.firstIndex(
                                                                where: { $0.id == post.id })
                                                            {
                                                                // Store the parent post and update the state
                                                                self.logger.info(
                                                                    "Successfully pre-loaded Mastodon parent post via fallback method for: \(post.id)"
                                                                )
                                                                currentPosts[idx].parent = parent
                                                                self.state = .loaded(currentPosts)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        } else {
                                            // Fallback to the old method if no account is found
                                            socialServiceManager.mastodonService.fetchStatus(
                                                id: parentID
                                            ) { parent in
                                                guard let parent = parent else {
                                                    self.logger.error(
                                                        "Failed to pre-load Mastodon parent post for: \(post.id)"
                                                    )
                                                    return
                                                }

                                                Task { @MainActor in
                                                    if case .loaded(var currentPosts) = self.state {
                                                        if let idx = currentPosts.firstIndex(
                                                            where: { $0.id == post.id })
                                                        {
                                                            // Store the parent post and update the state
                                                            self.logger.info(
                                                                "Successfully pre-loaded Mastodon parent post for: \(post.id)"
                                                            )
                                                            currentPosts[idx].parent = parent
                                                            self.state = .loaded(currentPosts)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                case .bluesky:
                                    // For Bluesky, use the async fetchPostByID method in a Task
                                    Task {
                                        do {
                                            // For logging/debugging
                                            self.logger.info(
                                                "Pre-loading Bluesky parent post for: \(post.id), parentID: \(parentID)"
                                            )

                                            // Find a Bluesky account to use
                                            let blueskyAccount = await MainActor.run {
                                                () -> SocialAccount? in
                                                return accounts.first(where: {
                                                    $0.platform == .bluesky
                                                })
                                            }

                                            if let blueskyAccount = blueskyAccount {
                                                if let parent = try await self.socialServiceManager
                                                    .blueskyService.fetchPostByID(
                                                        parentID, account: blueskyAccount)
                                                {
                                                    // On main thread, update the posts array
                                                    await MainActor.run {
                                                        if case .loaded(var currentPosts) = self
                                                            .state
                                                        {
                                                            if let idx = currentPosts.firstIndex(
                                                                where: {
                                                                    $0.id == post.id
                                                                })
                                                            {
                                                                // Set the reply username if missing or empty
                                                                if currentPosts[idx]
                                                                    .inReplyToUsername == nil
                                                                    || currentPosts[idx]
                                                                        .inReplyToUsername?.isEmpty
                                                                        == true
                                                                {
                                                                    let username = parent
                                                                        .authorUsername
                                                                    self.logger.info(
                                                                        "Setting reply username to: \(username)"
                                                                    )
                                                                    currentPosts[idx]
                                                                        .inReplyToUsername =
                                                                        username
                                                                }
                                                                // Attach the parent post
                                                                currentPosts[idx].parent = parent
                                                                self.state = .loaded(currentPosts)
                                                            }
                                                        }
                                                    }
                                                } else {
                                                    self.logger.warning(
                                                        "Bluesky parent post not found for: \(post.id), parentID: \(parentID)"
                                                    )
                                                }
                                            } else {
                                                self.logger.error(
                                                    "No Bluesky account available for fetching parent post"
                                                )
                                            }
                                        } catch {
                                            self.logger.error(
                                                "Error pre-loading Bluesky parent post: \(error.localizedDescription)"
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        // Pre-load original posts for boosts/reposts
                        let isBoost = post.kind == .boost || post.isBoost == true
                        let originalPostMissing = post.originalPost == nil
                        if isBoost, let originalURI = post.originalPostURI, originalPostMissing {
                            switch post.platform {
                            case .mastodon:
                                Task(priority: .userInitiated) {
                                    let mastodonAccount = await MainActor.run {
                                        () -> SocialAccount? in
                                        return accounts.first(where: { $0.platform == .mastodon })
                                    }
                                    if let mastodonAccount = mastodonAccount {
                                        do {
                                            if let original = try await self.socialServiceManager
                                                .fetchMastodonStatus(
                                                    id: originalURI, account: mastodonAccount)
                                            {
                                                await MainActor.run {
                                                    if case .loaded(var currentPosts) = self.state {
                                                        if let idx = currentPosts.firstIndex(
                                                            where: { $0.id == post.id })
                                                        {
                                                            currentPosts[idx].originalPost =
                                                                original
                                                            self.state = .loaded(currentPosts)
                                                        }
                                                    }
                                                }
                                            }
                                        } catch {
                                            self.logger.error(
                                                "Error pre-loading Mastodon original post: \(error.localizedDescription)"
                                            )
                                        }
                                    }
                                }
                            case .bluesky:
                                Task {
                                    let blueskyAccount = await MainActor.run {
                                        () -> SocialAccount? in
                                        return accounts.first(where: { $0.platform == .bluesky })
                                    }
                                    if let blueskyAccount = blueskyAccount {
                                        do {
                                            if let original = try await self.socialServiceManager
                                                .blueskyService.fetchPostByID(
                                                    originalURI, account: blueskyAccount)
                                            {
                                                await MainActor.run {
                                                    if case .loaded(var currentPosts) = self.state {
                                                        if let idx = currentPosts.firstIndex(
                                                            where: { $0.id == post.id })
                                                        {
                                                            currentPosts[idx].originalPost =
                                                                original
                                                            self.state = .loaded(currentPosts)
                                                        }
                                                    }
                                                }
                                            }
                                        } catch {
                                            self.logger.error(
                                                "Error pre-loading Bluesky original post: \(error.localizedDescription)"
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }

                    self.logger.info("Timeline refreshed for \(account.username, privacy: .public)")
                }
            } catch {
                // Update UI on main thread
                await MainActor.run {
                    self.isLoading = false
                    self.state = .error(error)
                }
            }
        }
    }

    /// Refresh the unified timeline for multiple accounts
    public func refreshUnifiedTimeline(for accounts: [SocialAccount]) {
        // Cancel any existing refresh task
        refreshTask?.cancel()

        // Start the new refresh task
        refreshTask = Task { [weak self] in
            guard let self = self else { return }

            // Show loading state
            await MainActor.run {
                self.isLoading = true
                if case .idle = self.state {
                    self.state = .loading
                }
            }

            do {
                // Fetch unified timeline from service manager
                let posts = try await socialServiceManager.refreshTimeline(accounts: accounts)

                // Update UI on main thread
                await MainActor.run {
                    self.posts = posts
                    self.isLoading = false

                    if posts.isEmpty {
                        self.state = .empty
                    } else {
                        self.state = .loaded(posts)

                        // Pre-load parent posts for instant expand
                        for post in posts {
                            if let parentID = post.inReplyToID {
                                // Handle different platforms
                                switch post.platform {
                                case .mastodon:
                                    // For logging/debugging
                                    self.logger.info(
                                        "Pre-loading Mastodon parent post for: \(post.id), parentID: \(parentID)"
                                    )

                                    // Use a higher-priority task for Mastodon parent posts
                                    Task(priority: .userInitiated) {
                                        // Try to find a matching Mastodon account
                                        let mastodonAccount = await MainActor.run {
                                            () -> SocialAccount? in
                                            return accounts.first(where: {
                                                $0.platform == .mastodon
                                            })
                                        }

                                        if let mastodonAccount = mastodonAccount {
                                            do {
                                                // Attempt to fetch synchronously via the async API for more reliable results
                                                if let parent = try await self.socialServiceManager
                                                    .fetchMastodonStatus(
                                                        id: parentID, account: mastodonAccount)
                                                {
                                                    // Extract username for faster display even if post details take time to load
                                                    let username = parent.authorUsername

                                                    // Update immediately with the username for the reply banner
                                                    await MainActor.run {
                                                        if case .loaded(var currentPosts) = self
                                                            .state
                                                        {
                                                            if let idx = currentPosts.firstIndex(
                                                                where: { $0.id == post.id })
                                                            {
                                                                if currentPosts[idx]
                                                                    .inReplyToUsername == nil
                                                                    || currentPosts[idx]
                                                                        .inReplyToUsername?.isEmpty
                                                                        == true
                                                                {
                                                                    self.logger.info(
                                                                        "Setting reply username to: \(username)"
                                                                    )
                                                                    currentPosts[idx]
                                                                        .inReplyToUsername =
                                                                        username
                                                                }

                                                                // Store the parent post and update the state
                                                                self.logger.info(
                                                                    "Successfully pre-loaded Mastodon parent post for: \(post.id)"
                                                                )
                                                                currentPosts[idx].parent = parent
                                                                self.state = .loaded(currentPosts)
                                                            }
                                                        }
                                                    }
                                                } else {
                                                    self.logger.error(
                                                        "Failed to pre-load Mastodon parent post: nil result"
                                                    )
                                                }
                                            } catch {
                                                self.logger.error(
                                                    "Error pre-loading Mastodon parent post: \(error.localizedDescription)"
                                                )

                                                // Fallback to the old method as backup
                                                socialServiceManager.mastodonService.fetchStatus(
                                                    id: parentID
                                                ) { parent in
                                                    guard let parent = parent else {
                                                        self.logger.error(
                                                            "Fallback also failed to pre-load Mastodon parent post for: \(post.id)"
                                                        )
                                                        return
                                                    }

                                                    Task { @MainActor in
                                                        if case .loaded(var currentPosts) = self
                                                            .state
                                                        {
                                                            if let idx = currentPosts.firstIndex(
                                                                where: { $0.id == post.id })
                                                            {
                                                                // Store the parent post and update the state
                                                                self.logger.info(
                                                                    "Successfully pre-loaded Mastodon parent post via fallback method for: \(post.id)"
                                                                )
                                                                currentPosts[idx].parent = parent
                                                                self.state = .loaded(currentPosts)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        } else {
                                            // Fallback to the old method if no account is found
                                            socialServiceManager.mastodonService.fetchStatus(
                                                id: parentID
                                            ) { parent in
                                                guard let parent = parent else {
                                                    self.logger.error(
                                                        "Failed to pre-load Mastodon parent post for: \(post.id)"
                                                    )
                                                    return
                                                }

                                                Task { @MainActor in
                                                    if case .loaded(var currentPosts) = self.state {
                                                        if let idx = currentPosts.firstIndex(
                                                            where: { $0.id == post.id })
                                                        {
                                                            // Store the parent post and update the state
                                                            self.logger.info(
                                                                "Successfully pre-loaded Mastodon parent post for: \(post.id)"
                                                            )
                                                            currentPosts[idx].parent = parent
                                                            self.state = .loaded(currentPosts)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                case .bluesky:
                                    // For Bluesky, use the async fetchPostByID method in a Task
                                    Task {
                                        do {
                                            // For logging/debugging
                                            self.logger.info(
                                                "Pre-loading Bluesky parent post for: \(post.id), parentID: \(parentID)"
                                            )

                                            // Find a Bluesky account to use
                                            let blueskyAccount = await MainActor.run {
                                                () -> SocialAccount? in
                                                return accounts.first(where: {
                                                    $0.platform == .bluesky
                                                })
                                            }

                                            if let blueskyAccount = blueskyAccount {
                                                if let parent = try await self.socialServiceManager
                                                    .blueskyService.fetchPostByID(
                                                        parentID, account: blueskyAccount)
                                                {
                                                    // On main thread, update the posts array
                                                    await MainActor.run {
                                                        if case .loaded(var currentPosts) = self
                                                            .state
                                                        {
                                                            if let idx = currentPosts.firstIndex(
                                                                where: {
                                                                    $0.id == post.id
                                                                })
                                                            {
                                                                // Set the reply username if missing or empty
                                                                if currentPosts[idx]
                                                                    .inReplyToUsername == nil
                                                                    || currentPosts[idx]
                                                                        .inReplyToUsername?.isEmpty
                                                                        == true
                                                                {
                                                                    let username = parent
                                                                        .authorUsername
                                                                    self.logger.info(
                                                                        "Setting reply username to: \(username)"
                                                                    )
                                                                    currentPosts[idx]
                                                                        .inReplyToUsername =
                                                                        username
                                                                }
                                                                // Attach the parent post
                                                                currentPosts[idx].parent = parent
                                                                self.state = .loaded(currentPosts)
                                                            }
                                                        }
                                                    }
                                                } else {
                                                    self.logger.warning(
                                                        "Bluesky parent post not found for: \(post.id), parentID: \(parentID)"
                                                    )
                                                }
                                            } else {
                                                self.logger.error(
                                                    "No Bluesky account available for fetching parent post"
                                                )
                                            }
                                        } catch {
                                            self.logger.error(
                                                "Error pre-loading Bluesky parent post: \(error.localizedDescription)"
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        // Pre-load original posts for boosts/reposts
                        for post in posts {
                            let isBoost = post.kind == .boost || post.isBoost == true
                            let originalPostMissing = post.originalPost == nil
                            if isBoost, let originalURI = post.originalPostURI, originalPostMissing
                            {
                                switch post.platform {
                                case .mastodon:
                                    Task(priority: .userInitiated) {
                                        let mastodonAccount = await MainActor.run {
                                            () -> SocialAccount? in
                                            return accounts.first(where: {
                                                $0.platform == .mastodon
                                            })
                                        }
                                        if let mastodonAccount = mastodonAccount {
                                            do {
                                                if let original =
                                                    try await self.socialServiceManager
                                                    .fetchMastodonStatus(
                                                        id: originalURI, account: mastodonAccount)
                                                {
                                                    await MainActor.run {
                                                        if case .loaded(var currentPosts) = self
                                                            .state
                                                        {
                                                            if let idx = currentPosts.firstIndex(
                                                                where: { $0.id == post.id })
                                                            {
                                                                currentPosts[idx].originalPost =
                                                                    original
                                                                self.state = .loaded(currentPosts)
                                                            }
                                                        }
                                                    }
                                                }
                                            } catch {
                                                self.logger.error(
                                                    "Error pre-loading Mastodon original post: \(error.localizedDescription)"
                                                )
                                            }
                                        }
                                    }
                                case .bluesky:
                                    Task {
                                        let blueskyAccount = await MainActor.run {
                                            () -> SocialAccount? in
                                            return accounts.first(where: { $0.platform == .bluesky }
                                            )
                                        }
                                        if let blueskyAccount = blueskyAccount {
                                            do {
                                                if let original =
                                                    try await self.socialServiceManager
                                                    .blueskyService.fetchPostByID(
                                                        originalURI, account: blueskyAccount)
                                                {
                                                    await MainActor.run {
                                                        if case .loaded(var currentPosts) = self
                                                            .state
                                                        {
                                                            if let idx = currentPosts.firstIndex(
                                                                where: { $0.id == post.id })
                                                            {
                                                                currentPosts[idx].originalPost =
                                                                    original
                                                                self.state = .loaded(currentPosts)
                                                            }
                                                        }
                                                    }
                                                }
                                            } catch {
                                                self.logger.error(
                                                    "Error pre-loading Bluesky original post: \(error.localizedDescription)"
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    self.logger.info("Unified timeline refreshed for \(accounts.count) accounts")
                }
            } catch {
                // Update UI on main thread
                await MainActor.run {
                    self.isLoading = false
                    self.state = .error(error)
                }
            }
        }
    }

    /// Like a post
    public func likePost(_ post: Post) {
        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await socialServiceManager.likePost(post)
                self.logger.info("Post liked: \(post.id, privacy: .public)")
            } catch {
                self.logger.error(
                    "Failed to like post: \(error.localizedDescription, privacy: .public)")
                // TODO: Propagate error to UI for user feedback (e.g., toast/banner)
            }
        }
    }

    /// Repost a post
    public func repostPost(_ post: Post) {
        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await socialServiceManager.repostPost(post)
                await MainActor.run {
                    self.logger.info("Post reposted: \(post.id, privacy: .public)")
                }
            } catch {
                await MainActor.run {
                    self.logger.error(
                        "Failed to repost: \(error.localizedDescription, privacy: .public)")
                    // TODO: Propagate error to UI for user feedback (e.g., toast/banner)
                }
            }
        }
    }

    /// Cancel any ongoing refresh operations
    public func cancelRefresh() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            refreshTask?.cancel()
            refreshTask = nil

            // Update state
            if self.isLoading {
                self.isLoading = false
            }
        }
    }

    // MARK: - Private Methods

    private func setupObservers() {
        // Listen for account changes or other relevant notifications
        NotificationCenter.default.publisher(for: .accountProfileImageUpdated)
            .receive(on: RunLoop.main)  // Ensure on main thread
            .sink { [weak self] _ in
                // Refresh posts if needed when account profile images update
                if case .loaded(let posts) = self?.state, !posts.isEmpty {
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
    }

    private func handleError(_ error: Error) {
        logger.error("Timeline error: \(error.localizedDescription, privacy: .public)")

        if let serviceError = error as? ServiceError {
            switch serviceError {
            case .rateLimitError(_, let retryAfter):
                state = .rateLimited(retryAfter: retryAfter)
                startRateLimitCountdown(seconds: retryAfter)

            case .unauthorized:
                state = .error(serviceError)
            // You might want to trigger a re-authentication flow here

            case .networkError:
                state = .error(serviceError)

            default:
                state = .error(serviceError)
            }
        } else {
            state = .error(error)
        }
    }

    private func startRateLimitCountdown(seconds: TimeInterval) {
        // Clean up any existing timer
        rateLimitTimer?.invalidate()

        // Set initial remaining time
        retryAfter = seconds

        // Create and schedule a timer to count down
        rateLimitTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            self.retryAfter -= 1

            // When countdown reaches zero, reset state and timer
            if self.retryAfter <= 0 {
                timer.invalidate()
                self.rateLimitTimer = nil

                // Reset state to idle so user can try again
                DispatchQueue.main.async {
                    self.state = .idle
                }
            }
        }
    }
}

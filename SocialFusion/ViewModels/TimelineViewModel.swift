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
    private let serialQueue = DispatchQueue(label: "TimelineViewModel.serial", qos: .userInitiated)
    private var refreshTask: Task<Void, Never>?

    public init(socialServiceManager: SocialServiceManager = .shared) {
        self.socialServiceManager = socialServiceManager
        setupObservers()
    }

    deinit {
        refreshTask?.cancel()
        cancellables.removeAll()
    }

    // MARK: - Public Methods

    /// Refresh the timeline for a specific account
    public func refreshTimeline(for account: SocialAccount) {
        // Cancel any existing refresh task
        refreshTask?.cancel()

        // Start the new refresh task
        refreshTask = Task { [weak self] in
            guard let self = self else { return }

            // Thread-safe loading state update
            await self.safeStateUpdate {
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

                        // Pre-load parent posts for smooth reply banner expansion
                        // Use deferred state updates to prevent AttributeGraph cycles
                        for post in posts {
                            if let parentID = post.inReplyToID {
                                // Handle different platforms
                                switch post.platform {
                                case .mastodon:
                                    Task(priority: .userInitiated) {
                                        // Find a matching Mastodon account
                                        let mastodonAccount = await MainActor.run {
                                            return accounts.first(where: {
                                                $0.platform == .mastodon
                                            })
                                        }

                                        if let mastodonAccount = mastodonAccount {
                                            do {
                                                if let parent = try await self.socialServiceManager
                                                    .fetchMastodonStatus(
                                                        id: parentID, account: mastodonAccount)
                                                {
                                                    // Defer the state update to the next runloop cycle
                                                    // This prevents "Modifying state during view update" errors
                                                    DispatchQueue.main.async {
                                                        self.updatePost(withId: post.id) {
                                                            newPost in
                                                            newPost.parent = parent
                                                            if newPost.inReplyToUsername?.isEmpty
                                                                != false
                                                            {
                                                                newPost.inReplyToUsername =
                                                                    parent.authorUsername
                                                            }
                                                        }
                                                    }
                                                }
                                            } catch {
                                                self.logger.error(
                                                    "Error pre-loading Mastodon parent: \(error.localizedDescription)"
                                                )
                                            }
                                        }
                                    }
                                case .bluesky:
                                    Task(priority: .userInitiated) {
                                        // Find a Bluesky account
                                        let blueskyAccount = await MainActor.run {
                                            return accounts.first(where: { $0.platform == .bluesky }
                                            )
                                        }

                                        if let blueskyAccount = blueskyAccount {
                                            do {
                                                if let parent = try await self.socialServiceManager
                                                    .blueskyService.fetchPostByID(
                                                        parentID, account: blueskyAccount)
                                                {
                                                    // Defer the state update to the next runloop cycle
                                                    DispatchQueue.main.async {
                                                        self.updatePost(withId: post.id) {
                                                            newPost in
                                                            newPost.parent = parent
                                                            if newPost.inReplyToUsername?.isEmpty
                                                                != false
                                                            {
                                                                newPost.inReplyToUsername =
                                                                    parent.authorUsername
                                                            }
                                                        }
                                                    }
                                                }
                                            } catch {
                                                self.logger.error(
                                                    "Error pre-loading Bluesky parent: \(error.localizedDescription)"
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Pre-load original posts for boosts/reposts for smooth expansion
                        for post in posts {
                            let isBoost = post.kind == .boost || post.isBoost == true
                            let originalPostMissing = post.originalPost == nil
                            if isBoost, let originalURI = post.originalPostURI, originalPostMissing
                            {
                                switch post.platform {
                                case .mastodon:
                                    Task(priority: .userInitiated) {
                                        let mastodonAccount = await MainActor.run {
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
                                                    DispatchQueue.main.async {
                                                        self.updatePost(withId: post.id) {
                                                            newPost in
                                                            newPost.originalPost = original
                                                        }
                                                    }
                                                }
                                            } catch {
                                                self.logger.error(
                                                    "Error pre-loading Mastodon original: \(error.localizedDescription)"
                                                )
                                            }
                                        }
                                    }
                                case .bluesky:
                                    Task(priority: .userInitiated) {
                                        let blueskyAccount = await MainActor.run {
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
                                                    DispatchQueue.main.async {
                                                        self.updatePost(withId: post.id) {
                                                            newPost in
                                                            newPost.originalPost = original
                                                        }
                                                    }
                                                }
                                            } catch {
                                                self.logger.error(
                                                    "Error pre-loading Bluesky original: \(error.localizedDescription)"
                                                )
                                            }
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

                        // Pre-load parent posts for smooth reply banner expansion
                        // Use deferred state updates to prevent AttributeGraph cycles
                        for post in posts {
                            if let parentID = post.inReplyToID {
                                // Handle different platforms
                                switch post.platform {
                                case .mastodon:
                                    Task(priority: .userInitiated) {
                                        // Find a matching Mastodon account
                                        let mastodonAccount = await MainActor.run {
                                            return accounts.first(where: {
                                                $0.platform == .mastodon
                                            })
                                        }

                                        if let mastodonAccount = mastodonAccount {
                                            do {
                                                if let parent = try await self.socialServiceManager
                                                    .fetchMastodonStatus(
                                                        id: parentID, account: mastodonAccount)
                                                {
                                                    // Defer the state update to the next runloop cycle
                                                    // This prevents "Modifying state during view update" errors
                                                    DispatchQueue.main.async {
                                                        self.updatePost(withId: post.id) {
                                                            newPost in
                                                            newPost.parent = parent
                                                            if newPost.inReplyToUsername?.isEmpty
                                                                != false
                                                            {
                                                                newPost.inReplyToUsername =
                                                                    parent.authorUsername
                                                            }
                                                        }
                                                    }
                                                }
                                            } catch {
                                                self.logger.error(
                                                    "Error pre-loading Mastodon parent: \(error.localizedDescription)"
                                                )
                                            }
                                        }
                                    }
                                case .bluesky:
                                    Task(priority: .userInitiated) {
                                        // Find a Bluesky account
                                        let blueskyAccount = await MainActor.run {
                                            return accounts.first(where: { $0.platform == .bluesky }
                                            )
                                        }

                                        if let blueskyAccount = blueskyAccount {
                                            do {
                                                if let parent = try await self.socialServiceManager
                                                    .blueskyService.fetchPostByID(
                                                        parentID, account: blueskyAccount)
                                                {
                                                    // Defer the state update to the next runloop cycle
                                                    DispatchQueue.main.async {
                                                        self.updatePost(withId: post.id) {
                                                            newPost in
                                                            newPost.parent = parent
                                                            if newPost.inReplyToUsername?.isEmpty
                                                                != false
                                                            {
                                                                newPost.inReplyToUsername =
                                                                    parent.authorUsername
                                                            }
                                                        }
                                                    }
                                                }
                                            } catch {
                                                self.logger.error(
                                                    "Error pre-loading Bluesky parent: \(error.localizedDescription)"
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Pre-load original posts for boosts/reposts for smooth expansion
                        for post in posts {
                            let isBoost = post.kind == .boost || post.isBoost == true
                            let originalPostMissing = post.originalPost == nil
                            if isBoost, let originalURI = post.originalPostURI, originalPostMissing
                            {
                                switch post.platform {
                                case .mastodon:
                                    Task(priority: .userInitiated) {
                                        let mastodonAccount = await MainActor.run {
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
                                                    DispatchQueue.main.async {
                                                        self.updatePost(withId: post.id) {
                                                            newPost in
                                                            newPost.originalPost = original
                                                        }
                                                    }
                                                }
                                            } catch {
                                                self.logger.error(
                                                    "Error pre-loading Mastodon original: \(error.localizedDescription)"
                                                )
                                            }
                                        }
                                    }
                                case .bluesky:
                                    Task(priority: .userInitiated) {
                                        let blueskyAccount = await MainActor.run {
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
                                                    DispatchQueue.main.async {
                                                        self.updatePost(withId: post.id) {
                                                            newPost in
                                                            newPost.originalPost = original
                                                        }
                                                    }
                                                }
                                            } catch {
                                                self.logger.error(
                                                    "Error pre-loading Bluesky original: \(error.localizedDescription)"
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

    /// Safely update a specific post in the timeline without causing AttributeGraph cycles
    @MainActor
    private func updatePost(withId postId: String, using updateBlock: (inout Post) -> Void) {
        if case .loaded(let currentPosts) = self.state {
            let updatedPosts = currentPosts.map { existingPost in
                if existingPost.id == postId {
                    var newPost = existingPost
                    updateBlock(&newPost)
                    return newPost
                }
                return existingPost
            }
            self.state = .loaded(updatedPosts)
        }
    }

    /// Thread-safe state update method to prevent concurrent access crashes
    @MainActor
    private func safeStateUpdate(_ update: @escaping () -> Void) async {
        guard !Task.isCancelled else { return }
        update()
    }

    private func setupObservers() {
        // Listen for account changes or other relevant notifications
        NotificationCenter.default.publisher(for: .accountProfileImageUpdated)
            .receive(on: RunLoop.main)  // Ensure on main thread
            .sink { [weak self] _ in
                // Instead of manually triggering objectWillChange (which can cause AttributeGraph cycles),
                // use a deferred state update to refresh the UI safely
                if case .loaded(let posts) = self?.state, !posts.isEmpty {
                    // Defer the state refresh to prevent "Modifying state during view update" errors
                    DispatchQueue.main.async {
                        // Simply reassign the same state to trigger a UI refresh
                        // This is safer than manual objectWillChange.send()
                        self?.state = .loaded(posts)
                    }
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

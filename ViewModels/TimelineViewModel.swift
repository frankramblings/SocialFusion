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
public class TimelineViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published public var state: TimelineState = .idle
    @Published public var isRefreshing: Bool = false
    @Published public var lastRefreshDate: Date?
    @Published var postIDs: [String] = []

    // MARK: - Account(s) Ownership
    public let accounts: [SocialAccount]

    // MARK: - Private Properties

    private let logger = Logger(subsystem: "com.socialfusion", category: "TimelineViewModel")
    private let socialServiceManager = SocialServiceManager.shared
    private var refreshTask: Task<Void, Never>?
    private var rateLimitTimer: Timer?
    private var rateLimitSecondsRemaining: TimeInterval = 0

    // Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init(accounts: [SocialAccount]) {
        self.accounts = accounts
        setupObservers()
    }

    // MARK: - Public Methods

    /// Refresh the timeline for a specific account
    public func refreshTimeline(for account: SocialAccount) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self = self else { return }

            await MainActor.run {
                self.isRefreshing = true
                if case .idle = self.state {
                    self.state = .loading
                }
            }

            do {
                let posts = try await self.socialServiceManager.refreshTimeline(accounts: [account])
                await MainActor.run {
                    self.lastRefreshDate = Date()
                    self.isRefreshing = false
                    if posts.isEmpty {
                        self.state = .empty
                    } else {
                        self.state = .loaded(posts)
                        // Queue background hydration without immediate state updates
                        self.hydratePostRelationshipsInBackground(posts: posts)
                    }
                    self.logger.info("Timeline refreshed for \(account.username, privacy: .public)")
                }
            } catch {
                await MainActor.run {
                    self.isRefreshing = false
                    self.state = .error(error)
                }
            }
        }
    }

    /// Refresh the unified timeline for multiple accounts
    public func refreshUnifiedTimeline() {
        // Prevent multiple simultaneous refreshes
        guard refreshTask == nil || refreshTask?.isCancelled == true else {
            logger.info("Timeline refresh already in progress, skipping")
            return
        }

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self = self else { return }
            await MainActor.run {
                self.isRefreshing = true
                if case .idle = self.state {
                    self.state = .loading
                }
            }
            do {
                let posts = try await self.socialServiceManager.refreshTimeline(
                    accounts: self.accounts)
                await MainActor.run {
                    self.lastRefreshDate = Date()
                    self.isRefreshing = false
                    if posts.isEmpty {
                        self.state = .empty
                    } else {
                        self.state = .loaded(posts)
                        // Queue background hydration without immediate state updates
                        self.hydratePostRelationshipsInBackground(posts: posts)
                    }
                    self.logger.info(
                        "Unified timeline refreshed for \(self.accounts.count) accounts")
                }
            } catch {
                await MainActor.run {
                    self.isRefreshing = false
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
            if isRefreshing {
                isRefreshing = false
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
        rateLimitSecondsRemaining = seconds

        // Create and schedule a timer to count down
        rateLimitTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            self.rateLimitSecondsRemaining -= 1

            // When countdown reaches zero, reset state and timer
            if self.rateLimitSecondsRemaining <= 0 {
                timer.invalidate()
                self.rateLimitTimer = nil

                // Reset state to idle so user can try again
                DispatchQueue.main.async {
                    self.state = .idle
                }
            }
        }
    }

    func fetchTimeline() async {
        do {
            let posts = try await socialServiceManager.refreshTimeline(accounts: self.accounts)
            await MainActor.run {
                PostStore.shared.upsert(posts)
                postIDs = posts.map { $0.id }
            }
        } catch {
            await MainActor.run {
                PostStore.shared.error = SocialFusionError(
                    message: "Failed to fetch timeline: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private Background Hydration

    /// Hydrate post relationships in background without causing state mutation cycles
    private func hydratePostRelationshipsInBackground(posts: [Post]) {
        Task.detached { [weak self] in
            guard let self = self else { return }

            // Collect all parent posts that need hydration
            var parentsToFetch: [(postId: String, parentId: String, platform: SocialPlatform)] = []
            var originalsToFetch: [(postId: String, originalId: String, platform: SocialPlatform)] =
                []

            for post in posts {
                // Collect missing parent posts
                if let parentID = post.inReplyToID, post.parent == nil {
                    parentsToFetch.append(
                        (postId: post.id, parentId: parentID, platform: post.platform))
                }

                // Collect missing original posts for reposts
                if post.isReposted, let originalId = post.originalPost?.id, post.originalPost == nil
                {
                    originalsToFetch.append(
                        (postId: post.id, originalId: originalId, platform: post.platform))
                }
            }

            // Batch fetch parent posts
            await self.batchFetchParentPosts(parentsToFetch)

            // Batch fetch original posts
            await self.batchFetchOriginalPosts(originalsToFetch)
        }
    }

    private func batchFetchParentPosts(
        _ fetchRequests: [(postId: String, parentId: String, platform: SocialPlatform)]
    ) async {
        guard !fetchRequests.isEmpty else { return }

        var hydratedPosts: [String: Post] = [:]

        // Fetch all parent posts concurrently
        await withTaskGroup(of: (String, Post?).self) { group in
            for request in fetchRequests {
                group.addTask { [weak self] in
                    guard let self = self else { return (request.postId, nil) }

                    do {
                        let parent: Post?
                        switch request.platform {
                        case .mastodon:
                            if let account = self.accounts.first(where: { $0.platform == .mastodon }
                            ) {
                                parent = try await self.socialServiceManager.fetchMastodonStatus(
                                    id: request.parentId, account: account)
                            } else {
                                parent = nil
                            }
                        case .bluesky:
                            parent = try await self.socialServiceManager.fetchBlueskyPostByID(
                                request.parentId)
                        }
                        return (request.postId, parent)
                    } catch {
                        self.logger.warning(
                            "Failed to fetch parent post \(request.parentId): \(error)")
                        return (request.postId, nil)
                    }
                }
            }

            for await (postId, parent) in group {
                if let parent = parent {
                    hydratedPosts[postId] = parent
                }
            }
        }

        // Apply all updates in a single state change
        await MainActor.run {
            if case .loaded(var currentPosts) = self.state, !hydratedPosts.isEmpty {
                for i in 0..<currentPosts.count {
                    if let parent = hydratedPosts[currentPosts[i].id] {
                        currentPosts[i].parent = parent
                        if currentPosts[i].inReplyToUsername?.isEmpty != false {
                            currentPosts[i].inReplyToUsername = parent.authorUsername
                        }
                    }
                }
                self.state = .loaded(currentPosts)
                self.logger.info("Batch updated \(hydratedPosts.count) parent posts")
            }
        }
    }

    private func batchFetchOriginalPosts(
        _ fetchRequests: [(postId: String, originalId: String, platform: SocialPlatform)]
    ) async {
        guard !fetchRequests.isEmpty else { return }

        var hydratedPosts: [String: Post] = [:]

        // Fetch all original posts concurrently
        await withTaskGroup(of: (String, Post?).self) { group in
            for request in fetchRequests {
                group.addTask { [weak self] in
                    guard let self = self else { return (request.postId, nil) }

                    do {
                        let original: Post?
                        switch request.platform {
                        case .mastodon:
                            if let account = self.accounts.first(where: { $0.platform == .mastodon }
                            ) {
                                original = try await self.socialServiceManager.fetchMastodonStatus(
                                    id: request.originalId, account: account)
                            } else {
                                original = nil
                            }
                        case .bluesky:
                            original = try await self.socialServiceManager.fetchBlueskyPostByID(
                                request.originalId)
                        }
                        return (request.postId, original)
                    } catch {
                        self.logger.warning(
                            "Failed to fetch original post \(request.originalId): \(error)")
                        return (request.postId, nil)
                    }
                }
            }

            for await (postId, original) in group {
                if let original = original {
                    hydratedPosts[postId] = original
                }
            }
        }

        // Apply all updates in a single state change
        await MainActor.run {
            if case .loaded(var currentPosts) = self.state, !hydratedPosts.isEmpty {
                for i in 0..<currentPosts.count {
                    if let original = hydratedPosts[currentPosts[i].id] {
                        currentPosts[i].originalPost = original
                    }
                }
                self.state = .loaded(currentPosts)
                self.logger.info("Batch updated \(hydratedPosts.count) original posts")
            }
        }
    }
}

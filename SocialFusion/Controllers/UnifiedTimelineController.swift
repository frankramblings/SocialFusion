import Combine
import Foundation
import SwiftUI

/// Single source of truth for all timeline functionality
/// Consolidates multiple competing implementations into one reliable system
@MainActor
final class UnifiedTimelineController: ObservableObject {

    // MARK: - Published State (Single Source of Truth)

    @Published private(set) var posts: [Post] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?
    @Published private(set) var lastRefreshDate: Date?
    @Published private(set) var unreadCount: Int = 0

    // MARK: - Private Properties

    private let serviceManager: SocialServiceManager
    private var refreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // Prevent multiple refresh attempts
    private var isRefreshing = false
    private var lastRefreshTime = Date.distantPast
    private let minRefreshInterval: TimeInterval = 2.0

    // MARK: - Initialization

    init(serviceManager: SocialServiceManager) {
        self.serviceManager = serviceManager
        setupObservers()
        print("🎯 UnifiedTimelineController: Initialized as single source of truth")
    }

    // Convenience initializer for shared instance - must be called from MainActor context
    convenience init() {
        self.init(serviceManager: SocialServiceManager.shared)
    }

    deinit {
        refreshTask?.cancel()
        cancellables.removeAll()
    }

    // MARK: - Private Setup

    private func setupObservers() {
        // Listen to serviceManager's unifiedTimeline changes
        serviceManager.$unifiedTimeline
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPosts in
                guard let self = self else { return }
                self.posts = newPosts
                print(
                    "🎯 UnifiedTimelineController: Received \(newPosts.count) posts from serviceManager"
                )
            }
            .store(in: &cancellables)

        // Listen to loading state changes
        serviceManager.$isLoadingTimeline
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                guard let self = self else { return }
                self.isLoading = isLoading
            }
            .store(in: &cancellables)

        // Listen to error changes
        serviceManager.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                guard let self = self else { return }
                self.error = error
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Interface

    /// Refresh timeline with intelligent deduplication
    func refreshTimeline(force: Bool = false) async {
        let now = Date()

        // Prevent rapid refresh attempts
        if !force && isRefreshing {
            print("🎯 UnifiedTimelineController: Refresh already in progress, skipping")
            return
        }

        if !force && now.timeIntervalSince(lastRefreshTime) < minRefreshInterval {
            print("🎯 UnifiedTimelineController: Refresh too soon, skipping")
            return
        }

        isRefreshing = true
        lastRefreshTime = now

        defer {
            isRefreshing = false
        }

        print("🎯 UnifiedTimelineController: Starting refresh (force: \(force))")

        // Cancel any existing refresh
        refreshTask?.cancel()

        refreshTask = Task {
            do {
                await serviceManager.ensureTimelineRefresh(force: force)
                await MainActor.run {
                    self.lastRefreshDate = Date()
                    print("🎯 UnifiedTimelineController: Refresh completed successfully")
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    print("🎯 UnifiedTimelineController: Refresh failed: \(error)")
                }
            }
        }

        await refreshTask?.value
    }

    /// Ensure timeline is loaded when view appears
    func ensureTimelineLoaded() async {
        if posts.isEmpty && !isLoading {
            print("🎯 UnifiedTimelineController: Timeline empty, ensuring refresh")
            await refreshTimeline(force: false)
        }
    }

    /// Handle post interactions
    func likePost(_ post: Post) async {
        // Optimistic update
        updatePostOptimistically(post.id) { updatedPost in
            updatedPost.isLiked.toggle()
            updatedPost.likeCount += updatedPost.isLiked ? 1 : -1
        }

        // Server update
        do {
            if post.isLiked {
                _ = try await serviceManager.unlikePost(post)
            } else {
                _ = try await serviceManager.likePost(post)
            }
        } catch {
            // Revert optimistic update on error
            updatePostOptimistically(post.id) { updatedPost in
                updatedPost.isLiked = post.isLiked
                updatedPost.likeCount = post.likeCount
            }
            self.error = error
        }
    }

    func repostPost(_ post: Post) async {
        // Optimistic update
        updatePostOptimistically(post.id) { updatedPost in
            updatedPost.isReposted.toggle()
            updatedPost.repostCount += updatedPost.isReposted ? 1 : -1
        }

        // Server update
        do {
            if post.isReposted {
                _ = try await serviceManager.unrepostPost(post)
            } else {
                _ = try await serviceManager.repostPost(post)
            }
        } catch {
            // Revert optimistic update on error
            updatePostOptimistically(post.id) { updatedPost in
                updatedPost.isReposted = post.isReposted
                updatedPost.repostCount = post.repostCount
            }
            self.error = error
        }
    }

    /// Clear any current error
    func clearError() {
        error = nil
    }

    // MARK: - Private Helpers

    private func updatePostOptimistically(_ postId: String, update: (inout Post) -> Void) {
        posts = posts.map { post in
            if post.id == postId {
                var updatedPost = post
                update(&updatedPost)
                return updatedPost
            }
            return post
        }
    }
}

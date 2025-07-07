import Combine
import Foundation
import SwiftUI

/// Unified timeline controller that manages posts from all platforms
/// Implements proper SwiftUI state management to prevent AttributeGraph cycles
@MainActor
class UnifiedTimelineController: ObservableObject {

    // MARK: - Published State (Single Source of Truth)

    @Published private(set) var posts: [Post] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error? = nil
    @Published private(set) var lastRefreshDate: Date?
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var isLoadingNextPage: Bool = false
    @Published private(set) var hasNextPage: Bool = true

    // MARK: - Private Properties

    private let serviceManager: SocialServiceManager
    private var cancellables = Set<AnyCancellable>()
    private var isInitialized = false

    // MARK: - Initialization

    init(serviceManager: SocialServiceManager) {
        self.serviceManager = serviceManager
        setupBindings()
    }

    deinit {
        cancellables.removeAll()
    }

    // MARK: - Private Setup

    /// Setup bindings for service manager updates
    private func setupBindings() {
        // Listen to timeline changes from service manager
        serviceManager.$unifiedTimeline
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPosts in
                self?.updatePosts(newPosts)
            }
            .store(in: &cancellables)

        serviceManager.$isLoadingTimeline
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.isLoading = isLoading
            }
            .store(in: &cancellables)

        serviceManager.$timelineError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.error = error
            }
            .store(in: &cancellables)

        serviceManager.$isLoadingNextPage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.isLoadingNextPage = isLoading
            }
            .store(in: &cancellables)

        serviceManager.$hasNextPage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasNext in
                self?.hasNextPage = hasNext
            }
            .store(in: &cancellables)
    }

    /// Update posts with proper state management
    private func updatePosts(_ newPosts: [Post]) {
        // Prevent unnecessary updates that could cause cycles
        guard self.posts != newPosts else { return }

        self.posts = newPosts
        self.lastRefreshDate = Date()

        if !isInitialized {
            isInitialized = true
        }
    }

    // MARK: - Public Interface

    /// Refresh timeline - proper async/await pattern
    func refreshTimeline() {
        // Prevent multiple concurrent refreshes
        guard !isLoading else { return }

        Task {
            do {
                try await serviceManager.refreshTimeline(force: false)
            } catch {
                // Error is automatically propagated via binding
            }
        }
    }

    /// Like or unlike a post - proper event-driven pattern
    func likePost(_ post: Post) {
        // Create intent for the action
        let intent = PostActionIntent.like(post: post)
        processPostAction(intent)
    }

    /// Repost or unrepost a post - proper event-driven pattern
    func repostPost(_ post: Post) {
        // Create intent for the action
        let intent = PostActionIntent.repost(post: post)
        processPostAction(intent)
    }

    /// Clear error state
    func clearError() {
        self.error = nil
    }

    /// Load next page for infinite scroll
    func loadNextPage() async {
        guard !isLoadingNextPage && hasNextPage else { return }
        
        do {
            try await serviceManager.fetchNextPage()
        } catch {
            // Error is automatically propagated via binding
        }
    }

    // MARK: - Private Helpers

    /// Process post actions using proper intent pattern
    private func processPostAction(_ intent: PostActionIntent) {
        // Apply optimistic update
        applyOptimisticUpdate(for: intent)

        // Execute network request
        Task {
            do {
                let updatedPost = try await executePostAction(intent)
                await confirmOptimisticUpdate(for: intent, with: updatedPost)
            } catch {
                await revertOptimisticUpdate(for: intent)
            }
        }
    }

    /// Apply optimistic update for immediate UI feedback
    private func applyOptimisticUpdate(for intent: PostActionIntent) {
        updatePostInPlace(intent.postId) { post in
            switch intent {
            case .like:
                post.isLiked.toggle()
                post.likeCount += post.isLiked ? 1 : -1
            case .repost:
                post.isReposted.toggle()
                post.repostCount += post.isReposted ? 1 : -1
            }
        }
    }

    /// Execute the actual network request
    private func executePostAction(_ intent: PostActionIntent) async throws -> Post {
        switch intent {
        case .like(let post):
            return post.isLiked
                ? try await serviceManager.unlikePost(post)
                : try await serviceManager.likePost(post)
        case .repost(let post):
            return post.isReposted
                ? try await serviceManager.unrepostPost(post)
                : try await serviceManager.repostPost(post)
        }
    }

    /// Confirm optimistic update with server response
    private func confirmOptimisticUpdate(for intent: PostActionIntent, with updatedPost: Post) async
    {
        updatePostInPlace(intent.postId) { post in
            post.isLiked = updatedPost.isLiked
            post.likeCount = updatedPost.likeCount
            post.isReposted = updatedPost.isReposted
            post.repostCount = updatedPost.repostCount
        }
    }

    /// Revert optimistic update on failure
    private func revertOptimisticUpdate(for intent: PostActionIntent) async {
        updatePostInPlace(intent.postId) { post in
            switch intent {
            case .like:
                post.isLiked.toggle()
                post.likeCount += post.isLiked ? 1 : -1
            case .repost:
                post.isReposted.toggle()
                post.repostCount += post.isReposted ? 1 : -1
            }
        }
    }

    /// Update a specific post in place
    private func updatePostInPlace(_ postId: String, update: (inout Post) -> Void) {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return }
        update(&posts[index])
    }
}

// MARK: - Post Action Intent

/// Intent pattern for post actions to prevent AttributeGraph cycles
private enum PostActionIntent {
    case like(post: Post)
    case repost(post: Post)

    var postId: String {
        switch self {
        case .like(let post), .repost(let post):
            return post.id
        }
    }
}

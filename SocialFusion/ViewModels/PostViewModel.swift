import Combine
import Foundation
import SwiftUI

/// A ViewModel for managing a single post
/// Implements proper SwiftUI state management to prevent AttributeGraph cycles
@MainActor
public class PostViewModel: ObservableObject {
    // MARK: - Properties

    public var post: Post
    @Published public var isLiked: Bool
    @Published public var isReposted: Bool
    @Published public var likeCount: Int
    @Published public var repostCount: Int
    @Published public var replyCount: Int
    @Published public var isLoading: Bool = false
    @Published public var error: Error?
    public var quotedPostViewModel: PostViewModel?

    // MARK: - Private Properties

    private let serviceManager: SocialServiceManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init(post: Post, serviceManager: SocialServiceManager) {
        self.post = post
        self.serviceManager = serviceManager

        // Initialize state from post - single source of truth
        self.isLiked = post.isLiked
        self.isReposted = post.isReposted
        self.likeCount = post.likeCount
        self.repostCount = post.repostCount
        self.replyCount = post.replyCount

        // Initialize quoted post view model if needed
        if let quotedPost = post.quotedPost {
            self.quotedPostViewModel = PostViewModel(
                post: quotedPost, serviceManager: serviceManager)
        }
    }

    deinit {
        cancellables.removeAll()
        quotedPostViewModel = nil
    }

    // MARK: - Public Methods

    /// Toggle like/unlike the post - proper intent-based pattern
    public func like() {
        guard !isLoading else { return }

        let intent = PostActionIntent.like(originalState: isLiked, originalCount: likeCount)
        processPostAction(intent)
    }

    /// Toggle repost/unrepost the post - proper intent-based pattern
    public func repost() {
        guard !isLoading else { return }

        let intent = PostActionIntent.repost(originalState: isReposted, originalCount: repostCount)
        processPostAction(intent)
    }

    /// Reply to the post - proper async pattern
    public func reply(content: String) async throws -> Post {
        guard !isLoading else { throw PostError.operationInProgress }

        isLoading = true
        error = nil

        do {
            let reply = try await serviceManager.replyToPost(post, content: content)

            // Update reply count
            self.replyCount += 1
            self.post.replyCount += 1
            self.post.isReplied = true

            self.isLoading = false
            return reply
        } catch {
            self.error = error
            self.isLoading = false
            throw error
        }
    }

    /// Share the post - proper event-driven pattern
    public func share() {
        guard let url = URL(string: post.originalURL) else { return }

        let activityViewController = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )

        // Present the share sheet
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first,
            let rootViewController = window.rootViewController
        {

            // Find the top-most view controller
            var topController = rootViewController
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }

            // Configure for iPad
            if let popoverController = activityViewController.popoverPresentationController {
                popoverController.sourceView = topController.view
                popoverController.sourceRect = CGRect(
                    x: topController.view.bounds.midX,
                    y: topController.view.bounds.midY,
                    width: 0,
                    height: 0
                )
            }

            topController.present(activityViewController, animated: true)
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
                await setError(error)
            }
        }
    }

    /// Apply optimistic update for immediate UI feedback
    private func applyOptimisticUpdate(for intent: PostActionIntent) {
        isLoading = true
        error = nil

        switch intent {
        case .like(let originalState, let originalCount):
            isLiked = !originalState
            likeCount = originalCount + (isLiked ? 1 : -1)
        case .repost(let originalState, let originalCount):
            isReposted = !originalState
            repostCount = originalCount + (isReposted ? 1 : -1)
        }
    }

    /// Execute the actual network request
    private func executePostAction(_ intent: PostActionIntent) async throws -> Post {
        switch intent {
        case .like(let originalState, _):
            return originalState
                ? try await serviceManager.unlikePost(post)
                : try await serviceManager.likePost(post)
        case .repost(let originalState, _):
            return originalState
                ? try await serviceManager.unrepostPost(post)
                : try await serviceManager.repostPost(post)
        }
    }

    /// Confirm optimistic update with server response
    private func confirmOptimisticUpdate(for intent: PostActionIntent, with updatedPost: Post) async
    {
        // Update the post model
        self.post = updatedPost

        // Update published state
        self.isLiked = updatedPost.isLiked
        self.likeCount = updatedPost.likeCount
        self.isReposted = updatedPost.isReposted
        self.repostCount = updatedPost.repostCount
        self.replyCount = updatedPost.replyCount

        self.isLoading = false
    }

    /// Revert optimistic update on failure
    private func revertOptimisticUpdate(for intent: PostActionIntent) async {
        switch intent {
        case .like(let originalState, let originalCount):
            self.isLiked = originalState
            self.likeCount = originalCount
        case .repost(let originalState, let originalCount):
            self.isReposted = originalState
            self.repostCount = originalCount
        }

        self.isLoading = false
    }

    /// Set error state safely
    private func setError(_ error: Error) async {
        self.error = error
    }
}

// MARK: - Post Action Intent

/// Intent pattern for post actions to prevent AttributeGraph cycles
private enum PostActionIntent {
    case like(originalState: Bool, originalCount: Int)
    case repost(originalState: Bool, originalCount: Int)
}

// MARK: - Errors

enum PostError: LocalizedError {
    case operationInProgress

    var errorDescription: String? {
        switch self {
        case .operationInProgress:
            return "An operation is already in progress"
        }
    }
}

// MARK: - Preview Helper

extension PostViewModel {
    static var preview: PostViewModel {
        PostViewModel(
            post: Post(
                id: "preview-1",
                content: "This is a preview post",
                authorName: "Preview User",
                authorUsername: "previewuser",
                authorProfilePictureURL: "https://example.com/avatar.jpg",
                createdAt: Date(),
                platform: .bluesky,
                originalURL: "https://example.com/post/1",
                platformSpecificId: "preview-1",
                likeCount: 42,
                repostCount: 12,
                replyCount: 5,
                isLiked: false,
                isReposted: false,
                attachments: []
            ),
            serviceManager: SocialServiceManager()
        )
    }
}

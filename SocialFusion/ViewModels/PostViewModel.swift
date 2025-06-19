import Combine
import Foundation
import SwiftUI

/// A ViewModel for managing a single post
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

    // State change callback for UI updates
    public var onStateChange: (() -> Void)?

    // MARK: - Private Properties

    private let serviceManager: SocialServiceManager
    private var cancellables = Set<AnyCancellable>()
    private let serialQueue = DispatchQueue(label: "PostViewModel.serial", qos: .userInitiated)

    // MARK: - Initialization

    public init(post: Post, serviceManager: SocialServiceManager) {
        self.post = post
        self.serviceManager = serviceManager

        // Initialize state from post
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

        // Removed setupObservers() to prevent AttributeGraph cycles
        // State updates are now handled directly in the action methods
    }

    deinit {
        cancellables.removeAll()
        quotedPostViewModel = nil
    }

    // MARK: - Public Methods

    /// Toggle like/unlike the post
    public func like() {
        guard !isLoading else {
            print("[PostViewModel] ⚠️ Like operation already in progress for post \(post.id)")
            return
        }

        print(
            "[PostViewModel] 🔄 Like button tapped for post \(post.id), current isLiked: \(isLiked), platform: \(post.platform)"
        )

        // Store original values for potential revert
        let originalLiked = isLiked
        let originalCount = likeCount

        // Optimistic UI update
        isLiked.toggle()
        likeCount += isLiked ? 1 : -1
        isLoading = true
        error = nil

        Task {
            do {
                let updatedPost: Post
                if originalLiked {
                    print("[PostViewModel] 👎 Attempting to UNLIKE post \(post.id)")
                    updatedPost = try await serviceManager.unlikePost(post)
                } else {
                    print("[PostViewModel] 👍 Attempting to LIKE post \(post.id)")
                    updatedPost = try await serviceManager.likePost(post)
                }

                print(
                    "[PostViewModel] ✅ Like/unlike completed for post \(post.id), new isLiked: \(updatedPost.isLiked), new likeCount: \(updatedPost.likeCount)"
                )

                // Update with server response
                self.post = updatedPost
                self.isLiked = updatedPost.isLiked
                self.likeCount = updatedPost.likeCount
                self.replyCount = updatedPost.replyCount
                self.isLoading = false

            } catch {
                print("[PostViewModel] ❌ Like/unlike failed for post \(post.id): \(error)")

                // Revert optimistic update
                self.isLiked = originalLiked
                self.likeCount = originalCount
                self.error = error
                self.isLoading = false
            }
        }
    }

    /// Toggle repost/unrepost the post
    public func repost() {
        guard !isLoading else {
            print("[PostViewModel] ⚠️ Repost operation already in progress for post \(post.id)")
            return
        }

        print(
            "[PostViewModel] 🔄 Repost button tapped for post \(post.id), current isReposted: \(isReposted), platform: \(post.platform)"
        )

        // Store original values for potential revert
        let originalReposted = isReposted
        let originalCount = repostCount

        // Optimistic UI update
        isReposted.toggle()
        repostCount += isReposted ? 1 : -1
        isLoading = true
        error = nil

        Task {
            do {
                let updatedPost: Post
                if originalReposted {
                    print("[PostViewModel] 🔄 Attempting to UNREPOST post \(post.id)")
                    updatedPost = try await serviceManager.unrepostPost(post)
                } else {
                    print("[PostViewModel] 🔄 Attempting to REPOST post \(post.id)")
                    updatedPost = try await serviceManager.repostPost(post)
                }

                print(
                    "[PostViewModel] ✅ Repost/unrepost completed for post \(post.id), new isReposted: \(updatedPost.isReposted), new repostCount: \(updatedPost.repostCount)"
                )

                // Update with server response
                self.post = updatedPost
                self.isReposted = updatedPost.isReposted
                self.repostCount = updatedPost.repostCount
                self.replyCount = updatedPost.replyCount
                self.isLoading = false

            } catch {
                print("[PostViewModel] ❌ Repost/unrepost failed for post \(post.id): \(error)")

                // Revert optimistic update
                self.isReposted = originalReposted
                self.repostCount = originalCount
                self.error = error
                self.isLoading = false
            }
        }
    }

    /// Reply to the post
    public func reply(content: String) async throws -> Post {
        guard !isLoading else { throw PostError.operationInProgress }

        isLoading = true
        error = nil

        do {
            let reply = try await serviceManager.replyToPost(post, content: content)
            self.replyCount += 1
            self.isLoading = false
            return reply
        } catch {
            self.error = error
            self.isLoading = false
            throw error
        }
    }

    /// Share the post
    public func share() {
        // Create the share sheet with the post URL
        guard let url = URL(string: post.originalURL) else { return }

        Task { @MainActor in
            let activityViewController = UIActivityViewController(
                activityItems: [url],
                applicationActivities: nil
            )

            // Present the share sheet
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                let window = windowScene.windows.first,
                let rootViewController = window.rootViewController
            {

                // Find the topmost view controller
                var topViewController = rootViewController
                while let presentedVC = topViewController.presentedViewController {
                    topViewController = presentedVC
                }

                // Configure for iPad
                if let popover = activityViewController.popoverPresentationController {
                    popover.sourceView = window
                    popover.sourceRect = CGRect(
                        x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }

                topViewController.present(activityViewController, animated: true)
            }
        }
    }

    // MARK: - Private Methods

    // Removed setupObservers method to prevent AttributeGraph cycles
    // The observer was creating feedback loops by modifying @Published properties
    // in response to other @Published property changes

    // MARK: - Computed Properties
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

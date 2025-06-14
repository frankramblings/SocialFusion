import Combine
import Foundation
import SwiftUI

/// A ViewModel for managing a single post
public class PostViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published public var post: Post
    @Published public var isLiked: Bool
    @Published public var isReposted: Bool
    @Published public var likeCount: Int
    @Published public var repostCount: Int
    @Published public var replyCount: Int
    @Published public var isLoading: Bool = false
    @Published public var error: Error?
    @Published public var quotedPostViewModel: PostViewModel?

    // MARK: - Private Properties

    private let serviceManager: SocialServiceManager
    private var cancellables = Set<AnyCancellable>()

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

        // Set up observers for post changes
        setupObservers()
    }

    // MARK: - Public Methods

    /// Toggle like/unlike the post
    public func like() {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        Task {
            do {
                let updatedPost: Post
                if isLiked {
                    updatedPost = try await serviceManager.unlikePost(post)
                } else {
                    updatedPost = try await serviceManager.likePost(post)
                }
                await MainActor.run {
                    self.post = updatedPost
                    self.isLiked = updatedPost.isLiked
                    self.likeCount = updatedPost.likeCount
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }

    /// Toggle repost/unrepost the post
    public func repost() {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        Task {
            do {
                let updatedPost: Post
                if isReposted {
                    updatedPost = try await serviceManager.unrepostPost(post)
                } else {
                    updatedPost = try await serviceManager.repostPost(post)
                }
                await MainActor.run {
                    self.post = updatedPost
                    self.isReposted = updatedPost.isReposted
                    self.repostCount = updatedPost.repostCount
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    self.isLoading = false
                }
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
            await MainActor.run {
                self.replyCount += 1
                self.isLoading = false
            }
            return reply
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
            throw error
        }
    }

    /// Share the post
    public func share() {
        // Create the share sheet with the post URL
        guard let url = URL(string: post.originalURL) else { return }

        DispatchQueue.main.async {
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

    private func setupObservers() {
        // Observe post changes
        $post
            .sink { [weak self] updatedPost in
                self?.isLiked = updatedPost.isLiked
                self?.isReposted = updatedPost.isReposted
                self?.likeCount = updatedPost.likeCount
                self?.repostCount = updatedPost.repostCount
                self?.replyCount = updatedPost.replyCount

                // Update quoted post view model if needed
                if let quotedPost = updatedPost.quotedPost {
                    self?.quotedPostViewModel = PostViewModel(
                        post: quotedPost,
                        serviceManager: self?.serviceManager ?? SocialServiceManager.shared)
                } else {
                    self?.quotedPostViewModel = nil
                }
            }
            .store(in: &cancellables)
    }

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

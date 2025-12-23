import SwiftUI

/// A view that displays a row of action buttons for a post
struct PostActionBar: View {
    let post: Post
    let replyCount: Int
    let repostCount: Int
    let likeCount: Int
    let isReplying: Bool
    let isReposted: Bool
    let isLiked: Bool
    let isReplied: Bool
    let onReply: () -> Void
    let onRepost: () -> Void
    let onLike: () -> Void
    let onShare: () -> Void
    let postActionStore: PostActionStore?
    let postActionCoordinator: PostActionCoordinator?

    init(
        post: Post,
        replyCount: Int,
        repostCount: Int,
        likeCount: Int,
        isReplying: Bool,
        isReposted: Bool,
        isLiked: Bool,
        isReplied: Bool,
        onReply: @escaping () -> Void,
        onRepost: @escaping () -> Void,
        onLike: @escaping () -> Void,
        onShare: @escaping () -> Void,
        postActionStore: PostActionStore? = nil,
        postActionCoordinator: PostActionCoordinator? = nil
    ) {
        self.post = post
        self.replyCount = replyCount
        self.repostCount = repostCount
        self.likeCount = likeCount
        self.isReplying = isReplying
        self.isReposted = isReposted
        self.isLiked = isLiked
        self.isReplied = isReplied
        self.onReply = onReply
        self.onRepost = onRepost
        self.onLike = onLike
        self.onShare = onShare
        self.postActionStore = postActionStore
        self.postActionCoordinator = postActionCoordinator
    }

    // Platform color helper
    private var platformColor: Color {
        switch post.platform {
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
        }
    }

    // Helper function to format counts
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            if FeatureFlagManager.isEnabled(.postActionsV2),
                let store = postActionStore,
                let coordinator = postActionCoordinator
            {
                UnifiedInteractionButtons(
                    post: post,
                    store: store,
                    coordinator: coordinator,
                    onReply: onReply,
                    onShare: onShare,
                    includeShare: false
                )

                PostShareButton(
                    post: post,
                    onTap: onShare
                )
            } else {
            UnifiedReplyButton(
                count: replyCount,
                isReplied: isReplied,
                platform: post.platform,
                onTap: onReply
            )
            .accessibilityLabel("Reply")

            UnifiedRepostButton(
                isReposted: isReposted,
                count: repostCount,
                    isProcessing: false,
                onTap: onRepost
            )
            .accessibilityLabel(isReposted ? "Undo Repost" : "Repost")

            UnifiedLikeButton(
                isLiked: isLiked,
                count: likeCount,
                    isProcessing: false,
                onTap: onLike
            )
            .accessibilityLabel(isLiked ? "Unlike" : "Like")

            PostShareButton(
                post: post,
                onTap: onShare
            )
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

/// A view that displays a row of action buttons for a post using PostViewModel
struct PostActionBarWithViewModel: View {
    @ObservedObject var viewModel: PostViewModel
    let isReplying: Bool
    let onReply: () -> Void
    let onRepost: () -> Void
    let onLike: () -> Void
    let onShare: () -> Void
    let postActionStore: PostActionStore?
    let postActionCoordinator: PostActionCoordinator?

    init(
        viewModel: PostViewModel,
        isReplying: Bool,
        onReply: @escaping () -> Void,
        onRepost: @escaping () -> Void,
        onLike: @escaping () -> Void,
        onShare: @escaping () -> Void,
        postActionStore: PostActionStore? = nil,
        postActionCoordinator: PostActionCoordinator? = nil
    ) {
        self.viewModel = viewModel
        self.isReplying = isReplying
        self.onReply = onReply
        self.onRepost = onRepost
        self.onLike = onLike
        self.onShare = onShare
        self.postActionStore = postActionStore
        self.postActionCoordinator = postActionCoordinator
    }

    var body: some View {
        HStack(spacing: 16) {
            if FeatureFlagManager.isEnabled(.postActionsV2),
                let store = postActionStore,
                let coordinator = postActionCoordinator
            {
                UnifiedInteractionButtons(
                    post: viewModel.post,
                    store: store,
                    coordinator: coordinator,
                    onReply: onReply,
                    onShare: onShare,
                    includeShare: false
                )

                PostShareButton(
                    post: viewModel.post,
                    onTap: onShare
                )
            } else {
            UnifiedReplyButton(
                count: viewModel.replyCount,
                isReplied: viewModel.post.isReplied,
                platform: viewModel.post.platform,
                onTap: onReply
            )
            .accessibilityLabel("Reply")

            UnifiedRepostButton(
                isReposted: viewModel.isReposted,
                count: viewModel.repostCount,
                isProcessing: viewModel.isLoading,
                onTap: onRepost
            )
            .accessibilityLabel(viewModel.isReposted ? "Undo Repost" : "Repost")

            UnifiedLikeButton(
                isLiked: viewModel.isLiked,
                count: viewModel.likeCount,
                isProcessing: viewModel.isLoading,
                onTap: onLike
            )
            .accessibilityLabel(viewModel.isLiked ? "Unlike" : "Like")

            PostShareButton(
                post: viewModel.post,
                onTap: onShare
            )
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

/// A view that displays a post action button with count
private struct PostActionButton: View {
    let icon: String
    let count: Int
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text("\(count)")
            }
        }
        .foregroundColor(isActive ? .accentColor : .secondary)
    }
}

/// A view that displays a post action button without count
private struct PostActionIconButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
        }
        .foregroundColor(.secondary)
    }
}

// MARK: - Preview
struct PostActionBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Bluesky post with all actions
            PostActionBar(
                post: Post(
                    id: "1",
                    content: "Test post",
                    authorName: "Test User",
                    authorUsername: "testuser",
                    authorProfilePictureURL: "",
                    createdAt: Date(),
                    platform: .bluesky,
                    originalURL: "",
                    attachments: []
                ),
                replyCount: 42,
                repostCount: 123,
                likeCount: 456,
                isReplying: false,
                isReposted: true,
                isLiked: true,
                isReplied: false,
                onReply: {},
                onRepost: {},
                onLike: {},
                onShare: {}
            )

            // Mastodon post with no interactions
            PostActionBar(
                post: Post(
                    id: "2",
                    content: "Test post",
                    authorName: "Test User",
                    authorUsername: "testuser",
                    authorProfilePictureURL: "",
                    createdAt: Date(),
                    platform: .mastodon,
                    originalURL: "",
                    attachments: []
                ),
                replyCount: 0,
                repostCount: 0,
                likeCount: 0,
                isReplying: false,
                isReposted: false,
                isLiked: false,
                isReplied: false,
                onReply: {},
                onRepost: {},
                onLike: {},
                onShare: {}
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}

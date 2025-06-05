import SwiftUI

/// A view that displays a post card with all its components
struct PostCardView: View {
    let post: Post
    let replyCount: Int
    let repostCount: Int
    let likeCount: Int
    let isReplying: Bool
    let isReposted: Bool
    let isLiked: Bool
    let onAuthorTap: () -> Void
    let onReply: () -> Void
    let onRepost: () -> Void
    let onLike: () -> Void
    let onShare: () -> Void
    let onMediaTap: (Post.Attachment) -> Void
    let onOpenInBrowser: () -> Void
    let onCopyLink: () -> Void
    let onReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author section
            PostAuthorView(
                post: post,
                onAuthorTap: onAuthorTap
            )

            // Content section
            PostContent(
                content: post.content,
                hashtags: post.hashtags,
                mentions: post.mentions,
                onHashtagTap: { _ in },
                onMentionTap: { _ in }
            )

            // Media section
            if !post.attachments.isEmpty {
                UnifiedMediaGridView(attachments: post.attachments)
            }

            // Action bar
            PostActionBar(
                post: post,
                replyCount: replyCount,
                repostCount: repostCount,
                likeCount: likeCount,
                isReplying: isReplying,
                isReposted: isReposted,
                isLiked: isLiked,
                onReply: onReply,
                onRepost: onRepost,
                onLike: onLike,
                onShare: onShare
            )

            // Menu
            PostMenu(
                post: post,
                onOpenInBrowser: onOpenInBrowser,
                onCopyLink: onCopyLink,
                onShare: onShare,
                onReport: onReport
            )
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

// MARK: - Preview
struct PostCardView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Bluesky post with media
            PostCardView(
                post: Post(
                    id: "1",
                    content: "This is a test post with #hashtags and @mentions",
                    authorName: "John Doe",
                    authorUsername: "johndoe",
                    authorProfilePictureURL: "https://example.com/avatar.jpg",
                    createdAt: Date(),
                    platform: .bluesky,
                    originalURL: "",
                    attachments: [
                        Post.Attachment(
                            type: .image,
                            url: "https://example.com/image.jpg",
                            previewURL: "https://example.com/preview.jpg",
                            altText: "Test image"
                        )
                    ]
                ),
                replyCount: 42,
                repostCount: 123,
                likeCount: 456,
                isReplying: false,
                isReposted: true,
                isLiked: true,
                onAuthorTap: {},
                onReply: {},
                onRepost: {},
                onLike: {},
                onShare: {},
                onMediaTap: { _ in },
                onOpenInBrowser: {},
                onCopyLink: {},
                onReport: {}
            )

            // Mastodon post without media
            PostCardView(
                post: Post(
                    id: "2",
                    content: "This is a test post without media",
                    authorName: "Jane Smith",
                    authorUsername: "janesmith",
                    authorProfilePictureURL: "https://example.com/avatar.jpg",
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
                onAuthorTap: {},
                onReply: {},
                onRepost: {},
                onLike: {},
                onShare: {},
                onMediaTap: { _ in },
                onOpenInBrowser: {},
                onCopyLink: {},
                onReport: {}
            )
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .previewLayout(.sizeThatFits)
    }
}

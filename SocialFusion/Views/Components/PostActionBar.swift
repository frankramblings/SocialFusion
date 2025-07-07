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

    var body: some View {
        HStack(spacing: 16) {
            // Reply button
            PostReplyButton(
                post: post,
                replyCount: replyCount,
                isReplying: isReplying,
                isReplied: isReplied,
                onTap: onReply
            )

            // Repost button
            PostRepostButton(
                post: post,
                repostCount: repostCount,
                isReposted: isReposted,
                onTap: onRepost
            )

            // Like button
            PostLikeButton(
                post: post,
                likeCount: likeCount,
                isLiked: isLiked,
                onTap: onLike
            )

            // Share button
            PostShareButton(
                post: post,
                onTap: onShare
            )

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

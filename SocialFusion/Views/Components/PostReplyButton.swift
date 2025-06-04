import SwiftUI

/// A view that displays a button for replying to a post
struct PostReplyButton: View {
    let post: Post
    let replyCount: Int
    let isReplying: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left")
                    .foregroundColor(isReplying ? platformColor : .secondary)

                if replyCount > 0 {
                    Text(formatCount(replyCount))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var platformColor: Color {
        switch post.platform {
        case .bluesky:
            return .blue
        case .mastodon:
            return .purple
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}

// MARK: - Preview
struct PostReplyButton_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 16) {
            // Bluesky post with replies
            PostReplyButton(
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
                isReplying: false,
                onTap: {}
            )

            // Mastodon post with replies
            PostReplyButton(
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
                replyCount: 1234,
                isReplying: true,
                onTap: {}
            )

            // Post without replies
            PostReplyButton(
                post: Post(
                    id: "3",
                    content: "Test post",
                    authorName: "Test User",
                    authorUsername: "testuser",
                    authorProfilePictureURL: "",
                    createdAt: Date(),
                    platform: .bluesky,
                    originalURL: "",
                    attachments: []
                ),
                replyCount: 0,
                isReplying: false,
                onTap: {}
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}

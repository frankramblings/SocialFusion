import SwiftUI

/// A view that displays a button for reposting a post
struct PostRepostButton: View {
    let post: Post
    let repostCount: Int
    let isReposted: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: isReposted ? "arrow.2.squarepath.fill" : "arrow.2.squarepath")
                    .foregroundColor(isReposted ? platformColor : .secondary)

                if repostCount > 0 {
                    Text(formatCount(repostCount))
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
struct PostRepostButton_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 16) {
            // Bluesky post with reposts
            PostRepostButton(
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
                repostCount: 42,
                isReposted: false,
                onTap: {}
            )

            // Mastodon post with reposts
            PostRepostButton(
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
                repostCount: 1234,
                isReposted: true,
                onTap: {}
            )

            // Post without reposts
            PostRepostButton(
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
                repostCount: 0,
                isReposted: false,
                onTap: {}
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}

import SwiftUI

/// A view that displays a banner indicating a post is a reply
struct PostReplyBanner: View {
    let post: Post
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            print("[DEBUG] PostReplyBanner tapped for postID: \(post.id)")
            onTap()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left")
                    .foregroundColor(platformColor)

                if let inReplyToUsername = post.inReplyToUsername {
                    Text("Replying to @\(inReplyToUsername)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("Replying to post")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(platformColor.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var platformColor: Color {
        switch post.platform {
        case .bluesky:
            return Color.blue
        case .mastodon:
            return Color.purple
        }
    }
}

// MARK: - Preview
struct PostReplyBanner_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Bluesky reply banner with username
            PostReplyBanner(
                post: Post(
                    id: "1",
                    content: "Test post",
                    authorName: "Test User",
                    authorUsername: "testuser",
                    authorProfilePictureURL: "",
                    createdAt: Date(),
                    platform: .bluesky,
                    originalURL: "",
                    attachments: [],
                    inReplyToID: "123",
                    inReplyToUsername: "originaluser"
                ),
                onTap: {}
            )

            // Mastodon reply banner without username
            PostReplyBanner(
                post: Post(
                    id: "2",
                    content: "Test post",
                    authorName: "Test User",
                    authorUsername: "testuser",
                    authorProfilePictureURL: "",
                    createdAt: Date(),
                    platform: .mastodon,
                    originalURL: "",
                    attachments: [],
                    inReplyToID: "456"
                ),
                onTap: {}
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}

import SwiftUI

/// A view that displays a banner indicating a post has been boosted/reposted
struct PostBoostBanner: View {
    let post: Post
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.2.squarepath")
                    .foregroundColor(platformColor)

                Text("\(post.authorName) boosted")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
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
struct PostBoostBanner_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Bluesky boost banner
            PostBoostBanner(
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
                    isReposted: true
                ),
                onTap: {}
            )

            // Mastodon boost banner
            PostBoostBanner(
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
                    isReposted: true
                ),
                onTap: {}
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}

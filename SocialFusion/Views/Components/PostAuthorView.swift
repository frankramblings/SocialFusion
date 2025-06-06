import SwiftUI

/// A view that displays the author information for a post
struct PostAuthorView: View {
    let post: Post
    let onAuthorTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Avatar with platform indicator as colored border
            PostAvatar(
                imageURL: post.authorProfilePictureURL,
                platform: post.platform,
                size: 40
            )
            .onTapGesture(perform: onAuthorTap)

            // Author info
            VStack(alignment: .leading, spacing: 2) {
                // Just the name, no platform badge
                Text(post.authorName)
                    .font(.headline)
                    .foregroundColor(.primary)

                // Username
                Text("@\(post.authorUsername)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Timestamp on the right
            Text(timeAgoString)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var timeAgoString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: post.createdAt, relativeTo: Date())
    }
}

// MARK: - Preview
struct PostAuthorView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Bluesky author
            PostAuthorView(
                post: Post(
                    id: "1",
                    content: "Test post",
                    authorName: "John Doe",
                    authorUsername: "johndoe",
                    authorProfilePictureURL: "https://example.com/avatar.jpg",
                    createdAt: Date(),
                    platform: .bluesky,
                    originalURL: "",
                    attachments: []
                ),
                onAuthorTap: {}
            )

            // Mastodon author
            PostAuthorView(
                post: Post(
                    id: "2",
                    content: "Test post",
                    authorName: "Jane Smith",
                    authorUsername: "janesmith",
                    authorProfilePictureURL: "https://example.com/avatar.jpg",
                    createdAt: Date(),
                    platform: .mastodon,
                    originalURL: "",
                    attachments: []
                ),
                onAuthorTap: {}
            )

            // Author without profile picture
            PostAuthorView(
                post: Post(
                    id: "3",
                    content: "Test post",
                    authorName: "Anonymous User",
                    authorUsername: "anonymous",
                    authorProfilePictureURL: "",
                    createdAt: Date(),
                    platform: .bluesky,
                    originalURL: "",
                    attachments: []
                ),
                onAuthorTap: {}
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}

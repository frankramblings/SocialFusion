import SwiftUI

/// A view that displays the author information for a post
struct PostAuthorView: View {
    let post: Post
    let onAuthorTap: () -> Void

    // Extract stable values to prevent view rebuilds from cancelling AsyncImage
    private let stableAuthorImageURL: String
    private let stableAuthorName: String
    private let stableAuthorUsername: String
    private let stablePlatform: SocialPlatform
    private let stableCreatedAt: Date
    private let stableAuthorEmojiMap: [String: String]?

    init(post: Post, onAuthorTap: @escaping () -> Void) {
        self.post = post
        self.onAuthorTap = onAuthorTap

        // Capture stable values at init time to prevent AsyncImage cancellation
        self.stableAuthorImageURL = post.authorProfilePictureURL
        self.stableAuthorName = post.authorName
        self.stableAuthorUsername = post.authorUsername
        self.stablePlatform = post.platform
        self.stableCreatedAt = post.createdAt
        self.stableAuthorEmojiMap = post.authorEmojiMap
    }

    var body: some View {
        HStack(spacing: 12) {
            // Author avatar
            Button(action: onAuthorTap) {
                PostAuthorImageView(
                    authorProfilePictureURL: stableAuthorImageURL,
                    platform: stablePlatform,
                    size: 44,
                    authorName: stableAuthorName
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Author info
            VStack(alignment: .leading, spacing: 2) {
                Button(action: onAuthorTap) {
                    EmojiDisplayNameText(
                        stableAuthorName,
                        emojiMap: stableAuthorEmojiMap,
                        font: .subheadline,
                        fontWeight: .semibold,
                        foregroundColor: .primary,
                        lineLimit: 1
                    )
                }
                .buttonStyle(PlainButtonStyle())

                HStack(spacing: 4) {
                    Button(action: onAuthorTap) {
                        Text("@\(stableAuthorUsername)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(formatRelativeTime(from: stableCreatedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }

    private var timeAgoString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: post.createdAt, relativeTo: Date())
    }

    private func formatRelativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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

import SwiftUI

/// A view that displays a button for sharing a post
struct PostShareButton: View {
    let post: Post
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "square.and.arrow.up")
                .foregroundColor(.secondary)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview
struct PostShareButton_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 16) {
            // Bluesky post share button
            PostShareButton(
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
                onTap: {}
            )

            // Mastodon post share button
            PostShareButton(
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
                onTap: {}
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}

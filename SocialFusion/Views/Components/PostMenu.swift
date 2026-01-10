import SwiftUI
import os.log

/// A view that displays platform-specific actions for a post
struct PostMenu: View {
    let post: Post
    let onAction: (PostAction) -> Void
    private let menuLogger = Logger(subsystem: "com.socialfusion", category: "PostMenu")

    var body: some View {
        Menu {
            ForEach(PostAction.platformActions(for: post), id: \.self) { action in
                menuButton(for: action)
            }

            Divider()

            menuButton(for: .openInBrowser)
            menuButton(for: .copyLink)
            menuButton(for: .shareSheet)

            Divider()

            menuButton(for: .report)
        } label: {
            Image(systemName: "ellipsis")
                .foregroundColor(.secondary)
        }
    }

    private func menuButton(for action: PostAction) -> some View {
        Button(role: action.menuRole) {
            menuLogger.info("📋 PostMenu tap: \(action.menuLabel, privacy: .public)")
            onAction(action)
        } label: {
            Label(action.menuLabel, systemImage: action.menuSystemImage)
        }
    }
}

// MARK: - Preview
struct PostMenu_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 16) {
            // Bluesky post menu
            PostMenu(
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
                onAction: { _ in }
            )

            // Mastodon post menu
            PostMenu(
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
                onAction: { _ in }
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}

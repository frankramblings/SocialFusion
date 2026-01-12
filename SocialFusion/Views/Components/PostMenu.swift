import SwiftUI
import os.log

/// A view that displays platform-specific actions for a post
struct PostMenu: View {
    let post: Post
    var state: PostActionState?
    let onAction: (PostAction) -> Void
    private let menuLogger = Logger(subsystem: "com.socialfusion", category: "PostMenu")

    /// Effective state for menu label derivation: uses provided state or derives from post
    private var effectiveState: PostActionState {
        state ?? post.makeActionState()
    }

    var body: some View {
        Menu {
            ForEach(PostAction.platformActions(for: post), id: \.self) { action in
                menuButton(for: action)
            }

            Divider()

            menuButton(for: .openInBrowser)
            menuButton(for: .copyLink)
            menuButton(for: .shareSheet)
            menuButton(for: .shareAsImage)

            Divider()

            menuButton(for: .report)
        } label: {
            Image(systemName: "ellipsis")
                .foregroundColor(.secondary)
        }
    }

    private func menuButton(for action: PostAction) -> some View {
        let label = action.menuLabel(for: effectiveState)
        let icon = action.menuSystemImage(for: effectiveState)
        return Button(role: action.menuRole) {
            menuLogger.info("📋 PostMenu tap: \(label, privacy: .public)")
            onAction(action)
        } label: {
            Label(label, systemImage: icon)
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

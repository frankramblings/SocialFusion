import SwiftUI

/// A view that displays platform-specific actions for a post
struct PostMenu: View {
    let post: Post
    let onAction: (PostAction) -> Void
    let onOpenInBrowser: () -> Void
    let onCopyLink: () -> Void
    let onShare: () -> Void
    let onReport: () -> Void

    var body: some View {
        Menu {
            // Platform-specific actions
            if post.platform == .bluesky {
                blueskyActions
            } else if post.platform == .mastodon {
                mastodonActions
            }

            Divider()

            // Common actions
            Button(action: onOpenInBrowser) {
                Label("Open in Browser", systemImage: "arrow.up.right.square")
            }

            Button(action: onCopyLink) {
                Label("Copy Link", systemImage: "link")
            }

            Button(action: onShare) {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive, action: onReport) {
                Label("Report", systemImage: "exclamationmark.triangle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundColor(.secondary)
        }
    }

    private var blueskyActions: some View {
        Group {
            Button(action: { onAction(.follow) }) {
                Label("Follow", systemImage: "person.badge.plus")
            }

            Button(action: { onAction(.mute) }) {
                Label("Mute", systemImage: "speaker.slash")
            }

            Button(action: { onAction(.block) }) {
                Label("Block", systemImage: "hand.raised")
            }
        }
    }

    private var mastodonActions: some View {
        Group {
            Button(action: { onAction(.follow) }) {
                Label("Follow", systemImage: "person.badge.plus")
            }

            Button(action: { onAction(.mute) }) {
                Label("Mute", systemImage: "speaker.slash")
            }

            Button(action: { onAction(.block) }) {
                Label("Block", systemImage: "hand.raised")
            }

            Button(action: { onAction(.addToList) }) {
                Label("Add to Lists", systemImage: "list.bullet")
            }
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
                onAction: { _ in },
                onOpenInBrowser: {},
                onCopyLink: {},
                onShare: {},
                onReport: {}
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
                onAction: { _ in },
                onOpenInBrowser: {},
                onCopyLink: {},
                onShare: {},
                onReport: {}
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}

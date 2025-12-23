import SwiftUI

/// Custom button style that provides smooth Apple-like feedback when pressed
struct SmoothScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .animation(
                .interactiveSpring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.05),
                value: configuration.isPressed)
    }
}

/// ActionBar component for social media post interactions
struct ActionBar: View {
    @ObservedObject var post: Post
    let onAction: (PostAction) -> Void
    let onOpenInBrowser: () -> Void
    let onCopyLink: () -> Void
    let onReport: () -> Void

    // Icon size for better visibility
    private let iconSize: CGFloat = 18

    // Platform color helper
    private var platformColor: Color {
        switch post.platform {
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
        }
    }

    // Track operation state per button
    @State private var isLikeProcessing = false
    @State private var isRepostProcessing = false

    var body: some View {
        HStack {
            // Reply button
            UnifiedReplyButton(
                count: post.replyCount,
                isReplied: post.isReplied,
                platform: post.platform,
                onTap: { onAction(.reply) }
            )
            .accessibilityLabel("Reply")

            Spacer()

            // Repost button
            UnifiedRepostButton(
                isReposted: post.isReposted,
                count: post.repostCount,
                isProcessing: isRepostProcessing,
                onTap: {
                    isRepostProcessing = true
                    onAction(.repost)
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        isRepostProcessing = false
                    }
                }
            )
            .accessibilityLabel(post.isReposted ? "Undo Repost" : "Repost")

            Spacer()

            // Quote button
            Button {
                // Add haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()

                onAction(.quote)
            } label: {
                Image(systemName: "quote.opening")
                    .font(.system(size: iconSize))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(SmoothScaleButtonStyle())
            .accessibilityLabel("Quote Post")

            Spacer()

            // Like button
            UnifiedLikeButton(
                isLiked: post.isLiked,
                count: post.likeCount,
                isProcessing: isLikeProcessing,
                onTap: {
                    isLikeProcessing = true
                    onAction(.like)
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        isLikeProcessing = false
                    }
                }
            )
            .accessibilityLabel(post.isLiked ? "Unlike" : "Like")

            Spacer()

            // Share button
            Button {
                // Add haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()

                onAction(.share)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: iconSize))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(SmoothScaleButtonStyle())
            .accessibilityLabel("Share")

            Spacer()

            // Menu button (three dots)
            Menu {
                // Platform-specific actions
                if post.platform == .bluesky {
                    Button(action: {}) {
                        Label("Follow", systemImage: "person.badge.plus")
                    }
                    Button(action: {}) {
                        Label("Mute", systemImage: "speaker.slash")
                    }
                    Button(action: {}) {
                        Label("Block", systemImage: "hand.raised")
                    }
                } else if post.platform == .mastodon {
                    Button(action: {}) {
                        Label("Follow", systemImage: "person.badge.plus")
                    }
                    Button(action: {}) {
                        Label("Mute", systemImage: "speaker.slash")
                    }
                    Button(action: {}) {
                        Label("Block", systemImage: "hand.raised")
                    }
                    Button(action: {}) {
                        Label("Add to Lists", systemImage: "list.bullet")
                    }
                }

                Divider()

                // Common actions
                Button(action: onOpenInBrowser) {
                    Label("Open in Browser", systemImage: "arrow.up.right.square")
                }
                Button(action: onCopyLink) {
                    Label("Copy Link", systemImage: "link")
                }
                Button(action: { onAction(.share) }) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Divider()

                Button(role: .destructive, action: onReport) {
                    Label("Report", systemImage: "exclamationmark.triangle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: iconSize))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("More options")
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 16)
    }
}

struct ActionBarV2: View {
    @ObservedObject var post: Post
    @ObservedObject var store: PostActionStore
    let coordinator: PostActionCoordinator
    let onReply: () -> Void
    let onShare: () -> Void
    let onOpenInBrowser: () -> Void
    let onCopyLink: () -> Void
    let onReport: () -> Void

    private var quoteButton: some View {
        Button {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        } label: {
            Image(systemName: "quote.opening")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
        }
        .buttonStyle(SmoothScaleButtonStyle())
        .accessibilityLabel("Quote Post")
    }

    var body: some View {
        HStack {
            UnifiedInteractionButtons(
                post: post,
                store: store,
                coordinator: coordinator,
                onReply: onReply,
                onShare: onShare,
                includeShare: false
            )

            Spacer()

            quoteButton

            Spacer()

            Button {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                onShare()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(SmoothScaleButtonStyle())
            .accessibilityLabel("Share")

            Spacer()

            Menu {
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
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("More options")
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 16)
    }
}

/// ActionBarViewModel for observing PostViewModel state changes
struct ObservableActionBar: View {
    @ObservedObject var viewModel: PostViewModel
    let onAction: (PostAction) -> Void
    let onOpenInBrowser: () -> Void
    let onCopyLink: () -> Void
    let onReport: () -> Void

    var body: some View {
        ActionBar(
            post: viewModel.post,
            onAction: onAction,
            onOpenInBrowser: onOpenInBrowser,
            onCopyLink: onCopyLink,
            onReport: onReport
        )
    }
}

#Preview("Normal State") {
    let samplePost = Post(
        id: "1",
        content: "Sample post content",
        authorName: "Test User",
        authorUsername: "testuser",
        authorProfilePictureURL: "",
        createdAt: Date(),
        platform: .mastodon,
        originalURL: "",
        attachments: []
    )

    ActionBar(
        post: samplePost,
        onAction: { _ in },
        onOpenInBrowser: {},
        onCopyLink: {},
        onReport: {}
    )
    .padding()
    .background(Color.black)
}

#Preview("Active State") {
    let samplePost = Post(
        id: "2",
        content: "Sample post content",
        authorName: "Test User",
        authorUsername: "testuser",
        authorProfilePictureURL: "",
        createdAt: Date(),
        platform: .bluesky,
        originalURL: "",
        attachments: []
    )

    ActionBar(
        post: samplePost,
        onAction: { _ in },
        onOpenInBrowser: {},
        onCopyLink: {},
        onReport: {}
    )
    .padding()
    .background(Color.black)
}

#Preview("No Counts") {
    let samplePost = Post(
        id: "3",
        content: "Sample post content",
        authorName: "Test User",
        authorUsername: "testuser",
        authorProfilePictureURL: "",
        createdAt: Date(),
        platform: .mastodon,
        originalURL: "",
        attachments: []
    )

    ActionBar(
        post: samplePost,
        onAction: { _ in },
        onOpenInBrowser: {},
        onCopyLink: {},
        onReport: {}
    )
    .padding()
    .background(Color.black)
}

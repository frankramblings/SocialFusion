import SwiftUI
import os.log

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
    let onMenuOpen: (() -> Void)?

    // Icon size for better visibility
    private let iconSize: CGFloat = 18
    private let menuLogger = Logger(subsystem: "com.socialfusion", category: "PostMenu")

    // Platform color helper
    private var platformColor: Color {
        switch post.platform {
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
        }
    }

    private var menuOpenTrigger: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { onMenuOpen?() }
    }

    // Track operation state per button
    @State private var isLikeProcessing = false
    @State private var isRepostProcessing = false
    @State private var isReplyProcessing = false

    init(
        post: Post,
        onAction: @escaping (PostAction) -> Void,
        onMenuOpen: (() -> Void)? = nil
    ) {
        self.post = post
        self.onAction = onAction
        self.onMenuOpen = onMenuOpen
    }

    var body: some View {
        HStack(spacing: 0) {
            // Reply button
            UnifiedReplyButton(
                count: post.replyCount,
                isReplied: post.isReplied,
                platform: post.platform,
                isProcessing: isReplyProcessing,
                onTap: {
                    isReplyProcessing = true
                    onAction(.reply)
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        isReplyProcessing = false
                    }
                }
            )
            .accessibilityLabel("Reply")
            .frame(maxWidth: .infinity)

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
            .frame(maxWidth: .infinity)

            // Quote button
            UnifiedQuoteButton(
                isQuoted: post.isQuoted,
                platform: post.platform,
                isProcessing: false, // Quote opens compose view, no async processing needed
                onTap: {
                    onAction(.quote)
                }
            )
            .accessibilityLabel(post.isQuoted ? "Quoted. Double tap to quote again" : "Quote Post")
            .frame(maxWidth: .infinity)

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
            .frame(maxWidth: .infinity)

            // Share button
            PostShareButton(
                post: post,
                onTap: { onAction(.share) }
            )
            .frame(maxWidth: .infinity)

            // Menu button (three dots)
            Menu {
                menuOpenTrigger

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
                    .font(.system(size: iconSize))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .simultaneousGesture(
                TapGesture().onEnded { onMenuOpen?() }
            )
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("More options")
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 0)
    }

    /// Derives current action state from the post for menu label computation
    private var currentState: PostActionState {
        post.makeActionState()
    }

    private func menuButton(for action: PostAction) -> some View {
        let label = action.menuLabel(for: currentState)
        let icon = action.menuSystemImage(for: currentState)
        return Button(role: action.menuRole) {
            menuLogger.info("📋 ActionBar menu tap: \(label, privacy: .public)")
            onAction(action)
        } label: {
            Label(label, systemImage: icon)
        }
    }
}

struct ActionBarV2: View {
    @ObservedObject var post: Post
    @ObservedObject var store: PostActionStore
    let coordinator: PostActionCoordinator
    let onAction: (PostAction) -> Void
    let onMenuOpen: (() -> Void)?
    private let menuLogger = Logger(subsystem: "com.socialfusion", category: "PostMenu")

    private var actionKey: String { post.stableId }
    private var state: PostActionState { store.state(for: post) }
    private var isProcessing: Bool { store.inflightKeys.contains(actionKey) }
    private var isPending: Bool { store.pendingKeys.contains(actionKey) }

    private var menuOpenTrigger: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { onMenuOpen?() }
    }

    init(
        post: Post,
        store: PostActionStore,
        coordinator: PostActionCoordinator,
        onAction: @escaping (PostAction) -> Void,
        onMenuOpen: (() -> Void)? = nil
    ) {
        self.post = post
        self.store = store
        self.coordinator = coordinator
        self.onAction = onAction
        self.onMenuOpen = onMenuOpen
    }

    private var quoteButton: some View {
        UnifiedQuoteButton(
            isQuoted: state.isQuoted,
            platform: post.platform,
            isProcessing: false, // Quote opens compose view, no async processing needed
            onTap: {
                onAction(.quote)
            }
        )
        .accessibilityLabel(state.isQuoted ? "Quoted. Double tap to quote again" : "Quote Post")
    }

    var body: some View {
        HStack(spacing: 0) {
            UnifiedReplyButton(
                count: state.replyCount,
                isReplied: state.isReplied,
                platform: post.platform,
                isProcessing: false, // Reply opens compose view, no async processing needed
                onTap: {
                    onAction(.reply)
                }
            )
            .accessibilityLabel(state.isReplied ? "Reply sent. Double tap to reply again" : "Reply. Double tap to reply")
            .frame(maxWidth: .infinity)

            UnifiedRepostButton(
                isReposted: state.isReposted,
                count: state.repostCount,
                isProcessing: isProcessing,
                onTap: { coordinator.toggleRepost(for: post) }
            )
            .accessibilityLabel(state.isReposted ? "Reposted. Double tap to undo repost" : "Repost. Double tap to repost")
            .frame(maxWidth: .infinity)

            UnifiedLikeButton(
                isLiked: state.isLiked,
                count: state.likeCount,
                isProcessing: isProcessing,
                onTap: { coordinator.toggleLike(for: post) }
            )
            .accessibilityLabel(state.isLiked ? "Liked. Double tap to unlike" : "Like. Double tap to like")
            .frame(maxWidth: .infinity)

            quoteButton
                .frame(maxWidth: .infinity)

            PostShareButton(
                post: post,
                onTap: { onAction(.share) }
            )
            .frame(maxWidth: .infinity)

            Menu {
                menuOpenTrigger

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
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .simultaneousGesture(
                TapGesture().onEnded { onMenuOpen?() }
            )
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("More options")
            .frame(maxWidth: .infinity)
        }
        .opacity(isPending ? 0.7 : 1.0)
        .padding(.vertical, 2)
        .padding(.horizontal, 0)
    }

    private func menuButton(for action: PostAction) -> some View {
        let label = action.menuLabel(for: state)
        let icon = action.menuSystemImage(for: state)
        return Button(role: action.menuRole) {
            menuLogger.info("📋 ActionBarV2 menu tap: \(label, privacy: .public)")
            onAction(action)
        } label: {
            Label(label, systemImage: icon)
        }
    }
}

/// ActionBarViewModel for observing PostViewModel state changes
struct ObservableActionBar: View {
    @ObservedObject var viewModel: PostViewModel
    let onAction: (PostAction) -> Void

    var body: some View {
        ActionBar(
            post: viewModel.post,
            onAction: onAction
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
        onAction: { _ in }
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
        onAction: { _ in }
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
        onAction: { _ in }
    )
    .padding()
    .background(Color.black)
}

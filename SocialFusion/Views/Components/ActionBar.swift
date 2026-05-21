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

    @EnvironmentObject private var watchedConversationStore: WatchedConversationStore
    @EnvironmentObject private var fusedMomentStore: FusedMomentStore

    // Icon size for better visibility
    private let iconSize: CGFloat = 18
    private let menuLogger = Logger(subsystem: "com.socialfusion", category: "PostMenu")

    // Platform color via SocialPlatform.swiftUIColor (canonical hex).
    private var platformColor: Color { post.platform.swiftUIColor }

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
            .accessibilityValue(replyValue(count: post.replyCount, isReplied: post.isReplied))
            .accessibilityHint("Opens the reply composer")
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
            .accessibilityLabel("Repost")
            .accessibilityValue(repostValue(count: post.repostCount, isReposted: post.isReposted))
            .accessibilityHint(post.isReposted ? "Removes your repost" : "Reposts to your timeline")
            .accessibilityAddTraits(post.isReposted ? .isSelected : [])
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
            .accessibilityLabel("Quote")
            .accessibilityHint("Opens the composer with this post quoted")
            .accessibilityAddTraits(post.isQuoted ? .isSelected : [])
            .frame(maxWidth: .infinity)

            // Like button
            UnifiedLikeButton(
                isLiked: post.isLiked,
                count: post.likeCount,
                platform: post.platform,
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
            .accessibilityLabel("Like")
            .accessibilityValue(likeValue(count: post.likeCount, isLiked: post.isLiked))
            .accessibilityHint(post.isLiked ? "Removes your like" : "Likes this post")
            .accessibilityAddTraits(post.isLiked ? .isSelected : [])
            .frame(maxWidth: .infinity)

            // Share button
            PostShareButton(
                post: post,
                onTap: { onAction(.share) }
            )
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityLabel("Share")
            .accessibilityHint("Opens share options")

            // Menu button (three dots)
            Menu {
                menuOpenTrigger

                ForEach(PostAction.platformActions(for: post), id: \.self) { action in
                    menuButton(for: action)
                }

                Divider()

                watchButton

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
            // Pre-warm a tap haptic so the menu open feels
            // acknowledged. Mirrors PostMenu.swift's pattern
            // (the canonical kebab menu has the same beat).
            .simultaneousGesture(
                TapGesture().onEnded {
                    HapticEngine.tap.trigger()
                    onMenuOpen?()
                }
            )
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("More options")
            .accessibilityHint("Shows additional actions for this post")
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 0)
    }

    /// Derives current action state from the post for menu label computation
    private var currentState: PostActionState {
        post.makeActionState()
    }

    // MARK: - Accessibility values

    fileprivate func replyValue(count: Int, isReplied: Bool) -> String {
        let parts = [
            isReplied ? "You replied" : nil,
            count > 0 ? "\(count) repl\(count == 1 ? "y" : "ies")" : nil,
        ].compactMap { $0 }
        return parts.joined(separator: ", ")
    }

    fileprivate func repostValue(count: Int, isReposted: Bool) -> String {
        let parts = [
            isReposted ? "Reposted" : nil,
            count > 0 ? "\(count) repost\(count == 1 ? "" : "s")" : nil,
        ].compactMap { $0 }
        return parts.joined(separator: ", ")
    }

    fileprivate func likeValue(count: Int, isLiked: Bool) -> String {
        let parts = [
            isLiked ? "Liked" : nil,
            count > 0 ? "\(count) like\(count == 1 ? "" : "s")" : nil,
        ].compactMap { $0 }
        return parts.joined(separator: ", ")
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

    @ViewBuilder
    private var watchButton: some View {
        let isWatching = watchedConversationStore.isWatching(rootPostID: post.id)
        Button {
            if isWatching {
                watchedConversationStore.unwatch(rootPostID: post.id)
                HapticEngine.selection.trigger()
            } else {
                let moment = fusedMomentStore.moment(for: post.id)
                watchedConversationStore.watch(WatchedConversation(
                    rootPostID: post.id,
                    platform: post.platform,
                    fusedMomentID: moment?.id,
                    summary: WatchedConversation.Summary(
                        authorName: post.authorName,
                        contentPreview: post.content
                    )
                ))
                // Starting a watch is a commitment ("ping me on either
                // network"), worth the success notification. Unwatch is
                // just a removal — selection-changed haptic is enough.
                HapticEngine.success.trigger()
            }
        } label: {
            Label(
                isWatching ? "Stop watching" : "Watch conversation",
                systemImage: isWatching ? "bell.slash" : "bell"
            )
        }
    }
}

struct ActionBarV2: View {
    @ObservedObject var post: Post
    @ObservedObject var store: PostActionStore
    let coordinator: PostActionCoordinator
    let onAction: (PostAction) -> Void
    let onMenuOpen: (() -> Void)?

    @EnvironmentObject private var watchedConversationStore: WatchedConversationStore
    @EnvironmentObject private var fusedMomentStore: FusedMomentStore

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
        .accessibilityLabel("Quote")
        .accessibilityHint("Opens the composer with this post quoted")
        .accessibilityAddTraits(state.isQuoted ? .isSelected : [])
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
            .accessibilityLabel("Reply")
            .accessibilityValue(actionBarReplyValue(count: state.replyCount, isReplied: state.isReplied))
            .accessibilityHint("Opens the reply composer")
            .frame(maxWidth: .infinity)

            UnifiedRepostButton(
                isReposted: state.isReposted,
                count: state.repostCount,
                isProcessing: isProcessing,
                onTap: { coordinator.toggleRepost(for: post) }
            )
            .accessibilityLabel("Repost")
            .accessibilityValue(actionBarRepostValue(count: state.repostCount, isReposted: state.isReposted))
            .accessibilityHint(state.isReposted ? "Removes your repost" : "Reposts to your timeline")
            .accessibilityAddTraits(state.isReposted ? .isSelected : [])
            .frame(maxWidth: .infinity)

            UnifiedLikeButton(
                isLiked: state.isLiked,
                count: state.likeCount,
                platform: post.platform,
                isProcessing: isProcessing,
                onTap: { coordinator.toggleLike(for: post) }
            )
            .accessibilityLabel("Like")
            .accessibilityValue(actionBarLikeValue(count: state.likeCount, isLiked: state.isLiked))
            .accessibilityHint(state.isLiked ? "Removes your like" : "Likes this post")
            .accessibilityAddTraits(state.isLiked ? .isSelected : [])
            .frame(maxWidth: .infinity)

            quoteButton
                .frame(maxWidth: .infinity)

            PostShareButton(
                post: post,
                onTap: { onAction(.share) }
            )
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityLabel("Share")
            .accessibilityHint("Opens share options")

            Menu {
                menuOpenTrigger

                ForEach(PostAction.platformActions(for: post), id: \.self) { action in
                    menuButton(for: action)
                }

                Divider()

                watchButton

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
            // Pre-warm a tap haptic so the menu open feels
            // acknowledged. Mirrors PostMenu.swift's pattern
            // (the canonical kebab menu has the same beat).
            .simultaneousGesture(
                TapGesture().onEnded {
                    HapticEngine.tap.trigger()
                    onMenuOpen?()
                }
            )
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("More options")
            .accessibilityHint("Shows additional actions for this post")
            .frame(maxWidth: .infinity, minHeight: 44)
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

    // MARK: - Accessibility values

    private func actionBarReplyValue(count: Int, isReplied: Bool) -> String {
        let parts = [
            isReplied ? "You replied" : nil,
            count > 0 ? "\(count) repl\(count == 1 ? "y" : "ies")" : nil,
        ].compactMap { $0 }
        return parts.joined(separator: ", ")
    }

    private func actionBarRepostValue(count: Int, isReposted: Bool) -> String {
        let parts = [
            isReposted ? "Reposted" : nil,
            count > 0 ? "\(count) repost\(count == 1 ? "" : "s")" : nil,
        ].compactMap { $0 }
        return parts.joined(separator: ", ")
    }

    private func actionBarLikeValue(count: Int, isLiked: Bool) -> String {
        let parts = [
            isLiked ? "Liked" : nil,
            count > 0 ? "\(count) like\(count == 1 ? "" : "s")" : nil,
        ].compactMap { $0 }
        return parts.joined(separator: ", ")
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

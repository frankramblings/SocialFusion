import SwiftUI

// MARK: - Unified Like Button

struct UnifiedLikeButton: View {
    let isLiked: Bool
    let count: Int
    let isProcessing: Bool
    let onTap: () async -> Void

    @State private var isPressed = false
    @State private var errorShake = false

    var body: some View {
        Button {
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()

            Task { await onTap() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 18))
                    .foregroundColor(isLiked ? .red : .secondary)
                    .scaleEffect(isLiked ? 1.1 : 1.0)
                    .animation(
                        .spring(response: 0.12, dampingFraction: 0.7, blendDuration: 0.05),
                        value: isLiked
                    )

                if count > 0 {
                    if #available(iOS 17.0, *) {
                        Text(formatCount(count))
                            .font(.caption)
                            .foregroundColor(isLiked ? .red : .secondary)
                            .contentTransition(.numericText())
                            .animation(
                                .spring(response: 0.12, dampingFraction: 0.7, blendDuration: 0.05),
                                value: count
                            )
                    } else {
                    Text(formatCount(count))
                        .font(.caption)
                        .foregroundColor(isLiked ? .red : .secondary)
                        .animation(
                                .spring(response: 0.12, dampingFraction: 0.7, blendDuration: 0.05),
                                value: count
                        )
                    }
                }
            }
            .opacity(isProcessing ? 0.6 : 1.0)
            .scaleEffect(isPressed ? 0.85 : 1.0)
            .offset(x: errorShake ? -5 : 0)
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .animation(
            .interactiveSpring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.05),
            value: isPressed
        )
        .onLongPressGesture(
            minimumDuration: 0, maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(
                    .interactiveSpring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.05)
                ) {
                    isPressed = pressing
                }
            }, perform: {}
        )
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}

// MARK: - Unified Repost Button

struct UnifiedRepostButton: View {
    let isReposted: Bool
    let count: Int
    let isProcessing: Bool
    let onTap: () async -> Void

    @State private var isPressed = false
    @State private var errorShake = false

    var body: some View {
        Button {
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()

            Task { await onTap() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isReposted ? "arrow.2.squarepath" : "arrow.2.squarepath")
                    .font(.system(size: 18))
                    .foregroundColor(isReposted ? .green : .secondary)
                    .scaleEffect(isReposted ? 1.1 : 1.0)
                    .animation(
                        .spring(response: 0.12, dampingFraction: 0.7, blendDuration: 0.05),
                        value: isReposted
                    )

                if count > 0 {
                    if #available(iOS 17.0, *) {
                        Text(formatCount(count))
                            .font(.caption)
                            .foregroundColor(isReposted ? .green : .secondary)
                            .contentTransition(.numericText())
                            .animation(
                                .spring(response: 0.12, dampingFraction: 0.7, blendDuration: 0.05),
                                value: count
                            )
                    } else {
                    Text(formatCount(count))
                        .font(.caption)
                        .foregroundColor(isReposted ? .green : .secondary)
                        .animation(
                                .spring(response: 0.12, dampingFraction: 0.7, blendDuration: 0.05),
                                value: count
                        )
                    }
                }
            }
            .opacity(isProcessing ? 0.6 : 1.0)
            .scaleEffect(isPressed ? 0.85 : 1.0)
            .offset(x: errorShake ? -5 : 0)
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .animation(
            .interactiveSpring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.05),
            value: isPressed
        )
        .onLongPressGesture(
            minimumDuration: 0, maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(
                    .interactiveSpring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.05)
                ) {
                    isPressed = pressing
                }
            }, perform: {}
        )
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}

// MARK: - Unified Reply Button

struct UnifiedReplyButton: View {
    let count: Int
    let isReplied: Bool
    let platform: SocialPlatform
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()

            onTap()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 18))
                    .foregroundColor(isReplied ? platformColor : .secondary)
                    .scaleEffect(isReplied ? 1.05 : 1.0)
                    .animation(
                        .spring(response: 0.12, dampingFraction: 0.7, blendDuration: 0.05),
                        value: isReplied
                    )

                if count > 0 {
                    if #available(iOS 17.0, *) {
                        Text(formatCount(count))
                            .font(.caption)
                            .foregroundColor(isReplied ? platformColor : .secondary)
                            .contentTransition(.numericText())
                            .animation(
                                .spring(response: 0.12, dampingFraction: 0.7, blendDuration: 0.05),
                                value: count
                            )
                    } else {
                    Text(formatCount(count))
                        .font(.caption)
                        .foregroundColor(isReplied ? platformColor : .secondary)
                        .animation(
                                .spring(response: 0.12, dampingFraction: 0.7, blendDuration: 0.05),
                                value: count
                        )
                    }
                }
            }
            .scaleEffect(isPressed ? 0.85 : 1.0)
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .animation(
            .interactiveSpring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.05),
            value: isPressed
        )
        .onLongPressGesture(
            minimumDuration: 0, maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(
                    .interactiveSpring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.05)
                ) {
                    isPressed = pressing
                }
            }, perform: {}
        )
    }

    private var platformColor: Color {
        switch platform {
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}

struct UnifiedInteractionButtons: View {
    let post: Post
    @ObservedObject var store: PostActionStore
    let coordinator: PostActionCoordinator
    let onReply: () -> Void
    let onShare: () -> Void
    let includeShare: Bool

    init(
        post: Post,
        store: PostActionStore,
        coordinator: PostActionCoordinator,
        onReply: @escaping () -> Void,
        onShare: @escaping () -> Void,
        includeShare: Bool = true
    ) {
        self.post = post
        self._store = ObservedObject(initialValue: store)
        self.coordinator = coordinator
        self.onReply = onReply
        self.onShare = onShare
        self.includeShare = includeShare
    }

    private var actionKey: String { post.stableId }

    private var state: PostActionState {
        store.state(for: post)
    }

    private var isProcessing: Bool {
        store.inflightKeys.contains(actionKey)
    }

    private var isPending: Bool {
        store.pendingKeys.contains(actionKey)
    }

    var body: some View {
        HStack {
            UnifiedReplyButton(
                count: state.replyCount,
                isReplied: post.isReplied,
                platform: post.platform,
                onTap: onReply
            )
            .accessibilityLabel(post.isReplied ? "Reply sent. Double tap to reply again" : "Reply. Double tap to reply")

            Spacer()

            UnifiedRepostButton(
                isReposted: state.isReposted,
                count: state.repostCount,
                isProcessing: isProcessing,
                onTap: { coordinator.toggleRepost(for: post) }
            )
            .accessibilityLabel(state.isReposted ? "Reposted. Double tap to undo repost" : "Repost. Double tap to repost")

            Spacer()

            UnifiedLikeButton(
                isLiked: state.isLiked,
                count: state.likeCount,
                isProcessing: isProcessing,
                onTap: { coordinator.toggleLike(for: post) }
            )
            .accessibilityLabel(state.isLiked ? "Liked. Double tap to unlike" : "Like. Double tap to like")

            if includeShare {
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
                .frame(width: 44, height: 44)
                .buttonStyle(SmoothScaleButtonStyle())
                .accessibilityLabel("Share")
            }
        }
        .opacity(isPending ? 0.7 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isProcessing)
    }
}

// MARK: - Preview

#Preview("Unified Buttons") {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            UnifiedReplyButton(
                count: 42,
                isReplied: false,
                platform: .bluesky,
                onTap: {}
            )

            UnifiedRepostButton(
                isReposted: true,
                count: 123,
                isProcessing: false,
                onTap: {}
            )

            UnifiedLikeButton(
                isLiked: true,
                count: 456,
                isProcessing: false,
                onTap: {}
            )
        }

        HStack(spacing: 16) {
            UnifiedReplyButton(
                count: 0,
                isReplied: true,
                platform: .mastodon,
                onTap: {}
            )

            UnifiedRepostButton(
                isReposted: false,
                count: 0,
                isProcessing: true,
                onTap: {}
            )

            UnifiedLikeButton(
                isLiked: false,
                count: 0,
                isProcessing: false,
                onTap: {}
            )
        }
    }
    .padding()
}

// MARK: - Small Unified Buttons (Convenience Wrappers)

struct SmallUnifiedReplyButton: View {
    let count: Int
    let isReplied: Bool
    let platform: SocialPlatform
    let onTap: () -> Void
    
    var body: some View {
        UnifiedReplyButton(
            count: count,
            isReplied: isReplied,
            platform: platform,
            onTap: onTap
        )
        .scaleEffect(0.85) // Make it smaller
    }
}

struct SmallUnifiedRepostButton: View {
    let isReposted: Bool
    let count: Int
    var isProcessing: Bool = false
    let onTap: () -> Void
    
    var body: some View {
        UnifiedRepostButton(
            isReposted: isReposted,
            count: count,
            isProcessing: isProcessing,
            onTap: { onTap() }
        )
        .scaleEffect(0.85)
    }
}

struct SmallUnifiedLikeButton: View {
    let isLiked: Bool
    let count: Int
    var isProcessing: Bool = false
    let onTap: () -> Void
    
    var body: some View {
        UnifiedLikeButton(
            isLiked: isLiked,
            count: count,
            isProcessing: isProcessing,
            onTap: { onTap() }
        )
        .scaleEffect(0.85)
    }
}

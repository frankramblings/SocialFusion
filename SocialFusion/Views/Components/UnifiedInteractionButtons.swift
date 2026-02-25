import SwiftUI

// MARK: - Shake Effect

struct ShakeEffect: GeometryEffect {
  var amount: CGFloat = 5
  var shakesPerUnit = 3
  var animatableData: CGFloat

  func effectValue(size: CGSize) -> ProjectionTransform {
    ProjectionTransform(
      CGAffineTransform(translationX: amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)), y: 0)
    )
  }
}

// MARK: - Unified Like Button

struct UnifiedLikeButton: View {
  let isLiked: Bool
  let count: Int
  let platform: SocialPlatform
  let isProcessing: Bool
  let onTap: () async -> Void

  @State private var isPressed = false
  @State private var errorShake = false
  @State private var animateLike = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var likeColor: Color {
    switch platform {
    case .mastodon:
      return Color(red: 255 / 255, green: 179 / 255, blue: 0)  // Gold
    case .bluesky:
      return .red
    }
  }

  var body: some View {
    Button {
      if !isLiked {
        // Haptic on like only — absence is feedback on unlike
        HapticEngine.tap.trigger()

        if !reduceMotion {
          withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.5)) {
            animateLike = true
          }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.15)) {
              animateLike = false
            }
          }
        }
      }

      Task { await onTap() }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: isLiked ? "heart.fill" : "heart")
          .font(.system(size: 18))
          .foregroundColor(isLiked ? likeColor : .secondary)
          .scaleEffect(animateLike ? 1.3 : (isLiked ? 1.05 : 1.0))
          .animation(
            reduceMotion ? .none : .spring(response: 0.12, dampingFraction: 0.7, blendDuration: 0.05),
            value: isLiked
          )

        RollingNumberView(count, font: .caption, color: isLiked ? likeColor : .secondary)
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
}

// MARK: - Unified Repost Button

struct UnifiedRepostButton: View {
  let isReposted: Bool
  let count: Int
  let isProcessing: Bool
  let onTap: () async -> Void

  @State private var isPressed = false
  @State private var errorShake = false
  @State private var rotationDegrees: Double = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button {
      if !isReposted {
        // Weightier haptic for amplifying someone's voice
        HapticEngine.selection.trigger()

        if !reduceMotion {
          withAnimation(.easeInOut(duration: 0.5)) {
            rotationDegrees += 360
          }
        }
      }

      Task { await onTap() }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "arrow.2.squarepath")
          .font(.system(size: 18))
          .foregroundColor(isReposted ? .green : .secondary)
          .rotationEffect(.degrees(rotationDegrees))
          .scaleEffect(isReposted ? 1.1 : 1.0)
          .animation(
            reduceMotion ? .none : .spring(response: 0.12, dampingFraction: 0.7, blendDuration: 0.05),
            value: isReposted
          )

        RollingNumberView(count, font: .caption, color: isReposted ? .green : .secondary)
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
}

// MARK: - Unified Reply Button

struct UnifiedReplyButton: View {
  let count: Int
  let isReplied: Bool
  let platform: SocialPlatform
  let isProcessing: Bool
  let onTap: () async -> Void

  @State private var isPressed = false
  @State private var errorShake = false
  @State private var bounceForward = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button {
      // Haptic feedback
      HapticEngine.tap.trigger()

      if !reduceMotion {
        withAnimation(.spring(response: 0.15, dampingFraction: 0.4)) {
          bounceForward = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
          withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
            bounceForward = false
          }
        }
      }

      Task { await onTap() }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "bubble.left")
          .font(.system(size: 18))
          .foregroundColor(isReplied ? platformColor : .secondary)
          .offset(x: bounceForward ? 2 : 0)
          .scaleEffect(isReplied ? 1.05 : 1.0)
          .animation(
            reduceMotion ? .none : .spring(response: 0.12, dampingFraction: 0.7, blendDuration: 0.05),
            value: isReplied
          )

        RollingNumberView(count, font: Font.caption, color: isReplied ? platformColor : Color.secondary)
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

  private var platformColor: Color {
    switch platform {
    case .mastodon:
      return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
    case .bluesky:
      return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
    }
  }
}

// MARK: - Unified Quote Button

struct UnifiedQuoteButton: View {
  let isQuoted: Bool
  let platform: SocialPlatform
  let isProcessing: Bool
  let onTap: () async -> Void

  @State private var isPressed = false
  @State private var errorShake = false

  private var platformColor: Color {
    switch platform {
    case .mastodon:
      return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
    case .bluesky:
      return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
    }
  }

  var body: some View {
    Button {
      // Haptic feedback
      HapticEngine.tap.trigger()

      Task { await onTap() }
    } label: {
      Image(systemName: "quote.opening")
        .font(.system(size: 18))
        .foregroundColor(isQuoted ? platformColor : .secondary)
        .scaleEffect(isQuoted ? 1.1 : 1.0)
        .animation(
          .spring(response: 0.12, dampingFraction: 0.7, blendDuration: 0.05),
          value: isQuoted
        )
    }
    .opacity(isProcessing ? 0.6 : 1.0)
    .scaleEffect(isPressed ? 0.85 : 1.0)
    .offset(x: errorShake ? -5 : 0)
    .frame(minWidth: 44, minHeight: 44)
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
}

struct UnifiedInteractionButtons: View {
  let post: Post
  @ObservedObject var store: PostActionStore
  let coordinator: PostActionCoordinator
  let onReply: () async -> Void
  let onShare: () -> Void
  let includeShare: Bool

  init(
    post: Post,
    store: PostActionStore,
    coordinator: PostActionCoordinator,
    onReply: @escaping () async -> Void,
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

  private var hasError: Bool {
    store.errorKeys.contains(actionKey)
  }

  var body: some View {
    HStack {
      UnifiedReplyButton(
        count: state.replyCount,
        isReplied: state.isReplied,
        platform: post.platform,
        isProcessing: isProcessing,
        onTap: { await onReply() }
      )
      .modifier(ShakeEffect(animatableData: hasError ? 1 : 0))
      .animation(.default, value: hasError)
      .accessibilityLabel(state.isReplied ? "Reply sent. Double tap to reply again" : "Reply. Double tap to reply")

      Spacer()

      UnifiedRepostButton(
        isReposted: state.isReposted,
        count: state.repostCount,
        isProcessing: isProcessing,
        onTap: { coordinator.toggleRepost(for: post) }
      )
      .modifier(ShakeEffect(animatableData: hasError ? 1 : 0))
      .animation(.default, value: hasError)
      .accessibilityLabel(state.isReposted ? "Reposted. Double tap to undo repost" : "Repost. Double tap to repost")

      Spacer()

      UnifiedLikeButton(
        isLiked: state.isLiked,
        count: state.likeCount,
        platform: post.platform,
        isProcessing: isProcessing,
        onTap: { coordinator.toggleLike(for: post) }
      )
      .modifier(ShakeEffect(animatableData: hasError ? 1 : 0))
      .animation(.default, value: hasError)
      .accessibilityLabel(state.isLiked ? "Liked. Double tap to unlike" : "Like. Double tap to like")

      Spacer()

      UnifiedQuoteButton(
        isQuoted: state.isQuoted,
        platform: post.platform,
        isProcessing: false,  // Quote opens compose view, no async processing needed
        onTap: {
          await onReply()  // Quote uses reply handler for now
        }
      )
      .modifier(ShakeEffect(animatableData: hasError ? 1 : 0))
      .animation(.default, value: hasError)
      .accessibilityLabel(state.isQuoted ? "Quoted. Double tap to quote again" : "Quote Post")

      if includeShare {
        Spacer()

        PostShareButton(
          post: post,
          onTap: onShare
        )
        .frame(width: 44, height: 44)
        .accessibilityLabel("Share post")
        .accessibilityHint("Opens share options")
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
        isProcessing: false,
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
        platform: .bluesky,
        isProcessing: false,
        onTap: {}
      )
    }

    HStack(spacing: 16) {
      UnifiedReplyButton(
        count: 0,
        isReplied: true,
        platform: .mastodon,
        isProcessing: false,
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
        platform: .mastodon,
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
  let isProcessing: Bool
  let onTap: () async -> Void

  var body: some View {
    UnifiedReplyButton(
      count: count,
      isReplied: isReplied,
      platform: platform,
      isProcessing: isProcessing,
      onTap: onTap
    )
    .scaleEffect(0.85)  // Make it smaller
  }
}

struct SmallUnifiedRepostButton: View {
  let isReposted: Bool
  let count: Int
  var isProcessing: Bool = false
  let onTap: () async -> Void

  var body: some View {
    UnifiedRepostButton(
      isReposted: isReposted,
      count: count,
      isProcessing: isProcessing,
      onTap: onTap
    )
    .scaleEffect(0.85)
  }
}

struct SmallUnifiedLikeButton: View {
  let isLiked: Bool
  let count: Int
  let platform: SocialPlatform
  var isProcessing: Bool = false
  let onTap: () async -> Void

  var body: some View {
    UnifiedLikeButton(
      isLiked: isLiked,
      count: count,
      platform: platform,
      isProcessing: isProcessing,
      onTap: onTap
    )
    .scaleEffect(0.85)
  }
}

struct SmallUnifiedQuoteButton: View {
  let isQuoted: Bool
  let platform: SocialPlatform
  var isProcessing: Bool = false
  let onTap: () async -> Void

  var body: some View {
    UnifiedQuoteButton(
      isQuoted: isQuoted,
      platform: platform,
      isProcessing: isProcessing,
      onTap: onTap
    )
    .scaleEffect(0.85)
  }
}

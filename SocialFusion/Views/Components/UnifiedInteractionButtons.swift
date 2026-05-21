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

// MARK: - Heart Burst Particle

/// A single particle in the heart-burst effect that radiates outward when liking a post.
/// Each particle has its own angle, distance, scale, and opacity curve to feel organic.
private struct HeartBurstParticle: View {
  let angle: Double
  let distance: CGFloat
  let scale: CGFloat
  let color: Color
  let symbol: String
  let progress: CGFloat  // 0 -> 1

  var body: some View {
    // Custom easing: fast out, slow in, fade at the end
    let eased = 1 - pow(1 - progress, 2.4)
    let x = cos(angle * .pi / 180) * distance * eased
    let y = sin(angle * .pi / 180) * distance * eased
    // Particles grow quickly, then settle
    let currentScale = scale * (progress < 0.3
      ? (progress / 0.3) * 1.2
      : 1.0 + (1 - progress) * 0.15)
    // Opacity ramps up fast, fades smoothly
    let opacity: Double = progress < 0.15
      ? Double(progress / 0.15)
      : Double(1.0 - max(0, (progress - 0.55) / 0.45))

    Image(systemName: symbol)
      .font(.system(size: 7, weight: .bold))
      .foregroundColor(color)
      .scaleEffect(currentScale)
      .opacity(opacity)
      .offset(x: x, y: y)
  }
}

/// A burst of hearts radiating from a center point.
/// Uses TimelineView for buttery-smooth particle animation independent of view updates.
private struct HeartBurstView: View {
  let color: Color
  let startDate: Date
  let duration: Double = 0.7

  // 8 particles at varying angles, distances, and sizes for an organic feel
  private let particles: [(angle: Double, distance: CGFloat, scale: CGFloat, symbol: String)] = [
    (angle:  -90, distance: 28, scale: 1.0,  symbol: "heart.fill"),
    (angle:  -50, distance: 24, scale: 0.85, symbol: "heart.fill"),
    (angle:  -10, distance: 30, scale: 1.0,  symbol: "heart.fill"),
    (angle:   30, distance: 24, scale: 0.8,  symbol: "heart.fill"),
    (angle:   90, distance: 26, scale: 0.9,  symbol: "heart.fill"),
    (angle:  130, distance: 22, scale: 0.75, symbol: "heart.fill"),
    (angle:  170, distance: 28, scale: 0.95, symbol: "heart.fill"),
    (angle: -130, distance: 24, scale: 0.8,  symbol: "heart.fill"),
  ]

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
      let elapsed = context.date.timeIntervalSince(startDate)
      let progress = CGFloat(min(max(elapsed / duration, 0), 1))

      ZStack {
        // Radial ring flash — a single white-hot pulse that fades immediately
        Circle()
          .stroke(color.opacity(0.6), lineWidth: 2)
          .frame(width: 8 + progress * 36, height: 8 + progress * 36)
          .opacity(progress < 0.5 ? Double(1.0 - progress * 2) : 0)
          .blur(radius: progress * 1.5)

        ForEach(0..<particles.count, id: \.self) { i in
          let p = particles[i]
          HeartBurstParticle(
            angle: p.angle,
            distance: p.distance,
            scale: p.scale,
            color: color,
            symbol: p.symbol,
            progress: progress
          )
        }
      }
      .allowsHitTesting(false)
    }
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
  @State private var burstStart: Date? = nil
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
          // Trigger particle burst
          burstStart = Date()
          // Auto-clear after burst completes
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            if let start = burstStart, Date().timeIntervalSince(start) >= 0.7 {
              burstStart = nil
            }
          }

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
        ZStack {
          // Particle burst overlays the heart without affecting layout
          if let start = burstStart, !reduceMotion {
            HeartBurstView(color: likeColor, startDate: start)
              .frame(width: 1, height: 1)
              .allowsHitTesting(false)
          }

          Image(systemName: isLiked ? "heart.fill" : "heart")
            .font(.system(size: 18))
            .foregroundColor(isLiked ? likeColor : .secondary)
            .contentTransition(.symbolEffect(.replace))
            .scaleEffect(animateLike ? 1.35 : (isLiked ? 1.05 : 1.0))
            .animation(
              reduceMotion ? .none : .spring(response: 0.12, dampingFraction: 0.6, blendDuration: 0.05),
              value: isLiked
            )
        }

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

  private var platformColor: Color { platform.swiftUIColor }
}

// MARK: - Unified Quote Button

struct UnifiedQuoteButton: View {
  let isQuoted: Bool
  let platform: SocialPlatform
  let isProcessing: Bool
  let onTap: () async -> Void

  @State private var isPressed = false
  @State private var errorShake = false

  private var platformColor: Color { platform.swiftUIColor }

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

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

  // MARK: - Accessibility values
  //
  // VoiceOver reads label → value → traits → hint. Label is the action ("Like"),
  // value is the current state and count ("Liked, 42 likes"), traits convey
  // selection, and hint describes what tapping does — without the redundant
  // "Double tap to..." phrasing that VoiceOver synthesizes automatically.

  private var replyAccessibilityValue: String {
    let countPart = state.replyCount > 0
      ? "\(state.replyCount) repl\(state.replyCount == 1 ? "y" : "ies")"
      : ""
    return [state.isReplied ? "You replied" : nil, countPart.isEmpty ? nil : countPart]
      .compactMap { $0 }
      .joined(separator: ", ")
  }

  private var repostAccessibilityValue: String {
    let countPart = state.repostCount > 0
      ? "\(state.repostCount) repost\(state.repostCount == 1 ? "" : "s")"
      : ""
    return [state.isReposted ? "Reposted" : nil, countPart.isEmpty ? nil : countPart]
      .compactMap { $0 }
      .joined(separator: ", ")
  }

  private var likeAccessibilityValue: String {
    let countPart = state.likeCount > 0
      ? "\(state.likeCount) like\(state.likeCount == 1 ? "" : "s")"
      : ""
    return [state.isLiked ? "Liked" : nil, countPart.isEmpty ? nil : countPart]
      .compactMap { $0 }
      .joined(separator: ", ")
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
      .animation(reduceMotion ? nil : .default, value: hasError)
      .accessibilityLabel("Reply")
      .accessibilityValue(replyAccessibilityValue)
      .accessibilityHint("Opens the reply composer")

      Spacer()

      UnifiedRepostButton(
        isReposted: state.isReposted,
        count: state.repostCount,
        isProcessing: isProcessing,
        onTap: { coordinator.toggleRepost(for: post) }
      )
      .modifier(ShakeEffect(animatableData: hasError ? 1 : 0))
      .animation(reduceMotion ? nil : .default, value: hasError)
      .accessibilityLabel("Repost")
      .accessibilityValue(repostAccessibilityValue)
      .accessibilityHint(state.isReposted ? "Removes your repost" : "Reposts to your timeline")
      .accessibilityAddTraits(state.isReposted ? .isSelected : [])

      Spacer()

      UnifiedLikeButton(
        isLiked: state.isLiked,
        count: state.likeCount,
        platform: post.platform,
        isProcessing: isProcessing,
        onTap: { coordinator.toggleLike(for: post) }
      )
      .modifier(ShakeEffect(animatableData: hasError ? 1 : 0))
      .animation(reduceMotion ? nil : .default, value: hasError)
      .accessibilityLabel("Like")
      .accessibilityValue(likeAccessibilityValue)
      .accessibilityHint(state.isLiked ? "Removes your like" : "Likes this post")
      .accessibilityAddTraits(state.isLiked ? .isSelected : [])

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
      .animation(reduceMotion ? nil : .default, value: hasError)
      .accessibilityLabel("Quote")
      .accessibilityHint("Opens the composer with this post quoted")
      .accessibilityAddTraits(state.isQuoted ? .isSelected : [])

      if includeShare {
        Spacer()

        PostShareButton(
          post: post,
          onTap: onShare
        )
        .frame(width: 44, height: 44)
        .accessibilityLabel("Share")
        .accessibilityHint("Opens share options")
      }
    }
    .opacity(isPending ? 0.7 : 1.0)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isProcessing)
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

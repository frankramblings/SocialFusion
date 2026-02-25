# Timeline Polish & Interaction Feedback — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform the timeline scrolling feel and interaction feedback to best-in-class indie app quality — skeleton loading, spring animations, rich haptics, living motion.

**Architecture:** Additive polish layer on existing MVVM architecture. New reusable animation components (`SkeletonPostCard`, `RollingNumberView`, `AnimatedHeartButton`, etc.) composed into existing views. No structural changes to controllers, stores, or data flow. All animations respect `reduceMotion` and maintain 60fps scroll.

**Tech Stack:** SwiftUI animations (`.spring`, `.interactiveSpring`, `matchedGeometryEffect`), `TimelineView(.animation)` for shimmer, `GeometryReader` for parallax, existing `HapticEngine`, existing `PostActionStore` optimistic updates.

**Design doc:** `docs/plans/2026-02-25-timeline-polish-design.md`

---

## Task 1: Skeleton Post Card Component

Creates the shimmer placeholder that replaces the loading spinner.

**Files:**
- Create: `SocialFusion/Views/Components/SkeletonPostCard.swift`
- Modify: `SocialFusion/Views/ConsolidatedTimelineView.swift` (lines ~498-508, loading state)

**Step 1: Create SkeletonPostCard.swift**

```swift
import SwiftUI

/// Shimmer placeholder matching PostCardView layout.
/// Uses a single shared TimelineView for efficient animation.
struct SkeletonPostCard: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Shared phase drives all shimmer bars in sync.
  let shimmerPhase: Double

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      // Avatar circle
      Circle()
        .fill(shimmerGradient)
        .frame(width: 44, height: 44)

      VStack(alignment: .leading, spacing: 8) {
        // Display name bar
        RoundedRectangle(cornerRadius: 4)
          .fill(shimmerGradient)
          .frame(width: 120, height: 14)

        // Handle bar
        RoundedRectangle(cornerRadius: 4)
          .fill(shimmerGradient)
          .frame(width: 80, height: 12)

        // Body text lines
        VStack(alignment: .leading, spacing: 6) {
          ForEach(0..<3, id: \.self) { i in
            RoundedRectangle(cornerRadius: 4)
              .fill(shimmerGradient)
              .frame(maxWidth: i == 2 ? 180 : .infinity, height: 12)
          }
        }
        .padding(.top, 4)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Loading post")
  }

  private var shimmerGradient: some ShapeStyle {
    if reduceMotion {
      return AnyShapeStyle(Color.gray.opacity(0.15))
    }
    return AnyShapeStyle(
      LinearGradient(
        stops: [
          .init(color: Color.gray.opacity(0.1), location: shimmerPhase - 0.3),
          .init(color: Color.gray.opacity(0.25), location: shimmerPhase),
          .init(color: Color.gray.opacity(0.1), location: shimmerPhase + 0.3),
        ],
        startPoint: .leading,
        endPoint: .trailing
      )
    )
  }
}

/// Container that drives the shimmer animation for multiple skeleton cards.
struct SkeletonTimelineView: View {
  let cardCount: Int

  init(cardCount: Int = 5) {
    self.cardCount = min(cardCount, 6) // Performance cap
  }

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
      let phase = shimmerPhase(for: timeline.date)
      LazyVStack(spacing: 0) {
        ForEach(0..<cardCount, id: \.self) { _ in
          SkeletonPostCard(shimmerPhase: phase)
          Divider().padding(.leading, 72)
        }
      }
    }
  }

  private func shimmerPhase(for date: Date) -> Double {
    let seconds = date.timeIntervalSinceReferenceDate
    // 1.5 second cycle, 0 → 1.3 range
    return (seconds.truncatingRemainder(dividingBy: 1.5) / 1.5) * 1.3
  }
}
```

**Step 2: Replace loading state in ConsolidatedTimelineView**

In `ConsolidatedTimelineView.swift`, find the loading state (around line 498-508):

```swift
// BEFORE (around line 503):
case .loading:
    ConsolidatedTimelineEmptyStateView(
        state: .loading,
        onRetry: {
            controller.refreshTimeline()
        },

// AFTER:
case .loading:
    SkeletonTimelineView()
        .transition(.opacity)
```

Keep `ConsolidatedTimelineEmptyStateView` for other states (noAccounts, offline, etc.) — only replace `.loading`.

**Step 3: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add SocialFusion/Views/Components/SkeletonPostCard.swift
git add SocialFusion/Views/ConsolidatedTimelineView.swift
git commit -m "feat: add skeleton shimmer loading for timeline

Replace spinner with shimmer placeholders matching PostCardView layout.
Uses shared TimelineView for efficient animation. Max 6 cards.
Respects reduceMotion accessibility setting."
```

---

## Task 2: Rolling Number View Component

Reusable animated count display for all action buttons.

**Files:**
- Create: `SocialFusion/Views/Components/RollingNumberView.swift`

**Step 1: Create RollingNumberView.swift**

```swift
import SwiftUI

/// Animated number display that rolls digits vertically on change.
/// Increment rolls up, decrement rolls down.
struct RollingNumberView: View {
  let value: Int
  let font: Font
  let color: Color

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(_ value: Int, font: Font = .caption, color: Color = .secondary) {
    self.value = value
    self.font = font
    self.color = color
  }

  var body: some View {
    if value > 0 {
      if reduceMotion {
        Text(formattedValue)
          .font(font)
          .foregroundColor(color)
      } else {
        Text(formattedValue)
          .font(font)
          .foregroundColor(color)
          .contentTransition(.numericText(value: Double(value)))
          .animation(.spring(response: 0.2, dampingFraction: 0.8), value: value)
      }
    }
  }

  private var formattedValue: String {
    if value >= 1_000_000 {
      return String(format: "%.1fM", Double(value) / 1_000_000)
    } else if value >= 1_000 {
      return String(format: "%.1fK", Double(value) / 1_000)
    } else {
      return "\(value)"
    }
  }
}
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 3: Commit**

```bash
git add SocialFusion/Views/Components/RollingNumberView.swift
git commit -m "feat: add RollingNumberView with spring-animated count transitions

Digits roll vertically on change with spring physics.
Uses contentTransition(.numericText) for smooth morphing.
Respects reduceMotion. Formats K/M thresholds."
```

---

## Task 3: Enhanced Like Button with Heart Animation

Upgrades `UnifiedLikeButton` with the design spec animations.

**Files:**
- Modify: `SocialFusion/Views/Components/UnifiedInteractionButtons.swift` (lines 5-83, UnifiedLikeButton)

**Step 1: Rewrite UnifiedLikeButton**

Replace the existing `UnifiedLikeButton` (lines 5-83) with:

```swift
struct UnifiedLikeButton: View {
  let isLiked: Bool
  let count: Int
  let platform: SocialPlatform
  let isProcessing: Bool
  let onTap: () async -> Void

  @State private var isPressed = false
  @State private var animateLike = false
  @State private var errorShake = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var likeColor: Color {
    switch platform {
    case .mastodon: return Color(red: 255/255, green: 179/255, blue: 0) // gold
    case .bluesky: return .red
    }
  }

  var body: some View {
    Button {
      if !isLiked {
        HapticEngine.tap.trigger()
        if !reduceMotion {
          withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.5)) {
            animateLike = true
          }
          // Settle back after the pop
          Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeOut(duration: 0.15)) {
              animateLike = false
            }
          }
        }
      }
      // No haptic on unlike — absence is feedback
      Task { await onTap() }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: isLiked ? "heart.fill" : "heart")
          .font(.system(size: 18))
          .foregroundColor(isLiked ? likeColor : .secondary)
          .scaleEffect(animateLike ? 1.3 : (isLiked ? 1.05 : 1.0))
          .animation(
            reduceMotion ? .none : .spring(response: 0.12, dampingFraction: 0.7),
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
        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
          isPressed = pressing
        }
      }, perform: {}
    )
  }
}
```

Note: This adds a `platform` parameter. Update all call sites:
- `UnifiedInteractionButtons` body (line ~378): pass `platform: post.platform`
- `SmallUnifiedLikeButton` (line ~508): add `platform` parameter and pass through
- Preview at bottom: add `platform: .bluesky`

**Step 2: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 3: Commit**

```bash
git add SocialFusion/Views/Components/UnifiedInteractionButtons.swift
git commit -m "feat: enhanced like button with heart pop animation

Heart scales to 1.3x with interactive spring on like, settles back.
Platform-aware colors (gold for Mastodon, red for Bluesky).
Uses RollingNumberView for animated count. No haptic on unlike.
Respects reduceMotion."
```

---

## Task 4: Enhanced Repost Button with Rotation Animation

Upgrades `UnifiedRepostButton` with 360-degree rotation on boost.

**Files:**
- Modify: `SocialFusion/Views/Components/UnifiedInteractionButtons.swift` (lines 87-165, UnifiedRepostButton)

**Step 1: Rewrite UnifiedRepostButton**

Replace `UnifiedRepostButton` (lines 87-165) with:

```swift
struct UnifiedRepostButton: View {
  let isReposted: Bool
  let count: Int
  let isProcessing: Bool
  let onTap: () async -> Void

  @State private var isPressed = false
  @State private var rotationDegrees: Double = 0
  @State private var errorShake = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button {
      if !isReposted {
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
            reduceMotion ? .none : .spring(response: 0.12, dampingFraction: 0.7),
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
        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
          isPressed = pressing
        }
      }, perform: {}
    )
  }
}
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 3: Commit**

```bash
git add SocialFusion/Views/Components/UnifiedInteractionButtons.swift
git commit -m "feat: enhanced repost button with 360° rotation animation

Icon rotates full circle on boost with easeInOut over 0.5s.
Uses .selection haptic for weightier feedback.
RollingNumberView for animated count. Respects reduceMotion."
```

---

## Task 5: Enhanced Reply Button with Bounce-Forward Animation

Upgrades `UnifiedReplyButton` with directional bounce.

**Files:**
- Modify: `SocialFusion/Views/Components/UnifiedInteractionButtons.swift` (lines 169-257, UnifiedReplyButton)

**Step 1: Rewrite UnifiedReplyButton**

Replace `UnifiedReplyButton` (lines 169-257) with:

```swift
struct UnifiedReplyButton: View {
  let count: Int
  let isReplied: Bool
  let platform: SocialPlatform
  let isProcessing: Bool
  let onTap: () async -> Void

  @State private var isPressed = false
  @State private var bounceForward = false
  @State private var errorShake = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button {
      HapticEngine.tap.trigger()
      if !reduceMotion {
        withAnimation(.spring(response: 0.15, dampingFraction: 0.4)) {
          bounceForward = true
        }
        Task { @MainActor in
          try? await Task.sleep(nanoseconds: 150_000_000)
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
            reduceMotion ? .none : .spring(response: 0.12, dampingFraction: 0.7),
            value: isReplied
          )

        RollingNumberView(count, font: .caption, color: isReplied ? platformColor : .secondary)
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
        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
          isPressed = pressing
        }
      }, perform: {}
    )
  }

  private var platformColor: Color {
    switch platform {
    case .mastodon: return Color(red: 99/255, green: 100/255, blue: 255/255)
    case .bluesky: return Color(red: 0, green: 133/255, blue: 255/255)
    }
  }
}
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 3: Commit**

```bash
git add SocialFusion/Views/Components/UnifiedInteractionButtons.swift
git commit -m "feat: enhanced reply button with bounce-forward animation

Reply icon translates 2pt right and springs back on tap.
RollingNumberView for animated count. Respects reduceMotion."
```

---

## Task 6: Error Shake Animation for Action Failures

Adds shake + haptic feedback when an action fails.

**Files:**
- Modify: `SocialFusion/Views/Components/UnifiedInteractionButtons.swift` (add shake modifier)
- Modify: `SocialFusion/Stores/PostActionCoordinator.swift` (trigger error state)

**Step 1: Add shake animation modifier**

Create a reusable modifier. Add at the top of `UnifiedInteractionButtons.swift`:

```swift
/// Shake animation modifier for error feedback.
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
```

**Step 2: Wire error shake into buttons**

In each button (Like, Repost, Reply), the existing `errorShake` state is already declared but never triggered. Add to each button's `onTap` closure — after the async action completes, check for failure. The coordinator already handles errors; we need to expose a per-post error signal.

Add to `PostActionStore.swift`:

```swift
/// Keys that had their last action fail. Cleared on next successful action.
@Published private(set) var errorKeys: Set<ActionKey> = []

func markError(for key: ActionKey) {
  errorKeys.insert(key)
  HapticEngine.error.trigger()
  // Auto-clear after shake duration
  Task { @MainActor in
    try? await Task.sleep(nanoseconds: 600_000_000)
    errorKeys.remove(key)
  }
}

func clearError(for key: ActionKey) {
  errorKeys.remove(key)
}
```

Then in each button, observe the error state:

```swift
.modifier(ShakeEffect(animatableData: store.errorKeys.contains(actionKey) ? 1 : 0))
```

This requires passing `store` and `actionKey` into each button. The `UnifiedInteractionButtons` container already has these — thread them through.

**Step 3: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 4: Commit**

```bash
git add SocialFusion/Views/Components/UnifiedInteractionButtons.swift
git add SocialFusion/Stores/PostActionStore.swift
git commit -m "feat: error shake animation with haptic on action failure

Buttons shake horizontally (3 oscillations) on error with .error haptic.
Auto-clears after 600ms. Uses GeometryEffect for GPU-accelerated shake."
```

---

## Task 7: Staggered Entrance Animation

Posts cascade in on initial load and pagination.

**Files:**
- Modify: `SocialFusion/Views/ConsolidatedTimelineView.swift` (timeline list rendering)

**Step 1: Add entrance animation state**

In `ConsolidatedTimelineView`, add state tracking for initial appearance:

```swift
@State private var appearedPostIds: Set<String> = []
@State private var isInitialLoad = true
```

**Step 2: Add entrance modifier to post cards**

Wrap each post card in the timeline's `ForEach` with an entrance animation. Find the post rendering loop and add:

```swift
.opacity(appearedPostIds.contains(post.id) ? 1 : 0)
.offset(y: appearedPostIds.contains(post.id) ? 0 : 8)
.onAppear {
  guard isInitialLoad || isPaginating else {
    // Normal scroll — appear instantly
    appearedPostIds.insert(post.id)
    return
  }
  let index = controller.posts.firstIndex(where: { $0.id == post.id }) ?? 0
  let staggerIndex = min(index, 5) // Cap at 5 for stagger
  let delay = Double(staggerIndex) * 0.05
  withAnimation(.easeOut(duration: 0.25).delay(delay)) {
    appearedPostIds.insert(post.id)
  }
}
```

**Step 3: Clear entrance state after initial load**

After the first batch appears, set `isInitialLoad = false` so subsequent scroll doesn't animate:

```swift
.onAppear {
  Task { @MainActor in
    try? await Task.sleep(nanoseconds: 500_000_000)
    isInitialLoad = false
  }
}
```

Wrap all entrance logic in `if !reduceMotion` — with reduceMotion, posts appear instantly (always in `appearedPostIds`).

**Step 4: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 5: Commit**

```bash
git add SocialFusion/Views/ConsolidatedTimelineView.swift
git commit -m "feat: staggered entrance animation for timeline posts

Posts cascade in with 50ms offsets on initial load and pagination.
8pt upward slide + fade. Capped at first 6 visible posts.
Normal scrolling bypasses animation. Respects reduceMotion."
```

---

## Task 8: "Caught Up" Marker

Inline separator showing where the user last left off.

**Files:**
- Create: `SocialFusion/Views/Components/CaughtUpMarker.swift`
- Modify: `SocialFusion/Views/ConsolidatedTimelineView.swift` (insert marker in post list)
- Modify: `SocialFusion/Controllers/UnifiedTimelineController.swift` (expose last-read position)

**Step 1: Create CaughtUpMarker.swift**

```swift
import SwiftUI

/// Subtle inline separator indicating where the user left off.
struct CaughtUpMarker: View {
  var body: some View {
    HStack(spacing: 12) {
      line
      Text("You're caught up")
        .font(.caption)
        .foregroundColor(.secondary)
      line
    }
    .opacity(0.3)
    .padding(.vertical, 12)
    .padding(.horizontal, 16)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("You are caught up with your timeline")
  }

  private var line: some View {
    Rectangle()
      .fill(Color.secondary)
      .frame(height: 0.5)
  }
}
```

**Step 2: Insert marker in timeline**

In `ConsolidatedTimelineView`, within the post `ForEach`, check if the current post ID matches `lastReadPostId` and insert the marker:

```swift
if post.id == lastReadPostId && !controller.isNearTop {
  CaughtUpMarker()
    .transition(.opacity)
}
```

The `lastReadPostId` property already exists in the view (used by `jumpToLastReadButton`).

**Step 3: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 4: Commit**

```bash
git add SocialFusion/Views/Components/CaughtUpMarker.swift
git add SocialFusion/Views/ConsolidatedTimelineView.swift
git commit -m "feat: add 'You're caught up' inline marker

Subtle separator at last-read position in timeline.
0.3 opacity — present but not demanding.
VoiceOver-friendly with descriptive accessibility label."
```

---

## Task 9: Ambient Unread Pulse

The new posts pill gently breathes to draw attention.

**Files:**
- Modify: `SocialFusion/Views/ConsolidatedTimelineView.swift` (lines ~984-1015, `newPostsPill`)

**Step 1: Add breathing animation to new posts pill**

In the `newPostsPill` method, add an opacity pulse:

```swift
@State private var unreadPulseActive = false

// Inside newPostsPill, add to the pill's Button:
.opacity(unreadPulseActive ? 1.0 : 0.85)
.animation(
  reduceMotion ? .none : .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
  value: unreadPulseActive
)
.onAppear { unreadPulseActive = true }
.onDisappear { unreadPulseActive = false }
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 3: Commit**

```bash
git add SocialFusion/Views/ConsolidatedTimelineView.swift
git commit -m "feat: ambient breathing pulse on unread posts pill

Opacity oscillates 0.85-1.0 on 2-second cycle.
Draws the eye without being demanding. Respects reduceMotion."
```

---

## Task 10: Enhanced Scroll-to-Top with Distance Awareness

Smart animation based on scroll distance.

**Files:**
- Modify: `SocialFusion/Views/ConsolidatedTimelineView.swift` (lines ~1124-1135, `scrollToTop`)

**Step 1: Rewrite scrollToTop**

Replace the existing `scrollToTop` method:

```swift
private func scrollToTop(using proxy: ScrollViewProxy) {
  guard let topId = controller.posts.first.map(scrollIdentifier(for:)) else { return }

  // Estimate distance: if unread count or scroll position suggests far away, use fade
  let isLongDistance = controller.unreadAboveViewportCount > 20 || !controller.isNearTop

  if isLongDistance && !reduceMotion {
    // Fade out, jump, fade in
    withAnimation(.easeOut(duration: 0.15)) {
      scrollToTopOpacity = 0.3
    }
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 150_000_000)
      if #available(iOS 17.0, *) {
        scrollAnchorId = topId
      } else {
        proxy.scrollTo(topId, anchor: .top)
      }
      try? await Task.sleep(nanoseconds: 50_000_000)
      withAnimation(.easeIn(duration: 0.2)) {
        scrollToTopOpacity = 1.0
      }
      HapticEngine.tap.trigger()
    }
  } else {
    // Short distance: smooth scroll
    withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.4)) {
      if #available(iOS 17.0, *) {
        scrollAnchorId = topId
      } else {
        proxy.scrollTo(topId, anchor: .top)
      }
    }
    HapticEngine.tap.trigger()
  }
}

@State private var scrollToTopOpacity: Double = 1.0
```

Apply `scrollToTopOpacity` to the timeline ScrollView:

```swift
.opacity(scrollToTopOpacity)
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 3: Commit**

```bash
git add SocialFusion/Views/ConsolidatedTimelineView.swift
git commit -m "feat: distance-aware scroll-to-top animation

Short distance (<20 posts): smooth animated scroll.
Long distance: fade out, jump, fade in for instant feel.
Haptic tap on landing. Respects reduceMotion."
```

---

## Task 11: Contextual Depth for Threads

Visual hierarchy in post detail thread view.

**Files:**
- Modify: `SocialFusion/Views/Components/PostDetailView.swift` (reply rendering)

**Step 1: Add depth styling to replies**

In `PostDetailView`, find where reply posts are rendered in the thread. Add indentation and opacity based on depth:

```swift
// For each reply in the thread:
PostCardView(post: reply, ...)
  .padding(.leading, min(CGFloat(replyDepth) * 12, 36)) // Max 3 levels of indent
  .opacity(replyDepth == 0 ? 1.0 : 0.95)
  .overlay(alignment: .leading) {
    if replyDepth >= 3 {
      Rectangle()
        .fill(platformAccentColor(for: reply))
        .frame(width: 2)
        .padding(.vertical, 4)
    }
  }
```

Where `platformAccentColor` returns Mastodon purple or Bluesky blue.

For the focused/parent post, add subtle elevation:

```swift
// The main focused post:
PostCardView(post: viewModel.post, ...)
  .shadow(color: Color.primary.opacity(0.06), radius: 4, y: 2)
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 3: Commit**

```bash
git add SocialFusion/Views/Components/PostDetailView.swift
git commit -m "feat: contextual depth styling for thread replies

Parent post has subtle shadow elevation. Replies indent 12pt per level.
Deep replies (3+) get platform-colored left accent line.
Spatial hierarchy makes threads feel like conversations."
```

---

## Task 12: Media Parallax on Scroll

Subtle depth effect on images as posts scroll past.

**Files:**
- Create: `SocialFusion/Views/Components/ParallaxMediaModifier.swift`
- Modify: `SocialFusion/Views/Components/MediaGridView.swift` (or wherever media images are rendered in timeline)

**Step 1: Create ParallaxMediaModifier.swift**

```swift
import SwiftUI

/// Adds subtle parallax scrolling effect to media content.
/// Images scroll at 85% of card speed, creating 15% depth.
struct ParallaxMediaModifier: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    if reduceMotion {
      content
    } else {
      GeometryReader { geo in
        let midY = geo.frame(in: .global).midY
        let screenHeight = UIScreen.main.bounds.height
        let offset = (midY - screenHeight / 2) * 0.15 // 15% parallax

        content
          .offset(y: -offset)
      }
      .clipped()
    }
  }
}

extension View {
  func parallaxOnScroll() -> some View {
    modifier(ParallaxMediaModifier())
  }
}
```

**Step 2: Apply to media in timeline**

Find where media images are rendered in `MediaGridView.swift` or `PostCardView.swift` media section and add `.parallaxOnScroll()` to the image container.

**Step 3: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 4: Commit**

```bash
git add SocialFusion/Views/Components/ParallaxMediaModifier.swift
git add SocialFusion/Views/Components/MediaGridView.swift
git commit -m "feat: subtle parallax effect on media during scroll

Images scroll at 85% of card speed for 15% depth effect.
4-line GeometryReader calculation — zero performance overhead.
Respects reduceMotion."
```

---

## Task 13: New Post Highlight Glow

After posting, the new post gets a brief platform-colored border glow.

**Files:**
- Modify: `SocialFusion/Views/ConsolidatedTimelineView.swift` (post rendering)
- Modify: `SocialFusion/Stores/DraftStore.swift` or wherever post-success is signaled

**Step 1: Add highlight state**

In `ConsolidatedTimelineView`:

```swift
@State private var highlightedPostId: String?
```

When a new post is successfully published (observe from the compose flow or a notification), set `highlightedPostId` to the new post's ID.

**Step 2: Add highlight overlay to post cards**

In the post `ForEach`, add to each post card:

```swift
.overlay(
  RoundedRectangle(cornerRadius: 12, style: .continuous)
    .stroke(
      highlightedPostId == post.id ? platformGlowColor(for: post) : .clear,
      lineWidth: 1
    )
    .opacity(highlightedPostId == post.id ? 1 : 0)
    .animation(.easeOut(duration: 1.0), value: highlightedPostId)
)
.onChange(of: highlightedPostId) { _, newValue in
  if newValue == post.id {
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      withAnimation(.easeOut(duration: 0.3)) {
        highlightedPostId = nil
      }
    }
  }
}
```

Where `platformGlowColor` returns gold (#6364FF) for Mastodon, blue (#0085FF) for Bluesky.

**Step 3: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 4: Commit**

```bash
git add SocialFusion/Views/ConsolidatedTimelineView.swift
git commit -m "feat: platform-colored glow on newly published posts

After posting, a 1px border in platform color fades in and out
over 1.2 seconds. You know your post landed."
```

---

## Task 14: Compose Sheet Choreography

Timeline scales and blurs behind the compose sheet.

**Files:**
- Modify: `SocialFusion/Views/ConsolidatedTimelineView.swift` (or `ContentView.swift` wherever compose sheet is presented)

**Step 1: Add compose presentation state**

Find where the compose sheet is presented (`.sheet` modifier). Add state:

```swift
@State private var isComposePresented = false
```

Apply background effect to the timeline when compose is showing:

```swift
.scaleEffect(isComposePresented && !reduceMotion ? 0.95 : 1.0)
.blur(radius: isComposePresented && !reduceTransparency ? 3 : 0)
.animation(.spring(response: 0.4, dampingFraction: 0.85), value: isComposePresented)
```

Wire `isComposePresented` to the sheet's `onDismiss` and presentation trigger.

**Step 2: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 3: Commit**

```bash
git add SocialFusion/Views/ConsolidatedTimelineView.swift
git commit -m "feat: compose sheet choreography with backdrop blur

Timeline scales to 0.95x and blurs 3pt when compose opens.
Springs back on dismiss. Respects reduceMotion and reduceTransparency."
```

---

## Task 15: Wiring & Integration Pass

Final pass to ensure all new components are properly connected.

**Files:**
- All modified files from Tasks 1-14

**Step 1: Verify HapticEngine usage is consistent**

Ensure every interaction button triggers the correct haptic pattern as specified:
- Like: `.tap` (already wired in Task 3)
- Repost: `.selection` (already wired in Task 4)
- Reply: `.tap` (already wired in Task 5)
- Bookmark: `.success` (wire in PostActionBar or bookmark handler)
- Share: `.tap` (already exists in PostShareButton)
- Error: `.error` (wired in Task 6)

**Step 2: Verify all animations check reduceMotion**

Grep for all new `withAnimation` calls and verify they're wrapped in `!reduceMotion` checks or use `reduceMotion ? .none : ...` pattern.

Run: `grep -rn "withAnimation" SocialFusion/Views/Components/RollingNumberView.swift SocialFusion/Views/Components/SkeletonPostCard.swift SocialFusion/Views/Components/ParallaxMediaModifier.swift SocialFusion/Views/Components/CaughtUpMarker.swift`

**Step 3: Full build**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED with zero warnings from new code.

**Step 4: Commit**

```bash
git add -A
git commit -m "chore: integration pass for timeline polish

Verify haptic consistency, reduceMotion compliance, and
build health across all new animation components."
```

---

## Dependency Graph

```
Task 1 (Skeleton)     — independent
Task 2 (RollingNumber) — independent
Task 3 (Like button)   — depends on Task 2
Task 4 (Repost button) — depends on Task 2
Task 5 (Reply button)  — depends on Task 2
Task 6 (Error shake)   — depends on Tasks 3-5
Task 7 (Stagger)       — independent
Task 8 (Caught up)     — independent
Task 9 (Unread pulse)  — independent
Task 10 (Scroll-to-top) — independent
Task 11 (Thread depth) — independent
Task 12 (Parallax)     — independent
Task 13 (Post glow)    — independent
Task 14 (Compose blur) — independent
Task 15 (Integration)  — depends on all above
```

**Parallelizable groups:**
- Group A: Tasks 1, 2, 7, 8, 9, 10, 11, 12, 13, 14 (all independent)
- Group B: Tasks 3, 4, 5 (after Task 2)
- Group C: Task 6 (after Group B)
- Group D: Task 15 (after all)

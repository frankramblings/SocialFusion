# Timeline Polish & Interaction Feedback Design

**Date**: 2026-02-25
**Status**: Approved
**Approach**: A (Ivory Tactile) + C (Living Timeline)
**Goal**: Make the timeline scroll feel and every interaction tap feel best-in-class — Gruber-approved, MacStories-featured craft.

---

## Principles

- Haptics only, no sound. Tactile and silent.
- Every animation respects `reduceMotion`. The app feels polished with motion disabled — just calmer.
- 60fps scroll guarantee. No animation runs during scroll deceleration that isn't `GeometryReader`-driven.
- Progressive enhancement: A-tier polish is the foundation, C-tier motion is layered on top.

---

## Section 1: Skeleton Loading & Timeline Entrance

### Skeleton Placeholders

When the timeline loads or paginates, show shimmer-animated placeholder cards matching PostCardView layout: circle for avatar, two short bars for display name/handle, three longer bars for body text, rectangle for media. Show 4-5 skeleton cards during initial load instead of a centered spinner.

Shimmer uses a single shared `TimelineView(.animation)` — not per-card timers. Max 6 skeleton cards; beyond that, simple "Loading more..." text.

### Staggered Entrance

When posts resolve from skeleton to real content, each card fades in with a 50ms stagger offset combined with a subtle 8pt upward slide. Only on initial load and pagination — never during normal scrolling.

Capped at the first visible batch (5-6 posts). Beyond that, posts appear instantly.

### New Post Insertion

Pull-to-refresh new posts slide in from the top with `.spring(response: 0.35, dampingFraction: 0.75)`. Tapping the unread count banner scrolls up and new posts cascade into view.

---

## Section 2: Interaction Feedback

### Like

- **On tap**: Heart scales to 1.3x with `.interactiveSpring(response: 0.3, dampingFraction: 0.5)`, fills with color (Mastodon gold / Bluesky red), settles back to 1.0x. Count rolls vertically (old slides up, new slides in from below). Haptic: `.tap` (light impact).
- **On unlike**: Heart deflates to outline with `.easeOut(duration: 0.2)`. No haptic — absence is feedback.

### Repost/Boost

- **On tap**: Repost icon rotates 360 degrees with ease-in-ease-out over 0.5s, scales to 1.2x at midpoint. Color fills (green). Count rolls. Haptic: `.selection` (medium — amplifying someone's voice should feel weighty).
- **On un-repost**: Icon fades to outline, no rotation.

### Reply

- **On tap**: Reply icon "bounces forward" — translates 2pt right then springs back. Haptic: `.tap`. Compose sheet slides up with `.spring(response: 0.4, dampingFraction: 0.85)`.

### Bookmark

- **On tap**: Bookmark icon fills from bottom to top over 0.25s. Haptic: `.success`. Brief toast: "Saved" with platform icon.

### Share

- Existing spring animation preserved. On completion: icon morphs to checkmark with `.success` haptic.

### Error States

- Action failure: icon shakes horizontally (3 rapid oscillations, 2pt amplitude) with `.error` haptic. Optimistic update rolls back with reverse animation. No alert dialog.

### Rolling Number Count

Custom `RollingNumberView`: digits slide vertically with `.spring` physics. Increment rolls up, decrement rolls down. 0.2s for single-digit changes. Threshold crossings (999 -> 1K) use crossfade morph.

---

## Section 3: Pull-to-Refresh & Scroll Physics

### Custom Pull-to-Refresh

Replace stock spinner with custom indicator. As user pulls, a SocialFusion icon (fusion circles from LaunchAnimationView) appears and scales proportionally. At trigger threshold, circles begin fusion animation (miniaturized launch bloom). On completion: circles resolve, indicator shrinks with `.spring`, `HapticEngine.refreshComplete(hasNewContent:)` fires. New content = satisfying double-tap haptic. No new content = single soft tap. User feels the result without looking.

### Scroll-to-Top

Tab bar tap while on timeline: smooth scroll with `.easeInOut(duration: 0.4)` for short distances (< 20 posts). Quick fade-out/fade-in for long distances (timeline fades to 0.3 opacity, scrolls, fades back). Light haptic tap on landing.

### Scroll Velocity Awareness

Fast scrolling (> 1500pt/s): reduce media loading priority, show blurred thumbnails. Thumbnails sharpen with 150ms soft focus-in when scrolling decelerates. CachedAsyncImage priority tiers already support this — tie to scroll velocity.

### "Caught Up" Marker

Inline separator where user last left off: thin line with "You're caught up" in caption text. 0.3 opacity — present but not demanding. VoiceOver announces: "You are caught up with your timeline."

---

## Section 4: Living Timeline — Motion & Choreography

### Hero Transitions to Post Detail

Tapping a post expands the PostCardView in place. Avatar, name, body text stay pinned. Card grows to fill screen. Timeline fades to 0.1 opacity behind. Reply thread loads below with staggered entrance (50ms offsets). Dismiss by swiping down — card contracts back to timeline position with matched geometry.

Implementation: `matchedGeometryEffect` with `NavigationTransition`. Fallback: if geometry matching fails (off-screen post), standard push with spring timing.

### Reactive Media on Scroll

Images have subtle parallax: scroll at 85% of card speed (15% depth effect). 4-line GeometryReader calculation. Videos auto-mute on scroll-away, pause at 60% offscreen. GIFs slow frame rate when partially offscreen, resume at full speed when centered.

### Contextual Depth for Threads

Parent post: full opacity with subtle shadow. Each reply: indents 12pt, drops to 95% opacity. Deep replies (3+ levels): thin left-border accent line in platform color. Spatial hierarchy, not animation.

### Ambient Unread Pulse

Unread count banner: opacity oscillates 0.85 to 1.0 on 2-second cycle. Draws the eye without screaming. On scroll-up to reveal unread posts, banner dissolves and new posts cascade in (connecting to Section 1 spring insertion).

### Compose Sheet Choreography

Opening compose: sheet rises with spring, timeline behind scales to 0.95x and blurs (3pt). On posting: sheet collapses, timeline un-blurs and un-scales. After 300ms beat, new post appears at top with brief highlight glow (1px gold/blue border fading over 1s, platform-dependent). You know your post landed.

---

## Section 5: Accessibility & Performance Contract

### Accessibility

- `UIAccessibility.isReduceMotionEnabled`: Springs become instant state changes, staggered entrances become simultaneous fades, parallax disabled, hero transition falls back to standard push, ambient pulses stop.
- `isReduceTransparencyEnabled`: Disables blur effects (compose backdrop, scroll-velocity blur).
- All new interactive elements get `accessibilityLabel` and `accessibilityHint`. Rolling numbers announced as final value.
- "Caught up" marker announced via VoiceOver.
- Haptics remain on for all users (accessibility aid) unless system haptics toggle is off.

### Performance Contract

- **60fps scroll**: No animation during scroll deceleration unless GeometryReader-driven. Profile with Instruments before merging.
- **Skeleton loading**: Max 6 cards. Single shared `TimelineView(.animation)`.
- **Image priority**: Blur threshold at scroll velocity > 1500pt/s. Below: `.normal` priority. Above: `.background` with blur placeholder.
- **Hero transition**: 16ms geometry calculation budget. Missed frame = fallback to standard push.
- **Memory**: Animation state released for off-screen posts. Active animation window = visible ± 3 posts.

---

## Competitive Context

This design targets the gap between Openvibe (multi-platform, poorly executed) and Ivory/Mona (single-platform, beautifully crafted). No multi-platform social client currently combines this level of interaction design with unified timeline ambition.

**Benchmarks**: Ivory (sensory design), Mona (accessibility excellence), Skeets (reading position stability), Ice Cubes (SwiftUI architecture).

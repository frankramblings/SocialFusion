# Cinematic Profile Scrolling Polish -- Design Document

**Date:** 2026-02-28
**Status:** Approved
**Branch:** `feature/profile-view-redesign` (existing implementation to refine)

## Problem

The profile view redesign on `feature/profile-view-redesign` has the structural pieces in place -- banner parallax, 3D avatar tilt, avatar docking, pinned tabs -- but the scrolling behavior has rough edges that prevent it from feeling first-party smooth. Specific issues:

1. Banner parallax only works on pull-down; scroll-up has no depth effect
2. Avatar shrink uses hardcoded absolute coordinates (breaks across devices)
3. Avatar dock is a hard opacity snap, not a smooth crossfade
4. 3D tilt oscillates on both axes (wobbly rather than cinematic)
5. Pull-down banner stretch is linear (no rubber-band tension)
6. "Progressive blur" is an opacity-fading material, not actual gaussian blur
7. Tab bar shadow draws even when tabs aren't pinned

## Design

### 1. Banner -- Sticky + Progressive Blur (Apple Music style)

**Architecture change:** Move the banner out of the ScrollView into a fixed background layer. Content scrolls *over* the banner.

```
ZStack(alignment: .top) {
  bannerSection          // Layer 0: pinned behind content
  ScrollView { ... }     // Layer 1: content flows over banner
}
```

**Scroll-up behavior:**
- Banner stays pinned at `y: 0` regardless of scroll offset
- `blur(radius:)` increases from 0 to ~20 as content scrolls past banner height
- Overlay darkens from 0% to ~30% opacity simultaneously
- Both driven by `scrollUp / bannerHeight` (proportional, not threshold-based)

**Pull-down (overscroll) behavior:**
- Banner stretches with decelerating curve: `stretchAmount = overscroll * 0.6`
- Image scales from center-bottom to fill extra height
- Rubber-band tension -- first 50pt of pull gives most of the stretch, further pulling barely changes it

### 2. Avatar -- Crossfade Docking + Refined 3D Tilt

**Crossfade transition (scroll-up):**
- Content avatar (72pt) fades from `opacity 1.0 -> 0.0` and scales from `1.0 -> 0.7` over a ~30pt scroll window as it approaches the nav bar area
- Nav bar avatar (28pt) fades in with inverse timing: `opacity 0.0 -> 1.0`, `scale 0.5 -> 1.0`
- Scroll-driven (not spring-animated) for the main motion; `.animation(.easeInOut(duration: 0.25))` for the final settle

**Docking threshold:**
- Derived from actual geometry: docks when `avatarRow.minY` in scroll coordinate space drops below safe area top + nav bar height (~50pt)
- No hardcoded pixel values -- works across iPhone, iPad, orientation changes

**3D tilt (pull-down overscroll):**
- Single axis only: X-axis tilt toward the viewer (`axis: (x: 1, y: 0, z: 0)`)
- Decelerating curve: `tiltAngle = min(8, sqrt(overscroll) * 1.2)`
- Max 8 degrees (was 15 -- subtler is better)
- Shadow deepens proportionally: `radius: min(8, overscroll * 0.1)`, `y: min(4, overscroll * 0.05)`

### 3. Tab Bar -- Conditional Shadow + Sliding Underline

**Shadow:**
- Zero shadow when in natural position (not pinned)
- Shadow fades in when tabs reach and stick to the top (detect via GeometryReader comparing `minY` to safe area top)
- Values: `color: .black.opacity(0.08), radius: 4, y: 2`
- Animated with `.animation(.easeOut(duration: 0.15))`

**Underline indicator:**
- Replace per-tab show/hide with `matchedGeometryEffect` so the underline physically slides between tabs
- Keeps the 2pt height and accent color

### 4. Scroll Offset Tracking

- `GeometryReader` inside ScrollView publishes offset through a `PreferenceKey`
- Banner section reads this offset to drive blur/stretch
- Consistent with existing `ParallaxMediaModifier` pattern (PreferenceKey propagation)

### 5. Accessibility

- When `accessibilityReduceMotion` is enabled:
  - No sticky banner (scrolls normally with content)
  - No crossfade window (avatar transition is instant)
  - No 3D tilt on pull-down
  - No progressive blur animation (static overlay)
- Mirrors existing `ParallaxMediaModifier` `@Environment(\.accessibilityReduceMotion)` pattern

## Files Affected

### Modify
- `SocialFusion/Views/Components/ProfileHeaderView.swift` -- major refactor: extract banner into separate sticky layer, fix avatar crossfade, fix 3D tilt, add progressive blur
- `SocialFusion/Views/ProfileView.swift` -- restructure body to ZStack layout with banner as background layer
- `SocialFusion/Views/Components/ProfileTabBar.swift` -- add conditional shadow, matchedGeometryEffect underline

### No new files needed
All changes are refinements to existing components on the `feature/profile-view-redesign` branch.

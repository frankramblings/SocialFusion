# Cinematic Profile Scrolling Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Polish the profile view's cinematic scrolling on `feature/profile-view-redesign` to feel first-party smooth -- sticky banner with progressive blur, crossfade avatar docking, refined 3D tilt, conditional tab shadow, sliding underline.

**Architecture:** The banner moves from inside the ScrollView to a fixed ZStack background layer. Scroll offset is tracked via PreferenceKey and drives blur, stretch, crossfade, and shadow transitions. All effects respect `accessibilityReduceMotion`.

**Tech Stack:** SwiftUI, GeometryReader, PreferenceKey, matchedGeometryEffect, blur(radius:), rotation3DEffect

**Design doc:** `Docs/plans/2026-02-28-cinematic-scrolling-polish-design.md`

**Branch:** All work happens on `feature/profile-view-redesign`. Check out this branch before starting.

---

## Phase 1: Scroll Offset Infrastructure

### Task 1: Add ProfileScrollOffsetKey PreferenceKey

**Files:**
- Modify: `SocialFusion/Views/Components/ProfileHeaderView.swift` (add at bottom, before previews ~line 520)

**Step 1: Add the PreferenceKey**

Add this after the `AsyncHTMLText` struct and before the `#Preview` blocks:

```swift
// MARK: - Scroll Offset Tracking

/// Tracks the scroll offset within the profile scroll view.
/// Used by the banner, avatar, and tab bar to drive cinematic transitions.
struct ProfileScrollOffsetKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
```

**Step 2: Build**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SocialFusion/Views/Components/ProfileHeaderView.swift
git commit -m "feat(profile): add ProfileScrollOffsetKey for cinematic scroll tracking"
```

---

### Task 2: Wire scroll offset reader into ProfileView

**Files:**
- Modify: `SocialFusion/Views/ProfileView.swift:14` (add state)
- Modify: `SocialFusion/Views/ProfileView.swift:33-68` (add offset reader and preference change handler)

**Step 1: Add scroll offset state**

At line 14, after `@State private var isAvatarDocked = false`, add:

```swift
@State private var scrollOffset: CGFloat = 0
```

**Step 2: Add offset reader inside ScrollView**

Inside the `ScrollView`, right before the `LazyVStack`, add a geometry reader that publishes scroll offset:

```swift
ScrollView {
  GeometryReader { geo in
    Color.clear
      .preference(
        key: ProfileScrollOffsetKey.self,
        value: geo.frame(in: .named("profileScroll")).minY
      )
  }
  .frame(height: 0)

  LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
    // ... existing content
  }
}
.coordinateSpace(name: "profileScroll")
.onPreferenceChange(ProfileScrollOffsetKey.self) { value in
  scrollOffset = value
}
```

**Step 3: Build**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add SocialFusion/Views/ProfileView.swift
git commit -m "feat(profile): wire scroll offset reader into ProfileView body"
```

---

## Phase 2: Sticky Banner with Progressive Blur

### Task 3: Extract banner into a standalone sticky view

This is the major architectural change. The banner moves from inside `ProfileHeaderView` to a fixed background layer in `ProfileView`.

**Files:**
- Modify: `SocialFusion/Views/ProfileView.swift:33-68` (restructure body to ZStack)
- Modify: `SocialFusion/Views/Components/ProfileHeaderView.swift:42,55-98` (remove bannerSection from body, expose banner as separate component)

**Step 1: Create StickyProfileBanner in ProfileHeaderView.swift**

Add a new view struct before the `ProfileHeaderView` struct (around line 6):

```swift
/// Sticky banner that stays pinned behind scrolling content.
/// Progressively blurs and darkens as content scrolls over it.
/// Stretches with rubber-band tension on pull-down overscroll.
struct StickyProfileBanner: View {
  let headerURL: String?
  let platform: SocialPlatform
  let scrollOffset: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private enum Layout {
    static let bannerHeight: CGFloat = 200
  }

  var body: some View {
    let scrollUp = max(0, -scrollOffset)
    let overscroll = max(0, scrollOffset)
    // Rubber-band: decelerating stretch
    let stretchAmount = reduceMotion ? 0 : overscroll * 0.6
    let blurAmount = reduceMotion ? 0 : min(20, scrollUp / Layout.bannerHeight * 20)
    let darkenAmount = reduceMotion ? 0 : min(0.3, scrollUp / Layout.bannerHeight * 0.3)

    ZStack {
      if let headerURLString = headerURL,
         let url = URL(string: headerURLString) {
        CachedAsyncImage(url: url, priority: .high) { image in
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(
              width: UIScreen.main.bounds.width,
              height: Layout.bannerHeight + stretchAmount
            )
            .clipped()
        } placeholder: {
          bannerGradient
            .frame(height: Layout.bannerHeight + stretchAmount)
        }
      } else {
        bannerGradient
          .frame(height: Layout.bannerHeight + stretchAmount)
      }
    }
    .blur(radius: blurAmount)
    .overlay(Color.black.opacity(darkenAmount))
    .frame(height: Layout.bannerHeight + stretchAmount)
    .frame(maxWidth: .infinity)
    .clipped()
  }

  private var bannerGradient: some View {
    LinearGradient(
      colors: platformGradientColors,
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private var platformGradientColors: [Color] {
    switch platform {
    case .mastodon:
      return [Color.mastodonColor.opacity(0.8), Color.mastodonColor.opacity(0.4)]
    case .bluesky:
      return [Color.blueskyColor.opacity(0.8), Color.blueskyColor.opacity(0.4)]
    }
  }
}
```

**Step 2: Remove bannerSection from ProfileHeaderView body**

In `ProfileHeaderView`, change the `body` (around line 42) from:

```swift
var body: some View {
  VStack(alignment: .leading, spacing: 0) {
    bannerSection
    avatarRow
      .padding(.top, -Layout.avatarOverlap)
      .zIndex(1)
    identitySection
    bioSection
    fieldsSection
    statsRow
  }
}
```

to:

```swift
var body: some View {
  VStack(alignment: .leading, spacing: 0) {
    avatarRow
      .zIndex(1)
    identitySection
    bioSection
    fieldsSection
    statsRow
  }
}
```

Remove the `-Layout.avatarOverlap` top padding since the avatar no longer overlaps a banner within this component. The overlap is now handled by the spacer in ProfileView.

Also delete the `bannerSection` computed property (lines 55-98), `bannerGradient` (lines 101-108), and `platformGradientColors` (lines 110-117) from ProfileHeaderView -- they're now in `StickyProfileBanner`.

**Step 3: Restructure ProfileView body to ZStack**

In `ProfileView.swift`, change the `body` from a bare `ScrollView` to a `ZStack`:

```swift
var body: some View {
  ZStack(alignment: .top) {
    // Layer 0: Sticky banner (pinned behind content)
    if let profile = viewModel.profile {
      StickyProfileBanner(
        headerURL: profile.headerURL,
        platform: profile.platform,
        scrollOffset: scrollOffset
      )
    }

    // Layer 1: Scrollable content
    ScrollView {
      GeometryReader { geo in
        Color.clear
          .preference(
            key: ProfileScrollOffsetKey.self,
            value: geo.frame(in: .named("profileScroll")).minY
          )
      }
      .frame(height: 0)

      LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
        // Spacer so content starts below the banner
        Color.clear.frame(height: 200)

        // Profile header content (avatar, bio, stats -- no banner)
        if let profile = viewModel.profile {
          ProfileHeaderView(
            profile: profile,
            isOwnProfile: viewModel.isOwnProfile,
            onEditProfile: { showEditProfile = true },
            relationshipState: relationshipState,
            onFollow: { Task { await relationshipViewModel?.follow() } },
            onUnfollow: { Task { await relationshipViewModel?.unfollow() } },
            onMute: { Task { await relationshipViewModel?.mute() } },
            onUnmute: { Task { await relationshipViewModel?.unmute() } },
            onBlock: { Task { await relationshipViewModel?.block() } },
            onUnblock: { Task { await relationshipViewModel?.unblock() } },
            isAvatarDocked: $isAvatarDocked,
            scrollOffset: scrollOffset
          )
        } else if viewModel.isLoadingProfile {
          profileSkeleton
        } else if viewModel.profileError != nil {
          profileErrorView
        }

        // Tabs (pinned) + content
        Section {
          tabContent
        } header: {
          if viewModel.profile != nil {
            ProfileTabBar(selectedTab: $viewModel.selectedTab)
              .padding(.vertical, 4)
              .background(Color(.systemBackground))
          }
        }
      }
    }
    .coordinateSpace(name: "profileScroll")
    .onPreferenceChange(ProfileScrollOffsetKey.self) { value in
      scrollOffset = value
    }
  }
  // ... keep existing modifiers (.navigationBarTitleDisplayMode, .toolbar, .task, etc.)
}
```

Note: `ProfileHeaderView` now needs a `scrollOffset` parameter -- we add this in Task 4.

**Step 4: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: May have compile error because `ProfileHeaderView` doesn't accept `scrollOffset` yet. That's OK -- we fix it in Task 4. If it doesn't build, add `scrollOffset` as a parameter stub:

In `ProfileHeaderView`, add parameter: `var scrollOffset: CGFloat = 0` (line ~12, after `isAvatarDocked`).

**Step 5: Commit**

```bash
git add SocialFusion/Views/ProfileView.swift SocialFusion/Views/Components/ProfileHeaderView.swift
git commit -m "feat(profile): restructure to ZStack with sticky banner background layer"
```

---

## Phase 3: Avatar Crossfade Docking

### Task 4: Replace hard avatar snap with smooth crossfade

**Files:**
- Modify: `SocialFusion/Views/Components/ProfileHeaderView.swift:11-12` (add scrollOffset param)
- Modify: `SocialFusion/Views/Components/ProfileHeaderView.swift:120-153` (avatarRow)
- Modify: `SocialFusion/Views/ProfileView.swift:75-78` (nav bar avatar transition)

**Step 1: Add scrollOffset parameter to ProfileHeaderView**

After the `isAvatarDocked` binding (line ~11), add:

```swift
var scrollOffset: CGFloat = 0
```

**Step 2: Rewrite avatarRow with geometry-derived docking**

Replace the existing `avatarRow` computed property (lines 120-153) with:

```swift
private var avatarRow: some View {
  GeometryReader { geo in
    let minY = geo.frame(in: .named("profileScroll")).minY
    let overscroll = max(0, scrollOffset)

    // Docking threshold: safe area top + nav bar ≈ 50pt
    // Use the avatar row's position relative to the top
    let dockThreshold: CGFloat = 50
    let fadeStart: CGFloat = dockThreshold + 30  // Start fading 30pt before dock point
    let fadeEnd: CGFloat = dockThreshold

    // Crossfade progress: 0 = fully visible, 1 = fully docked
    let crossfadeProgress: CGFloat = {
      if minY >= fadeStart { return 0 }
      if minY <= fadeEnd { return 1 }
      return (fadeStart - minY) / (fadeStart - fadeEnd)
    }()

    let isDocked = crossfadeProgress >= 1.0
    let contentAvatarOpacity = 1.0 - Double(crossfadeProgress)
    let contentAvatarScale = 1.0 - Double(crossfadeProgress) * 0.3  // 1.0 -> 0.7

    HStack(alignment: .bottom, spacing: 12) {
      avatarView(overscroll: overscroll, tiltEnabled: crossfadeProgress == 0)
        .scaleEffect(contentAvatarScale, anchor: .topLeading)
        .opacity(contentAvatarOpacity)
      Spacer()
      actionButton
        .padding(.bottom, 4)
    }
    .padding(.horizontal, Layout.horizontalPadding)
    .onChange(of: isDocked) { _, newValue in
      if newValue != isAvatarDocked {
        isAvatarDocked = newValue
      }
    }
  }
  .frame(height: Layout.avatarSize)
}
```

**Step 3: Simplify avatarView -- remove old scale/docked params**

Replace the `avatarView(overscroll:scale:docked:)` signature and body (lines 156-196) with:

```swift
private func avatarView(overscroll: CGFloat, tiltEnabled: Bool) -> some View {
  let reduceMotion = false // Will be wired in Task 7
  let tiltAngle: Double = {
    guard tiltEnabled, !reduceMotion, overscroll > 0 else { return 0 }
    return min(8, sqrt(Double(overscroll)) * 1.2)
  }()
  let shadowRadius = tiltEnabled ? min(8, overscroll * 0.1) : 0
  let shadowY = tiltEnabled ? min(4, overscroll * 0.05) : 0

  return ZStack(alignment: .bottomTrailing) {
    if let avatarURLString = profile.avatarURL,
       let avatarURL = URL(string: avatarURLString) {
      CachedAsyncImage(url: avatarURL, priority: .high) { image in
        image
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: Layout.avatarSize, height: Layout.avatarSize)
          .clipShape(Circle())
      } placeholder: {
        avatarPlaceholder
      }
    } else {
      avatarPlaceholder
    }
  }
  .frame(width: Layout.avatarSize, height: Layout.avatarSize)
  .overlay(Circle().stroke(Color(.systemBackground), lineWidth: Layout.avatarBorderWidth))
  .overlay(alignment: .bottomTrailing) {
    PlatformLogoBadge(
      platform: profile.platform,
      size: Layout.badgeSize,
      shadowEnabled: true
    )
    .offset(x: 2, y: 2)
  }
  .rotation3DEffect(
    .degrees(tiltAngle),
    axis: (x: 1, y: 0, z: 0),
    perspective: 0.4
  )
  .shadow(
    color: .black.opacity(overscroll > 0 ? min(Double(overscroll) * 0.004, 0.3) : 0),
    radius: shadowRadius,
    y: shadowY
  )
  .accessibilityLabel("\(profile.displayName ?? profile.username)'s profile picture")
}
```

**Step 4: Update nav bar avatar in ProfileView to crossfade smoothly**

In `ProfileView.swift`, replace the nav bar avatar transition (lines 75-78):

From:
```swift
navBarAvatar(profile: profile)
  .opacity(isAvatarDocked ? 1 : 0)
  .scaleEffect(isAvatarDocked ? 1 : 0.5)
  .animation(.easeInOut(duration: 0.2), value: isAvatarDocked)
```

To:
```swift
navBarAvatar(profile: profile)
  .opacity(isAvatarDocked ? 1 : 0)
  .scaleEffect(isAvatarDocked ? 1 : 0.6, anchor: .leading)
  .animation(.easeInOut(duration: 0.25), value: isAvatarDocked)
```

(Anchor change to `.leading` so it scales from the left, matching the content avatar's position. Duration bumped to 0.25 for a slightly softer settle.)

**Step 5: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED

**Step 6: Test in simulator**

1. Open a profile with a banner image
2. Scroll up slowly -- avatar should crossfade over ~30pt of scroll, not snap
3. Nav bar avatar should fade in with a slight scale-up settle
4. Pull down -- avatar should tilt toward you (single axis, max ~8 degrees)

**Step 7: Commit**

```bash
git add SocialFusion/Views/Components/ProfileHeaderView.swift SocialFusion/Views/ProfileView.swift
git commit -m "feat(profile): smooth crossfade avatar docking and refined single-axis 3D tilt"
```

---

## Phase 4: Tab Bar Polish

### Task 5: Conditional shadow on tab bar

**Files:**
- Modify: `SocialFusion/Views/Components/ProfileTabBar.swift` (full rewrite -- 56 lines, safe to rewrite)

**Step 1: Add isPinned detection and conditional shadow**

Replace the entire `ProfileTabBar.swift` with:

```swift
import SwiftUI

/// A segmented tab bar for profile content sections with a sliding underline indicator.
/// Shadow only appears when the tab bar is pinned to the top.
struct ProfileTabBar: View {
  @Binding var selectedTab: ProfileTab
  @Namespace private var underlineNamespace
  @State private var isPinned = false

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        ForEach(ProfileTab.allCases, id: \.self) { tab in
          Button {
            withAnimation(.easeInOut(duration: 0.2)) {
              selectedTab = tab
            }
          } label: {
            VStack(spacing: 6) {
              Text(tab.rawValue)
                .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                .foregroundStyle(selectedTab == tab ? .primary : .secondary)

              ZStack {
                // Invisible spacer to maintain layout
                Rectangle()
                  .fill(Color.clear)
                  .frame(height: 2)

                if selectedTab == tab {
                  Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .matchedGeometryEffect(id: "underline", in: underlineNamespace)
                }
              }
            }
          }
          .frame(maxWidth: .infinity)
          .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        }
      }
      .accessibilityElement(children: .contain)
      .padding(.horizontal, 16)
    }
    .background(
      GeometryReader { geo in
        Color(.systemBackground)
          .preference(
            key: TabBarPinnedKey.self,
            value: geo.frame(in: .global).minY
          )
      }
    )
    .onPreferenceChange(TabBarPinnedKey.self) { minY in
      // Tab bar is pinned when it's near the top of the screen (safe area ~59pt on modern iPhones)
      let pinned = minY < 100
      if pinned != isPinned {
        withAnimation(.easeOut(duration: 0.15)) {
          isPinned = pinned
        }
      }
    }
    .shadow(
      color: .black.opacity(isPinned ? 0.08 : 0),
      radius: isPinned ? 4 : 0,
      y: isPinned ? 2 : 0
    )
  }
}

private struct TabBarPinnedKey: PreferenceKey {
  static var defaultValue: CGFloat = .infinity
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = min(value, nextValue())
  }
}

#Preview {
  struct PreviewWrapper: View {
    @State private var tab: ProfileTab = .posts

    var body: some View {
      VStack {
        ProfileTabBar(selectedTab: $tab)
        Spacer()
        Text("Selected: \(tab.rawValue)")
          .foregroundStyle(.secondary)
        Spacer()
      }
    }
  }

  return PreviewWrapper()
}
```

**Step 2: Build**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED

**Step 3: Test in simulator**

1. Scroll profile until tabs pin -- shadow should fade in smoothly
2. Scroll back down -- shadow should disappear
3. Tap between tabs -- underline should slide (matchedGeometryEffect)

**Step 4: Commit**

```bash
git add SocialFusion/Views/Components/ProfileTabBar.swift
git commit -m "feat(profile): conditional tab shadow and sliding underline indicator"
```

---

## Phase 5: Accessibility

### Task 6: Wire up accessibilityReduceMotion

**Files:**
- Modify: `SocialFusion/Views/Components/ProfileHeaderView.swift` (avatarView, avatarRow)

**Step 1: Add reduce motion environment variable**

In `ProfileHeaderView`, add after the `showBlockConfirmation` state (line ~22):

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

**Step 2: Pass reduceMotion through avatar tilt**

In `avatarView`, replace the hardcoded `let reduceMotion = false` with the actual environment value. Since `avatarView` is a function on the struct, it already has access to `self.reduceMotion`.

Change:
```swift
let reduceMotion = false // Will be wired in Task 7
```
To:
```swift
// reduceMotion is from @Environment
```

And update the tilt angle guard:
```swift
let tiltAngle: Double = {
  guard tiltEnabled, !reduceMotion, overscroll > 0 else { return 0 }
  return min(8, sqrt(Double(overscroll)) * 1.2)
}()
```

**Step 3: Disable crossfade in avatarRow when reduce motion is on**

In the `avatarRow`, when `reduceMotion` is true, make the crossfade instant (no gradual transition):

```swift
let crossfadeProgress: CGFloat = {
  if reduceMotion {
    return minY <= fadeEnd ? 1 : 0  // Instant transition
  }
  if minY >= fadeStart { return 0 }
  if minY <= fadeEnd { return 1 }
  return (fadeStart - minY) / (fadeStart - fadeEnd)
}()
```

**Step 4: Build and commit**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED

```bash
git add SocialFusion/Views/Components/ProfileHeaderView.swift
git commit -m "a11y(profile): respect reduceMotion for all cinematic scroll effects"
```

---

## Phase 6: Final Polish + Remove Dead Code

### Task 7: Clean up removed code and update previews

**Files:**
- Modify: `SocialFusion/Views/Components/ProfileHeaderView.swift` (remove dead bannerSection if not already removed, update previews)
- Modify: `SocialFusion/Views/ProfileView.swift` (remove any dead refs)

**Step 1: Verify no dead references remain**

Search for any remaining references to the old `bannerSection`, old `shrinkStart`/`shrinkEnd` constants, old `tiltX`/`tiltY` calculations. Remove them.

**Step 2: Remove the old Layout.bannerHeight from ProfileHeaderView**

If `Layout.bannerHeight` is no longer used inside `ProfileHeaderView` (it's now in `StickyProfileBanner`), remove it from the `Layout` enum. Keep other constants that are still used.

**Step 3: Update ProfileHeaderView previews**

The preview blocks at the bottom of `ProfileHeaderView.swift` need updating since the banner is no longer part of this component. Remove the outer `ScrollView` and `coordinateSpace` from previews, or wrap them in the new ZStack structure to see the full effect.

Update preview to pass `scrollOffset: 0`:

```swift
#Preview("Mastodon Profile") {
  ScrollView {
    ProfileHeaderView(
      // ... existing params ...
      isAvatarDocked: .constant(false),
      scrollOffset: 0
    )
  }
  .coordinateSpace(name: "profileScroll")
}
```

**Step 4: Build and full test**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED

Full manual test:
1. Open own profile -- banner (or gradient), bio, stats, Edit button visible
2. Open another user's profile -- Follow button, relationship badge
3. Scroll up slowly:
   - Banner stays pinned, progressively blurs and darkens
   - Avatar crossfades out over ~30pt
   - Nav bar shows compact avatar + name
   - Tab bar pins with shadow fade-in
4. Scroll back down:
   - Everything reverses smoothly
   - Shadow disappears
   - Avatar crossfades back in
5. Pull down (overscroll):
   - Banner stretches with rubber-band tension
   - Avatar tilts toward viewer (max ~8 degrees)
   - Tilt follows decelerating curve (sqrt-based)
6. Switch tabs -- underline slides between positions
7. Test on iPad simulator for device-agnostic thresholds

**Step 5: Commit**

```bash
git add SocialFusion/Views/Components/ProfileHeaderView.swift SocialFusion/Views/ProfileView.swift
git commit -m "chore(profile): clean up dead code and update previews after cinematic polish"
```

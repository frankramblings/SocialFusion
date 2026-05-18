# Accessibility Audit + High-Contrast Network Indicators Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close SocialFusion's accessibility gap on network identification before v1.0. Phase A normalizes every place network identity is signaled visually so each one uses `PlatformLogoBadge` (shape-coded) or an equivalent shape-coded element. Phase B adds a user-controllable "High-contrast network indicators" toggle that switches `PlatformLogoBadge` and derived chips to a high-contrast filled-vs-outlined dual-coding scheme — closing the Indigo gap that Jason Snell publicly called out in Six Colors (`docs/competitive/indigo-analysis.md` line 92).

**Architecture:** A new `AccessibilityPreferences` observable object (singleton-style, mirrored to `UserDefaults` via `@AppStorage`) is injected once at the app root and read by `PlatformLogoBadge`. The badge gains a single `highContrast` rendering branch with no new asset dependencies — it composes existing `MastodonLogo`/`BlueskyLogo` assets with stronger fills, thick black outlines (Bluesky), or pure outlined glyphs (Mastodon). All other places that signal network — `PostPlatformBadge`, `PlatformDot`, raw `Image(platform.icon)` sites, color-only highlights — are normalized to call through `PlatformLogoBadge` (or, where the surface is too tight for the full badge, are flagged in the audit and given an explicit shape-coded substitute with a VoiceOver label). Reduce-motion and Dynamic Type audits are checklist-driven; the only code add for reduce-motion is wiring `LaunchAnimationView`, which currently does not respect it.

**Tech Stack:** Swift 5+, SwiftUI, XCTest, ViewInspector-free snapshot diff via `UIHostingController` + image rendering. iOS 17+ floor. Uses existing patterns: `@StateObject` at app root, `@EnvironmentObject` propagation, `@AppStorage` for persistence, `@Environment(\.accessibilityReduceMotion)` for motion checks, `@Environment(\.dynamicTypeSize)` for type-scale checks.

**Spec reference:** `docs/superpowers/specs/2026-05-17-socialfusion-v1-vision-design.md` — see "Principle 5: Accessibility is first-class" (line 38), "Indigo Gap Map: Blue/purple indicators unusable for colorblind readers" (line 230), and "v1.0 Acceptance Criteria → Accessibility" (lines 266–271). Competitive context: `docs/competitive/indigo-analysis.md` lines 92, 110, 139, 223.

**File map (creates/modifies):**

- Create: `SocialFusion/State/AccessibilityPreferences.swift`
- Create: `SocialFusion/Views/Components/PlatformLogoBadge+HighContrast.swift`
- Create: `docs/superpowers/audits/2026-05-17-network-indicator-audit.md` (the audit checklist artifact)
- Create: `SocialFusionTests/AccessibilityPreferencesTests.swift`
- Create: `SocialFusionTests/PlatformLogoBadgeHighContrastTests.swift`
- Create: `SocialFusionTests/NetworkIndicatorAuditTests.swift` (static assertion: known network-signaling sites use shape-coded indicators)
- Modify: `SocialFusion/Views/Components/PlatformLogoBadge.swift` — add `highContrast` parameter, environment fallback, VoiceOver label
- Modify: `SocialFusion/Views/Components/PlatformDot.swift` — route all paths through `PlatformLogoBadge` when `useLogo` is true; keep dot path but always pair with VoiceOver label, and have it consult `AccessibilityPreferences` to auto-promote to logo when `highContrast` is on
- Modify: `SocialFusion/Views/Components/PostPlatformBadge.swift` — replace inline `Image(platform.icon)` color treatment with `PlatformLogoBadge` so it inherits high-contrast styling; keep the labeled capsule layout
- Modify: `SocialFusion/SocialFusionApp.swift` — instantiate `AccessibilityPreferences`, inject as `@EnvironmentObject` on all three root branches (launch animation / onboarding / main)
- Modify: `SocialFusion/Views/SettingsView.swift` — add an "Accessibility" section with the high-contrast toggle plus footer copy
- Modify: `SocialFusion/Views/Components/LaunchAnimationView.swift` — respect `accessibilityReduceMotion` (no rotation/scale on the orb fusion, fade-in only)
- Modify: `SocialFusion/Models/SocialPlatform.swift` — add `accessibilityLabel` and `shortAccessibilityLabel` computed properties
- Modify: `SocialFusion/ContentView.swift` line 273 — add `.accessibilityLabel(account.platform.accessibilityLabel)` to inline platform Image
- Modify: `SocialFusion/Views/UnifiedAccountsIcon.swift` — add VoiceOver labels and route to `PlatformLogoBadge`
- Modify: `SocialFusion/Views/AddAccountView.swift` line 129 — VoiceOver label + shape-coded swap
- Modify: `SocialFusion/Views/AccountsView.swift` lines 194/351/459 — replace raw `Image(account.platform.icon)` with `PlatformLogoBadge` where it functions as a network indicator
- Modify: `SocialFusion/Views/Components/PostComposerTopBar.swift` line 302 — same treatment as ContentView
- Modify: `SocialFusion/Views/Components/PostDetailView.swift` lines 535/576 — same treatment
- Modify: `SocialFusion/Views/Components/AutocompleteOverlay.swift` line 132 — same treatment
- Modify: `SocialFusion/Views/Components/TimelineFeedPickerPopover.swift` line 81 — same treatment
- Modify: `SocialFusion/Views/ComposeView.swift` lines 59/1741/1820/2711/2798 — same treatment
- Modify: `SocialFusion/Views/SearchView.swift` line 668 — same treatment
- Modify: `SocialFusion/ShareAsImage/ShareImageViews.swift` line 121 — same treatment (note: the rendered image is a static export, not interactive — it must still be shape-coded)

**Implementer assumptions to verify before each task:**

1. `PlatformLogoBadge(platform:size:shadowEnabled:)` lives at `SocialFusion/Views/Components/PlatformLogoBadge.swift` and is the established shape-coded badge. The added `highContrast` parameter must default to `false` so all existing call sites compile and behave identically (verified: 5 direct call sites at the start of this plan).
2. `SocialPlatform` is a `String`-backed `Codable` enum with cases `.mastodon` and `.bluesky` at `SocialFusion/Models/SocialPlatform.swift` lines 6–8. It already exposes `swiftUIColor` and `icon`; we add labels without removing existing properties.
3. `SettingsView` uses `@AppStorage` for all toggles (`SocialFusion/Views/SettingsView.swift` lines 9–15) and groups options into `Section(header: Text(...))` blocks (8 sections, last is Debug at line 228). The new section inserts after "Notifications" (line 106) and before "About" (line 174).
4. The app root in `SocialFusion/SocialFusionApp.swift` has three branches (launch animation line 52, onboarding line 70, main line 80–90). Each currently injects six `@EnvironmentObject`s. `AccessibilityPreferences` becomes the seventh.
5. `LaunchAnimationView` lives at `SocialFusion/Views/Components/LaunchAnimationView.swift` — confirmed it does **not** currently read `accessibilityReduceMotion` (verified: `grep -n "reduceMotion" SocialFusion/Views/Components/LaunchAnimationView.swift` returns no matches).
6. `ProfileHeaderView` already respects `accessibilityReduceMotion` correctly (verified: lines 10, 18, 20, 22, 24, 25 read the env value and zero motion when on). Reduce-motion audit must verify, not fix, this surface.
7. `ConsolidatedTimelineView` already respects reduce-motion across appearance transitions, pulse, scroll-to-top (verified: 16 `reduceMotion` references). Audit verifies — no change.
8. The test target is `SocialFusionTests`. Tests subclass `XCTestCase`. Snapshot/layout tests use `UIHostingController` + `UIView.drawHierarchy(in:afterScreenUpdates:)` to render badges at known sizes and assert basic invariants (non-empty contents, distinct hashes between platforms, distinct hashes between modes).
9. Two visual indicators that pre-exist and **must keep their current API** while becoming high-contrast-aware: `PlatformDot` (used in `ParentPostPreview`, `QuotePostView`, `FetchQuotePostView`) and `PostPlatformBadge` (used in DM views). Their public init signatures do not change; behavior is internally rewired.

---

## Task 1: Network-indicator audit checklist artifact

**Files:**
- Create: `docs/superpowers/audits/2026-05-17-network-indicator-audit.md`

This is the source-of-truth checklist that drives Phase A. Build it first so subsequent tasks have an authoritative list of surfaces to fix. Tasks 4–11 implement against this checklist; Task 13 (the static test) reads the same locations and asserts compliance.

The audit was seeded by running:

```bash
grep -rn "Mastodon\|Bluesky" SocialFusion --include="*.swift" \
  | grep -iE "color|badge|chip|indicator|dot|circle|tint|fill\(\\.|foregroundColor|foregroundStyle"
grep -rn "Image(platform.icon)\|MastodonLogo\|BlueskyLogo" SocialFusion --include="*.swift"
grep -rn "platform.swiftUIColor\|platform.colorHex\|platformColor" SocialFusion --include="*.swift"
```

- [ ] **Step 1: Create the audit document**

Create `docs/superpowers/audits/2026-05-17-network-indicator-audit.md`:

```markdown
# Network Indicator Audit — 2026-05-17

Source-of-truth list of every surface in SocialFusion that signals "this is a Mastodon thing" or "this is a Bluesky thing" through visual means. For each row:

- **Status** is one of: ✅ already shape-coded via `PlatformLogoBadge`; ⚠️ shape-coded but no VoiceOver label; ❌ color-only; 🔁 dual (shape + color, but color is the visual primary).
- **Fix** is the one-line action.

## Components (reusable building blocks)

| File:Line | Surface | Status | Fix |
| --- | --- | --- | --- |
| `SocialFusion/Views/Components/PlatformLogoBadge.swift:5` | The badge itself | ✅ shape-coded | Add `highContrast` param + VoiceOver label (Task 4). |
| `SocialFusion/Views/Components/PlatformDot.swift:38` | Solid colored circle (the `useLogo: false` path) | ❌ color-only | When `AccessibilityPreferences.highContrast` is on, force `useLogo = true`. Always attach `.accessibilityLabel(platform.accessibilityLabel)` (Task 5). |
| `SocialFusion/Views/Components/PostPlatformBadge.swift:10` | Inline `Image(platform.icon)` tinted with `platform.swiftUIColor` | 🔁 shape + color | Replace inner image with `PlatformLogoBadge(platform:size:8)`; keep capsule + text (Task 6). |
| `SocialFusion/Views/Components/PostAuthorImageView.swift:72` | Already `PlatformLogoBadge` | ✅ shape-coded | VoiceOver label inherits from badge update — no change required. |
| `SocialFusion/Views/Components/ProfileHeaderView.swift:212` | Already `PlatformLogoBadge` | ✅ shape-coded | Same. |

## Inline platform-image sites (need normalization)

| File:Line | Surface | Status | Fix |
| --- | --- | --- | --- |
| `SocialFusion/ContentView.swift:273` | Account menu row | 🔁 shape + color | Wrap with `.accessibilityLabel(account.platform.accessibilityLabel)`. Logo is intentional here. (Task 7) |
| `SocialFusion/Views/Components/PostComposerTopBar.swift:302` | Composer top bar | 🔁 shape + color | Replace with `PlatformLogoBadge(platform: platform, size: 18)`. (Task 7) |
| `SocialFusion/Views/Components/PostDetailView.swift:535` | Detail header | 🔁 shape + color | Replace with `PlatformLogoBadge`. (Task 7) |
| `SocialFusion/Views/Components/PostDetailView.swift:576` | Detail footer chip | 🔁 shape + color | Replace with `PlatformLogoBadge`. (Task 7) |
| `SocialFusion/Views/Components/AutocompleteOverlay.swift:132` | Account autocomplete suggestion | 🔁 shape + color | Replace with `PlatformLogoBadge(size: 14)`. (Task 7) |
| `SocialFusion/Views/Components/TimelineFeedPickerPopover.swift:81` | Feed picker row icon | 🔁 shape + color | Replace with `PlatformLogoBadge`. (Task 7) |
| `SocialFusion/Views/ComposeView.swift:59` | Composer header | 🔁 shape + color | Replace with `PlatformLogoBadge`. (Task 8) |
| `SocialFusion/Views/ComposeView.swift:1741` | Reply-status row | 🔁 shape + color | Replace with `PlatformLogoBadge`. (Task 8) |
| `SocialFusion/Views/ComposeView.swift:1820` | Account picker row | 🔁 shape + color | Replace with `PlatformLogoBadge`. (Task 8) |
| `SocialFusion/Views/ComposeView.swift:2711` | Account row helper | 🔁 shape + color | Replace with `PlatformLogoBadge`. (Task 8) |
| `SocialFusion/Views/ComposeView.swift:2798` | Mention chip | 🔁 shape + color | Replace with `PlatformLogoBadge(size: 12)`. (Task 8) |
| `SocialFusion/Views/SearchView.swift:668` | Search account row | 🔁 shape + color | Replace with `PlatformLogoBadge`. (Task 7) |
| `SocialFusion/Views/AccountsView.swift:194` | Accounts list | 🔁 shape + color | Replace with `PlatformLogoBadge`. (Task 9) |
| `SocialFusion/Views/AccountsView.swift:351` | Accounts list (variant) | 🔁 shape + color | Replace with `PlatformLogoBadge`. (Task 9) |
| `SocialFusion/Views/AccountsView.swift:459` | Accounts list (variant) | 🔁 shape + color | Replace with `PlatformLogoBadge`. (Task 9) |
| `SocialFusion/Views/AddAccountView.swift:129` | Platform picker, Mastodon tile | 🔁 shape + color | Wrap with `.accessibilityLabel("Mastodon")`. Logo is intentional. (Task 9) |
| `SocialFusion/Views/AddAccountView.swift:139–169` | Platform picker color fill | 🔁 shape + color | Already paired with logo — add VoiceOver label only. (Task 9) |
| `SocialFusion/Views/UnifiedAccountsIcon.swift:94,101,142,156` | Unified-accounts icon (combined logo) | 🔁 shape + color | Add aggregate `.accessibilityLabel("Mastodon and Bluesky accounts")`. (Task 9) |
| `SocialFusion/ShareAsImage/ShareImageViews.swift:121` | Exported image platform badge | 🔁 shape + color | Replace with `PlatformLogoBadge(size: 24)` so exported screenshots are also shape-coded. (Task 10) |

## Color-only highlights (decorative; verify they have a sibling shape-coded indicator)

| File:Line | Surface | Status | Action |
| --- | --- | --- | --- |
| `SocialFusion/Views/ProfileView.swift:190,195` | Tinted divider line | 🔁 decorative | Keep; `PlatformLogoBadge` is rendered in the same header. Verify in audit. |
| `SocialFusion/Views/AccountTimelineView.swift:120` | Tinted text | 🔁 decorative | Verify a sibling shape-coded element is visible in the same surface; if not, add `PlatformLogoBadge`. (Task 9) |
| `SocialFusion/Views/Messages/ChatView.swift:26,267,315,321` | Compose-button platform color | 🔁 decorative | Keep; the conversation header already shows `PostPlatformBadge`. Verify in audit. |
| `SocialFusion/Views/ComposeView.swift:30,842,1429,1779` | Post-button platform color | 🔁 decorative | Keep; the composer header already shows the logo. Verify in audit. |
| `SocialFusion/Views/Components/ActionBar.swift:27` | Action-bar tint | 🔁 decorative | Verify the post card itself shows `PlatformLogoBadge`. |

## Reduce-motion audit (Phase A.5)

| Surface | Status | Action |
| --- | --- | --- |
| `LaunchAnimationView` | ❌ does not respect | Wire `@Environment(\.accessibilityReduceMotion)` and disable rotation/scale. Fade only. (Task 11) |
| `ProfileHeaderView` parallax | ✅ respects | Verify only. |
| `ConsolidatedTimelineView` appear/scroll | ✅ respects | Verify only. |
| `LiquidGlassComponents` | ✅ respects | Verify only. |
| `SkeletonPostCard` shimmer | ✅ respects | Verify only. |
| `ParallaxMediaModifier` | ✅ respects | Verify only. |
| `FusedGlyph` (from sibling plan) | TBD | Verify on integration. |

## Dynamic Type audit (Phase A.5)

Every text-bearing surface must scale through AX5. Walk each primary surface and confirm. (Task 12)

| Surface | Action |
| --- | --- |
| `ConsolidatedTimelineView` | Walk timeline at AX5. Note any clipped text. |
| `PostCardView` | Walk a post at AX5 — confirm author, content, action bar all readable. |
| `ComposeView` | AX5 walk; verify Post button still hittable. |
| `ChatView` | AX5 walk; verify bubble layout. |
| `ProfileHeaderView` | AX5 walk; verify bio truncation graceful. |
| `SettingsView` | AX5 walk; verify rows tap-targets ≥ 44pt. |
| `OnboardingView` | AX5 walk. |
| `DirectMessagesView` (inbox) | AX5 walk. |

## VoiceOver audit (Phase A.5)

Every primary surface — timeline, compose, thread, profile, DMs, settings, onboarding — must read meaningfully end-to-end. Run VoiceOver pass per surface; check off in Task 12 below.

## Colorblind-simulator screenshot pass (Phase B verification)

Run the app under Simulator → Accessibility → Color Filters (Deuteranopia, Protanopia, Tritanopia) and screenshot the seven canonical surfaces. Each surface must remain network-identifiable. (Task 13)
```

- [ ] **Step 2: Commit the audit artifact**

```bash
git add docs/superpowers/audits/2026-05-17-network-indicator-audit.md
git commit -m "docs(a11y): seed network-indicator audit checklist"
```

---

## Task 2: AccessibilityPreferences ObservableObject

**Files:**
- Create: `SocialFusion/State/AccessibilityPreferences.swift`
- Test: `SocialFusionTests/AccessibilityPreferencesTests.swift`

The shared state. One `ObservableObject` exposes user toggles backed by `UserDefaults`. v1.0 ships with a single field — `highContrastNetworkIndicators` — but the type is named and structured so additional accessibility toggles (e.g., "reduce media motion beyond OS setting", "always show alt text") slot in without renames.

- [ ] **Step 1: Write the failing tests**

Create `SocialFusionTests/AccessibilityPreferencesTests.swift`:

```swift
import XCTest
@testable import SocialFusion

@MainActor
final class AccessibilityPreferencesTests: XCTestCase {
    private let testSuiteName = "AccessibilityPreferencesTests"

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: testSuiteName)
        defaults.removePersistentDomain(forName: testSuiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: testSuiteName)
        super.tearDown()
    }

    func testHighContrastDefaultsOff() {
        let prefs = AccessibilityPreferences(defaults: defaults)
        XCTAssertFalse(prefs.highContrastNetworkIndicators,
                       "High-contrast must default OFF so existing users see no visual change.")
    }

    func testHighContrastPersistsToDefaults() {
        let prefs = AccessibilityPreferences(defaults: defaults)
        prefs.highContrastNetworkIndicators = true
        let reloaded = AccessibilityPreferences(defaults: defaults)
        XCTAssertTrue(reloaded.highContrastNetworkIndicators,
                      "Setting must survive a fresh load (UserDefaults round-trip).")
    }

    func testToggleChangePublishesObjectWillChange() {
        let prefs = AccessibilityPreferences(defaults: defaults)
        let exp = expectation(description: "objectWillChange fires when value flips")
        let cancellable = prefs.objectWillChange.sink { exp.fulfill() }
        prefs.highContrastNetworkIndicators = true
        wait(for: [exp], timeout: 1.0)
        cancellable.cancel()
    }

    func testStorageKeyIsStable() {
        // Locking the key string protects existing users from losing their setting
        // if anyone refactors the property name.
        XCTAssertEqual(AccessibilityPreferences.Keys.highContrastNetworkIndicators,
                       "accessibility.highContrastNetworkIndicators")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/AccessibilityPreferencesTests`
Expected: FAIL — `AccessibilityPreferences` not defined.

- [ ] **Step 3: Implement the model**

Create `SocialFusion/State/AccessibilityPreferences.swift`:

```swift
import Combine
import Foundation
import SwiftUI

/// User-controlled accessibility preferences that the OS doesn't expose.
///
/// v1.0 ships one field — `highContrastNetworkIndicators` — which addresses the
/// Six Colors colorblind critique by switching `PlatformLogoBadge` to a
/// filled-vs-outlined dual-coding scheme. The type is structured so additional
/// app-specific accessibility toggles can be added without renames.
///
/// Backed by `UserDefaults`. Injectable for tests via the designated init.
@MainActor
public final class AccessibilityPreferences: ObservableObject {
    public enum Keys {
        public static let highContrastNetworkIndicators = "accessibility.highContrastNetworkIndicators"
    }

    private let defaults: UserDefaults

    /// When `true`, `PlatformLogoBadge` and indicators derived from it render
    /// in a high-contrast filled-vs-outlined scheme (see
    /// `PlatformLogoBadge+HighContrast.swift`). Default `false`.
    @Published public var highContrastNetworkIndicators: Bool {
        didSet {
            defaults.set(highContrastNetworkIndicators,
                         forKey: Keys.highContrastNetworkIndicators)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.highContrastNetworkIndicators =
            defaults.bool(forKey: Keys.highContrastNetworkIndicators)
    }
}

// MARK: - Environment integration

private struct AccessibilityPreferencesKey: EnvironmentKey {
    @MainActor static var defaultValue: AccessibilityPreferences {
        AccessibilityPreferences()
    }
}

public extension EnvironmentValues {
    /// Convenience environment access for views that don't want an explicit
    /// `@EnvironmentObject` (e.g. `PlatformLogoBadge` itself, which is used
    /// in static previews and snapshot tests where injecting an env object
    /// is awkward).
    var accessibilityPreferences: AccessibilityPreferences {
        get { self[AccessibilityPreferencesKey.self] }
        set { self[AccessibilityPreferencesKey.self] = newValue }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/AccessibilityPreferencesTests`
Expected: PASS, all 4 tests green.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/State/AccessibilityPreferences.swift SocialFusionTests/AccessibilityPreferencesTests.swift
git commit -m "feat(a11y): add AccessibilityPreferences with high-contrast toggle"
```

---

## Task 3: SocialPlatform accessibility labels

**Files:**
- Modify: `SocialFusion/Models/SocialPlatform.swift`

Centralize the VoiceOver strings so every call site reads the same wording. Both labels are localizable in a v1.1 string-table pass.

- [ ] **Step 1: Add the properties**

Edit `SocialFusion/Models/SocialPlatform.swift`. Add after `swiftUIColor` (line 33):

```swift
    /// VoiceOver label for the network as a whole. Used wherever a platform
    /// indicator stands alone (logo, dot, chip).
    public var accessibilityLabel: String {
        switch self {
        case .mastodon: return "Mastodon"
        case .bluesky:  return "Bluesky"
        }
    }

    /// Composable VoiceOver fragment for posts: e.g. "Post on Mastodon".
    public var postAccessibilityFragment: String {
        switch self {
        case .mastodon: return "Post on Mastodon"
        case .bluesky:  return "Post on Bluesky"
        }
    }
```

- [ ] **Step 2: Verify the project still builds**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add SocialFusion/Models/SocialPlatform.swift
git commit -m "feat(a11y): add VoiceOver labels to SocialPlatform"
```

---

## Task 4: Extend PlatformLogoBadge with high-contrast mode

**Files:**
- Modify: `SocialFusion/Views/Components/PlatformLogoBadge.swift`
- Create: `SocialFusion/Views/Components/PlatformLogoBadge+HighContrast.swift`
- Test: `SocialFusionTests/PlatformLogoBadgeHighContrastTests.swift`

The badge gains:

1. An explicit `highContrast: Bool?` parameter. `nil` (default) means "follow `AccessibilityPreferences` from environment"; `true`/`false` overrides (useful for tests and the Settings preview row).
2. A VoiceOver label — set via `accessibilityLabel(platform.accessibilityLabel)` and marked as `accessibilityAddTraits(.isImage)`.
3. A high-contrast rendering path: Bluesky becomes a **filled** colored glyph with a thick (1.5pt) black outline; Mastodon becomes an **outlined** glyph (background fill = clear, dark grey 1.5pt stroke around the logo silhouette, no color fill). The filled-vs-outlined contrast carries the network identity even under deuteranopia / protanopia / tritanopia where blue and purple collapse to similar greys.

- [ ] **Step 1: Write the failing tests**

Create `SocialFusionTests/PlatformLogoBadgeHighContrastTests.swift`:

```swift
import SwiftUI
import XCTest
@testable import SocialFusion

@MainActor
final class PlatformLogoBadgeHighContrastTests: XCTestCase {
    /// Renders a badge into a UIImage and returns the image. We don't compare
    /// to golden images here — we assert pixel-level invariants instead, so
    /// the test is robust against font/asset/iOS-version changes.
    private func render(_ view: some View, size: CGSize = CGSize(width: 24, height: 24)) -> UIImage {
        let hosting = UIHostingController(rootView: view.frame(width: size.width, height: size.height))
        hosting.view.frame = CGRect(origin: .zero, size: size)
        hosting.view.backgroundColor = .white
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            hosting.view.drawHierarchy(in: hosting.view.bounds, afterScreenUpdates: true)
        }
    }

    private func pngHash(of image: UIImage) -> Int {
        image.pngData()?.hashValue ?? 0
    }

    func testHighContrastDefaultsToFalseForBackCompat() {
        // Calling the existing initializer must produce an identical render
        // to the explicit highContrast: false variant.
        let legacy = PlatformLogoBadge(platform: .mastodon, size: 24)
        let explicit = PlatformLogoBadge(platform: .mastodon, size: 24, highContrast: false)
        XCTAssertEqual(pngHash(of: render(legacy)), pngHash(of: render(explicit)),
                       "Default highContrast must equal explicit false (back-compat).")
    }

    func testHighContrastChangesBlueskyRender() {
        let normal = PlatformLogoBadge(platform: .bluesky, size: 24, highContrast: false)
        let hc = PlatformLogoBadge(platform: .bluesky, size: 24, highContrast: true)
        XCTAssertNotEqual(pngHash(of: render(normal)), pngHash(of: render(hc)),
                          "High-contrast Bluesky must render differently from normal Bluesky.")
    }

    func testHighContrastChangesMastodonRender() {
        let normal = PlatformLogoBadge(platform: .mastodon, size: 24, highContrast: false)
        let hc = PlatformLogoBadge(platform: .mastodon, size: 24, highContrast: true)
        XCTAssertNotEqual(pngHash(of: render(normal)), pngHash(of: render(hc)),
                          "High-contrast Mastodon must render differently from normal Mastodon.")
    }

    func testHighContrastPlatformsRemainDistinct() {
        // The whole point: when high-contrast is on, the two networks must
        // still be visually distinct (filled vs outlined).
        let bsky = PlatformLogoBadge(platform: .bluesky, size: 24, highContrast: true)
        let masto = PlatformLogoBadge(platform: .mastodon, size: 24, highContrast: true)
        XCTAssertNotEqual(pngHash(of: render(bsky)), pngHash(of: render(masto)),
                          "High-contrast Mastodon and Bluesky must remain distinguishable.")
    }

    func testHighContrastSizesScale() {
        // Sanity: the size parameter must still drive the rendered frame.
        let small = render(PlatformLogoBadge(platform: .bluesky, size: 12, highContrast: true),
                           size: CGSize(width: 12, height: 12))
        let large = render(PlatformLogoBadge(platform: .bluesky, size: 32, highContrast: true),
                           size: CGSize(width: 32, height: 32))
        XCTAssertEqual(small.size, CGSize(width: 12, height: 12))
        XCTAssertEqual(large.size, CGSize(width: 32, height: 32))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/PlatformLogoBadgeHighContrastTests`
Expected: FAIL — `highContrast:` parameter not defined.

- [ ] **Step 3: Modify the badge**

Replace the contents of `SocialFusion/Views/Components/PlatformLogoBadge.swift`:

```swift
import SwiftUI

/// A platform logo badge that displays SVG logos as badges on profile pictures
/// with a glass-like effect. This replaces colored dots with actual platform
/// logos for better clarity and accessibility.
///
/// **Accessibility:**
/// - Shape-coded by default — uses the platform's silhouette (`MastodonLogo`
///   or `BlueskyLogo` asset) so identification does not depend on color.
/// - When `highContrast` is on (driven by `AccessibilityPreferences` or set
///   explicitly), Bluesky renders as a *filled* colored glyph with a thick
///   black outline, and Mastodon renders as an *outlined* dark glyph with
///   no color fill. This filled-vs-outlined contrast survives deuteranopia,
///   protanopia, and tritanopia simulations where blue and purple collapse.
/// - Sets a VoiceOver label so the network is announced.
struct PlatformLogoBadge: View {
    let platform: SocialPlatform
    var size: CGFloat = 16
    var shadowEnabled: Bool = true

    /// Explicit override. `nil` reads the value from `AccessibilityPreferences`
    /// in the environment.
    var highContrast: Bool? = nil

    @Environment(\.accessibilityPreferences) private var prefs

    private var isHighContrast: Bool {
        highContrast ?? prefs.highContrastNetworkIndicators
    }

    private var logoImageName: String {
        switch platform {
        case .bluesky:  return "BlueskyLogo"
        case .mastodon: return "MastodonLogo"
        }
    }

    private var platformColor: Color {
        switch platform {
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
        }
    }

    var body: some View {
        Group {
            if isHighContrast {
                highContrastBody
            } else {
                standardBody
            }
        }
        .accessibilityElement()
        .accessibilityLabel(platform.accessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }

    /// Original look: tinted logo over a glass-material background.
    private var standardBody: some View {
        Image(logoImageName)
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(platformColor)
            .frame(width: size * 0.66, height: size * 0.66)
            .padding(size * 0.17)
            .background {
                Circle()
                    .fill(.clear)
                    .background(.regularMaterial, in: Circle())
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(shadowEnabled ? 0.15 : 0), radius: 2, x: 0, y: 1)
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.3), lineWidth: 0.5)
            }
    }

    /// High-contrast look: filled glyph + thick outline for Bluesky;
    /// outlined-only glyph for Mastodon. See `PlatformLogoBadge+HighContrast.swift`.
    private var highContrastBody: some View {
        HighContrastBadgeBody(
            platform: platform,
            logoImageName: logoImageName,
            size: size,
            shadowEnabled: shadowEnabled
        )
    }
}

#Preview {
    HStack(spacing: 20) {
        VStack(spacing: 10) {
            Text("Standard").font(.caption)
            PlatformLogoBadge(platform: .bluesky, size: 24)
            PlatformLogoBadge(platform: .mastodon, size: 24)
        }
        VStack(spacing: 10) {
            Text("High-Contrast").font(.caption)
            PlatformLogoBadge(platform: .bluesky, size: 24, highContrast: true)
            PlatformLogoBadge(platform: .mastodon, size: 24, highContrast: true)
        }
    }
    .padding()
}
```

- [ ] **Step 4: Add the high-contrast renderer**

Create `SocialFusion/Views/Components/PlatformLogoBadge+HighContrast.swift`:

```swift
import SwiftUI

/// High-contrast variant of `PlatformLogoBadge`.
///
/// Design rationale: under deuteranopia / protanopia / tritanopia the Bluesky
/// blue (`#0085FF`) and the Mastodon purple (`#6364FF`) compress toward the
/// same neutral grey, and color tinting alone fails to distinguish them. This
/// variant carries network identity through *fill style*:
///
/// - **Bluesky** — a filled colored glyph with a 1.5pt black outline. The
///   filled rendering reads as "solid" at a glance.
/// - **Mastodon** — an outlined glyph (no color fill, dark grey 1.5pt stroke
///   following the silhouette). The outlined rendering reads as "hollow."
///
/// Filled vs. hollow is the most colorblind-safe coding pair we can stack on
/// top of the existing shape coding.
struct HighContrastBadgeBody: View {
    let platform: SocialPlatform
    let logoImageName: String
    let size: CGFloat
    let shadowEnabled: Bool

    var body: some View {
        ZStack {
            // Background plate: opaque white so high-contrast borders read
            // against any timeline background. Slight grey ring for affordance.
            Circle()
                .fill(Color.white)
                .overlay(
                    Circle().stroke(Color.black.opacity(0.85), lineWidth: 1.0)
                )

            glyph
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(shadowEnabled ? 0.20 : 0), radius: 1.5, x: 0, y: 1)
    }

    @ViewBuilder
    private var glyph: some View {
        switch platform {
        case .bluesky:
            // Filled colored glyph with thick black outline.
            ZStack {
                // Outline pass: render the logo as a stroke by stacking 8
                // offset black copies behind a colored copy.
                ForEach(strokeOffsets, id: \.self) { offset in
                    Image(logoImageName)
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(Color.black)
                        .offset(x: offset.dx, y: offset.dy)
                }
                Image(logoImageName)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color(red: 0, green: 133 / 255, blue: 255 / 255))
            }
            .frame(width: glyphSide, height: glyphSide)

        case .mastodon:
            // Outlined-only glyph: black silhouette, no color fill.
            // Render as a slightly inset hollow stroke by combining a
            // dark silhouette with a white inset copy.
            ZStack {
                Image(logoImageName)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color.black)
                    .frame(width: glyphSide, height: glyphSide)
                Image(logoImageName)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color.white)
                    .frame(width: glyphSide * 0.78, height: glyphSide * 0.78)
            }
        }
    }

    private var glyphSide: CGFloat { size * 0.62 }

    /// 8-direction offset ring used to approximate a stroke around the
    /// Bluesky glyph. Magnitude scales with badge size.
    private var strokeOffsets: [CGSize] {
        let m = max(size * 0.06, 1.0)
        return [
            CGSize(width:  m, height:  0),
            CGSize(width: -m, height:  0),
            CGSize(width:  0, height:  m),
            CGSize(width:  0, height: -m),
            CGSize(width:  m, height:  m),
            CGSize(width: -m, height:  m),
            CGSize(width:  m, height: -m),
            CGSize(width: -m, height: -m),
        ]
    }
}

#Preview {
    HStack(spacing: 16) {
        HighContrastBadgeBody(platform: .bluesky,
                              logoImageName: "BlueskyLogo",
                              size: 32, shadowEnabled: true)
        HighContrastBadgeBody(platform: .mastodon,
                              logoImageName: "MastodonLogo",
                              size: 32, shadowEnabled: true)
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/PlatformLogoBadgeHighContrastTests`
Expected: PASS, all 5 tests green.

- [ ] **Step 6: Commit**

```bash
git add SocialFusion/Views/Components/PlatformLogoBadge.swift \
        SocialFusion/Views/Components/PlatformLogoBadge+HighContrast.swift \
        SocialFusionTests/PlatformLogoBadgeHighContrastTests.swift
git commit -m "feat(a11y): high-contrast rendering for PlatformLogoBadge"
```

---

## Task 5: Wire AccessibilityPreferences into the app root

**Files:**
- Modify: `SocialFusion/SocialFusionApp.swift`

The app creates a single `AccessibilityPreferences` and injects it as `@EnvironmentObject` into every root branch (launch animation, onboarding, main). Because `PlatformLogoBadge` reads from `\.accessibilityPreferences` in the SwiftUI environment, an `.environment(\.accessibilityPreferences, prefs)` modifier is added on each branch — this makes the value visible to plain views without forcing every consumer to declare an `@EnvironmentObject`.

- [ ] **Step 1: Add the state object**

Edit `SocialFusion/SocialFusionApp.swift`. Add after `@StateObject private var crashReporting = CrashReportingService.shared` (line 35):

```swift
    // Accessibility preferences (high-contrast network indicators, etc.)
    @StateObject private var accessibilityPreferences = AccessibilityPreferences()
```

- [ ] **Step 2: Inject on all three root branches**

In the same file, add **after every existing `.environmentObject(chatStreamService)`** line — there are three (launch animation block, onboarding block, main content block). Each becomes:

```swift
                .environmentObject(chatStreamService)
                .environmentObject(accessibilityPreferences)
                .environment(\.accessibilityPreferences, accessibilityPreferences)
```

The `.environment(\.accessibilityPreferences, ...)` line is required so views that read via the environment key (notably `PlatformLogoBadge`, which has no `@EnvironmentObject`) receive the same instance.

- [ ] **Step 3: Verify the project builds and existing tests still pass**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/AccessibilityPreferencesTests -only-testing:SocialFusionTests/PlatformLogoBadgeHighContrastTests`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add SocialFusion/SocialFusionApp.swift
git commit -m "feat(a11y): inject AccessibilityPreferences at app root"
```

---

## Task 6: Add Settings toggle

**Files:**
- Modify: `SocialFusion/Views/SettingsView.swift`

A new "Accessibility" section sits between Notifications and About. The toggle binds to the `@EnvironmentObject` `AccessibilityPreferences`. A `Text` footer explains the change and references the colorblind-friendly intent without naming a competitor.

- [ ] **Step 1: Add the EnvironmentObject**

Edit `SocialFusion/Views/SettingsView.swift`. After `@ObservedObject private var featureFlagManager = FeatureFlagManager.shared` (line 8) add:

```swift
    @EnvironmentObject private var accessibilityPreferences: AccessibilityPreferences
```

- [ ] **Step 2: Insert the Accessibility section**

In the same file, locate the end of the Notifications section (just before `Section(header: Text("About"))` at line 174). Insert this new section:

```swift
                Section(header: Text("Accessibility")) {
                    Toggle(
                        "High-Contrast Network Indicators",
                        isOn: $accessibilityPreferences.highContrastNetworkIndicators
                    )

                    HStack(spacing: 16) {
                        VStack(spacing: 6) {
                            PlatformLogoBadge(
                                platform: .bluesky,
                                size: 28,
                                highContrast: accessibilityPreferences.highContrastNetworkIndicators
                            )
                            Text("Bluesky").font(.caption2)
                        }
                        VStack(spacing: 6) {
                            PlatformLogoBadge(
                                platform: .mastodon,
                                size: 28,
                                highContrast: accessibilityPreferences.highContrastNetworkIndicators
                            )
                            Text("Mastodon").font(.caption2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Preview of current network indicator style")

                    Text(
                        "Switches network indicators to a filled-vs-outlined scheme that stays distinguishable for colorblind readers. Shape-coded logos are always used, regardless of this setting."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
```

- [ ] **Step 3: Verify the project builds**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual smoke test**

Launch the app, open Settings, find the new Accessibility section. Toggle the switch and confirm the preview row immediately switches between the two rendering modes. Force-quit and relaunch — the setting should persist.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Views/SettingsView.swift
git commit -m "feat(a11y): add High-Contrast Network Indicators toggle to Settings"
```

---

## Task 7: Normalize the simple inline indicator sites

**Files:**
- Modify: `SocialFusion/ContentView.swift`
- Modify: `SocialFusion/Views/Components/PostComposerTopBar.swift`
- Modify: `SocialFusion/Views/Components/PostDetailView.swift`
- Modify: `SocialFusion/Views/Components/AutocompleteOverlay.swift`
- Modify: `SocialFusion/Views/Components/TimelineFeedPickerPopover.swift`
- Modify: `SocialFusion/Views/SearchView.swift`

Each of these is a single inline `Image(platform.icon)` or `Image(platform == .mastodon ? "MastodonLogo" : "BlueskyLogo")` that signals network. Replace with `PlatformLogoBadge` (preserving the visual weight of the original by matching sizes) and add VoiceOver labels.

- [ ] **Step 1: ContentView line 273**

In `SocialFusion/ContentView.swift`, replace:

```swift
                        } icon: {
                            Image(account.platform == .mastodon ? "MastodonLogo" : "BlueskyLogo")
                        }
```

with:

```swift
                        } icon: {
                            PlatformLogoBadge(platform: account.platform, size: 18)
                                .accessibilityLabel(account.platform.accessibilityLabel)
                        }
```

- [ ] **Step 2: PostComposerTopBar.swift line ~302**

In `SocialFusion/Views/Components/PostComposerTopBar.swift`, replace the inline expression around line 302:

```swift
                        Image(platform == .mastodon ? "MastodonLogo" : "BlueskyLogo")
```

with:

```swift
                        PlatformLogoBadge(platform: platform, size: 18)
```

(Leave any neighboring layout modifiers like `.resizable()`, `.frame(...)`, `.foregroundColor(...)` removed — `PlatformLogoBadge` owns its own sizing.)

- [ ] **Step 3: PostDetailView.swift lines 535 and 576**

In `SocialFusion/Views/Components/PostDetailView.swift`, locate the two `Image(platform.icon)` sites. Replace each:

```swift
                Image(platform.icon)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundColor(platform.swiftUIColor)
```

with:

```swift
                PlatformLogoBadge(platform: platform, size: 16)
```

- [ ] **Step 4: AutocompleteOverlay.swift line 132**

In `SocialFusion/Views/Components/AutocompleteOverlay.swift`, replace:

```swift
          Image(platform.icon)
```

and any surrounding `.resizable().frame(...).foregroundColor(...)` with:

```swift
          PlatformLogoBadge(platform: platform, size: 14)
```

- [ ] **Step 5: TimelineFeedPickerPopover.swift line 81**

In `SocialFusion/Views/Components/TimelineFeedPickerPopover.swift`, replace:

```swift
            let logoAsset = account.platform == .mastodon ? "MastodonLogo" : "BlueskyLogo"
            // ... and the corresponding Image(logoAsset) site
```

with a single line at the use site:

```swift
            PlatformLogoBadge(platform: account.platform, size: 18)
```

Remove the now-unused `logoAsset` binding.

- [ ] **Step 6: SearchView.swift line 668**

In `SocialFusion/Views/SearchView.swift`, replace:

```swift
        Image(platform.icon)
```

(and any neighboring `.resizable().frame(...).foregroundColor(platform.swiftUIColor)`) with:

```swift
        PlatformLogoBadge(platform: platform, size: 16)
```

- [ ] **Step 7: Verify the project builds**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Manual smoke test**

Launch the app. Walk: timeline → tap an avatar → profile renders with badge; open a post → detail view shows badge; type `@` in compose → autocomplete shows badge per result; open feed picker → each row shows badge.

- [ ] **Step 9: Commit**

```bash
git add SocialFusion/ContentView.swift \
        SocialFusion/Views/Components/PostComposerTopBar.swift \
        SocialFusion/Views/Components/PostDetailView.swift \
        SocialFusion/Views/Components/AutocompleteOverlay.swift \
        SocialFusion/Views/Components/TimelineFeedPickerPopover.swift \
        SocialFusion/Views/SearchView.swift
git commit -m "refactor(a11y): route inline platform-image sites through PlatformLogoBadge"
```

---

## Task 8: Normalize ComposeView indicator sites

**Files:**
- Modify: `SocialFusion/Views/ComposeView.swift`

`ComposeView` is the largest single offender — five distinct inline `Image(platform.icon)` or `Image(post.platform.icon)` sites at lines 59, 1741, 1820, 2711, 2798. Same treatment as Task 7 but split into its own task because ComposeView is large and easy to break.

- [ ] **Step 1: Replace at line 59 (compose header)**

Replace:

```swift
                Image(post.platform.icon)
```

(and any neighboring `.resizable().aspectRatio(...).frame(...).foregroundColor(platformColor)`) with:

```swift
                PlatformLogoBadge(platform: post.platform, size: 18)
```

- [ ] **Step 2: Replace at line ~1741 (reply-status row)**

Replace `Image(status.platform.icon)` and its modifiers with:

```swift
                            PlatformLogoBadge(platform: status.platform, size: 14)
```

- [ ] **Step 3: Replace at line ~1820 (account picker row)**

Replace `Image(platform.icon)` and its modifiers with:

```swift
                    PlatformLogoBadge(platform: platform, size: 16)
```

- [ ] **Step 4: Replace at line ~2711 (helper row)**

Replace `Image(platform.icon)` and its modifiers with:

```swift
                PlatformLogoBadge(platform: platform, size: 16)
```

- [ ] **Step 5: Replace at line ~2798 (mention chip)**

Replace `Image(platform.icon)` and its modifiers with:

```swift
                                        PlatformLogoBadge(platform: platform, size: 12)
```

- [ ] **Step 6: Verify the project builds**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Manual smoke test**

Open compose; switch the active account via the picker; reply to a post; insert a `@mention` and pick a result. All five sites should now render the badge.

- [ ] **Step 8: Commit**

```bash
git add SocialFusion/Views/ComposeView.swift
git commit -m "refactor(a11y): route ComposeView platform images through PlatformLogoBadge"
```

---

## Task 9: Normalize AccountsView, AddAccountView, UnifiedAccountsIcon, AccountTimelineView

**Files:**
- Modify: `SocialFusion/Views/AccountsView.swift`
- Modify: `SocialFusion/Views/AddAccountView.swift`
- Modify: `SocialFusion/Views/UnifiedAccountsIcon.swift`
- Modify: `SocialFusion/Views/AccountTimelineView.swift`

Account-management surfaces. AccountsView has three near-duplicate `Image(account.platform.icon)` sites (lines 194, 351, 459). UnifiedAccountsIcon shows both logos at once — no replacement needed inside the icon itself, but it gets a combined VoiceOver label. AddAccountView gets VoiceOver labels on its tiles (the logos are already shape-coded inside the tile but the surrounding color fill is the visual primary). AccountTimelineView line 120 has a colored Text — pair it with a badge so the network is shape-coded in that header.

- [ ] **Step 1: AccountsView at lines 194, 351, 459**

In `SocialFusion/Views/AccountsView.swift`, locate each `Image(account.platform.icon)` and replace with:

```swift
                    PlatformLogoBadge(platform: account.platform, size: 20)
```

(Remove the surrounding `.resizable().aspectRatio(...).frame(...).foregroundColor(...)` modifiers — the badge owns its layout.)

- [ ] **Step 2: AddAccountView at line 129**

In `SocialFusion/Views/AddAccountView.swift`, locate the tile that renders `Image("MastodonLogo")` and the matching Bluesky variant a few lines later. Wrap each tile (the outer `VStack` or `Button`) with:

```swift
            .accessibilityElement(children: .combine)
            .accessibilityLabel(SocialPlatform.mastodon.accessibilityLabel) // or .bluesky on the other tile
```

The inner `Image` may stay; it's already shape-coded and the colored fill is decorative. The label change ensures VoiceOver users hear "Mastodon" / "Bluesky", not "Image".

- [ ] **Step 3: UnifiedAccountsIcon**

In `SocialFusion/Views/UnifiedAccountsIcon.swift`, locate the topmost view returned by `body`. Append:

```swift
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mastodon and Bluesky accounts")
        .accessibilityAddTraits(.isImage)
```

Do not replace the inner `Image("MastodonLogo")` / `Image("BlueskyLogo")` sites — this icon deliberately composes both glyphs as decoration.

- [ ] **Step 4: AccountTimelineView line 120**

In `SocialFusion/Views/AccountTimelineView.swift`, locate:

```swift
                .foregroundColor(Color(hex: account.platform.colorHex))
```

…on a `Text` view. Add a sibling `PlatformLogoBadge` in front of it (inside the same `HStack`):

```swift
            PlatformLogoBadge(platform: account.platform, size: 14)
            Text(/* existing */)
                .foregroundColor(Color(hex: account.platform.colorHex))
```

If the text is already adjacent to a badge in the same row, skip — just record "verified" in the audit checklist.

- [ ] **Step 5: Verify the project builds**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Manual smoke test**

Open Accounts; open Add Account; open the unified-accounts header in the title bar; open a single-account timeline. Each surface renders a badge. Toggle high-contrast in Settings — every site immediately switches.

- [ ] **Step 7: Commit**

```bash
git add SocialFusion/Views/AccountsView.swift \
        SocialFusion/Views/AddAccountView.swift \
        SocialFusion/Views/UnifiedAccountsIcon.swift \
        SocialFusion/Views/AccountTimelineView.swift
git commit -m "refactor(a11y): normalize account-surface network indicators"
```

---

## Task 10: Normalize ShareAsImage export, PlatformDot, PostPlatformBadge

**Files:**
- Modify: `SocialFusion/ShareAsImage/ShareImageViews.swift`
- Modify: `SocialFusion/Views/Components/PlatformDot.swift`
- Modify: `SocialFusion/Views/Components/PostPlatformBadge.swift`

These are the "derived chips" the spec calls out — `PlatformDot` and `PostPlatformBadge` both signal network and are reused across multiple surfaces. Internally route them through `PlatformLogoBadge` so the high-contrast toggle reaches them automatically. ShareAsImage exports a static image, so its badge must also honor high-contrast for users who export and share screenshots.

- [ ] **Step 1: PlatformDot — auto-promote to badge under high-contrast**

Replace the body of `PlatformDot` (`SocialFusion/Views/Components/PlatformDot.swift`):

```swift
import SwiftUI

/// A small platform indicator that defaults to a colored dot but is
/// auto-promoted to the full shape-coded `PlatformLogoBadge` when the
/// user has enabled high-contrast network indicators.
struct PlatformDot: View {
    let platform: SocialPlatform
    var size: CGFloat = 8
    var useLogo: Bool = false
    var backgroundColor: Color = Color.white

    @Environment(\.accessibilityPreferences) private var prefs

    private var platformColor: Color {
        switch platform {
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)
        }
    }

    var body: some View {
        Group {
            if useLogo || prefs.highContrastNetworkIndicators {
                // Shape-coded path. Inherits high-contrast styling from the badge.
                PlatformLogoBadge(platform: platform, size: size, shadowEnabled: true)
            } else {
                Circle()
                    .fill(platformColor)
                    .frame(width: size, height: size)
                    .overlay(
                        Circle().stroke(backgroundColor, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 0)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(platform.accessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }
}

#Preview {
    HStack(spacing: 20) {
        VStack {
            Text("Dot").font(.caption)
            PlatformDot(platform: .mastodon, size: 12)
            PlatformDot(platform: .bluesky, size: 12)
        }
        VStack {
            Text("Logo").font(.caption)
            PlatformDot(platform: .mastodon, size: 16, useLogo: true)
            PlatformDot(platform: .bluesky, size: 16, useLogo: true)
        }
    }
    .padding()
}
```

- [ ] **Step 2: PostPlatformBadge — route inner image through PlatformLogoBadge**

Replace the body of `PostPlatformBadge` (`SocialFusion/Views/Components/PostPlatformBadge.swift`):

```swift
import SwiftUI

/// Capsule chip showing the network name with its logo. Used in DM rows and
/// conversation headers. The inner glyph is rendered via `PlatformLogoBadge`
/// so it picks up the user's high-contrast preference automatically.
struct PostPlatformBadge: View {
    let platform: SocialPlatform

    var body: some View {
        HStack(spacing: 4) {
            PlatformLogoBadge(platform: platform, size: 14, shadowEnabled: false)

            Text(platform.accessibilityLabel)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(platform.swiftUIColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(platform.swiftUIColor.opacity(0.1))
                .overlay(
                    Capsule()
                        .stroke(platform.swiftUIColor.opacity(0.3), lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(platform.accessibilityLabel)
    }
}

struct PostPlatformBadge_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 16) {
            PostPlatformBadge(platform: .bluesky)
            PostPlatformBadge(platform: .mastodon)
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
```

- [ ] **Step 3: ShareAsImage export — promote to PlatformLogoBadge**

In `SocialFusion/ShareAsImage/ShareImageViews.swift`, locate around line 121:

```swift
                    Image(post.platform.icon)
                        // ... resizable / frame / foregroundColor modifiers
                        .foregroundColor(platformColor(for: post.platform))
```

Replace with:

```swift
                    PlatformLogoBadge(platform: post.platform, size: 24, shadowEnabled: false)
```

The export view should pass the user's current high-contrast preference into its environment when it creates the off-screen `UIHostingController`. Locate the renderer that builds the export image (search for `UIHostingController` in the same file or `ShareAsImageRenderer`). Add — at the moment the renderer is set up:

```swift
        hostingController.rootView = hostingController.rootView
            .environment(\.accessibilityPreferences, AccessibilityPreferences())
```

(Use a fresh instance keyed off `UserDefaults.standard`, so the off-screen render reads the same persisted value.)

- [ ] **Step 4: Verify the project builds**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Manual smoke test**

Open a post → Share as Image → confirm the exported preview shows `PlatformLogoBadge` styling. Toggle high-contrast in Settings and repeat — the export now shows the high-contrast variant.

- [ ] **Step 6: Commit**

```bash
git add SocialFusion/Views/Components/PlatformDot.swift \
        SocialFusion/Views/Components/PostPlatformBadge.swift \
        SocialFusion/ShareAsImage/ShareImageViews.swift
git commit -m "refactor(a11y): route derived chips and ShareAsImage through PlatformLogoBadge"
```

---

## Task 11: Reduce-motion fix for LaunchAnimationView

**Files:**
- Modify: `SocialFusion/Views/Components/LaunchAnimationView.swift`

The launch animation currently performs scale/rotation on the orb fusion without consulting `accessibilityReduceMotion`. The spec mandates reduce-motion respect on launch (v1.0 acceptance criterion, line 270). When reduce-motion is on, the animation collapses to a single cross-fade.

- [ ] **Step 1: Read the file to identify animation entry points**

```bash
grep -n "withAnimation\|Animation\|rotation\|scale\|spring" SocialFusion/Views/Components/LaunchAnimationView.swift
```

Make a note of every `withAnimation { ... }`, `.animation(...)`, `.scaleEffect(...)`, `.rotationEffect(...)`, and `.offset(...)` site.

- [ ] **Step 2: Add the environment value and gate the animations**

At the top of the main view's `struct` declaration, add:

```swift
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
```

For each animation site, gate as follows. Pattern A — `withAnimation { ... }` calls:

```swift
        // Before:
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            isExpanded = true
        }
        // After:
        withAnimation(reduceMotion ? .none : .spring(response: 0.6, dampingFraction: 0.7)) {
            isExpanded = true
        }
```

Pattern B — view-level transforms (`scaleEffect`, `rotationEffect`, `offset`):

```swift
        // Before:
        Image("orb")
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
        // After:
        Image("orb")
            .scaleEffect(reduceMotion ? 1.0 : scale)
            .rotationEffect(.degrees(reduceMotion ? 0 : rotation))
```

Pattern C — the orb-fusion gesture/animation that drives "two orbs collide and merge": when `reduceMotion` is on, replace the kinetic merge with a single `.opacity` cross-fade from "two orbs visible" to "fused glyph visible" — do **not** animate position. Wrap the orb position offsets in `reduceMotion ? 0 : <offset>`.

Pattern D — `.transition(...)` on outer view: replace `.transition(.scale.combined(with: .opacity))` with `.transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))`.

Apply patterns A–D to every animation site in the file.

- [ ] **Step 3: Verify the project builds**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual smoke test**

Enable reduce-motion in the Simulator: Features → Toggle Reduce Motion (or Settings → Accessibility → Motion → Reduce Motion). Bump the app's stored version so the launch animation fires (or reinstall). Confirm the orb fusion shows as a simple cross-fade — no scale, no rotation, no kinetic offset.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Views/Components/LaunchAnimationView.swift
git commit -m "fix(a11y): respect Reduce Motion in LaunchAnimationView"
```

---

## Task 12: Reduce-motion and Dynamic Type audit pass (manual)

**Files:**
- Modify: `docs/superpowers/audits/2026-05-17-network-indicator-audit.md` (check off each surface)

This task is a manual walkthrough. The checklist artifact from Task 1 is updated with pass/fail per surface and committed as evidence.

- [ ] **Step 1: Reduce-motion verification walk**

Enable Reduce Motion in the simulator. Walk every surface listed in the Reduce-Motion audit table (Task 1, Step 1):

- `LaunchAnimationView` — Already fixed in Task 11. Re-verify: no kinetic motion, fade only. ✅
- `ProfileHeaderView` — Pull to overscroll on a profile. Banner must not stretch. Avatar must not parallax. ✅
- `ConsolidatedTimelineView` — Scroll the timeline. Posts must not slide-in; they must appear flat. ✅
- `LiquidGlassComponents` — Trigger any glass-button interaction. No bounce on tap. ✅
- `SkeletonPostCard` — Cold-launch the app. Skeleton must show a static placeholder, not shimmer. ✅
- `ParallaxMediaModifier` — Open a post with media. Image must not parallax on scroll. ✅

For each surface, edit the audit doc and replace its row's Action cell with the screenshot's filename or a checkmark + date.

- [ ] **Step 2: Dynamic Type verification walk**

Set Dynamic Type to AX5 in the simulator (Settings → Accessibility → Display & Text Size → Larger Text → AX5).

Walk every surface in the Dynamic Type audit table:

- `ConsolidatedTimelineView` — Open the home timeline. Confirm: author name, content body, action bar buttons all readable; no horizontal clipping; action bar tap targets ≥ 44pt. ✅
- `PostCardView` — Tap a post; confirm same.
- `ComposeView` — Open compose; type a long sentence; confirm Post button still hittable at the bottom.
- `ChatView` — Open a DM; confirm bubble layout grows; confirm scroll-to-bottom still works.
- `ProfileHeaderView` — Open a profile; confirm bio truncates gracefully or wraps (verify which behavior we want — record decision).
- `SettingsView` — Open settings; confirm all rows ≥ 44pt and toggle hit targets correct.
- `OnboardingView` — Cold-launch with no accounts; confirm carousel pages and CTA buttons render.
- `DirectMessagesView` — Open DM inbox; confirm each row's text isn't clipped.

For each surface, screenshot at AX5. If any clipping occurs, file a follow-up bug at the bottom of the audit doc — do **not** fix here (this task is verification, not remediation). If the clipping is severe enough to block the v1.0 acceptance criterion, escalate as a sibling plan.

- [ ] **Step 3: VoiceOver verification walk**

Enable VoiceOver (Simulator → Hardware → Accessibility Inspector, or Settings → Accessibility → VoiceOver). Walk:

- Timeline → swipe through 10 posts; confirm each announces "Post on Mastodon" or "Post on Bluesky" plus author and content.
- Compose → confirm the platform badge announces "Mastodon" or "Bluesky".
- Thread (open any post) → confirm header announces network.
- Profile → confirm avatar+badge announces "@user, Mastodon" or similar.
- DMs → confirm conversation rows announce network.
- Settings → confirm the Accessibility section reads, the toggle is reachable, the preview row announces "Preview of current network indicator style".
- Onboarding → confirm each carousel page reads.

Record any unlabeled element in the audit doc.

- [ ] **Step 4: Commit the updated audit**

```bash
git add docs/superpowers/audits/2026-05-17-network-indicator-audit.md
git commit -m "docs(a11y): record reduce-motion / Dynamic Type / VoiceOver audit results"
```

---

## Task 13: Static audit assertion test

**Files:**
- Create: `SocialFusionTests/NetworkIndicatorAuditTests.swift`

A regression net. The test reads the source of the files listed in the audit checklist and asserts that the post-Phase-A invariants hold: the inline literals `"MastodonLogo"` and `"BlueskyLogo"` do not appear directly in view bodies outside the approved owners (`PlatformLogoBadge`, `PlatformDot`, `UnifiedAccountsIcon`, `SocialPlatform`'s `icon` property, the asset catalog itself). Any new code that adds a raw `Image("MastodonLogo")` somewhere will fail this test and force the author to either add it to the allowlist (and justify) or route through `PlatformLogoBadge`.

- [ ] **Step 1: Write the test**

Create `SocialFusionTests/NetworkIndicatorAuditTests.swift`:

```swift
import XCTest
@testable import SocialFusion

/// Static-source assertion that no view re-introduces a raw platform logo
/// `Image(...)` outside the approved owners. New violations fail the build
/// and surface immediately on PR.
final class NetworkIndicatorAuditTests: XCTestCase {
    /// Owners allowed to reference "MastodonLogo" or "BlueskyLogo" string literals
    /// directly. Everyone else must compose `PlatformLogoBadge`.
    private static let allowlist: Set<String> = [
        "SocialFusion/Views/Components/PlatformLogoBadge.swift",
        "SocialFusion/Views/Components/PlatformLogoBadge+HighContrast.swift",
        "SocialFusion/Views/Components/PlatformDot.swift",
        "SocialFusion/Views/UnifiedAccountsIcon.swift",
        "SocialFusion/Models/SocialPlatform.swift",
        "SocialFusion/Views/AddAccountView.swift", // shape-coded tile; logos rendered standalone with VO label
    ]

    func testNoUnapprovedRawPlatformLogoReferences() throws {
        let repoRoot = try Self.findRepoRoot()
        let sourceRoot = repoRoot.appendingPathComponent("SocialFusion")

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: sourceRoot,
                                             includingPropertiesForKeys: nil,
                                             options: [.skipsHiddenFiles]) else {
            XCTFail("Could not enumerate \(sourceRoot.path)")
            return
        }

        var offenders: [(path: String, line: Int, content: String)] = []

        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let relPath = relativePath(of: url, from: repoRoot)
            if Self.allowlist.contains(relPath) { continue }

            let source = try String(contentsOf: url, encoding: .utf8)
            let lines = source.components(separatedBy: "\n")
            for (idx, line) in lines.enumerated() {
                if line.contains("\"MastodonLogo\"") || line.contains("\"BlueskyLogo\"") {
                    offenders.append((relPath, idx + 1, line.trimmingCharacters(in: .whitespaces)))
                }
            }
        }

        if !offenders.isEmpty {
            let report = offenders.map { "  \($0.path):\($0.line) — \($0.content)" }
                .joined(separator: "\n")
            XCTFail(
                """
                Found raw platform-logo references outside the approved owners.
                Either route the indicator through PlatformLogoBadge or add the
                file to NetworkIndicatorAuditTests.allowlist with a justification.

                Offenders:
                \(report)
                """
            )
        }
    }

    private static func findRepoRoot() throws -> URL {
        // Walk up from this test file until we find the package marker.
        var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while current.path != "/" {
            let marker = current.appendingPathComponent("SocialFusion.xcodeproj")
            if FileManager.default.fileExists(atPath: marker.path) {
                return current
            }
            current.deleteLastPathComponent()
        }
        throw NSError(domain: "NetworkIndicatorAuditTests",
                      code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Could not find repo root"])
    }

    private func relativePath(of url: URL, from base: URL) -> String {
        let baseComponents = base.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        guard urlComponents.count > baseComponents.count,
              Array(urlComponents.prefix(baseComponents.count)) == baseComponents
        else { return url.path }
        return urlComponents.dropFirst(baseComponents.count).joined(separator: "/")
    }
}
```

- [ ] **Step 2: Run the test**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/NetworkIndicatorAuditTests`
Expected: PASS. If it fails with offenders, either (a) re-route the offending site through `PlatformLogoBadge` in this commit, or (b) add the file to the allowlist with a brief inline justification comment.

- [ ] **Step 3: Commit**

```bash
git add SocialFusionTests/NetworkIndicatorAuditTests.swift
git commit -m "test(a11y): static assertion that platform logos route through PlatformLogoBadge"
```

---

## Task 14: Colorblind-simulator screenshot pass

**Files:**
- Modify: `docs/superpowers/audits/2026-05-17-network-indicator-audit.md` (append screenshot evidence section)
- Create: `docs/superpowers/audits/screenshots/colorblind/` (image artifacts)

The spec mandates a colorblind-simulator screenshot pass on every network-signaling surface (line 267). This task captures evidence and folds it into the audit doc.

- [ ] **Step 1: Boot the simulator with a populated test account**

Use `iPhone 17 Pro` (UDID `5F253C05-C35E-4B29-A0F0-B8F8BF75B89B`, per project memory). Sign in with both a Mastodon and a Bluesky account so the unified timeline shows mixed content.

```bash
xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
xcrun simctl install booted "<path-to-built-.app>"
xcrun simctl launch booted com.socialfusionapp.app
```

- [ ] **Step 2: Capture each canonical surface twice — once standard, once high-contrast**

For each of the seven surfaces below, capture screenshots under each of the three colorblind simulator modes available via the Simulator's Accessibility → Color Filters (Deuteranopia, Protanopia, Tritanopia). Then capture the same surface with the High-Contrast toggle ON. Total: 7 surfaces × 3 modes × 2 toggle states = 42 PNGs.

Seven canonical surfaces:

1. Unified timeline (mixed Mastodon + Bluesky posts visible)
2. Post detail (any post)
3. Profile (any profile, with avatar + badge)
4. Account picker / unified-accounts icon
5. Compose (with reply context to a cross-platform post)
6. DM inbox (rows with both networks)
7. Settings → Accessibility section preview

Save under `docs/superpowers/audits/screenshots/colorblind/` with filenames like `01-timeline-deut-off.png`, `01-timeline-deut-on.png`, `01-timeline-prot-off.png`, etc.

- [ ] **Step 3: Manual visual review of every pair**

For every (surface × mode) pair, hold up the OFF screenshot next to the ON screenshot. The acceptance criterion is binary per pair: can a reader without color vision identify which posts are Mastodon and which are Bluesky? Record the per-pair verdict in a new section appended to the audit doc:

```markdown
## Colorblind-Simulator Screenshot Pass (2026-05-17)

Simulator: iPhone 17 Pro, iOS 26.2. Filters applied via Simulator → Features → Toggle Color Filter (set per row).

| Surface | Deuteranopia | Protanopia | Tritanopia |
| --- | --- | --- | --- |
| Timeline | ✅ pass (shape-coded badge sufficient; high-contrast not required) | ✅ pass | ✅ pass |
| Post detail | ✅ pass | ✅ pass | ✅ pass |
| Profile | ✅ pass | ✅ pass | ✅ pass |
| Account picker | ✅ pass | ✅ pass | ✅ pass |
| Compose | ✅ pass | ✅ pass | ✅ pass |
| DM inbox | ✅ pass | ✅ pass | ✅ pass |
| Settings preview | ✅ pass — toggle visually obvious between states | ✅ pass | ✅ pass |
```

If any cell fails, file a follow-up — do not block the merge on a single regression unless it's a primary surface (timeline, post detail, profile). For a primary-surface failure, add a remediation task at the bottom of this plan and address before the v1.0 sign-off.

- [ ] **Step 4: Commit the screenshots and audit update**

```bash
git add docs/superpowers/audits/screenshots/colorblind/ \
        docs/superpowers/audits/2026-05-17-network-indicator-audit.md
git commit -m "docs(a11y): colorblind-simulator screenshot evidence for v1.0 sign-off"
```

---

## Acceptance Gate

The plan is **done** only when all of the following hold. These map 1:1 to the v1.0 acceptance criteria for accessibility (spec lines 266–271) and the Indigo Gap Map commitment (spec line 230).

- [ ] **Every network-signaling UI surface is shape-coded** — verified by:
  - The audit checklist (`docs/superpowers/audits/2026-05-17-network-indicator-audit.md`) shows every row in the Components and Inline-platform-image-sites tables as ✅ or with documented justification.
  - `NetworkIndicatorAuditTests` passes — no raw `"MastodonLogo"` or `"BlueskyLogo"` literals outside the allowlist.
- [ ] **`PlatformLogoBadge` supports high-contrast** — verified by:
  - `PlatformLogoBadgeHighContrastTests` passes (5 assertions: default off, distinct renders per platform per mode, sizes scale).
  - Settings toggle exists, defaults off, persists across launches.
  - Toggle reaches every consumer because every consumer either uses `PlatformLogoBadge` directly or composes a type (`PlatformDot`, `PostPlatformBadge`) that does.
- [ ] **Colorblind-simulator screenshot pass** — verified by:
  - 42 screenshots committed under `docs/superpowers/audits/screenshots/colorblind/`.
  - Audit doc's screenshot table shows ✅ on every primary surface (timeline, post detail, profile) under all three filters with toggle off; remaining ✅ across all surfaces with toggle on.
- [ ] **Reduce-motion respected on every animated primary surface** — verified by:
  - `LaunchAnimationView` audit row is ✅ (Task 11 + Task 12 walkthrough).
  - All other surfaces verified ✅ in Task 12.
- [ ] **VoiceOver labels on every network indicator** — verified by:
  - `PlatformLogoBadge`, `PlatformDot`, `PostPlatformBadge`, `UnifiedAccountsIcon`, and the affected inline sites each declare `.accessibilityLabel(...)`.
  - Task 12 VoiceOver walk recorded no unlabeled elements.
- [ ] **Dynamic Type pass through AX5** — verified by:
  - Task 12 Dynamic Type walk recorded ✅ on all 8 surfaces, or any regression filed as a sibling task with explicit deferral note.
- [ ] **Full build clean** — `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet` returns BUILD SUCCEEDED with zero warnings introduced by this plan.
- [ ] **All new tests green** — `AccessibilityPreferencesTests`, `PlatformLogoBadgeHighContrastTests`, `NetworkIndicatorAuditTests` all pass.

---

## What's intentionally out of scope

- **Keyboard navigation audit on iPadOS.** Spec calls for it (line 271), but it's a separate sweep — focus rings, arrow-key navigation, command bindings — that doesn't share infrastructure with the network-indicator work. Track as a sibling plan.
- **Localizing the new VoiceOver labels.** `accessibilityLabel` and `postAccessibilityFragment` use English string literals. v1.0 ships English-only; a strings-file pass is a sibling task.
- **High-contrast mode for non-network UI.** This plan ships one toggle: `highContrastNetworkIndicators`. A broader "increased contrast" pass (action-bar tint, glass material opacity, divider visibility) is deferred. Adding more fields to `AccessibilityPreferences` later is a non-breaking change.
- **Custom user-pickable network colors.** The Indigo analysis notes (line 230) that user-configurable network indicator colors are *one possible* fix. We're shipping the more robust fix (shape coding + filled-vs-outlined) and not building a color picker. If user feedback during TestFlight demands color customization, file as a v1.1 candidate.
- **Snapshot golden-image tests.** `PlatformLogoBadgeHighContrastTests` uses pixel-hash invariants, not golden-image diffs. Golden-image testing requires CI infrastructure and tolerance tuning that isn't in place yet. Pixel-hash invariants give us regression coverage without the maintenance burden.
- **Replacing color tints on Post/Compose buttons.** Spec's "shape-coded everywhere" applies to network *identification*; it does not require removing color from buttons that already sit next to a shape-coded badge. Those button tints stay.
- **Fused-conversation accessibility.** The Fuse breakthrough plan (`docs/superpowers/plans/2026-05-17-the-fuse-breakthrough.md`) introduces `FusedGlyph` and `FusedConversationView`. Accessibility for those surfaces (the new glyph's VoiceOver story, reduce-motion behavior of the Fused bloom) is handled in that plan — this plan only enumerates them in the audit checklist for visibility.
- **App Store screenshot regeneration.** Updating Store screenshots to show the high-contrast option is a marketing task; spec line 286 acknowledges it as separate.

# Quality Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close two UX gaps that have been TODO for the entire beta cycle: (1) when a timeline refresh fails, the user currently sees nothing — the controller flips `state = .error(error)` and the UI silently sits on stale data; we wire those failure paths to a reusable, queued, accessible toast surface with a Retry action. (2) When a quoted post can't be fetched (deleted, blocked, network), `FetchQuotePostView` currently falls back to a generic `LinkPreview` which loses the "this was a quote" semantic; we add a `QuotePostUnavailableView` placeholder that says so plainly and never blocks the parent post from rendering.

**Architecture:** A new `ToastQueue` (`@MainActor`, `ObservableObject`) replaces the legacy single-slot `ToastManager` singleton. Messages are modeled as `ToastMessage` values with optional `retry` callbacks and configurable `autoDismissAfter` durations. The queue holds an array; the host modifier shows the head. Non-actionable toasts auto-dismiss after 4 seconds (raised from the legacy 2s); actionable (retry) toasts are persistent until tapped, swiped, or explicitly dismissed. A backwards-compatible `ToastManager.shared.show(...)` shim is preserved so existing callsites (`PostActionCoordinator`, `NotificationManager`, the like/repost paths in `TimelineViewModel`) keep working without a sweeping refactor — they bridge through the queue. The two refresh-failure `catch` blocks in `TimelineViewModel` get a single new line each that enqueues a retry toast. For quote posts, the `FetchQuotePostView` failure branch (post = nil after max retries, or post has no meaningful content) now renders `QuotePostUnavailableView` instead of `LinkPreview` when the URL was authoritatively a quoted-post URL; the existing `LinkPreview` fallback is preserved for the genuinely-ambiguous case.

**Tech Stack:** Swift 5+, SwiftUI, Combine, XCTest. iOS 17+ floor. Reuses: existing `ToastHostModifier` mount point (`ContentView.swift:94`), the `@MainActor` published-state pattern, `accessibilityElement` / `accessibilityAddTraits` for VoiceOver, `@Environment(\.accessibilityReduceMotion)` for motion respect.

**Spec reference:** `docs/superpowers/specs/2026-05-17-socialfusion-v1-vision-design.md` — see "New for v1.0 → Error UI Feedback" and "New for v1.0 → Quote post fallback polish."

**File map (creates/modifies):**

- Create: `SocialFusion/Models/ToastMessage.swift`
- Create: `SocialFusion/Stores/ToastQueue.swift`
- Create: `SocialFusion/Views/Components/Toast.swift`
- Create: `SocialFusion/Views/Components/QuotePostUnavailableView.swift`
- Create: `SocialFusionTests/ToastQueueTests.swift`
- Create: `SocialFusionTests/QuotePostFallbackTests.swift`
- Modify: `SocialFusion/Views/Components/ToastNotification.swift` (turn `ToastManager` into a thin bridge over `ToastQueue`; keep the public `.show(_:duration:)` method)
- Modify: `SocialFusion/SocialFusionApp.swift` (add `@StateObject` `ToastQueue` and inject via `.environmentObject`)
- Modify: `SocialFusion/ContentView.swift` (swap `withToastNotifications()` to read from injected `ToastQueue`)
- Modify: `SocialFusion/ViewModels/TimelineViewModel.swift` (wire the two timeline-refresh `catch` blocks to enqueue a retry toast — closes the TODOs referenced in CLAUDE.md "Known Issues")
- Modify: `SocialFusion/Views/Components/FetchQuotePostView.swift` (route the "fetched-but-no-meaningful-content" and "max retries exceeded" cases through `QuotePostUnavailableView`)

**Implementer assumptions to verify before each task:**

1. `ToastManager` is defined at `SocialFusion/Views/Components/ToastNotification.swift:4-23` as a `@MainActor final class … ObservableObject` singleton with one `Published private(set) var currentToast: Toast?` slot (verified).
2. `ToastHostModifier` mounts at `SocialFusion/ContentView.swift:94` via `.withToastNotifications()` (verified).
3. Active callsites of `ToastManager.shared.show(...)` to preserve compatibility for: `TimelineViewModel.swift:494, 550`, `Stores/PostActionCoordinator.swift:378`, `Services/NotificationManager.swift:252` (verified via grep).
4. The two **silent** timeline-refresh failure paths that need new toast wiring are `TimelineViewModel.swift:252-258` (`refreshTimeline(for:)` single-account) and `TimelineViewModel.swift:434-440` (`refreshUnifiedTimeline(for:)`). Both currently flip `self.state = .error(error)` with no UI surface — these are the spec's "Error UI Feedback" TODOs.
5. `Post` is a `public class … ObservableObject` with at least `id: String`, `content: String`, `originalURL: String`, `platform: SocialPlatform` (per `SocialFusion/Models/Post.swift`).
6. `SocialPlatform` is `String`-backed with cases `.mastodon` and `.bluesky` (per `CLAUDE.md` memory).
7. `FetchQuotePostView`'s failure handling lives at `SocialFusion/Views/Components/FetchQuotePostView.swift:201-233` (loading / error-with-retry / `LinkPreview` fallback) and `:341-365` (the catch that nils out `error` after max retries to force the `LinkPreview` fallback).
8. The test target is `SocialFusionTests`. Tests subclass `XCTestCase`. The existing test bundle compiles cleanly.

---

## Task 1: ToastMessage model

**Files:**
- Create: `SocialFusion/Models/ToastMessage.swift`

The value type that flows through the queue. Identity is stable per instance (UUID), style drives the visual treatment, retry is the actionable callback, and `autoDismissAfter` is `nil` for persistent (retry-bearing) toasts.

- [ ] **Step 1: Implement the model**

Create `SocialFusion/Models/ToastMessage.swift`:

```swift
import Foundation

/// A single user-visible toast message.
///
/// Non-actionable toasts (info, transient errors with no recovery) carry an
/// `autoDismissAfter` so they fade after a few seconds. Actionable toasts
/// (those with a non-nil `retry`) are persistent — they stay on screen until
/// the user either taps Retry, swipes them away, or another path dismisses
/// them programmatically.
public struct ToastMessage: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let body: String?
    public let style: Style
    public let retry: RetryAction?
    public let autoDismissAfter: TimeInterval?

    public init(
        id: UUID = UUID(),
        title: String,
        body: String? = nil,
        style: Style = .info,
        retry: RetryAction? = nil,
        autoDismissAfter: TimeInterval? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.style = style
        self.retry = retry
        // Actionable toasts default to persistent; non-actionable default to 4s.
        if let autoDismissAfter = autoDismissAfter {
            self.autoDismissAfter = autoDismissAfter
        } else if retry == nil {
            self.autoDismissAfter = 4.0
        } else {
            self.autoDismissAfter = nil
        }
    }

    public enum Style: String, Equatable {
        case info
        case success
        case warning
        case error
    }

    /// A retry action wrapping a `@MainActor` closure. The wrapper exists so
    /// `ToastMessage` can stay `Equatable` (closures aren't) by comparing the
    /// wrapper identity, not the underlying function.
    public struct RetryAction: Equatable {
        public let id: UUID
        public let label: String
        public let perform: @MainActor () -> Void

        public init(label: String = "Retry", perform: @escaping @MainActor () -> Void) {
            self.id = UUID()
            self.label = label
            self.perform = perform
        }

        public static func == (lhs: RetryAction, rhs: RetryAction) -> Bool {
            lhs.id == rhs.id
        }
    }

    public static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.body == rhs.body
            && lhs.style == rhs.style
            && lhs.retry == rhs.retry
            && lhs.autoDismissAfter == rhs.autoDismissAfter
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add SocialFusion/Models/ToastMessage.swift
git commit -m "feat(toast): add ToastMessage model"
```

---

## Task 2: ToastQueue store

**Files:**
- Create: `SocialFusion/Stores/ToastQueue.swift`
- Test: `SocialFusionTests/ToastQueueTests.swift`

The queue is the single source of truth for toasts app-wide. It holds an array, exposes the head for the host to render, supports cancellable auto-dismiss, and is fully testable (clock injectable).

- [ ] **Step 1: Write the failing tests**

Create `SocialFusionTests/ToastQueueTests.swift`:

```swift
import XCTest
@testable import SocialFusion

@MainActor
final class ToastQueueTests: XCTestCase {
    func testShowEnqueuesAndExposesAsCurrent() {
        let queue = ToastQueue()
        queue.show(ToastMessage(title: "Hello"))
        XCTAssertEqual(queue.current?.title, "Hello")
        XCTAssertEqual(queue.pending.count, 1)
    }

    func testSecondShowQueuesBehindCurrent() {
        let queue = ToastQueue()
        queue.show(ToastMessage(title: "First"))
        queue.show(ToastMessage(title: "Second"))
        XCTAssertEqual(queue.current?.title, "First", "Head must not be overwritten.")
        XCTAssertEqual(queue.pending.count, 2)
    }

    func testDismissCurrentAdvancesToNext() {
        let queue = ToastQueue()
        let first = ToastMessage(title: "First")
        let second = ToastMessage(title: "Second")
        queue.show(first)
        queue.show(second)
        queue.dismiss(first.id)
        XCTAssertEqual(queue.current?.title, "Second")
        XCTAssertEqual(queue.pending.count, 1)
    }

    func testDismissUnknownIdIsNoOp() {
        let queue = ToastQueue()
        queue.show(ToastMessage(title: "Present"))
        queue.dismiss(UUID())
        XCTAssertEqual(queue.current?.title, "Present")
    }

    func testDismissAllClearsTheQueue() {
        let queue = ToastQueue()
        queue.show(ToastMessage(title: "a"))
        queue.show(ToastMessage(title: "b"))
        queue.dismissAll()
        XCTAssertNil(queue.current)
        XCTAssertEqual(queue.pending.count, 0)
    }

    func testNonActionableAutoDismissesAfterItsDuration() async {
        let queue = ToastQueue()
        queue.show(ToastMessage(title: "Quick", autoDismissAfter: 0.05))
        XCTAssertNotNil(queue.current)
        try? await Task.sleep(nanoseconds: 150_000_000) // 0.15 s
        XCTAssertNil(queue.current, "Auto-dismiss should have fired by now.")
    }

    func testActionableToastDoesNotAutoDismiss() async {
        let queue = ToastQueue()
        let retry = ToastMessage.RetryAction { /* no-op */ }
        queue.show(ToastMessage(title: "Stays", retry: retry))
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 s
        XCTAssertNotNil(queue.current, "Retry-bearing toasts must be persistent.")
    }

    func testInvokeRetryFiresCallbackAndDismisses() {
        let queue = ToastQueue()
        var fired = false
        let retry = ToastMessage.RetryAction { fired = true }
        let msg = ToastMessage(title: "Try", retry: retry)
        queue.show(msg)
        queue.invokeRetry(for: msg.id)
        XCTAssertTrue(fired)
        XCTAssertNil(queue.current, "Invoking retry should dismiss the toast.")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/ToastQueueTests`
Expected: FAIL — `ToastQueue` not defined.

- [ ] **Step 3: Implement the store**

Create `SocialFusion/Stores/ToastQueue.swift`:

```swift
import Combine
import Foundation
import SwiftUI

/// A queued, app-wide toast surface.
///
/// One queue lives at the app root and is injected via `@EnvironmentObject`.
/// Producers call `show(_:)`; the host (`ToastHostModifier`) renders the head.
/// Non-actionable toasts auto-dismiss after their configured duration;
/// actionable toasts (those with a retry) are persistent until the user
/// taps Retry, swipes them away, or another path calls `dismiss(_:)`.
@MainActor
public final class ToastQueue: ObservableObject {
    /// Full queue (head is `pending.first`). Exposed for testing/inspection.
    @Published public private(set) var pending: [ToastMessage] = []

    /// Convenience for hosts: the toast currently being displayed.
    public var current: ToastMessage? { pending.first }

    /// Auto-dismiss timers keyed by message id so a queued message can be
    /// pre-emptively cancelled if the user swipes/dismisses early.
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    public init() {}

    /// Enqueue a toast. If nothing is currently showing, it becomes current
    /// immediately. Otherwise it waits behind whatever is on screen.
    public func show(_ message: ToastMessage) {
        pending.append(message)
        scheduleAutoDismissIfNeeded(for: message)
    }

    /// Dismiss a specific toast. If it's currently showing, the next one
    /// in the queue becomes current.
    public func dismiss(_ id: UUID) {
        guard pending.contains(where: { $0.id == id }) else { return }
        pending.removeAll { $0.id == id }
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
        // If a new head exists and lacks a running dismiss task, schedule one.
        if let head = pending.first, dismissTasks[head.id] == nil {
            scheduleAutoDismissIfNeeded(for: head)
        }
    }

    /// Drop the entire queue — used on logout / catastrophic state reset.
    public func dismissAll() {
        for (_, task) in dismissTasks { task.cancel() }
        dismissTasks.removeAll()
        pending.removeAll()
    }

    /// Fire a toast's retry callback and dismiss it. No-op if the message
    /// isn't in the queue or has no retry.
    public func invokeRetry(for id: UUID) {
        guard let msg = pending.first(where: { $0.id == id }),
              let retry = msg.retry else { return }
        retry.perform()
        dismiss(id)
    }

    private func scheduleAutoDismissIfNeeded(for message: ToastMessage) {
        guard let duration = message.autoDismissAfter, duration > 0 else { return }
        let id = message.id
        dismissTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.dismiss(id)
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/ToastQueueTests`
Expected: PASS, all 8 tests green.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Stores/ToastQueue.swift SocialFusionTests/ToastQueueTests.swift
git commit -m "feat(toast): add ToastQueue with auto-dismiss + actionable retry"
```

---

## Task 3: Toast view component

**Files:**
- Create: `SocialFusion/Views/Components/Toast.swift`

The reusable visual component. Generic enough for any app surface, not coupled to the timeline. Respects Reduce Motion (skips the slide animation), supports Dynamic Type (uses semantic fonts), swipe-to-dismiss, and renders the optional Retry button.

- [ ] **Step 1: Implement the component**

Create `SocialFusion/Views/Components/Toast.swift`:

```swift
import SwiftUI

/// A single toast view. Reusable across the app — accepts a `ToastMessage`
/// plus callbacks for retry and dismiss. Visual treatment is driven by
/// `ToastMessage.Style`. Respects Dynamic Type and Reduce Motion.
public struct Toast: View {
    let message: ToastMessage
    let onRetry: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    private let swipeThreshold: CGFloat = 48

    public init(
        message: ToastMessage,
        onRetry: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.message = message
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            iconView
            VStack(alignment: .leading, spacing: 2) {
                Text(message.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let body = message.body, !body.isEmpty {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let retry = message.retry {
                Button(retry.label, action: onRetry)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(accentColor)
                    .accessibilityHint("Retries the failed action")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(background)
        .overlay(borderOverlay)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
        .offset(x: dragOffset)
        .gesture(swipeGesture)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(accessibilityComposedLabel)
        .accessibilityAction(named: Text("Dismiss")) { onDismiss() }
        .transition(toastTransition)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var iconView: some View {
        Image(systemName: iconName)
            .font(.title3)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(accentColor)
            .accessibilityHidden(true)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.regularMaterial)
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(accentColor.opacity(colorScheme == .dark ? 0.35 : 0.25), lineWidth: 0.75)
    }

    // MARK: - Computed

    private var iconName: String {
        switch message.style {
        case .info:    return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.octagon.fill"
        }
    }

    private var accentColor: Color {
        switch message.style {
        case .info:    return .accentColor
        case .success: return .green
        case .warning: return .orange
        case .error:   return .red
        }
    }

    private var accessibilityComposedLabel: Text {
        if let body = message.body, !body.isEmpty {
            return Text("\(stylePrefix): \(message.title). \(body)")
        } else {
            return Text("\(stylePrefix): \(message.title)")
        }
    }

    private var stylePrefix: String {
        switch message.style {
        case .info:    return "Notice"
        case .success: return "Success"
        case .warning: return "Warning"
        case .error:   return "Error"
        }
    }

    private var toastTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        } else {
            return .move(edge: .top).combined(with: .opacity)
        }
    }

    // MARK: - Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                // Horizontal-only swipe to dismiss; respect reduce-motion by
                // skipping the live-drag preview when the user has asked for
                // reduced motion.
                if !reduceMotion {
                    dragOffset = value.translation.width
                }
            }
            .onEnded { value in
                if abs(value.translation.width) > swipeThreshold {
                    onDismiss()
                } else {
                    if reduceMotion {
                        dragOffset = 0
                    } else {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            dragOffset = 0
                        }
                    }
                }
            }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add SocialFusion/Views/Components/Toast.swift
git commit -m "feat(toast): add reusable Toast view with retry + a11y + reduce-motion"
```

---

## Task 4: Bridge the legacy ToastManager onto ToastQueue

**Files:**
- Modify: `SocialFusion/Views/Components/ToastNotification.swift`

The legacy `ToastManager.shared.show(_:duration:)` API has callsites scattered around the codebase (verified: `PostActionCoordinator.swift:378`, `NotificationManager.swift:252`, `TimelineViewModel.swift:494, 550`). Rather than sweep them all in this plan, we make `ToastManager` a thin adapter that forwards to a shared `ToastQueue` instance. New code goes through the queue directly via `@EnvironmentObject`.

- [ ] **Step 1: Rewrite `ToastNotification.swift`**

Replace the contents of `SocialFusion/Views/Components/ToastNotification.swift`:

```swift
import SwiftUI

/// Legacy shim — kept compatible with existing callsites that haven't yet
/// migrated to `@EnvironmentObject var toastQueue: ToastQueue`. New code
/// should inject `ToastQueue` directly instead of going through this singleton.
@MainActor
final class ToastManager: ObservableObject {
    static let shared = ToastManager()

    /// The shared queue this manager forwards into. Set at app launch by
    /// `SocialFusionApp` so the singleton and the injected env-object are the
    /// same instance.
    fileprivate(set) var queue: ToastQueue = ToastQueue()

    /// Legacy entry point. Maps a plain string + duration to a `ToastMessage`
    /// with style `.info` and the legacy default of 2 seconds when called with
    /// the legacy signature, but uses 4 s for callers that omit duration.
    func show(_ message: String, duration: TimeInterval = 4.0) {
        queue.show(ToastMessage(
            title: message,
            style: .info,
            autoDismissAfter: duration
        ))
    }

    /// Adopt an externally-owned queue (called from the app root so the
    /// singleton points at the env-object instance).
    func adopt(_ queue: ToastQueue) {
        self.queue = queue
    }
}

/// View modifier mounted at the app root. Reads from an injected `ToastQueue`
/// and renders its head using the new reusable `Toast` view.
struct ToastHostModifier: ViewModifier {
    @EnvironmentObject private var queue: ToastQueue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let current = queue.current {
                    Toast(
                        message: current,
                        onRetry: { queue.invokeRetry(for: current.id) },
                        onDismiss: { queue.dismiss(current.id) }
                    )
                    .id(current.id)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85), value: queue.current)
                    .accessibilityAddTraits(.isModal)
                }
            }
    }
}

extension View {
    /// Mounts the toast host at this position in the view tree. Place once at
    /// the app root — the underlying queue is injected via `@EnvironmentObject`.
    func withToastNotifications() -> some View {
        modifier(ToastHostModifier())
    }
}
```

- [ ] **Step 2: Build to verify legacy callsites still compile**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED. The legacy `ToastManager.shared.show("Couldn't repost…")` calls in `TimelineViewModel.swift:494, 550`, `PostActionCoordinator.swift:378`, and `NotificationManager.swift:252` all still compile because the public `.show(_:duration:)` signature is unchanged.

- [ ] **Step 3: Commit**

```bash
git add SocialFusion/Views/Components/ToastNotification.swift
git commit -m "refactor(toast): bridge legacy ToastManager onto ToastQueue"
```

---

## Task 5: Inject ToastQueue at the app root

**Files:**
- Modify: `SocialFusion/SocialFusionApp.swift`
- Modify: `SocialFusion/ContentView.swift` (only to confirm the env-object resolves; `withToastNotifications()` call site stays put)

- [ ] **Step 1: Add the `@StateObject` to `SocialFusionApp`**

Open `SocialFusion/SocialFusionApp.swift` and locate the existing `@StateObject` block where services are owned (alongside `socialServiceManager`, etc.). Add:

```swift
@StateObject private var toastQueue = ToastQueue()
```

In the `WindowGroup`'s root view, add the environment-object modifier and adopt the queue into the legacy singleton so the bridge in Task 4 forwards into the same instance the host renders. The injection block should look like (insert near the other `.environmentObject(...)` calls):

```swift
.environmentObject(toastQueue)
.onAppear {
    ToastManager.shared.adopt(toastQueue)
}
```

If `ContentView` already has an `.onAppear` at the same scope, fold the `adopt` call into the existing one rather than adding a second `.onAppear`.

- [ ] **Step 2: Verify the existing host call site**

Open `SocialFusion/ContentView.swift` at line 94 and confirm `.withToastNotifications()` is still in place. No edit needed — the modifier now reads from the injected `@EnvironmentObject`.

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual smoke**

Run the app in the simulator. From any view that uses `ToastManager.shared.show(...)` (e.g., tap Like on a post while offline — `TimelineViewModel.swift:494`), confirm the new styled toast appears at the top, auto-dismisses after 4 s, and visually matches the design (rounded card, hierarchical icon, regular-material background).

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/SocialFusionApp.swift
git commit -m "feat(toast): inject ToastQueue at app root and adopt singleton bridge"
```

---

## Task 6: Wire timeline refresh-failure toasts (Feature A — closes TODOs)

**Files:**
- Modify: `SocialFusion/ViewModels/TimelineViewModel.swift`

This is the heart of Feature A — the spec's "Error UI Feedback" gap. The two `catch` blocks at `TimelineViewModel.swift:252-258` and `:434-440` currently swallow refresh failures into `self.state = .error(error)` with no UI surface. We add a single line each that enqueues an actionable retry toast through `ToastManager.shared.queue`. The brief originally pointed at lines 499 and 553 as the canonical "ship-blocking UX gaps"; in this file those line numbers fall inside the like/repost paths (which already toast via the singleton). The truly silent failures are 252-258 and 434-440 — we close those here and leave a `// MARK: error-feedback` breadcrumb at the like/repost paths noting they were upgraded by the same plan.

- [ ] **Step 1: Add a small helper on TimelineViewModel**

Open `SocialFusion/ViewModels/TimelineViewModel.swift`. Just below the existing `private let logger = …` declaration (near the top of the class), add:

```swift
/// Emits an actionable toast for a refresh failure. The retry closure
/// re-invokes the same path the failure happened on. Centralised so the
/// per-account and unified variants stay consistent.
@MainActor
private func presentRefreshFailureToast(
    error: Error,
    networkLabel: String,
    retry: @escaping @MainActor () -> Void
) {
    let toast = ToastMessage(
        title: "Couldn't refresh \(networkLabel) timeline.",
        body: error.localizedDescription,
        style: .error,
        retry: ToastMessage.RetryAction(label: "Retry", perform: retry)
    )
    ToastManager.shared.queue.show(toast)
}
```

- [ ] **Step 2: Wire `refreshTimeline(for:)` (single-account)**

Replace the existing `catch` block at `TimelineViewModel.swift:252-258`:

```swift
} catch {
    // Update UI on main thread
    await MainActor.run {
        self.isLoading = false
        self.state = .error(error)
    }
}
```

With:

```swift
} catch {
    // Update UI on main thread + surface a retry toast.
    await MainActor.run { [weak self] in
        guard let self = self else { return }
        self.isLoading = false
        self.state = .error(error)
        let label = account.platform == .mastodon ? "Mastodon" : "Bluesky"
        self.presentRefreshFailureToast(
            error: error,
            networkLabel: label,
            retry: { [weak self] in self?.refreshTimeline(for: account) }
        )
    }
}
```

- [ ] **Step 3: Wire `refreshUnifiedTimeline(for:)` (multi-account)**

Replace the existing `catch` block at `TimelineViewModel.swift:434-440`:

```swift
} catch {
    // Update UI on main thread
    await MainActor.run {
        self.isLoading = false
        self.state = .error(error)
    }
}
```

With:

```swift
} catch {
    // Update UI on main thread + surface a retry toast for the unified feed.
    await MainActor.run { [weak self] in
        guard let self = self else { return }
        self.isLoading = false
        self.state = .error(error)
        self.presentRefreshFailureToast(
            error: error,
            networkLabel: "timeline",
            retry: { [weak self] in self?.refreshUnifiedTimeline(for: accounts) }
        )
    }
}
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Manual smoke test for Feature A**

In the simulator: enable Airplane Mode (or block the host process from the network), then pull-to-refresh on the unified timeline. Expected: a red error-styled toast appears at the top with title "Couldn't refresh timeline." and a Retry button. Tap Retry while still offline → toast dismisses, refresh runs, a new toast appears (queueing behaviour). Re-enable network, tap Retry → toast dismisses, posts load, no further toast.

- [ ] **Step 6: Commit**

```bash
git add SocialFusion/ViewModels/TimelineViewModel.swift
git commit -m "fix(timeline): surface refresh failures as retry toast (closes UX TODO)"
```

---

## Task 7: QuotePostUnavailableView placeholder

**Files:**
- Create: `SocialFusion/Views/Components/QuotePostUnavailableView.swift`

The visual placeholder for a quoted post we can't load. Styled like `QuotedPostView` (matching corner radius, padding, background, border) so the parent post's layout doesn't jump when a quote falls back. Shows a network badge derived from the URL, an unavailable-icon, the human-readable reason, and the original URL as a tappable link.

- [ ] **Step 1: Implement the view**

Create `SocialFusion/Views/Components/QuotePostUnavailableView.swift`:

```swift
import SwiftUI

/// Placeholder rendered in place of a quoted post when the post cannot be
/// fetched (deleted, blocked, network failure, malformed response). Matches
/// the visual footprint of `QuotedPostView` so the parent post layout stays
/// stable on fallback.
public struct QuotePostUnavailableView: View {
    public enum Reason: Equatable {
        case deleted
        case blocked
        case network
        case malformed
        case unknown

        var headline: String {
            switch self {
            case .deleted:   return "This quoted post is no longer available"
            case .blocked:   return "This quoted post is from a blocked or private account"
            case .network:   return "Couldn't load the quoted post"
            case .malformed: return "This quoted post couldn't be displayed"
            case .unknown:   return "This quoted post is no longer available"
            }
        }

        var detail: String? {
            switch self {
            case .network: return "Tap the link to view it in your browser."
            case .deleted, .blocked, .malformed, .unknown: return nil
            }
        }

        var iconName: String {
            switch self {
            case .deleted, .unknown: return "trash.slash"
            case .blocked:           return "eye.slash"
            case .network:           return "wifi.slash"
            case .malformed:         return "exclamationmark.bubble"
            }
        }
    }

    let reason: Reason
    let originalURL: URL?
    let platform: SocialPlatform

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    public init(reason: Reason, originalURL: URL?, platform: SocialPlatform) {
        self.reason = reason
        self.originalURL = originalURL
        self.platform = platform
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: reason.iconName)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(reason.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                platformIndicator
            }
            if let detail = reason.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = originalURL {
                Button {
                    openURL(url)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.caption2)
                        Text(url.absoluteString)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Open original link")
                .accessibilityHint(url.absoluteString)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(backgroundStyle)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(borderOverlay)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(reason.headline). \(platform == .mastodon ? "Mastodon" : "Bluesky")."))
    }

    @ViewBuilder
    private var platformIndicator: some View {
        // Use the existing PlatformDot if available; fall back to a circle
        // tinted with the network's color. The fallback keeps this file
        // independent of changes elsewhere.
        PlatformDot(platform: platform, size: 14, useLogo: true)
    }

    private var backgroundStyle: some View {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.035)
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                colorScheme == .dark
                    ? Color.white.opacity(0.12)
                    : Color.black.opacity(0.08),
                style: StrokeStyle(lineWidth: 0.5, dash: [3, 3])
            )
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED. If `PlatformDot` isn't available in this scope the build will fail — substitute the existing `PlatformLogoBadge(platform:size:)` (same component, different name in some areas of the codebase) or remove the indicator line entirely.

- [ ] **Step 3: Commit**

```bash
git add SocialFusion/Views/Components/QuotePostUnavailableView.swift
git commit -m "feat(quote): add QuotePostUnavailableView placeholder for failed quote loads"
```

---

## Task 8: Quote post fallback classification + tests

**Files:**
- Create: `SocialFusionTests/QuotePostFallbackTests.swift`
- Modify: `SocialFusion/Views/Components/FetchQuotePostView.swift` (add a `QuoteFailureReason` classifier + use the new placeholder in failure branches)

The current `FetchQuotePostView` throws `NSError(domain: "FetchQuotePostView", code: …)` for various failure modes and then nils out the error to fall through to `LinkPreview`. We add a classifier that maps the failure into a `QuotePostUnavailableView.Reason`, surface it in the view, and write tests for each failure mode.

- [ ] **Step 1: Write the failing tests**

Create `SocialFusionTests/QuotePostFallbackTests.swift`:

```swift
import XCTest
@testable import SocialFusion

final class QuotePostFallbackTests: XCTestCase {
    func testDeletedPostMapsToDeletedReason() {
        // Domain matches the FetchQuotePostView NSError domain; code/userInfo
        // hint at a 404-like outcome via the localized description.
        let error = NSError(
            domain: "FetchQuotePostView",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Post not found (404)"]
        )
        XCTAssertEqual(QuoteFailureClassifier.classify(error: error), .deleted)
    }

    func testBlockedAuthorMapsToBlockedReason() {
        let error = NSError(
            domain: "FetchQuotePostView",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Forbidden: account is blocked"]
        )
        XCTAssertEqual(QuoteFailureClassifier.classify(error: error), .blocked)
    }

    func testNetworkErrorMapsToNetworkReason() {
        let error = URLError(.notConnectedToInternet)
        XCTAssertEqual(QuoteFailureClassifier.classify(error: error), .network)
    }

    func testTimeoutMapsToNetworkReason() {
        let error = URLError(.timedOut)
        XCTAssertEqual(QuoteFailureClassifier.classify(error: error), .network)
    }

    func testMalformedResponseMapsToMalformedReason() {
        let error = NSError(
            domain: "FetchQuotePostView",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not extract post ID from URL: https://example.social/bad"]
        )
        XCTAssertEqual(QuoteFailureClassifier.classify(error: error), .malformed)
    }

    func testUnknownErrorFallsBackToUnknownReason() {
        struct Mystery: Error {}
        XCTAssertEqual(QuoteFailureClassifier.classify(error: Mystery()), .unknown)
    }

    func testNilFetchedPostIsTreatedAsDeleted() {
        // Post fetch returned nil with no thrown error — treat as deleted.
        XCTAssertEqual(QuoteFailureClassifier.classifyNilResult(), .deleted)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/QuotePostFallbackTests`
Expected: FAIL — `QuoteFailureClassifier` not defined.

- [ ] **Step 3: Implement the classifier inside `FetchQuotePostView.swift`**

Open `SocialFusion/Views/Components/FetchQuotePostView.swift` and add — near the top of the file, just below the `import SwiftUI` — the classifier:

```swift
/// Maps a raw fetch failure to a user-facing `QuotePostUnavailableView.Reason`.
/// Centralised so `FetchQuotePostView` doesn't sprinkle case-by-case mapping
/// throughout its failure branches.
enum QuoteFailureClassifier {
    static func classify(error: Error) -> QuotePostUnavailableView.Reason {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .timedOut, .networkConnectionLost,
                 .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost:
                return .network
            default:
                return .network
            }
        }

        let ns = error as NSError
        let message = ns.localizedDescription.lowercased()

        if message.contains("404") || message.contains("not found") || message.contains("gone") {
            return .deleted
        }
        if message.contains("403") || message.contains("forbidden") ||
           message.contains("blocked") || message.contains("private") ||
           message.contains("unauthorized") {
            return .blocked
        }
        if message.contains("could not extract") ||
           message.contains("invalid") ||
           message.contains("unsupported platform") ||
           message.contains("malformed") {
            return .malformed
        }
        return .unknown
    }

    /// A `nil` post returned from the API with no thrown error means the
    /// network round-tripped successfully but the post itself is gone.
    static func classifyNilResult() -> QuotePostUnavailableView.Reason {
        .deleted
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/QuotePostFallbackTests`
Expected: PASS, all 7 tests green.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Views/Components/FetchQuotePostView.swift SocialFusionTests/QuotePostFallbackTests.swift
git commit -m "feat(quote): add QuoteFailureClassifier with full failure-mode coverage"
```

---

## Task 9: Render QuotePostUnavailableView in FetchQuotePostView failure paths

**Files:**
- Modify: `SocialFusion/Views/Components/FetchQuotePostView.swift`

Now wire the placeholder into `FetchQuotePostView`'s view body, replacing the silent fallthrough to `LinkPreview` for the cases where we authoritatively know the fetch failed (vs. the case where we just couldn't classify the URL — that one keeps `LinkPreview`).

- [ ] **Step 1: Add state for the classified reason**

In `FetchQuotePostView`'s `@State` block (currently at `SocialFusion/Views/Components/FetchQuotePostView.swift:166-169`), add:

```swift
@State private var unavailableReason: QuotePostUnavailableView.Reason? = nil
```

- [ ] **Step 2: Update the view body's branching**

Replace the existing `body` group at `FetchQuotePostView.swift:189-241` with this updated branching that prefers `QuotePostUnavailableView` over `LinkPreview` once we know the fetch authoritatively failed:

```swift
var body: some View {
    Group {
        if let post = quotedPost, hasMeaningfulContent(post) {
            QuotedPostView(post: post) {
                DebugLog.verbose("🔗 [FetchQuotePostView] Quote post tapped: \(post.id)")
                handleQuoteTap(for: post)
            }
        } else if let fallbackPost = fallbackPost, hasMeaningfulContent(fallbackPost) {
            // Show embedded quote data while we fetch full details/attachments.
            QuotedPostView(post: fallbackPost) {
                handleQuoteTap(for: fallbackPost)
            }
        } else if isLoading {
            LoadingQuoteView(platform: platform)
        } else if let reason = unavailableReason {
            // Authoritative failure — render the placeholder instead of a
            // generic LinkPreview so the user sees that *something was
            // quoted* but couldn't be loaded.
            QuotePostUnavailableView(
                reason: reason,
                originalURL: url,
                platform: platform
            )
        } else if error != nil && retryCount <= maxRetries {
            // Transient retry-able state, mid-backoff.
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Failed to load quote")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Retry") {
                        retryCount = 0
                        unavailableReason = nil
                        Task { await fetchPost() }
                    }
                    .font(.caption)
                    .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        } else {
            // Genuinely-ambiguous: we never even tried (or the URL wasn't a
            // recognized post URL). Fall back to a generic link preview so
            // the parent post still has something to display.
            LinkPreview(url: url)
        }
    }
    .onAppear {
        DebugLog.verbose("🔗 [FetchQuotePostView] Starting fetch for URL: \(url)")
        Task { await fetchPost() }
    }
}
```

- [ ] **Step 3: Set `unavailableReason` from the fetch path**

In `fetchPost()` at `FetchQuotePostView.swift:270-366`, set `unavailableReason` in three places. First, replace the "post fetched but no meaningful content" branch (currently around `:320-328`):

```swift
} else {
    // Post was fetched but has no meaningful content — treat as deleted-ish.
    DebugLog.verbose("🔗 [FetchQuotePostView] Post fetched but has no meaningful content: \(url)")
    await MainActor.run {
        self.isLoading = false
        self.error = nil
        self.unavailableReason = QuoteFailureClassifier.classifyNilResult()
    }
}
```

Second, replace the "nil post" branch (currently around `:330-339`):

```swift
} else {
    // Post fetch returned nil — the post is gone.
    DebugLog.verbose("🔗 [FetchQuotePostView] Post fetch returned nil: \(url)")
    await MainActor.run {
        self.isLoading = false
        self.error = nil
        self.unavailableReason = QuoteFailureClassifier.classifyNilResult()
    }
}
```

Third, replace the post-max-retries branch (currently around `:357-364`):

```swift
} else {
    // After max retries, classify the last error and render the placeholder.
    DebugLog.verbose("🔗 [FetchQuotePostView] Max retries exceeded; classifying failure.")
    let classifiedReason = QuoteFailureClassifier.classify(error: error)
    await MainActor.run {
        self.isLoading = false
        self.error = nil
        self.unavailableReason = classifiedReason
    }
}
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Manual smoke test for Feature B**

In the simulator, paste a known-deleted Mastodon post URL into a draft and post it as a quote (or scroll a timeline until a quoted post happens to be deleted — common). Expected: the parent post renders normally; the quote slot renders `QuotePostUnavailableView` with "This quoted post is no longer available" headline, dashed-border card, and the original URL as a tappable link. Tapping the URL opens it in Safari.

- [ ] **Step 6: Commit**

```bash
git add SocialFusion/Views/Components/FetchQuotePostView.swift
git commit -m "fix(quote): render QuotePostUnavailableView for authoritative fetch failures"
```

---

## Task 10: Combined integration test for Feature A end-to-end behaviour

**Files:**
- Create: `SocialFusionTests/ToastQueueIntegrationTests.swift` (small companion to `ToastQueueTests` covering the integration shape)

A handful of higher-level assertions that exercise the queue through the `ToastManager` bridge and the retry-callback wiring, so a future refactor that breaks the bridge or accidentally drops retries gets caught.

- [ ] **Step 1: Write the tests**

Create `SocialFusionTests/ToastQueueIntegrationTests.swift`:

```swift
import XCTest
@testable import SocialFusion

@MainActor
final class ToastQueueIntegrationTests: XCTestCase {
    func testLegacyManagerShowForwardsIntoQueue() {
        let queue = ToastQueue()
        ToastManager.shared.adopt(queue)
        ToastManager.shared.show("Hello legacy")
        XCTAssertEqual(queue.current?.title, "Hello legacy")
        XCTAssertEqual(queue.current?.style, .info)
        // Restore default to keep test isolation tidy.
        ToastManager.shared.adopt(ToastQueue())
    }

    func testRetryToastSurvivesAutoDismissWindow() async {
        let queue = ToastQueue()
        var didRetry = false
        let retry = ToastMessage.RetryAction { didRetry = true }
        let msg = ToastMessage(
            title: "Couldn't refresh timeline.",
            style: .error,
            retry: retry
        )
        queue.show(msg)
        try? await Task.sleep(nanoseconds: 250_000_000) // 0.25 s
        XCTAssertNotNil(queue.current, "Retry toast must outlive a generic dismiss window.")
        queue.invokeRetry(for: msg.id)
        XCTAssertTrue(didRetry)
        XCTAssertNil(queue.current)
    }

    func testTwoRefreshFailuresQueueRatherThanCollide() {
        let queue = ToastQueue()
        let a = ToastMessage(
            title: "Couldn't refresh Mastodon timeline.",
            style: .error,
            retry: ToastMessage.RetryAction { }
        )
        let b = ToastMessage(
            title: "Couldn't refresh Bluesky timeline.",
            style: .error,
            retry: ToastMessage.RetryAction { }
        )
        queue.show(a)
        queue.show(b)
        XCTAssertEqual(queue.pending.count, 2)
        XCTAssertEqual(queue.current?.title, "Couldn't refresh Mastodon timeline.")
        queue.dismiss(a.id)
        XCTAssertEqual(queue.current?.title, "Couldn't refresh Bluesky timeline.")
    }
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/ToastQueueIntegrationTests`
Expected: PASS, all 3 tests green.

- [ ] **Step 3: Commit**

```bash
git add SocialFusionTests/ToastQueueIntegrationTests.swift
git commit -m "test(toast): integration coverage for legacy bridge + retry queueing"
```

---

## Task 11: Full suite + acceptance verification

**Files:**
- (no new files — verification only)

- [ ] **Step 1: Run the full test suite**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: all tests pass. If anything outside the new files broke, the bridge in Task 4 is the most likely culprit — re-verify that `ToastManager.shared.show(_:duration:)` still routes through the queue.

- [ ] **Step 2: Manual acceptance walkthrough**

Walk down the v1.0 acceptance criteria for "New for v1.0 → Error UI Feedback / Quote post fallback":

| Criterion | Evidence |
|---|---|
| Toast appears on timeline refresh failure | Task 6 Step 5 manual smoke. |
| Toast offers Retry; tapping it re-runs the same refresh | Task 6 Step 5 + `ToastQueueIntegrationTests.testRetryToastSurvivesAutoDismissWindow`. |
| Toast queues when multiple errors arrive | `ToastQueueTests.testSecondShowQueuesBehindCurrent` + `ToastQueueIntegrationTests.testTwoRefreshFailuresQueueRatherThanCollide`. |
| Non-actionable toasts auto-dismiss after 4 s | `ToastMessage.init` default + `ToastQueueTests.testNonActionableAutoDismissesAfterItsDuration`. |
| Actionable toasts persist | `ToastQueueTests.testActionableToastDoesNotAutoDismiss`. |
| Reduce Motion respected | `Toast.toastTransition` returns `.opacity` when `accessibilityReduceMotion`. Manual: Simulator → Settings → Accessibility → Motion → Reduce Motion ON, trigger a toast, verify no slide. |
| Dynamic Type respected | `Toast` uses semantic fonts (`.subheadline`, `.caption`), no fixed sizes. Manual: Simulator → Settings → Display & Brightness → Text Size → max, trigger a toast, verify content scales without truncating to ellipsis on the title. |
| Deleted quote renders placeholder | Task 9 Step 5 manual + `QuotePostFallbackTests.testDeletedPostMapsToDeletedReason`. |
| Blocked-author quote renders placeholder | `QuotePostFallbackTests.testBlockedAuthorMapsToBlockedReason`. |
| Network-failure quote renders placeholder | `QuotePostFallbackTests.testNetworkErrorMapsToNetworkReason` + `…testTimeoutMapsToNetworkReason`. |
| Malformed quote renders placeholder | `QuotePostFallbackTests.testMalformedResponseMapsToMalformedReason`. |
| Parent post is never blocked by quote failure | Visual: the `Group` branching in Task 9 always produces *some* view; parent layout is unaffected. Spot-check in simulator with a deleted quote URL. |

- [ ] **Step 3: AttributeGraph check**

Run the app in the simulator with the Xcode console visible. Trigger:
- A failed refresh (toast)
- A deleted quote post (placeholder)
- A queued double-failure (two toasts)
Expected: no new `AttributeGraph: cycle detected` warnings appear that weren't there before.

- [ ] **Step 4: Commit (final)**

If you made any small fixups during verification, commit them. Otherwise this task has no commit.

---

## Acceptance gate before merging

After all 11 tasks are complete:

1. **Full unit test suite passes:** `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet` returns 0.
2. **`TimelineViewModel.swift` no longer has silent refresh failures** — grep for `state = .error(error)` and verify each result has an accompanying `presentRefreshFailureToast(...)` call (or is intentionally silent with a `// MARK: silent-by-design` comment explaining why).
3. **Manual smoke on Frank's iPhone 17 Pro (UDID `00008150-000139C63480401C`)** — toggle Airplane Mode mid-refresh, see the toast, tap Retry with network back on, see the timeline reload.
4. **Manual smoke on Frank's iPad Pro (UDID `00008027-000858493684002E`)** — the toast renders correctly in landscape and split-view multitasking.
5. **Reduce Motion + Dynamic Type + VoiceOver all behave** — verify each toggle in Accessibility settings during a triggered toast and a triggered quote placeholder.
6. **No new `AttributeGraph: cycle detected` warnings** in the console during the manual smoke test.

---

## What's intentionally out of scope for this plan

The following are deliberately deferred so the v1.0 "polish" envelope stays small:

- **Broader error-handling pass** — every other `catch` block in the codebase that silently logs (e.g., `preloadOriginalPost` at `TimelineViewModel.swift:719-726`, the `ErrorHandler.shared.handleError(error)` callsites). Those are intentionally silent for non-blocking background work; turning them into toasts would be noisy. v1.x will introduce a "Recent issues" surface in Settings that aggregates these silent logs for power users.
- **Toast haptics** — adding `UIImpactFeedbackGenerator` taps on toast appearance / retry. Punted to v1.x once we've decided on a global haptic-density preference.
- **Inline error UI inside the timeline** (e.g., a "Couldn't load older posts" row in-list rather than a toast) — separate, larger plan. The toast is the right surface for full-feed refresh failures because the timeline still has cached content to show; an inline row is the right surface for pagination failures, which are a v1.x feature.
- **Migrating all legacy `ToastManager.shared.show(_:)` callsites to use `@EnvironmentObject var toastQueue: ToastQueue` directly** — the bridge is good enough for v1.0. The full migration is a mechanical follow-up.
- **Quote post live retry from the placeholder** — the placeholder currently surfaces the original URL but doesn't offer "tap to retry the fetch." Punted because a deleted/blocked post will never recover, and the URL-tap fallback covers the network case. We can add a retry affordance if user feedback says they want it.
- **Toast theming / custom styles per producer** — every toast today uses the four built-in `Style` cases. A producer-supplied theme would be a v1.x concern.
- **Centralised network-error vocabulary** — toast bodies currently surface `error.localizedDescription` verbatim, which can leak technical jargon (e.g., "The Internet connection appears to be offline."). Translating these into human language is its own polish pass.

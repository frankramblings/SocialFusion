import XCTest
@testable import SocialFusion

/// Coverage for the queue + retry semantics on the evolved ToastManager.
/// Uses a fresh local ToastManager-equivalent flow via the shared singleton —
/// each test calls `dismissAll()` at the top to isolate from prior state.
@MainActor
final class ToastQueueTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        ToastManager.shared.dismissAll()
    }

    override func tearDown() async throws {
        ToastManager.shared.dismissAll()
        try await super.tearDown()
    }

    // MARK: - Queue semantics

    func testShowEnqueuesAndExposesAsCurrent() {
        let manager = ToastManager.shared
        manager.show("Hello")
        XCTAssertEqual(manager.currentToast?.message, "Hello")
        XCTAssertEqual(manager.pending.count, 1)
    }

    func testSecondShowQueuesBehindCurrent() {
        let manager = ToastManager.shared
        manager.show("First")
        manager.show("Second")
        XCTAssertEqual(manager.currentToast?.message, "First", "Head must not be overwritten.")
        XCTAssertEqual(manager.pending.count, 2)
    }

    func testDismissHeadAdvancesToNext() {
        let manager = ToastManager.shared
        manager.show("First")
        manager.show("Second")
        let firstId = manager.currentToast!.id
        manager.dismiss(firstId)
        XCTAssertEqual(manager.currentToast?.message, "Second")
        XCTAssertEqual(manager.pending.count, 1)
    }

    func testDismissUnknownIdIsNoOp() {
        let manager = ToastManager.shared
        manager.show("Present")
        manager.dismiss(UUID())
        XCTAssertEqual(manager.currentToast?.message, "Present")
    }

    func testDismissAllClearsTheQueue() {
        let manager = ToastManager.shared
        manager.show("a")
        manager.show("b")
        manager.dismissAll()
        XCTAssertNil(manager.currentToast)
        XCTAssertEqual(manager.pending.count, 0)
    }

    func testLegacyDismissDismissesHead() {
        let manager = ToastManager.shared
        manager.show("First")
        manager.show("Second")
        // Legacy dismiss() with no id — dismisses the head only.
        manager.dismiss()
        XCTAssertEqual(manager.currentToast?.message, "Second")
    }

    // MARK: - Auto-dismiss

    func testNonActionableAutoDismissesAfterDuration() async {
        let manager = ToastManager.shared
        manager.show("Quick", duration: 0.05)
        XCTAssertNotNil(manager.currentToast)
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 s
        XCTAssertNil(manager.currentToast, "Auto-dismiss should have fired by now.")
    }

    func testActionableToastIsPersistent() async {
        let manager = ToastManager.shared
        manager.showError("Stays") { /* no-op */ }
        try? await Task.sleep(nanoseconds: 250_000_000) // 0.25 s
        XCTAssertNotNil(manager.currentToast, "Retry-bearing toasts must be persistent.")
    }

    // MARK: - Retry

    func testInvokeRetryFiresCallbackAndDismisses() {
        let manager = ToastManager.shared
        var fired = false
        manager.showError("Try") { fired = true }
        let id = manager.currentToast!.id
        manager.invokeRetry(for: id)
        XCTAssertTrue(fired)
        XCTAssertNil(manager.currentToast, "Invoking retry should dismiss the toast.")
    }

    func testInvokeRetryOnNonActionableIsNoOp() {
        let manager = ToastManager.shared
        manager.show("Plain")
        let id = manager.currentToast!.id
        manager.invokeRetry(for: id)
        // No crash, no dismiss (no retry to fire).
        XCTAssertNotNil(manager.currentToast)
    }

    func testTwoRefreshFailuresQueueRatherThanCollide() {
        let manager = ToastManager.shared
        manager.showError("Couldn't refresh Mastodon timeline.") { }
        manager.showError("Couldn't refresh Bluesky timeline.") { }
        XCTAssertEqual(manager.pending.count, 2)
        XCTAssertEqual(manager.currentToast?.message, "Couldn't refresh Mastodon timeline.")
        let firstId = manager.currentToast!.id
        manager.dismiss(firstId)
        XCTAssertEqual(manager.currentToast?.message, "Couldn't refresh Bluesky timeline.")
    }

    // MARK: - Custom enqueue with explicit duration

    func testEnqueueWithCustomDurationOverridesDefault() async {
        let manager = ToastManager.shared
        // Build a Toast with severity=.error + no retry + a 0.05s duration —
        // overrides both the persistent-when-error implicit and the 2s default.
        let toast = ToastManager.Toast(
            message: "Custom",
            severity: .error,
            retry: nil,
            autoDismissAfter: 0.05
        )
        manager.enqueue(toast)
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 s
        XCTAssertNil(manager.currentToast, "Custom duration must auto-dismiss.")
    }
}

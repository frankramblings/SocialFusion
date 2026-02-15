import XCTest
@testable import SocialFusion

@MainActor
final class ViewTrackerPerformanceTests: XCTestCase {

  /// ViewTracker.shared should initialize without blocking for an extended period.
  func testViewTrackerInitIsNonBlocking() {
    let start = CFAbsoluteTimeGetCurrent()
    let tracker = ViewTracker.shared
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    XCTAssertNotNil(tracker)
    // Init should complete in under 100ms even with persistence load
    XCTAssertLessThan(elapsed, 0.1,
                      "ViewTracker init took \(elapsed)s — should be < 100ms")
  }

  /// markAsRead should return quickly (async persistence, not blocking).
  func testMarkAsReadIsNonBlocking() async {
    let tracker = ViewTracker.shared
    await tracker._test_resetState()

    let start = CFAbsoluteTimeGetCurrent()
    await tracker.markAsRead(postId: "perf-test-\(UUID().uuidString)", stableId: "stable-1")
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    // Should complete in under 10ms (just in-memory insert + schedule flush)
    XCTAssertLessThan(elapsed, 0.01,
                      "markAsRead took \(elapsed)s — should be < 10ms")

    await tracker._test_resetState()
  }

  /// Batch flush should complete without excessive time.
  func testFlushPerformance() async {
    let tracker = ViewTracker.shared
    await tracker._test_resetState()

    // Mark several posts
    for i in 0..<50 {
      await tracker.markAsRead(postId: "batch-\(i)", stableId: "stable-\(i)")
    }

    let start = CFAbsoluteTimeGetCurrent()
    await tracker._test_forceFlushPendingReadState()
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    // Flush of 50 entries should be under 500ms
    XCTAssertLessThan(elapsed, 0.5,
                      "Flush of 50 entries took \(elapsed)s — should be < 500ms")

    await tracker._test_resetState()
  }
}

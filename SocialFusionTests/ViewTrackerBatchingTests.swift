import XCTest
@testable import SocialFusion

@MainActor
final class ViewTrackerBatchingTests: XCTestCase {
    private let tracker = ViewTracker.shared

    override func setUp() async throws {
        try await super.setUp()
        await tracker._test_resetState()
    }

    override func tearDown() async throws {
        await tracker._test_resetState()
        try await super.tearDown()
    }

    func testMarkAsReadQueuesPendingEntryBeforeFlush() async {
        await tracker.markAsRead(postId: "post-1", stableId: "stable-1")

        XCTAssertTrue(tracker.isRead(postId: "post-1"))
        XCTAssertEqual(tracker.getLastReadPostId(), "post-1")
        XCTAssertEqual(tracker._test_pendingReadEntryCount(), 1)
    }

    func testDuplicateReadDoesNotIncreasePendingQueue() async {
        await tracker.markAsRead(postId: "post-1", stableId: "stable-1")
        await tracker.markAsRead(postId: "post-1", stableId: "stable-1b")

        XCTAssertEqual(tracker._test_pendingReadEntryCount(), 1)
        XCTAssertEqual(tracker.getLastReadPostId(), "post-1")
    }

    func testForceFlushClearsPendingQueue() async {
        await tracker.markAsRead(postId: "post-1", stableId: "stable-1")
        await tracker.markAsRead(postId: "post-2", stableId: "stable-2")

        XCTAssertEqual(tracker._test_pendingReadEntryCount(), 2)

        await tracker._test_forceFlushPendingReadState()

        XCTAssertEqual(tracker._test_pendingReadEntryCount(), 0)
        XCTAssertEqual(tracker.getLastReadPostId(), "post-2")
    }
}

import XCTest

@testable import SocialFusion

final class SocialFusionTimelineDebugTests: XCTestCase {
    var debug: SocialFusionTimelineDebug!

    override func setUp() {
        super.setUp()
        debug = SocialFusionTimelineDebug.shared
        // Clear any existing data
        debug.clearDebugData()
    }

    override func tearDown() {
        debug.clearDebugData()
        super.tearDown()
    }

    // MARK: - Feature Flag Tests

    func testDebugModeToggle() {
        // Initially disabled
        XCTAssertFalse(debug.isDebugModeEnabled())

        // Enable debug mode
        debug.setDebugMode(true)
        XCTAssertTrue(debug.isDebugModeEnabled())

        // Disable debug mode
        debug.setDebugMode(false)
        XCTAssertFalse(debug.isDebugModeEnabled())
    }

    func testVerboseLoggingToggle() {
        // Initially disabled
        XCTAssertFalse(debug.isVerboseLoggingEnabled())

        // Enable verbose logging
        debug.setVerboseLogging(true)
        XCTAssertTrue(debug.isVerboseLoggingEnabled())

        // Disable verbose logging
        debug.setVerboseLogging(false)
        XCTAssertFalse(debug.isVerboseLoggingEnabled())
    }

    // MARK: - Debug Notes Tests

    func testAddDebugNote() {
        let testNote = "Test debug note"
        debug.addDebugNote(testNote)

        let notes = debug.getDebugNotes()
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes[0].contains(testNote))
    }

    func testDebugNotesLimit() {
        // Add more than 1000 notes
        for i in 0..<1100 {
            debug.addDebugNote("Note \(i)")
        }

        let notes = debug.getDebugNotes()
        XCTAssertLessThanOrEqual(notes.count, 1000)
        XCTAssertEqual(notes.count, 1000)
    }

    // MARK: - Performance Tracking Tests

    func testPerformanceTracking() {
        // Enable debug mode for performance tracking
        debug.setDebugMode(true)

        let operation = "Test Operation"
        let duration: TimeInterval = 1.5

        debug.trackPerformance(operation, duration: duration)

        let metrics = debug.getPerformanceMetrics()
        XCTAssertEqual(metrics[operation], duration)
    }

    func testPerformanceTrackingDisabled() {
        // Ensure debug mode is disabled
        debug.setDebugMode(false)

        let operation = "Test Operation"
        let duration: TimeInterval = 1.5

        debug.trackPerformance(operation, duration: duration)

        let metrics = debug.getPerformanceMetrics()
        XCTAssertNil(metrics[operation])
    }

    // MARK: - Error Tracking Tests

    func testErrorTracking() {
        let error = AppError(
            type: .network,
            message: "Test error",
            isRetryable: true
        )

        debug.trackError(error)

        let errors = debug.getRecentErrors()
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].message, error.message)
    }

    func testErrorHistoryLimit() {
        // Add more than 100 errors
        for i in 0..<110 {
            let error = AppError(
                type: .network,
                message: "Test error \(i)",
                isRetryable: true
            )
            debug.trackError(error)
        }

        let errors = debug.getRecentErrors()
        XCTAssertLessThanOrEqual(errors.count, 100)
        XCTAssertEqual(errors.count, 100)
    }

    // MARK: - Post Tracking Tests

    func testBlueskyPostsTracking() {
        let testPosts = [Post(id: "1", content: "Test post")]
        debug.setBlueskyPosts(testPosts)

        let posts = debug.getBlueskyPosts()
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts[0].id, testPosts[0].id)
    }

    func testMastodonPostsTracking() {
        let testPosts = [Post(id: "1", content: "Test post")]
        debug.setMastodonPosts(testPosts)

        let posts = debug.getMastodonPosts()
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts[0].id, testPosts[0].id)
    }

    func testLastRefreshUpdate() {
        XCTAssertNil(debug.getLastRefresh())

        let testPosts = [Post(id: "1", content: "Test post")]
        debug.setBlueskyPosts(testPosts)

        XCTAssertNotNil(debug.getLastRefresh())
    }

    // MARK: - Data Clearing Tests

    func testClearDebugData() {
        // Add some test data
        debug.addDebugNote("Test note")
        debug.trackError(AppError(type: .network, message: "Test error"))
        debug.trackPerformance("Test", duration: 1.0)

        // Clear data
        debug.clearDebugData()

        // Verify everything is cleared
        XCTAssertEqual(debug.getDebugNotes().count, 1)  // Only the clear message remains
        XCTAssertEqual(debug.getRecentErrors().count, 0)
        XCTAssertEqual(debug.getPerformanceMetrics().count, 0)
    }
}

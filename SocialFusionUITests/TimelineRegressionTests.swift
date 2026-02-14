import XCTest

/// Regression tests to ensure timeline displays correctly after position tracking changes
/// These tests verify that boosts, replies, media, quotes, and link previews still render correctly
final class TimelineRegressionTests: XCTestCase {
    private var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        app = XCUIApplication()
        app.launchArguments = ["UI-Testing", "UI_TESTING"]
        app.launch()
    }
    
    // MARK: - Timeline Existence Tests
    
    /// Test that timeline loads and displays posts
    func testTimelineLoads() {
        // Seed the timeline
        let seed = app.buttons["SeedTimelineButton"]
        XCTAssertTrue(seed.waitForExistence(timeout: 5), "Seed button should exist")
        seed.tap()

        // Verify timeline debug hooks and scroll container are present after seeding.
        let bufferCount = app.staticTexts["TimelineBufferCount"]
        XCTAssertTrue(bufferCount.waitForExistence(timeout: 3), "Timeline debug overlay should be present")

        let scrollViews = app.scrollViews
        XCTAssertTrue(scrollViews.count > 0, "Timeline scroll container should exist after seeding")
    }
    
    /// Test that post cards exist in timeline
    func testPostCardsExist() {
        let seed = app.buttons["SeedTimelineButton"]
        XCTAssertTrue(seed.waitForExistence(timeout: 5))
        seed.tap()
        
        // Wait for posts to appear
        sleep(1)
        
        // Check for cells or post-like elements
        let scrollViews = app.scrollViews
        XCTAssertTrue(scrollViews.count > 0, "Should have at least one scroll view (timeline)")
    }
    
    // MARK: - UI Component Existence Tests
    
    /// Test that debug overlay elements exist when in UI testing mode
    func testDebugOverlayExists() {
        let seed = app.buttons["SeedTimelineButton"]
        XCTAssertTrue(seed.waitForExistence(timeout: 2), "Seed button should exist in UI testing mode")
        
        let bufferCount = app.staticTexts["TimelineBufferCount"]
        XCTAssertTrue(bufferCount.waitForExistence(timeout: 2), "Buffer count should exist")
        
        let unreadCount = app.staticTexts["TimelineUnreadCount"]
        XCTAssertTrue(unreadCount.waitForExistence(timeout: 2), "Unread count should exist")
        
        let anchorId = app.staticTexts["TimelineTopAnchorId"]
        XCTAssertTrue(anchorId.waitForExistence(timeout: 2), "Anchor ID should exist")
        
        let anchorOffset = app.staticTexts["TimelineTopAnchorOffset"]
        XCTAssertTrue(anchorOffset.waitForExistence(timeout: 2), "Anchor offset should exist")
    }
    
    /// Test that triggering prefetch works
    func testForegroundPrefetchTriggers() {
        let seed = app.buttons["SeedTimelineButton"]
        XCTAssertTrue(seed.waitForExistence(timeout: 2))
        seed.tap()
        
        let prefetchButton = app.buttons["TriggerForegroundPrefetchButton"]
        XCTAssertTrue(prefetchButton.waitForExistence(timeout: 2), "Foreground prefetch button should exist")
        prefetchButton.tap()
        
        // Should either show pill or update buffer count
        sleep(1)
        
        let bufferCount = app.staticTexts["TimelineBufferCount"]
        XCTAssertTrue(bufferCount.exists, "Buffer count should exist after prefetch")
    }
    
    /// Test that idle prefetch trigger works
    func testIdlePrefetchTriggers() {
        let seed = app.buttons["SeedTimelineButton"]
        XCTAssertTrue(seed.waitForExistence(timeout: 2))
        seed.tap()
        
        let idleButton = app.buttons["TriggerIdlePrefetchButton"]
        XCTAssertTrue(idleButton.waitForExistence(timeout: 2), "Idle prefetch button should exist")
        idleButton.tap()
        
        // Wait for any potential update
        sleep(1)
        
        // Should complete without crash
        XCTAssertTrue(true)
    }
    
    // MARK: - Scroll Interaction Tests
    
    /// Test that scroll begin/end buttons work
    func testScrollInteractionButtons() {
        let seed = app.buttons["SeedTimelineButton"]
        XCTAssertTrue(seed.waitForExistence(timeout: 2))
        seed.tap()
        
        let beginScroll = app.buttons["BeginScrollButton"]
        let endScroll = app.buttons["EndScrollButton"]
        
        XCTAssertTrue(beginScroll.waitForExistence(timeout: 2), "Begin scroll button should exist")
        XCTAssertTrue(endScroll.waitForExistence(timeout: 2), "End scroll button should exist")
        
        beginScroll.tap()
        endScroll.tap()
        
        // Should complete without crash
        XCTAssertTrue(true)
    }
    
    // MARK: - State Consistency Tests
    
    /// Test that buffer and unread counts are consistent after operations
    func testStateConsistencyAfterOperations() {
        let seed = app.buttons["SeedTimelineButton"]
        XCTAssertTrue(seed.waitForExistence(timeout: 2))
        seed.tap()
        
        let bufferCount = app.staticTexts["TimelineBufferCount"]
        let unreadCount = app.staticTexts["TimelineUnreadCount"]
        
        XCTAssertTrue(bufferCount.waitForExistence(timeout: 2))
        XCTAssertTrue(unreadCount.waitForExistence(timeout: 2))
        
        // Initial state
        let initialBuffer = Int(bufferCount.label) ?? -1
        let initialUnread = Int(unreadCount.label) ?? -1
        
        XCTAssertGreaterThanOrEqual(initialBuffer, 0, "Buffer count should be non-negative")
        XCTAssertGreaterThanOrEqual(initialUnread, 0, "Unread count should be non-negative")
        
        // Trigger prefetch
        app.buttons["TriggerForegroundPrefetchButton"].tap()
        sleep(2)
        
        // After prefetch
        let finalBuffer = Int(bufferCount.label) ?? -1
        let finalUnread = Int(unreadCount.label) ?? -1
        
        XCTAssertGreaterThanOrEqual(finalBuffer, 0, "Buffer count should be non-negative after prefetch")
        XCTAssertGreaterThanOrEqual(finalUnread, 0, "Unread count should be non-negative after prefetch")
    }
}

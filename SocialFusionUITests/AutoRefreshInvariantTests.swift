import XCTest

final class AutoRefreshInvariantTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        app = XCUIApplication()
        app.launchArguments = ["UI-Testing", "UI_TESTING"]
        app.launch()
    }

    private func waitForNewContentSignal(timeout: TimeInterval = 3.0) -> Bool {
        let pill = app.buttons["NewPostsPill"]
        let bufferCount = app.staticTexts["TimelineBufferCount"]
        let unreadCount = app.staticTexts["TimelineUnreadCount"]

        guard bufferCount.waitForExistence(timeout: 2), unreadCount.waitForExistence(timeout: 2) else {
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pill.exists { return true }
            let bufferValue = Int(bufferCount.label) ?? 0
            let unreadValue = Int(unreadCount.label) ?? 0
            if bufferValue > 0 || unreadValue > 0 { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    func testForegroundPrefetchIsBufferOnly() {
        let seed = app.buttons["SeedTimelineButton"]
        XCTAssertTrue(seed.waitForExistence(timeout: 2))
        seed.tap()

        let anchorId = app.staticTexts["TimelineTopAnchorId"]
        XCTAssertTrue(anchorId.waitForExistence(timeout: 2))
        let initialAnchor = anchorId.label

        app.buttons["TriggerForegroundPrefetchButton"].tap()
        XCTAssertTrue(
            waitForNewContentSignal(),
            "Expected a new content signal after foreground prefetch"
        )

        let finalAnchor = anchorId.label
        XCTAssertEqual(finalAnchor, initialAnchor)
    }

    func testScrollingSuppressesIndicatorChanges() {
        let seed = app.buttons["SeedTimelineButton"]
        XCTAssertTrue(seed.waitForExistence(timeout: 2))
        seed.tap()

        let bufferCount = app.staticTexts["TimelineBufferCount"]
        XCTAssertTrue(bufferCount.waitForExistence(timeout: 2))
        XCTAssertEqual(bufferCount.label, "0")

        app.buttons["BeginScrollButton"].tap()
        app.buttons["TriggerIdlePrefetchButton"].tap()

        XCTAssertFalse(app.buttons["UnifiedMergePill"].exists)
        XCTAssertEqual(bufferCount.label, "0")

        app.buttons["EndScrollButton"].tap()
        // Wait beyond interaction grace period so idle-triggered prefetch can proceed.
        sleep(5)
        app.buttons["TriggerIdlePrefetchButton"].tap()
        XCTAssertTrue(
            waitForNewContentSignal(),
            "Expected new content signal after scrolling stops and idle prefetch is triggered"
        )
    }

    func testMergeAtTopIsScrollStable() {
        let seed = app.buttons["SeedTimelineButton"]
        XCTAssertTrue(seed.waitForExistence(timeout: 2))
        seed.tap()

        app.buttons["TriggerForegroundPrefetchButton"].tap()
        _ = waitForNewContentSignal()

        let anchorId = app.staticTexts["TimelineTopAnchorId"]
        let anchorOffset = app.staticTexts["TimelineTopAnchorOffset"]
        XCTAssertTrue(anchorId.waitForExistence(timeout: 2))
        XCTAssertTrue(anchorOffset.waitForExistence(timeout: 2))

        let initialAnchor = anchorId.label
        let initialOffset = Double(anchorOffset.label) ?? 0

        let mergePill = app.buttons["NewPostsPill"]
        if mergePill.waitForExistence(timeout: 1) {
            mergePill.tap()
        }

        let finalAnchor = anchorId.label
        let finalOffset = Double(anchorOffset.label) ?? 0

        XCTAssertEqual(finalAnchor, initialAnchor)
        XCTAssertLessThan(abs(finalOffset - initialOffset), 1.0)
    }
}

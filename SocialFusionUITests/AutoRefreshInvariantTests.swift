import XCTest

final class AutoRefreshInvariantTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        app = XCUIApplication()
        app.launchArguments = ["UI-Testing", "UI_TESTING"]
        app.launch()
    }

    func testForegroundPrefetchIsBufferOnly() {
        let seed = app.buttons["SeedTimelineButton"]
        XCTAssertTrue(seed.waitForExistence(timeout: 2))
        seed.tap()

        let anchorId = app.staticTexts["TimelineTopAnchorId"]
        XCTAssertTrue(anchorId.waitForExistence(timeout: 2))
        let initialAnchor = anchorId.label

        app.buttons["TriggerForegroundPrefetchButton"].tap()

        let mergePill = app.buttons["NewPostsPill"]
        XCTAssertTrue(mergePill.waitForExistence(timeout: 2))

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
        app.buttons["TriggerIdlePrefetchButton"].tap()

        let mergePill = app.buttons["NewPostsPill"]
        XCTAssertTrue(mergePill.waitForExistence(timeout: 2))
        XCTAssertNotEqual(bufferCount.label, "0")
    }

    func testMergeAtTopIsScrollStable() {
        let seed = app.buttons["SeedTimelineButton"]
        XCTAssertTrue(seed.waitForExistence(timeout: 2))
        seed.tap()

        app.buttons["TriggerForegroundPrefetchButton"].tap()
        let mergePill = app.buttons["NewPostsPill"]
        XCTAssertTrue(mergePill.waitForExistence(timeout: 2))

        let anchorId = app.staticTexts["TimelineTopAnchorId"]
        let anchorOffset = app.staticTexts["TimelineTopAnchorOffset"]
        XCTAssertTrue(anchorId.waitForExistence(timeout: 2))
        XCTAssertTrue(anchorOffset.waitForExistence(timeout: 2))

        let initialAnchor = anchorId.label
        let initialOffset = Double(anchorOffset.label) ?? 0

        mergePill.tap()

        let finalAnchor = anchorId.label
        let finalOffset = Double(anchorOffset.label) ?? 0

        XCTAssertEqual(finalAnchor, initialAnchor)
        XCTAssertLessThan(abs(finalOffset - initialOffset), 1.0)
    }
}


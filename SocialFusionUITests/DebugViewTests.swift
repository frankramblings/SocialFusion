import XCTest

final class DebugViewTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        app = XCUIApplication()
        app.launchArguments = ["UI-Testing"]
        app.launch()
    }

    func testDebugViewNavigation() {
        // Enable debug mode
        app.buttons["Enable Debug Mode"].tap()

        // Open debug view
        app.buttons["Debug"].tap()

        // Verify tabs exist
        XCTAssertTrue(app.tabBars.buttons["Notes"].exists)
        XCTAssertTrue(app.tabBars.buttons["Performance"].exists)
        XCTAssertTrue(app.tabBars.buttons["Errors"].exists)
    }

    func testDebugNotesView() {
        // Enable debug mode
        app.buttons["Enable Debug Mode"].tap()

        // Open debug view
        app.buttons["Debug"].tap()

        // Add a test note
        app.buttons["Add Note"].tap()
        app.textFields["Note Text"].typeText("Test debug note")
        app.buttons["Save"].tap()

        // Verify note appears in list
        XCTAssertTrue(app.staticTexts["Test debug note"].exists)
    }

    func testPerformanceView() {
        // Enable debug mode and performance tracking
        app.buttons["Enable Debug Mode"].tap()
        app.buttons["Enable Performance Tracking"].tap()

        // Open debug view
        app.buttons["Debug"].tap()

        // Switch to performance tab
        app.tabBars.buttons["Performance"].tap()

        // Verify performance metrics are displayed
        XCTAssertTrue(app.staticTexts["Test Operation"].exists)
    }

    func testErrorView() {
        // Enable debug mode
        app.buttons["Enable Debug Mode"].tap()

        // Trigger an error
        app.buttons["Trigger Test Error"].tap()

        // Open debug view
        app.buttons["Debug"].tap()

        // Switch to errors tab
        app.tabBars.buttons["Errors"].tap()

        // Verify error appears in list
        XCTAssertTrue(app.staticTexts["Test error"].exists)
    }

    func testErrorDetailsView() {
        // Enable debug mode
        app.buttons["Enable Debug Mode"].tap()

        // Trigger an error
        app.buttons["Trigger Test Error"].tap()

        // Open debug view
        app.buttons["Debug"].tap()

        // Switch to errors tab
        app.tabBars.buttons["Errors"].tap()

        // Tap on error to show details
        app.staticTexts["Test error"].tap()

        // Verify error details are displayed
        XCTAssertTrue(app.staticTexts["Error Details"].exists)
        XCTAssertTrue(app.staticTexts["Type: network"].exists)
        XCTAssertTrue(app.staticTexts["Severity: high"].exists)
    }

    func testClearDebugData() {
        // Enable debug mode
        app.buttons["Enable Debug Mode"].tap()

        // Add some test data
        app.buttons["Add Note"].tap()
        app.textFields["Note Text"].typeText("Test note")
        app.buttons["Save"].tap()

        app.buttons["Trigger Test Error"].tap()

        // Open debug view
        app.buttons["Debug"].tap()

        // Clear data
        app.buttons["Clear Data"].tap()

        // Verify data is cleared
        XCTAssertFalse(app.staticTexts["Test note"].exists)
        XCTAssertFalse(app.staticTexts["Test error"].exists)
    }
}

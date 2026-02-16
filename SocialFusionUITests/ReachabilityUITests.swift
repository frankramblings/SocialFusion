import XCTest

final class ReachabilityUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  /// On a Pro Max viewport, a compose button should exist in the lower
  /// half of the screen (thumb-reachable zone).
  func testComposeButtonInThumbZone() throws {
    let app = XCUIApplication()
    app.launch()

    // Wait for the app to settle
    let exists = app.buttons["FloatingComposeButton"].waitForExistence(timeout: 5)
    XCTAssertTrue(exists, "Floating compose button must exist on large phone")

    let button = app.buttons["FloatingComposeButton"]
    let screenHeight = app.windows.firstMatch.frame.height

    // The button should be in the lower half of the screen
    XCTAssertGreaterThan(
      button.frame.midY, screenHeight * 0.5,
      "Floating compose button should be in the thumb zone (lower half)"
    )
  }

  /// The floating compose button should open the compose sheet.
  func testFloatingComposeOpensSheet() throws {
    let app = XCUIApplication()
    app.launch()

    let fab = app.buttons["FloatingComposeButton"]
    guard fab.waitForExistence(timeout: 5) else {
      XCTFail("Floating compose button not found")
      return
    }

    fab.tap()

    // Verify compose sheet appeared
    let composeView = app.navigationBars["New Post"].waitForExistence(timeout: 3)
      || app.textViews.firstMatch.waitForExistence(timeout: 3)
    XCTAssertTrue(composeView, "Compose sheet should appear after tapping floating button")
  }
}

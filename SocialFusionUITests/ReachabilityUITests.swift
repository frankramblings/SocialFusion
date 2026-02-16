import XCTest

final class ReachabilityUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  /// The toolbar compose button should be accessible and functional.
  func testComposeButtonExists() throws {
    let app = XCUIApplication()
    app.launch()

    let button = app.buttons["ComposeToolbarButton"]
    XCTAssertTrue(
      button.waitForExistence(timeout: 5),
      "Compose toolbar button must exist"
    )
  }

  /// The compose button should open the compose sheet.
  func testComposeButtonOpensSheet() throws {
    let app = XCUIApplication()
    app.launch()

    let button = app.buttons["ComposeToolbarButton"]
    guard button.waitForExistence(timeout: 5) else {
      XCTFail("Compose button not found")
      return
    }

    button.tap()

    let composeView = app.textViews.firstMatch.waitForExistence(timeout: 3)
    XCTAssertTrue(composeView, "Compose sheet should appear after tapping compose button")
  }
}

import XCTest

final class FullscreenMediaGestureUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  /// Verify that the fullscreen media view can be opened by tapping an image.
  /// This is a baseline test ensuring the viewer works before gesture tuning.
  func testFullscreenMediaViewOpens() throws {
    let app = XCUIApplication()
    app.launch()

    // Wait for timeline to load
    let firstImage = app.images.firstMatch
    guard firstImage.waitForExistence(timeout: 10) else {
      throw XCTSkip("No images in timeline to test fullscreen viewer")
    }

    firstImage.tap()

    // The fullscreen viewer should have a close button
    let closeButton = app.buttons["Close fullscreen viewer"]
    XCTAssertTrue(
      closeButton.waitForExistence(timeout: 3),
      "Fullscreen media viewer should open with a close button"
    )
  }

  /// Verify that the close button in fullscreen media view dismisses it.
  func testFullscreenMediaCloseButton() throws {
    let app = XCUIApplication()
    app.launch()

    let firstImage = app.images.firstMatch
    guard firstImage.waitForExistence(timeout: 10) else {
      throw XCTSkip("No images in timeline to test")
    }

    firstImage.tap()

    let closeButton = app.buttons["Close fullscreen viewer"]
    guard closeButton.waitForExistence(timeout: 3) else {
      XCTFail("Close button not found in fullscreen viewer")
      return
    }

    closeButton.tap()

    // After dismissal, close button should disappear
    XCTAssertFalse(
      closeButton.waitForExistence(timeout: 2),
      "Fullscreen viewer should be dismissed"
    )
  }

  /// Verify swipe-down gesture dismisses the fullscreen media viewer.
  /// The adjusted threshold should still allow intentional vertical dismissal.
  func testVerticalSwipeDismissesFullscreen() throws {
    let app = XCUIApplication()
    app.launch()

    let firstImage = app.images.firstMatch
    guard firstImage.waitForExistence(timeout: 10) else {
      throw XCTSkip("No images in timeline to test")
    }

    firstImage.tap()

    let closeButton = app.buttons["Close fullscreen viewer"]
    guard closeButton.waitForExistence(timeout: 3) else {
      XCTFail("Fullscreen viewer did not open")
      return
    }

    // Perform a strong vertical swipe down to dismiss
    let window = app.windows.firstMatch
    let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
    let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
    start.press(forDuration: 0.05, thenDragTo: end)

    // Verify dismissal
    XCTAssertFalse(
      closeButton.waitForExistence(timeout: 3),
      "Vertical swipe should dismiss fullscreen viewer"
    )
  }
}

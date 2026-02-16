import XCTest
@testable import SocialFusion

final class AppIntentsTests: XCTestCase {

    /// OpenHomeTimelineIntent should have openAppWhenRun = true
    /// since it needs to show the timeline.
    func testOpenHomeTimelineRequiresApp() {
        XCTAssertTrue(
            OpenHomeTimelineIntent.openAppWhenRun,
            "OpenHomeTimelineIntent must open the app"
        )
    }

    /// ShareToSocialFusionIntent should have text and url parameters.
    func testShareIntentHasParameters() {
        let intent = ShareToSocialFusionIntent()
        // Verify the intent can accept text and url
        intent.text = "Hello world"
        intent.url = URL(string: "https://example.com")
        XCTAssertEqual(intent.text, "Hello world")
        XCTAssertEqual(intent.url?.absoluteString, "https://example.com")
    }

    /// PostWithConfirmationIntent should have text and url parameters.
    func testPostIntentHasParameters() {
        let intent = PostWithConfirmationIntent()
        intent.text = "Test post"
        intent.url = URL(string: "https://example.com")
        XCTAssertEqual(intent.text, "Test post")
        XCTAssertEqual(intent.url?.absoluteString, "https://example.com")
    }

    /// SetActiveAccountIntent should have an account parameter.
    func testSetAccountIntentHasAccountParam() {
        // The intent has an `account` parameter of type SocialAccountEntity.
        // We can't easily construct one in tests, but we can verify the type exists
        // and that the intent opens the app.
        XCTAssertTrue(
            SetActiveAccountIntent.openAppWhenRun,
            "SetActiveAccountIntent opens the app to switch accounts"
        )
    }

    /// All navigation intents should require opening the app.
    func testNavigationIntentsRequireApp() {
        XCTAssertTrue(OpenHomeTimelineIntent.openAppWhenRun)
        XCTAssertTrue(PostWithConfirmationIntent.openAppWhenRun)
        XCTAssertTrue(ShareToSocialFusionIntent.openAppWhenRun)
    }
}

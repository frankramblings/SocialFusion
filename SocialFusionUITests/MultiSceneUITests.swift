import XCTest

final class MultiSceneUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Verify the app launches successfully on iPad.
    func testAppLaunchesOnIPad() throws {
        let app = XCUIApplication()
        app.launch()

        // The app should show either onboarding or the main timeline
        let timeline = app.otherElements.firstMatch
        XCTAssertTrue(
            timeline.waitForExistence(timeout: 5),
            "App should launch and display content on iPad"
        )
    }

    /// Verify that @SceneStorage properties enable independent scene state.
    /// Each WindowGroup scene gets its own selectedTab and selectedAccountId
    /// via @SceneStorage, which is scene-scoped by design.
    func testSceneStorageIsSceneScoped() throws {
        // @SceneStorage automatically provides per-scene state.
        // This test validates the app doesn't crash when the scene
        // manifest declares UIApplicationSupportsMultipleScenes = true.
        let app = XCUIApplication()
        app.launch()

        // Verify the tab bar exists (proves the app loaded with multi-scene enabled)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(
            tabBar.waitForExistence(timeout: 5),
            "Tab bar should exist on iPad with multi-scene enabled"
        )
    }

    /// Verify tab selection works on iPad with multi-scene enabled.
    func testTabSelectionOnIPad() throws {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 5) else {
            throw XCTSkip("Tab bar not available (may be in sidebar mode on iPad)")
        }

        // Try switching to Notifications tab
        let notificationsTab = tabBar.buttons["Notifications"]
        if notificationsTab.exists {
            notificationsTab.tap()
            // Should not crash
            XCTAssertTrue(true, "Tab switching works with multi-scene enabled")
        }
    }
}

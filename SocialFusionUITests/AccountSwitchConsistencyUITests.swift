import XCTest

final class AccountSwitchConsistencyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        app = XCUIApplication()
        app.launchArguments = ["UI-Testing", "UI_TESTING"]
        app.launch()
    }

    func testSwitchingAccountsKeepsLocalAndServiceSelectionsInSync() {
        let seedButton = app.buttons["SeedAccountSwitchFixturesButton"]
        XCTAssertTrue(seedButton.waitForExistence(timeout: 2), "Expected account fixture seed control")
        seedButton.tap()

        let selectedLocal = app.staticTexts["UITestSelectedAccountId"]
        let selectedService = app.staticTexts["UITestServiceSelectedAccountIds"]
        XCTAssertTrue(selectedLocal.waitForExistence(timeout: 2))
        XCTAssertTrue(selectedService.waitForExistence(timeout: 2))

        let switchMastodon = app.buttons["SwitchToTestMastodonAccountButton"]
        let switchBluesky = app.buttons["SwitchToTestBlueskyAccountButton"]
        let switchAll = app.buttons["SwitchToAllAccountsButton"]

        XCTAssertTrue(switchMastodon.exists)
        XCTAssertTrue(switchBluesky.exists)
        XCTAssertTrue(switchAll.exists)

        switchMastodon.tap()
        XCTAssertEqual(selectedLocal.label, "ui-test-mastodon")
        XCTAssertEqual(selectedService.label, "ui-test-mastodon")

        switchBluesky.tap()
        XCTAssertEqual(selectedLocal.label, "ui-test-bluesky")
        XCTAssertEqual(selectedService.label, "ui-test-bluesky")

        switchAll.tap()
        XCTAssertEqual(selectedLocal.label, "all")
        XCTAssertEqual(selectedService.label, "all")
    }
}

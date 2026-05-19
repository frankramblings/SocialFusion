import XCTest
@testable import SocialFusion

@MainActor
final class AccessibilityPreferencesTests: XCTestCase {
    private let testSuiteName = "AccessibilityPreferencesTests"

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: testSuiteName)
        defaults.removePersistentDomain(forName: testSuiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: testSuiteName)
        super.tearDown()
    }

    func testHighContrastDefaultsOff() {
        let prefs = AccessibilityPreferences(defaults: defaults)
        XCTAssertFalse(prefs.highContrastNetworkIndicators,
                       "High-contrast must default OFF so existing users see no visual change.")
    }

    func testHighContrastPersistsToDefaults() {
        let prefs = AccessibilityPreferences(defaults: defaults)
        prefs.highContrastNetworkIndicators = true
        let reloaded = AccessibilityPreferences(defaults: defaults)
        XCTAssertTrue(reloaded.highContrastNetworkIndicators,
                      "Setting must survive a fresh load (UserDefaults round-trip).")
    }

    func testToggleChangePublishesObjectWillChange() {
        let prefs = AccessibilityPreferences(defaults: defaults)
        let exp = expectation(description: "objectWillChange fires when value flips")
        let cancellable = prefs.objectWillChange.sink { _ in exp.fulfill() }
        prefs.highContrastNetworkIndicators = true
        wait(for: [exp], timeout: 1.0)
        cancellable.cancel()
    }

    func testStorageKeyIsStable() {
        // Locking the key string protects existing users from losing their setting
        // if anyone refactors the property name.
        XCTAssertEqual(AccessibilityPreferences.Keys.highContrastNetworkIndicators,
                       "accessibility.highContrastNetworkIndicators")
    }
}

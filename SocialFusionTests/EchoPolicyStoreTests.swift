import XCTest
@testable import SocialFusion

@MainActor
final class EchoPolicyStoreTests: XCTestCase {
    private let key = "echo-policy-test-key"

    override func setUp() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    func testDefaultIsAskEachTime() {
        let store = EchoPolicyStore(userDefaults: .standard, defaultsKey: key)
        XCTAssertEqual(store.policy, .askEachTime)
    }

    func testSettingPersistsAcrossInstances() {
        let s1 = EchoPolicyStore(userDefaults: .standard, defaultsKey: key)
        s1.policy = .echoOn
        let s2 = EchoPolicyStore(userDefaults: .standard, defaultsKey: key)
        XCTAssertEqual(s2.policy, .echoOn)
    }

    func testInitialDefaultsForFusedReplyStartingState() {
        let s = EchoPolicyStore(userDefaults: .standard, defaultsKey: key)

        s.policy = .echoOn
        XCTAssertEqual(s.initialReplyTargets(originalPlatform: .mastodon),
                       Set([SocialPlatform.mastodon, .bluesky]))

        s.policy = .echoOff
        XCTAssertEqual(s.initialReplyTargets(originalPlatform: .mastodon),
                       Set([SocialPlatform.mastodon]))

        s.policy = .askEachTime
        XCTAssertEqual(s.initialReplyTargets(originalPlatform: .mastodon), [])
    }
}

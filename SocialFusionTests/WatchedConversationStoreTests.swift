import XCTest
@testable import SocialFusion

@MainActor
final class WatchedConversationStoreTests: XCTestCase {
    private let key = "watched-conversations-test-key"

    override func setUp() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    func testWatchAndUnwatchToggle() {
        let store = WatchedConversationStore(userDefaults: .standard, defaultsKey: key)
        let conv = WatchedConversation(rootPostID: "m1", platform: .mastodon, fusedMomentID: "fused:m1+b1")
        XCTAssertFalse(store.isWatching(rootPostID: "m1"))
        store.watch(conv)
        XCTAssertTrue(store.isWatching(rootPostID: "m1"))
        store.unwatch(rootPostID: "m1")
        XCTAssertFalse(store.isWatching(rootPostID: "m1"))
    }

    func testPersistsAcrossInstances() {
        let s1 = WatchedConversationStore(userDefaults: .standard, defaultsKey: key)
        s1.watch(WatchedConversation(rootPostID: "m1", platform: .mastodon, fusedMomentID: nil))
        let s2 = WatchedConversationStore(userDefaults: .standard, defaultsKey: key)
        XCTAssertTrue(s2.isWatching(rootPostID: "m1"))
    }
}

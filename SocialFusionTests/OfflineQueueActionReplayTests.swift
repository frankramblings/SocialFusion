import XCTest
@testable import SocialFusion

@MainActor
final class OfflineQueueActionReplayTests: XCTestCase {
    func testFetchPostIdPrefersPlatformPostId() {
        let action = QueuedAction(
            postId: "local-post-id",
            platformPostId: "109876543210",
            platform: .mastodon,
            type: .like
        )

        XCTAssertEqual(action.fetchPostId, "109876543210")
    }

    func testFetchPostIdFallsBackToPostIdWhenPlatformPostIdMissing() {
        let action = QueuedAction(
            postId: "local-post-id",
            platformPostId: nil,
            platform: .bluesky,
            type: .repost
        )

        XCTAssertEqual(action.fetchPostId, "local-post-id")
    }

    func testQueueActionNormalizesEmptyPlatformPostId() {
        let saveKey = "offline_queue_test_\(UUID().uuidString)"
        let store = OfflineQueueStore(saveKey: saveKey)

        store.queueAction(
            postId: "legacy-post-id",
            platformPostId: "",
            platform: .mastodon,
            type: .like
        )

        XCTAssertEqual(store.queuedActions.count, 1)
        XCTAssertNil(store.queuedActions[0].platformPostId)
        XCTAssertEqual(store.queuedActions[0].fetchPostId, "legacy-post-id")

        UserDefaults.standard.removeObject(forKey: saveKey)
    }

    func testLegacyDecodeWithoutPlatformPostIdUsesPostIdForReplay() throws {
        let legacyJSON = """
        {
          "id": "4DD7ED35-4F91-4C4C-B5B0-A2EF6CBE4898",
          "postId": "legacy-post-id",
          "platform": "mastodon",
          "type": "like",
          "createdAt": 0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(QueuedAction.self, from: legacyJSON)

        XCTAssertNil(decoded.platformPostId)
        XCTAssertEqual(decoded.fetchPostId, "legacy-post-id")
    }
}

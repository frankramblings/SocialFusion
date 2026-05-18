import XCTest
@testable import SocialFusion

@MainActor
final class FusedMomentStoreTests: XCTestCase {
    func testInsertAndLookupByPostID() {
        let store = FusedMomentStore()
        let m = FusedMoment(
            mastodonPostID: "m1", blueskyPostID: "b1",
            authorIdentityKey: "author-1",
            firstSeenAt: Date(), confidence: 0.9
        )
        store.insert([m])
        XCTAssertEqual(store.moment(for: "m1")?.id, m.id)
        XCTAssertEqual(store.moment(for: "b1")?.id, m.id)
        XCTAssertNil(store.moment(for: "nonexistent"))
    }

    func testInsertingSameMomentTwiceIsIdempotent() {
        let store = FusedMomentStore()
        let m = FusedMoment(
            mastodonPostID: "m1", blueskyPostID: "b1",
            authorIdentityKey: "a", firstSeenAt: Date(), confidence: 0.9
        )
        store.insert([m, m])
        XCTAssertEqual(store.allMoments().count, 1)
    }

    func testTwinPostIDLookup() {
        let store = FusedMomentStore()
        let m = FusedMoment(
            mastodonPostID: "m1", blueskyPostID: "b1",
            authorIdentityKey: "a", firstSeenAt: Date(), confidence: 0.9
        )
        store.insert([m])
        XCTAssertEqual(store.twinPostID(for: "m1", on: .mastodon), "b1")
        XCTAssertEqual(store.twinPostID(for: "b1", on: .bluesky), "m1")
    }

    func testPendingBloomFiresOncePerMoment() {
        let store = FusedMomentStore()
        let m = FusedMoment(
            mastodonPostID: "m1", blueskyPostID: "b1",
            authorIdentityKey: "a", firstSeenAt: Date(), confidence: 0.9
        )
        store.insert([m])
        // First read should return true (bloom should play).
        XCTAssertTrue(store.consumePendingBloom(for: m.id))
        // Subsequent reads return false (already consumed).
        XCTAssertFalse(store.consumePendingBloom(for: m.id))
        XCTAssertFalse(store.consumePendingBloom(for: m.id))
    }

    func testConsumePendingBloomForUnknownMomentReturnsFalse() {
        let store = FusedMomentStore()
        XCTAssertFalse(store.consumePendingBloom(for: "fused:unknown+unknown"))
    }

    func testReinsertingMomentDoesNotRePrimeBloom() {
        // Once a moment has been seen on screen (bloom consumed), re-inserting it
        // from a fresh detection pass must not re-prime the bloom — otherwise the
        // glyph would pulse every timeline refresh, which is wrong.
        let store = FusedMomentStore()
        let m = FusedMoment(
            mastodonPostID: "m1", blueskyPostID: "b1",
            authorIdentityKey: "a", firstSeenAt: Date(), confidence: 0.9
        )
        store.insert([m])
        _ = store.consumePendingBloom(for: m.id) // simulate first appearance
        // Detector runs again, re-emits the same moment.
        store.insert([m])
        XCTAssertFalse(store.consumePendingBloom(for: m.id),
                       "Re-inserting an already-known moment must not re-prime the bloom.")
    }

    func testReinsertingUpdatesStoredMomentWithoutRePrimingBloom() {
        // A future detector pass may emit the same pair with refined confidence.
        // The store should:
        //   (a) replace the stored moment with the new version,
        //   (b) NOT re-prime the bloom (timeline already showed it).
        let store = FusedMomentStore()
        let first = FusedMoment(
            mastodonPostID: "m1", blueskyPostID: "b1",
            authorIdentityKey: "a", firstSeenAt: Date(), confidence: 0.80
        )
        store.insert([first])
        _ = store.consumePendingBloom(for: first.id) // simulate first appearance

        let refined = FusedMoment(
            mastodonPostID: "m1", blueskyPostID: "b1",
            authorIdentityKey: "a", firstSeenAt: first.firstSeenAt, confidence: 0.95
        )
        store.insert([refined])

        XCTAssertEqual(store.moment(for: "m1")?.confidence, 0.95,
                       "Re-insertion must update the stored moment so confidence refinement takes effect.")
        XCTAssertFalse(store.consumePendingBloom(for: first.id),
                       "Re-insertion must NOT re-prime the bloom — that's the existing invariant.")
    }
}

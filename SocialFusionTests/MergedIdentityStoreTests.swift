import XCTest
@testable import SocialFusion

@MainActor
final class MergedIdentityStoreTests: XCTestCase {
    func testInsertAndLookupBySide() {
        let store = MergedIdentityStore(userDefaults: makeEphemeralDefaults(), defaultsKey: "k")
        let m = makeMerge()
        store.insert([m])
        XCTAssertEqual(store.merge(forPlatform: .mastodon, accountID: m.mastodon.accountID)?.id, m.id)
        XCTAssertEqual(store.merge(forPlatform: .bluesky, accountID: m.bluesky.accountID)?.id, m.id)
        XCTAssertNil(store.merge(forPlatform: .mastodon, accountID: "nonexistent"))
    }

    func testInsertingSameMergeTwiceIsIdempotent() {
        let store = MergedIdentityStore(userDefaults: makeEphemeralDefaults(), defaultsKey: "k")
        let m = makeMerge()
        store.insert([m, m])
        XCTAssertEqual(store.allMerges().count, 1)
    }

    func testTwinKeyLookup() {
        let store = MergedIdentityStore(userDefaults: makeEphemeralDefaults(), defaultsKey: "k")
        let m = makeMerge()
        store.insert([m])
        let twin = store.twin(forPlatform: .mastodon, accountID: m.mastodon.accountID)
        XCTAssertEqual(twin?.platform, .bluesky)
        XCTAssertEqual(twin?.accountID, m.bluesky.accountID)
    }

    func testUserConfirmIsHigherPrecedenceThanHeuristic() {
        let store = MergedIdentityStore(userDefaults: makeEphemeralDefaults(), defaultsKey: "k")
        let masto = MergedIdentityKey(platform: .mastodon, accountID: "m", handle: "x@mastodon.social")
        let bsky = MergedIdentityKey(platform: .bluesky, accountID: "b", handle: "x.bsky.social")
        let heuristic = MergedIdentity(mastodon: masto, bluesky: bsky,
                                       provenance: .handleConvention, confidence: 0.78)
        store.insert([heuristic])
        store.confirmMerge(mastodon: masto, bluesky: bsky)
        XCTAssertEqual(store.merge(forPlatform: .mastodon, accountID: "m")?.provenance, .userConfirmed)
        XCTAssertEqual(store.merge(forPlatform: .mastodon, accountID: "m")?.confidence, 1.0)
    }

    func testUnmergeRemovesAndTombstones() {
        let store = MergedIdentityStore(userDefaults: makeEphemeralDefaults(), defaultsKey: "k")
        let m = makeMerge()
        store.insert([m])
        store.unmerge(id: m.id)
        XCTAssertNil(store.merge(forPlatform: .mastodon, accountID: m.mastodon.accountID))
        // Re-inserting the same heuristic merge should be blocked by the tombstone.
        store.insert([m])
        XCTAssertNil(store.merge(forPlatform: .mastodon, accountID: m.mastodon.accountID))
    }

    func testUserConfirmedMergePersistsAcrossInstances() {
        let defaults = makeEphemeralDefaults()
        let key = "persist-test-key"
        let masto = MergedIdentityKey(platform: .mastodon, accountID: "m", handle: "x@mastodon.social")
        let bsky = MergedIdentityKey(platform: .bluesky, accountID: "b", handle: "x.bsky.social")

        let s1 = MergedIdentityStore(userDefaults: defaults, defaultsKey: key)
        s1.confirmMerge(mastodon: masto, bluesky: bsky)

        let s2 = MergedIdentityStore(userDefaults: defaults, defaultsKey: key)
        XCTAssertEqual(s2.merge(forPlatform: .mastodon, accountID: "m")?.provenance, .userConfirmed)
    }

    func testUnmergePersistsAcrossInstances() {
        let defaults = makeEphemeralDefaults()
        let key = "tombstone-test-key"
        let m = makeMerge()

        let s1 = MergedIdentityStore(userDefaults: defaults, defaultsKey: key)
        s1.insert([m])
        s1.unmerge(id: m.id)

        let s2 = MergedIdentityStore(userDefaults: defaults, defaultsKey: key)
        s2.insert([m])
        XCTAssertNil(s2.merge(forPlatform: .mastodon, accountID: m.mastodon.accountID))
    }

    // MARK: - Helpers

    private func makeMerge() -> MergedIdentity {
        MergedIdentity(
            mastodon: MergedIdentityKey(platform: .mastodon, accountID: "m1", handle: "x@mastodon.social"),
            bluesky: MergedIdentityKey(platform: .bluesky, accountID: "b1", handle: "x.bsky.social"),
            provenance: .handleConvention,
            confidence: 0.78
        )
    }

    private func makeEphemeralDefaults() -> UserDefaults {
        let suite = "MergedIdentityStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

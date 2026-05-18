import XCTest
@testable import SocialFusion

@MainActor
final class MergedIdentityEndToEndTests: XCTestCase {
    /// Acceptance: a heuristic match flows from the matcher into the store
    /// and back out as a query result.
    func testHeuristicDetectionAndStoreInsertion() {
        let store = MergedIdentityStore(userDefaults: makeEphemeralDefaults(), defaultsKey: "k")
        let matcher = IdentityMatcher()
        let masto = makeProfile(id: "m", username: "gruber@mastodon.social", platform: .mastodon)
        let bsky = makeProfile(id: "b", username: "gruber.bsky.social", platform: .bluesky)
        guard let match = matcher.match(mastodon: masto, bluesky: bsky) else {
            XCTFail("Expected handle-convention match")
            return
        }
        store.insert([match])
        let lookup = store.merge(forPlatform: .mastodon, accountID: "m")
        XCTAssertEqual(lookup?.id, match.id)
        XCTAssertEqual(lookup?.provenance, .handleConvention)
    }

    /// Acceptance: user-confirmed merges persist across store instances and
    /// take precedence over fresh heuristic re-detection.
    func testUserConfirmationPersistsAndTrumpsHeuristic() {
        let defaults = makeEphemeralDefaults()
        let key = "e2e-confirm"
        let masto = MergedIdentityKey(platform: .mastodon, accountID: "m", handle: "gruber@mastodon.social")
        let bsky = MergedIdentityKey(platform: .bluesky, accountID: "b", handle: "gruber.bsky.social")

        let s1 = MergedIdentityStore(userDefaults: defaults, defaultsKey: key)
        s1.confirmMerge(mastodon: masto, bluesky: bsky)
        XCTAssertEqual(s1.merge(forPlatform: .mastodon, accountID: "m")?.provenance, .userConfirmed)

        // New session — heuristic match is re-detected, but user-confirmed wins.
        let s2 = MergedIdentityStore(userDefaults: defaults, defaultsKey: key)
        let heuristic = MergedIdentity(
            mastodon: masto, bluesky: bsky,
            provenance: .handleConvention, confidence: 0.78
        )
        s2.insert([heuristic])
        XCTAssertEqual(s2.merge(forPlatform: .mastodon, accountID: "m")?.provenance, .userConfirmed)
    }

    /// Acceptance: unmerge produces a tombstone that survives across sessions
    /// and blocks heuristic re-detection.
    func testUnmergeTombstonePersistsAcrossSessions() {
        let defaults = makeEphemeralDefaults()
        let key = "e2e-tombstone"
        let merge = MergedIdentity(
            mastodon: MergedIdentityKey(platform: .mastodon, accountID: "m", handle: "x@mastodon.social"),
            bluesky: MergedIdentityKey(platform: .bluesky, accountID: "b", handle: "x.bsky.social"),
            provenance: .handleConvention, confidence: 0.78
        )

        let s1 = MergedIdentityStore(userDefaults: defaults, defaultsKey: key)
        s1.insert([merge])
        s1.unmerge(id: merge.id)
        XCTAssertNil(s1.merge(forPlatform: .mastodon, accountID: "m"))

        let s2 = MergedIdentityStore(userDefaults: defaults, defaultsKey: key)
        s2.insert([merge])
        XCTAssertNil(s2.merge(forPlatform: .mastodon, accountID: "m"))
    }

    /// Acceptance: tombstones apply to the deterministic pair ID regardless
    /// of provenance, but explicit user confirmation overrides.
    func testTombstoneAppliesAcrossProvenances() {
        let store = MergedIdentityStore(userDefaults: makeEphemeralDefaults(), defaultsKey: "k")
        let merge = MergedIdentity(
            mastodon: MergedIdentityKey(platform: .mastodon, accountID: "m", handle: "x@mastodon.social"),
            bluesky: MergedIdentityKey(platform: .bluesky, accountID: "b", handle: "x.bsky.social"),
            provenance: .handleConvention, confidence: 0.78
        )
        store.insert([merge])
        store.unmerge(id: merge.id)

        let verified = MergedIdentity(
            mastodon: MergedIdentityKey(platform: .mastodon, accountID: "m", handle: "x@mastodon.social"),
            bluesky: MergedIdentityKey(platform: .bluesky, accountID: "b", handle: "x.bsky.social"),
            provenance: .verifiedBioCrossLink, confidence: 0.92
        )
        store.insert([verified])
        XCTAssertNil(store.merge(forPlatform: .mastodon, accountID: "m"))

        // But explicit user confirmation overrides the tombstone.
        store.confirmMerge(mastodon: verified.mastodon, bluesky: verified.bluesky)
        XCTAssertEqual(store.merge(forPlatform: .mastodon, accountID: "m")?.provenance, .userConfirmed)
    }

    // MARK: - Helpers

    private func makeProfile(id: String, username: String, platform: SocialPlatform) -> UserProfile {
        UserProfile(
            id: id, username: username, displayName: nil,
            avatarURL: nil, headerURL: nil, bio: nil,
            followersCount: 0, followingCount: 0, statusesCount: 0,
            platform: platform
        )
    }

    private func makeEphemeralDefaults() -> UserDefaults {
        let suite = "MergedIdentityEndToEndTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

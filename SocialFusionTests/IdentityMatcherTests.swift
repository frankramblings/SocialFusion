import XCTest
@testable import SocialFusion

final class IdentityMatcherTests: XCTestCase {
    // MARK: - Handle convention

    func testHandleConventionMatchesOnSharedLocalPart() {
        let matcher = IdentityMatcher()
        let masto = makeProfile(id: "m1", username: "gruber@mastodon.social", platform: .mastodon)
        let bsky = makeProfile(id: "b1", username: "gruber.bsky.social", platform: .bluesky)
        let result = matcher.match(mastodon: masto, bluesky: bsky)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.provenance, .handleConvention)
        XCTAssertEqual(result?.mastodon.handle, "gruber@mastodon.social")
        XCTAssertEqual(result?.bluesky.handle, "gruber.bsky.social")
    }

    func testHandleConventionRejectsMismatchedLocalParts() {
        let matcher = IdentityMatcher()
        let masto = makeProfile(id: "m1", username: "gruber@mastodon.social", platform: .mastodon)
        let bsky = makeProfile(id: "b1", username: "siracusa.bsky.social", platform: .bluesky)
        XCTAssertNil(matcher.match(mastodon: masto, bluesky: bsky))
    }

    func testHandleConventionRejectsUnconventionalDomains() {
        let matcher = IdentityMatcher()
        let masto = makeProfile(id: "m1", username: "alice@some-tiny-instance.example", platform: .mastodon)
        let bsky = makeProfile(id: "b1", username: "alice.bsky.social", platform: .bluesky)
        XCTAssertNil(matcher.match(mastodon: masto, bluesky: bsky))
    }

    func testHandleConventionAcceptsCustomBlueskyDomain() {
        let matcher = IdentityMatcher()
        let masto = makeProfile(id: "m1", username: "alice@example.com", platform: .mastodon)
        let bsky = makeProfile(id: "b1", username: "alice.example.com", platform: .bluesky)
        let result = matcher.match(mastodon: masto, bluesky: bsky)
        XCTAssertEqual(result?.provenance, .handleConvention)
    }

    // MARK: - Verified bio cross-link

    func testVerifiedBioCrossLinkBeatsHandleConvention() {
        let matcher = IdentityMatcher()
        let masto = makeProfile(
            id: "m1",
            username: "different@mastodon.social",
            platform: .mastodon,
            fields: [ProfileField(name: "Bluesky", value: "https://bsky.app/profile/zelda.bsky.social", isVerified: true)]
        )
        let bsky = makeProfile(
            id: "b1",
            username: "zelda.bsky.social",
            platform: .bluesky,
            bio: "I'm @different@mastodon.social on the fediverse."
        )
        let result = matcher.match(mastodon: masto, bluesky: bsky)
        XCTAssertEqual(result?.provenance, .verifiedBioCrossLink)
    }

    func testUnverifiedBioFieldDoesNotMatch() {
        let matcher = IdentityMatcher()
        let masto = makeProfile(
            id: "m1",
            username: "alice@mastodon.social",
            platform: .mastodon,
            fields: [ProfileField(name: "Bluesky", value: "https://bsky.app/profile/bob.bsky.social", isVerified: false)]
        )
        let bsky = makeProfile(id: "b1", username: "bob.bsky.social", platform: .bluesky)
        XCTAssertNil(matcher.match(mastodon: masto, bluesky: bsky))
    }

    func testBlueskyBioWithoutMastodonCounterClaimDoesNotMatch() {
        let matcher = IdentityMatcher()
        let masto = makeProfile(id: "m1", username: "alice@mastodon.social", platform: .mastodon)
        let bsky = makeProfile(
            id: "b1",
            username: "alice.bsky.team",
            platform: .bluesky,
            bio: "Also @alice@mastodon.social"
        )
        XCTAssertNil(matcher.match(mastodon: masto, bluesky: bsky))
    }

    // MARK: - Confidence ordering

    func testConfidenceOrdering() {
        let matcher = IdentityMatcher()

        let verifiedMasto = makeProfile(
            id: "m", username: "x@mastodon.social", platform: .mastodon,
            fields: [ProfileField(name: "BSky", value: "https://bsky.app/profile/x.bsky.social", isVerified: true)]
        )
        let verifiedBsky = makeProfile(
            id: "b", username: "x.bsky.social", platform: .bluesky,
            bio: "I'm @x@mastodon.social"
        )
        let verified = matcher.match(mastodon: verifiedMasto, bluesky: verifiedBsky)

        let convMasto = makeProfile(id: "m", username: "y@mastodon.social", platform: .mastodon)
        let convBsky = makeProfile(id: "b", username: "y.bsky.social", platform: .bluesky)
        let conv = matcher.match(mastodon: convMasto, bluesky: convBsky)

        XCTAssertNotNil(verified)
        XCTAssertNotNil(conv)
        XCTAssertGreaterThan(verified!.confidence, conv!.confidence)
    }

    // MARK: - Helpers

    private func makeProfile(
        id: String,
        username: String,
        platform: SocialPlatform,
        bio: String? = nil,
        fields: [ProfileField]? = nil
    ) -> UserProfile {
        UserProfile(
            id: id,
            username: username,
            displayName: nil,
            avatarURL: nil,
            headerURL: nil,
            bio: bio,
            followersCount: 0,
            followingCount: 0,
            statusesCount: 0,
            platform: platform,
            fields: fields
        )
    }
}

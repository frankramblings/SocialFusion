import XCTest
@testable import SocialFusion

/// Tests for `PostNavigationEnvironment.navigateToPostFusedAware`, the
/// helper that routes a tapped post to either the unified Fused conversation
/// view (when the post participates in a known FusedMoment) or the
/// per-network post detail. Spec Move 2 ("the conversation is the unit")
/// requires this routing wherever a Fused post can be tapped — this test
/// pins the contract so a future change to either branch can't silently
/// drop Fused posts back into the per-network detail.
@MainActor
final class PostNavigationEnvironmentTests: XCTestCase {

    private func makePost(id: String, platform: SocialPlatform = .mastodon) -> Post {
        Post(
            id: id,
            content: "Post \(id)",
            authorName: "Author",
            authorUsername: "author",
            authorProfilePictureURL: "",
            createdAt: Date(),
            platform: platform,
            originalURL: "https://example.com/\(id)",
            platformSpecificId: id
        )
    }

    /// Wait for the deferred-state-update Task inside the navigator to
    /// land its mutation on the main actor before assertions read it.
    /// The navigator sleeps 1ms before publishing to avoid AttributeGraph
    /// cycles; a generous 100ms wait keeps the test stable on slow runners.
    private func waitForDeferredUpdate() async {
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    func testFusedAwareRoutingOpensConversationWhenMomentExists() async {
        let store = FusedMomentStore()
        let moment = FusedMoment(
            mastodonPostID: "m1", blueskyPostID: "b1",
            authorIdentityKey: "author",
            firstSeenAt: Date(), confidence: 0.9
        )
        store.insert([moment])

        let nav = PostNavigationEnvironment()
        nav.navigateToPostFusedAware(makePost(id: "m1"), fusedMomentStore: store)
        await waitForDeferredUpdate()

        XCTAssertEqual(nav.selectedFusedMoment?.id, moment.id,
                       "Tapping a known Fused post must route to the unified conversation view.")
        XCTAssertNil(nav.selectedPost,
                     "Per-network detail must NOT also be selected — that would be a double-routing bug.")
    }

    func testFusedAwareRoutingFallsBackToPostDetailWhenNoMoment() async {
        let store = FusedMomentStore()
        let nav = PostNavigationEnvironment()

        nav.navigateToPostFusedAware(makePost(id: "standalone"), fusedMomentStore: store)
        await waitForDeferredUpdate()

        XCTAssertEqual(nav.selectedPost?.id, "standalone",
                       "Non-Fused posts must continue to route through the per-network detail.")
        XCTAssertNil(nav.selectedFusedMoment,
                     "Non-Fused posts must not select a moment.")
    }

    func testFusedAwareRoutingFollowsOriginalPostForBoosts() async {
        // A reposted Fused post: the wrapper post has its own ID, but the
        // moment lives on the original. The router has to look through
        // `originalPost` or it'd miss the moment and fall back to detail.
        let store = FusedMomentStore()
        let moment = FusedMoment(
            mastodonPostID: "original-m", blueskyPostID: "original-b",
            authorIdentityKey: "author",
            firstSeenAt: Date(), confidence: 0.9
        )
        store.insert([moment])

        let original = makePost(id: "original-m")
        let wrapper = Post(
            id: "wrapper",
            content: "",
            authorName: "Booster",
            authorUsername: "booster",
            authorProfilePictureURL: "",
            createdAt: Date(),
            platform: .mastodon,
            originalURL: "",
            originalPost: original,
            platformSpecificId: "wrapper"
        )

        let nav = PostNavigationEnvironment()
        nav.navigateToPostFusedAware(wrapper, fusedMomentStore: store)
        await waitForDeferredUpdate()

        XCTAssertEqual(nav.selectedFusedMoment?.id, moment.id,
                       "A boosted/reposted Fused post should still resolve to the unified view via its originalPost.")
    }
}

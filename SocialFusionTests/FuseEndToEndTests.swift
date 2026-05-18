import XCTest
@testable import SocialFusion

@MainActor
final class FuseEndToEndTests: XCTestCase {
    /// Acceptance: a cross-posted moment in the input buffer surfaces as a
    /// Fused post in the store after detection + insertion.
    func testNormalizationPipelineDetectsAndStoresFusedMoment() {
        let store = FusedMomentStore()
        let detector = FusedMomentDetector()
        let now = Date()
        let posts = [
            makePost(id: "m1", platform: .mastodon,
                     content: "Hello world, this is a test of cross-poster detection!",
                     authorId: "author-1", createdAt: now),
            makePost(id: "b1", platform: .bluesky,
                     content: "Hello world, this is a test of cross-poster detection!",
                     authorId: "author-1", createdAt: now.addingTimeInterval(60))
        ]
        let identityMap: FusedMomentDetector.IdentityKeyMap = [
            "mastodon:author-1": "merged:test-identity",
            "bluesky:author-1": "merged:test-identity"
        ]
        let detected = detector.detect(in: posts, identityMap: identityMap)
        store.insert(detected)
        XCTAssertNotNil(store.moment(for: "m1"))
        XCTAssertNotNil(store.moment(for: "b1"))
    }

    /// Acceptance: per-post composer Send-button label reflects all 4 toggle states.
    func testEchoComposerSendButtonLabelStates() {
        let vm = EchoComposeViewModel(
            moment: FusedMoment(mastodonPostID: "m", blueskyPostID: "b",
                                authorIdentityKey: "a", firstSeenAt: Date(), confidence: 0.9),
            initialTargets: [.mastodon, .bluesky]
        )
        XCTAssertEqual(vm.sendActionLabel, "Reply to both")
        vm.targets = [.mastodon]
        XCTAssertEqual(vm.sendActionLabel, "Reply on Mastodon")
        vm.targets = [.bluesky]
        XCTAssertEqual(vm.sendActionLabel, "Reply on Bluesky")
        vm.targets = []
        XCTAssertEqual(vm.sendActionLabel, "Reply…")
    }

    /// Acceptance: onboarding choice persists across store instances.
    func testEchoPolicyPersistsAcrossInstances() {
        let key = "echo-policy-e2e-key"
        UserDefaults.standard.removeObject(forKey: key)
        let s1 = EchoPolicyStore(userDefaults: .standard, defaultsKey: key)
        s1.policy = .echoOn
        let s2 = EchoPolicyStore(userDefaults: .standard, defaultsKey: key)
        XCTAssertEqual(s2.policy, .echoOn)
    }

    /// Acceptance: WatchedConversationStore round-trips through UserDefaults.
    func testWatchListPersists() {
        let key = "watched-e2e-key"
        UserDefaults.standard.removeObject(forKey: key)
        let s1 = WatchedConversationStore(userDefaults: .standard, defaultsKey: key)
        s1.watch(WatchedConversation(rootPostID: "m1", platform: .mastodon, fusedMomentID: nil))
        let s2 = WatchedConversationStore(userDefaults: .standard, defaultsKey: key)
        XCTAssertTrue(s2.isWatching(rootPostID: "m1"))
    }

    // MARK: - Helpers

    private func makePost(
        id: String, platform: SocialPlatform, content: String,
        authorId: String, createdAt: Date
    ) -> Post {
        // Argument order matches Post.init declaration: authorId sits between
        // authorUsername and authorProfilePictureURL. See FusedMomentDetectorTests
        // for the same pattern.
        Post(
            id: id,
            content: content,
            authorName: "Test",
            authorUsername: "t",
            authorId: authorId,
            authorProfilePictureURL: "",
            createdAt: createdAt,
            platform: platform,
            originalURL: "",
            attachments: [],
            mentions: [],
            tags: []
        )
    }
}

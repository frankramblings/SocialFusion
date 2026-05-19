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

    /// Acceptance, integration: dispatcher + optimistic insertion together —
    /// a successful dual-target Echo send lands two new replies in the
    /// view model's merged stream, sorted chronologically with whatever
    /// was already loaded. Mirrors what the production FusedConversationView
    /// onSend closure does end-to-end (minus the live service calls).
    func testFullEchoSendPipelineOptimisticallyInsertsBothReplies() async {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let mastoRoot = makePost(id: "m1", platform: .mastodon,
                                 content: "anchor", authorId: "a1", createdAt: base)
        let bskyRoot = makePost(id: "b1", platform: .bluesky,
                                content: "anchor", authorId: "a1", createdAt: base)
        let existingReply = makePost(id: "m_r0", platform: .mastodon,
                                     content: "thread starter", authorId: "a2",
                                     createdAt: base.addingTimeInterval(60))

        let fetcher = StubThreadFetcher(
            mastodonResult: .success((root: mastoRoot, replies: [existingReply])),
            blueskyResult: .success((root: bskyRoot, replies: []))
        )
        let vm = FusedConversationViewModel(
            moment: FusedMoment(
                mastodonPostID: "m1", blueskyPostID: "b1",
                authorIdentityKey: "a1", firstSeenAt: base, confidence: 0.9),
            threadFetcher: fetcher
        )
        await vm.load()
        XCTAssertEqual(vm.replies.count, 1, "Sanity: pre-send state is one existing reply")

        // Simulate the dispatcher's closures landing two new replies
        // newer than the existing reply.
        let mNew = makePost(id: "m_new", platform: .mastodon,
                            content: "echo reply", authorId: "me",
                            createdAt: base.addingTimeInterval(120))
        let bNew = makePost(id: "b_new", platform: .bluesky,
                            content: "echo reply", authorId: "me",
                            createdAt: base.addingTimeInterval(121))

        let result = await sendEchoedReply(
            targets: [.mastodon, .bluesky],
            sendToMastodon: { vm.insertSentReply(mNew) },
            sendToBluesky: { vm.insertSentReply(bNew) }
        )

        XCTAssertEqual(result.succeeded, [.mastodon, .bluesky])
        XCTAssertEqual(result.failed, [])
        XCTAssertEqual(
            vm.replies.map(\.id), ["m_r0", "m_new", "b_new"],
            "Both sent replies must be appended in chronological order after the existing thread starter.")
    }

    // MARK: - Helpers for the integration test

    /// Local stub matching `FusedConversationThreadFetching`. Kept private
    /// to this file so the production adapter isn't imported into tests.
    @MainActor
    private final class StubThreadFetcher: FusedConversationThreadFetching {
        let mastodonResult: Result<(root: Post, replies: [Post]), Error>
        let blueskyResult: Result<(root: Post, replies: [Post]), Error>

        init(
            mastodonResult: Result<(root: Post, replies: [Post]), Error>,
            blueskyResult: Result<(root: Post, replies: [Post]), Error>
        ) {
            self.mastodonResult = mastodonResult
            self.blueskyResult = blueskyResult
        }

        func fetchThread(postID: String, platform: SocialPlatform) async throws -> (root: Post, replies: [Post]) {
            switch platform {
            case .mastodon: return try mastodonResult.get()
            case .bluesky: return try blueskyResult.get()
            }
        }
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

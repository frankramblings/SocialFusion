import XCTest
@testable import SocialFusion

@MainActor
final class PostActionStoreTests: XCTestCase {

    private func makePost(id: String = UUID().uuidString, platform: SocialPlatform = .mastodon)
        -> Post
    {
        Post(
            id: id,
            content: "Test",
            authorName: "Tester",
            authorUsername: "tester",
            authorProfilePictureURL: "",
            createdAt: Date(),
            platform: platform,
            originalURL: "https://example.com",
            attachments: []
        )
    }

    func testOptimisticLikeIncrementsState() {
        let store = PostActionStore()
        let post = makePost()

        store.ensureState(for: post)
        let previous = store.optimisticLike(for: post.stableId)

        XCTAssertNotNil(previous)
        let updated = store.actions[post.stableId]
        XCTAssertEqual(updated?.isLiked, true)
        XCTAssertEqual(updated?.likeCount, previous!.likeCount + 1)
    }

    func testOptimisticRepostSetsState() {
        let store = PostActionStore()
        let post = makePost()
        store.ensureState(for: post)

        _ = store.optimisticRepost(for: post.stableId)

        XCTAssertEqual(store.actions[post.stableId]?.isReposted, true)
    }

    func testReconcileOverridesState() {
        let store = PostActionStore()
        let post = makePost()
        store.ensureState(for: post)

        let serverState = PostActionState(
            stableId: post.stableId,
            platform: post.platform,
            isLiked: true,
            isReposted: true,
            isReplied: false,
            isQuoted: false,
            likeCount: 42,
            repostCount: 7,
            replyCount: 3
        )

        store.reconcile(from: serverState)

        let reconciled = store.actions[post.stableId]
        XCTAssertEqual(reconciled?.isLiked, true)
        XCTAssertEqual(reconciled?.likeCount, 42)
        XCTAssertEqual(reconciled?.repostCount, 7)
        XCTAssertEqual(reconciled?.replyCount, 3)
    }

    func testPendingAndInflightFlags() {
        let store = PostActionStore()
        let post = makePost()
        store.ensureState(for: post)

        store.setPending(true, for: post.stableId)
        XCTAssertTrue(store.pendingKeys.contains(post.stableId))

        store.setPending(false, for: post.stableId)
        XCTAssertFalse(store.pendingKeys.contains(post.stableId))

        store.setInflight(true, for: post.stableId)
        XCTAssertTrue(store.inflightKeys.contains(post.stableId))

        store.setInflight(false, for: post.stableId)
        XCTAssertFalse(store.inflightKeys.contains(post.stableId))
    }

    func testRegisterLocalReplyIncrementsCount() {
        let store = PostActionStore()
        let post = makePost()
        store.ensureState(for: post)

        store.registerLocalReply(for: post.stableId)
        XCTAssertEqual(store.actions[post.stableId]?.replyCount, post.replyCount + 1)
    }
}


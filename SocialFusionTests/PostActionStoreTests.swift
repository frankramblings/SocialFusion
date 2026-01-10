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

    // MARK: - Menu Label State Flip Tests

    func testMenuLabelFlipsForFollow() {
        let state = PostActionState(
            stableId: "test",
            platform: .mastodon,
            isLiked: false,
            isReposted: false,
            isReplied: false,
            isQuoted: false,
            likeCount: 0,
            repostCount: 0,
            replyCount: 0,
            isFollowingAuthor: false
        )

        XCTAssertEqual(PostAction.follow.menuLabel(for: state), "Follow")

        var followingState = state
        followingState.isFollowingAuthor = true
        XCTAssertEqual(PostAction.follow.menuLabel(for: followingState), "Unfollow")
    }

    func testMenuLabelFlipsForMute() {
        let state = PostActionState(
            stableId: "test",
            platform: .mastodon,
            isLiked: false,
            isReposted: false,
            isReplied: false,
            isQuoted: false,
            likeCount: 0,
            repostCount: 0,
            replyCount: 0,
            isMutedAuthor: false
        )

        XCTAssertEqual(PostAction.mute.menuLabel(for: state), "Mute")

        var mutedState = state
        mutedState.isMutedAuthor = true
        XCTAssertEqual(PostAction.mute.menuLabel(for: mutedState), "Unmute")
    }

    func testMenuLabelFlipsForBlock() {
        let state = PostActionState(
            stableId: "test",
            platform: .mastodon,
            isLiked: false,
            isReposted: false,
            isReplied: false,
            isQuoted: false,
            likeCount: 0,
            repostCount: 0,
            replyCount: 0,
            isBlockedAuthor: false
        )

        XCTAssertEqual(PostAction.block.menuLabel(for: state), "Block")

        var blockedState = state
        blockedState.isBlockedAuthor = true
        XCTAssertEqual(PostAction.block.menuLabel(for: blockedState), "Unblock")
    }

    func testMenuIconFlipsForFollow() {
        let state = PostActionState(
            stableId: "test",
            platform: .mastodon,
            isLiked: false,
            isReposted: false,
            isReplied: false,
            isQuoted: false,
            likeCount: 0,
            repostCount: 0,
            replyCount: 0,
            isFollowingAuthor: false
        )

        XCTAssertEqual(PostAction.follow.menuSystemImage(for: state), "person.badge.plus")

        var followingState = state
        followingState.isFollowingAuthor = true
        XCTAssertEqual(PostAction.follow.menuSystemImage(for: followingState), "person.badge.minus")
    }

    // MARK: - Author-Level Propagation Tests

    private func makePostWithAuthor(id: String, authorId: String, platform: SocialPlatform = .mastodon) -> Post {
        Post(
            id: id,
            content: "Test",
            authorName: "Tester",
            authorUsername: "tester",
            authorId: authorId,
            authorProfilePictureURL: "",
            createdAt: Date(),
            platform: platform,
            originalURL: "https://example.com",
            attachments: []
        )
    }

    func testOptimisticFollowPropagatestoSiblingPosts() {
        let store = PostActionStore()

        // Create multiple posts from the same author
        let post1 = makePostWithAuthor(id: "1", authorId: "author-123")
        let post2 = makePostWithAuthor(id: "2", authorId: "author-123")
        let post3 = makePostWithAuthor(id: "3", authorId: "author-456") // Different author

        store.ensureState(for: post1)
        store.ensureState(for: post2)
        store.ensureState(for: post3)

        // Follow via post1
        _ = store.optimisticFollow(for: post1.stableId, shouldFollow: true)

        // Both post1 and post2 should now show following
        XCTAssertTrue(store.actions[post1.stableId]?.isFollowingAuthor == true)
        XCTAssertTrue(store.actions[post2.stableId]?.isFollowingAuthor == true)

        // post3 (different author) should not be affected
        XCTAssertTrue(store.actions[post3.stableId]?.isFollowingAuthor == false)
    }

    func testOptimisticMutePropagatestoSiblingPosts() {
        let store = PostActionStore()

        let post1 = makePostWithAuthor(id: "1", authorId: "author-123")
        let post2 = makePostWithAuthor(id: "2", authorId: "author-123")

        store.ensureState(for: post1)
        store.ensureState(for: post2)

        // Mute via post1
        _ = store.optimisticMute(for: post1.stableId, shouldMute: true)

        // Both posts should show muted
        XCTAssertTrue(store.actions[post1.stableId]?.isMutedAuthor == true)
        XCTAssertTrue(store.actions[post2.stableId]?.isMutedAuthor == true)
    }

    func testOptimisticBlockPropagatestoSiblingPosts() {
        let store = PostActionStore()

        let post1 = makePostWithAuthor(id: "1", authorId: "author-123")
        let post2 = makePostWithAuthor(id: "2", authorId: "author-123")

        store.ensureState(for: post1)
        store.ensureState(for: post2)

        // Block via post1
        _ = store.optimisticBlock(for: post1.stableId, shouldBlock: true)

        // Both posts should show blocked
        XCTAssertTrue(store.actions[post1.stableId]?.isBlockedAuthor == true)
        XCTAssertTrue(store.actions[post2.stableId]?.isBlockedAuthor == true)
    }

    func testReconcilePropagatesToSiblingPosts() {
        let store = PostActionStore()

        let post1 = makePostWithAuthor(id: "1", authorId: "author-123")
        let post2 = makePostWithAuthor(id: "2", authorId: "author-123")

        store.ensureState(for: post1)
        store.ensureState(for: post2)

        // Reconcile with server state showing following
        let serverState = PostActionState(
            stableId: post1.stableId,
            platform: post1.platform,
            isLiked: false,
            isReposted: false,
            isReplied: false,
            isQuoted: false,
            likeCount: 0,
            repostCount: 0,
            replyCount: 0,
            isFollowingAuthor: true,
            isMutedAuthor: false,
            isBlockedAuthor: false
        )

        store.reconcile(from: serverState)

        // Both posts should reflect following state
        XCTAssertTrue(store.actions[post1.stableId]?.isFollowingAuthor == true)
        XCTAssertTrue(store.actions[post2.stableId]?.isFollowingAuthor == true)
    }

    func testUnfollowPropagatestoSiblingPosts() {
        let store = PostActionStore()

        let post1 = makePostWithAuthor(id: "1", authorId: "author-123")
        let post2 = makePostWithAuthor(id: "2", authorId: "author-123")

        store.ensureState(for: post1)
        store.ensureState(for: post2)

        // First follow
        _ = store.optimisticFollow(for: post1.stableId, shouldFollow: true)
        XCTAssertTrue(store.actions[post1.stableId]?.isFollowingAuthor == true)
        XCTAssertTrue(store.actions[post2.stableId]?.isFollowingAuthor == true)

        // Then unfollow
        _ = store.optimisticFollow(for: post2.stableId, shouldFollow: false)
        XCTAssertTrue(store.actions[post1.stableId]?.isFollowingAuthor == false)
        XCTAssertTrue(store.actions[post2.stableId]?.isFollowingAuthor == false)
    }
}


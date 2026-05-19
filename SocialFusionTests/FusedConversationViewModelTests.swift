import XCTest

@testable import SocialFusion

@MainActor
final class FusedConversationViewModelTests: XCTestCase {

    // MARK: Tests

    func testStreamsRepliesAsEachSideResolves() async throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let mastoRoot = makePost(id: "m1", platform: .mastodon, createdAt: base)
        let mastoReply = makePost(
            id: "m_r1", platform: .mastodon,
            createdAt: base.addingTimeInterval(1))
        let bskyRoot = makePost(id: "b1", platform: .bluesky, createdAt: base)
        let bskyReply = makePost(
            id: "b_r1", platform: .bluesky,
            createdAt: base.addingTimeInterval(2))

        let fetcher = StubThreadFetcher(
            mastodonResult: .success((root: mastoRoot, replies: [mastoReply])),
            blueskyResult: .success((root: bskyRoot, replies: [bskyReply]))
        )

        let vm = FusedConversationViewModel(
            moment: FusedMoment(
                mastodonPostID: "m1",
                blueskyPostID: "b1",
                authorIdentityKey: "a",
                firstSeenAt: base,
                confidence: 0.9
            ),
            threadFetcher: fetcher
        )

        await vm.load()

        XCTAssertEqual(
            vm.replies.map(\.id), ["m_r1", "b_r1"],
            "Replies must be merged in createdAt-ascending order across both sides.")
        XCTAssertEqual(vm.mastodonStatus, .loaded)
        XCTAssertEqual(vm.blueskyStatus, .loaded)
        XCTAssertNotNil(vm.rootPost, "Root post should be set after either side resolves.")
    }

    func testInsertSentReplyAppendsAndSortsChronologically() async {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let mastoRoot = makePost(id: "m1", platform: .mastodon, createdAt: base)
        let existingReply = makePost(
            id: "m_r1", platform: .mastodon,
            createdAt: base.addingTimeInterval(1))

        let fetcher = StubThreadFetcher(
            mastodonResult: .success((root: mastoRoot, replies: [existingReply])),
            blueskyResult: .success((root: mastoRoot, replies: []))
        )
        let vm = FusedConversationViewModel(
            moment: FusedMoment(
                mastodonPostID: "m1", blueskyPostID: "b1",
                authorIdentityKey: "a", firstSeenAt: base, confidence: 0.9),
            threadFetcher: fetcher
        )
        await vm.load()

        // Send a reply timestamped between root and the existing reply.
        let sent = makePost(
            id: "m_new",
            platform: .mastodon,
            createdAt: base.addingTimeInterval(0.5))
        vm.insertSentReply(sent)

        XCTAssertEqual(
            vm.replies.map(\.id), ["m_new", "m_r1"],
            "Optimistic insert must place the sent reply in createdAt order, not at the end.")
    }

    func testInsertSentReplyIsIdempotentOnDuplicateID() async {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let mastoRoot = makePost(id: "m1", platform: .mastodon, createdAt: base)
        let reply = makePost(
            id: "m_r1", platform: .mastodon,
            createdAt: base.addingTimeInterval(1))

        let fetcher = StubThreadFetcher(
            mastodonResult: .success((root: mastoRoot, replies: [reply])),
            blueskyResult: .success((root: mastoRoot, replies: []))
        )
        let vm = FusedConversationViewModel(
            moment: FusedMoment(
                mastodonPostID: "m1", blueskyPostID: "b1",
                authorIdentityKey: "a", firstSeenAt: base, confidence: 0.9),
            threadFetcher: fetcher
        )
        await vm.load()
        XCTAssertEqual(vm.replies.count, 1)

        // A parallel server poll could land the same reply just after the
        // optimistic insert. The reinsert must be a no-op so the user
        // doesn't see their own reply duplicated.
        vm.insertSentReply(reply)
        XCTAssertEqual(
            vm.replies.count, 1,
            "Inserting a reply whose id already exists must be a no-op.")
    }

    /// Retry contract: a side that previously failed should re-fetch
    /// and, on success, flip to `.loaded` and merge its replies into
    /// the stream. Pins the recovery path the Fused outage banner's
    /// Retry button and the rotor action depend on.
    func testRetrySucceedsAfterFailure() async {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let mastoRoot = makePost(id: "m1", platform: .mastodon, createdAt: base)
        let mastoReply = makePost(
            id: "m_r1", platform: .mastodon,
            createdAt: base.addingTimeInterval(1))
        let bskyRoot = makePost(id: "b1", platform: .bluesky, createdAt: base)
        let bskyReply = makePost(
            id: "b_r1", platform: .bluesky,
            createdAt: base.addingTimeInterval(2))

        let fetcher = MutableStubThreadFetcher(
            mastodonResult: .success((root: mastoRoot, replies: [mastoReply])),
            blueskyResult: .failure(TestError.boom)
        )

        let vm = FusedConversationViewModel(
            moment: FusedMoment(
                mastodonPostID: "m1",
                blueskyPostID: "b1",
                authorIdentityKey: "a",
                firstSeenAt: base,
                confidence: 0.9
            ),
            threadFetcher: fetcher
        )

        await vm.load()
        guard case .failed = vm.blueskyStatus else {
            return XCTFail("Precondition: Bluesky side must be failed before retry.")
        }

        // Bluesky comes back online for the retry call.
        fetcher.blueskyResult = .success((root: bskyRoot, replies: [bskyReply]))
        await vm.retry(.bluesky)

        XCTAssertEqual(vm.blueskyStatus, .loaded)
        XCTAssertEqual(vm.replies.map(\.id).sorted(), ["b_r1", "m_r1"],
                       "Bluesky reply must merge into the stream after retry.")
    }

    func testHandlesOneSideOutageGracefully() async {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let mastoRoot = makePost(id: "m1", platform: .mastodon, createdAt: base)
        let mastoReply = makePost(
            id: "m_r1", platform: .mastodon,
            createdAt: base.addingTimeInterval(1))

        let fetcher = StubThreadFetcher(
            mastodonResult: .success((root: mastoRoot, replies: [mastoReply])),
            blueskyResult: .failure(TestError.boom)
        )

        let vm = FusedConversationViewModel(
            moment: FusedMoment(
                mastodonPostID: "m1",
                blueskyPostID: "b1",
                authorIdentityKey: "a",
                firstSeenAt: base,
                confidence: 0.9
            ),
            threadFetcher: fetcher
        )

        await vm.load()

        XCTAssertEqual(
            vm.replies.map(\.id), ["m_r1"],
            "Working side must still render when the other side fails.")
        XCTAssertEqual(vm.mastodonStatus, .loaded)
        if case .failed = vm.blueskyStatus {
            // Expected outcome.
        } else {
            XCTFail("Bluesky side should be in .failed status, got \(vm.blueskyStatus)")
        }
    }

    // MARK: Helpers

    /// Mirrors the `makePost` shape used by sibling Fuse tests (e.g.
    /// `FusedMomentDetectorTests`). The `Post.init` declaration lives at
    /// `SocialFusion/Models/Post.swift:764+` — argument order must match.
    private func makePost(
        id: String,
        platform: SocialPlatform,
        createdAt: Date
    ) -> Post {
        Post(
            id: id,
            content: "test \(id)",
            authorName: "Test Author",
            authorUsername: "testuser",
            authorId: "author-\(platform.rawValue)",
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

// MARK: - Stub thread fetcher

private enum TestError: Error { case boom }

/// In-memory stub for `FusedConversationThreadFetching`. Returns
/// platform-scoped canned results so each test can shape success / failure
/// independently per side.
@MainActor
private final class StubThreadFetcher: FusedConversationThreadFetching {
    typealias FetchResult = Result<(root: Post, replies: [Post]), Error>

    let mastodonResult: FetchResult
    let blueskyResult: FetchResult

    init(mastodonResult: FetchResult, blueskyResult: FetchResult) {
        self.mastodonResult = mastodonResult
        self.blueskyResult = blueskyResult
    }

    func fetchThread(
        postID: String,
        platform: SocialPlatform
    ) async throws -> (root: Post, replies: [Post]) {
        switch platform {
        case .mastodon: return try mastodonResult.get()
        case .bluesky: return try blueskyResult.get()
        }
    }
}

/// Same shape as `StubThreadFetcher` but the per-platform results are
/// mutable, so tests can change the canned outcome between successive
/// `fetchThread` calls — needed to simulate an outage that resolves
/// before the user retries.
@MainActor
private final class MutableStubThreadFetcher: FusedConversationThreadFetching {
    typealias FetchResult = Result<(root: Post, replies: [Post]), Error>

    var mastodonResult: FetchResult
    var blueskyResult: FetchResult

    init(mastodonResult: FetchResult, blueskyResult: FetchResult) {
        self.mastodonResult = mastodonResult
        self.blueskyResult = blueskyResult
    }

    func fetchThread(
        postID: String,
        platform: SocialPlatform
    ) async throws -> (root: Post, replies: [Post]) {
        switch platform {
        case .mastodon: return try mastodonResult.get()
        case .bluesky: return try blueskyResult.get()
        }
    }
}

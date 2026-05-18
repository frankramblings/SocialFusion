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

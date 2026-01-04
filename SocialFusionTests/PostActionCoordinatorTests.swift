import XCTest
@testable import SocialFusion

@MainActor
final class PostActionCoordinatorTests: XCTestCase {

    final class MockPostActionService: PostActionNetworking {
        var likeCalls = 0
        var unlikeCalls = 0
        var queuedStates: [PostActionState] = []
        var errorSequence: [Error] = []

        func like(post: Post) async throws -> PostActionState {
            likeCalls += 1
            if let error = dequeueError() { throw error }
            return dequeueState(for: post) ?? post.makeActionState(timestamp: Date())
        }

        func unlike(post: Post) async throws -> PostActionState {
            unlikeCalls += 1
            if let error = dequeueError() { throw error }
            return dequeueState(for: post) ?? post.makeActionState(timestamp: Date())
        }

        func repost(post: Post) async throws -> PostActionState {
            return try await like(post: post)
        }

        func unrepost(post: Post) async throws -> PostActionState {
            return try await unlike(post: post)
        }

        func fetchActions(for post: Post) async throws -> PostActionState {
            return post.makeActionState(timestamp: Date())
        }

        private func dequeueState(for post: Post) -> PostActionState? {
            if !queuedStates.isEmpty {
                return queuedStates.removeFirst()
            }
            return PostActionState(post: post)
        }

        private func dequeueError() -> Error? {
            if !errorSequence.isEmpty {
                return errorSequence.removeFirst()
            }
            return nil
        }
    }

    private func makePost(id: String = UUID().uuidString) -> Post {
        Post(
            id: id,
            content: "Post",
            authorName: "Author",
            authorUsername: "author",
            authorProfilePictureURL: "",
            createdAt: Date(),
            platform: .mastodon,
            originalURL: "https://example.com",
            attachments: []
        )
    }

    override func setUp() {
        super.setUp()
        SimpleEdgeCaseMonitor.shared.isNetworkAvailable = true
    }

    override func tearDown() {
        SimpleEdgeCaseMonitor.shared.isNetworkAvailable = true
        super.tearDown()
    }

    func testToggleLikeOptimisticallyUpdatesStore() async {
        let store = PostActionStore()
        let service = MockPostActionService()
        let coordinator = PostActionCoordinator(
            store: store,
            service: service,
            networkMonitor: SimpleEdgeCaseMonitor.shared
        )

        let post = makePost()
        service.queuedStates = [
            PostActionState(
                stableId: post.stableId,
                platform: post.platform,
                isLiked: true,
                isReposted: false,
                isReplied: false,
                isQuoted: false,
                likeCount: 10,
                repostCount: 1,
                replyCount: 2
            )
        ]

        coordinator.toggleLike(for: post)

        let expectation = expectation(description: "like completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if store.actions[post.stableId]?.isLiked == true {
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(service.likeCalls, 1)
        XCTAssertEqual(store.actions[post.stableId]?.likeCount, 10)
        XCTAssertFalse(store.pendingKeys.contains(post.stableId))
    }

    func testOfflineActionQueuesUntilNetworkReturns() {
        let store = PostActionStore()
        let service = MockPostActionService()
        let coordinator = PostActionCoordinator(
            store: store,
            service: service,
            networkMonitor: SimpleEdgeCaseMonitor.shared
        )

        let post = makePost()
        SimpleEdgeCaseMonitor.shared.isNetworkAvailable = false

        coordinator.toggleLike(for: post)

        XCTAssertTrue(store.pendingKeys.contains(post.stableId))
        XCTAssertEqual(service.likeCalls, 0)

        SimpleEdgeCaseMonitor.shared.isNetworkAvailable = true

        let expectation = expectation(description: "offline like flushed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if service.likeCalls > 0 {
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.5)
        XCTAssertTrue(service.likeCalls > 0)
        XCTAssertFalse(store.pendingKeys.contains(post.stableId))
    }
}


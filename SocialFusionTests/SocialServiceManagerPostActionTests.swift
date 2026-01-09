import XCTest
import Combine
@testable import SocialFusion

@MainActor
final class SocialServiceManagerPostActionTests: XCTestCase {
    var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        FeatureFlagManager.shared.enableFeature(.postActionsV2)
        SimpleEdgeCaseMonitor.shared.isNetworkAvailable = true
        cancellables = []
    }

    // Adapted: use the PostActionCoordinator + PostActionNetworking mock to validate
    // like/unlike state reconciliation without subclassing final services.
    final class MockActionService: PostActionNetworking {
        var likeQueue: [Result<PostActionState, Error>] = []
        var unlikeQueue: [Result<PostActionState, Error>] = []

        func like(post: Post) async throws -> PostActionState {
            if likeQueue.isEmpty { return PostActionState(post: post) }
            switch likeQueue.removeFirst() {
            case .success(let state): return state
            case .failure(let error): throw error
            }
        }
        func unlike(post: Post) async throws -> PostActionState {
            if unlikeQueue.isEmpty { return PostActionState(post: post) }
            switch unlikeQueue.removeFirst() {
            case .success(let state): return state
            case .failure(let error): throw error
            }
        }
        func repost(post: Post) async throws -> PostActionState { PostActionState(post: post) }
        func unrepost(post: Post) async throws -> PostActionState { PostActionState(post: post) }
        func follow(post: Post, shouldFollow: Bool) async throws -> PostActionState {
            var s = PostActionState(post: post); s.isFollowingAuthor = shouldFollow; return s
        }
        func mute(post: Post, shouldMute: Bool) async throws -> PostActionState {
            var s = PostActionState(post: post); s.isMutedAuthor = shouldMute; return s
        }
        func block(post: Post, shouldBlock: Bool) async throws -> PostActionState {
            var s = PostActionState(post: post); s.isBlockedAuthor = shouldBlock; return s
        }
        func fetchActions(for post: Post) async throws -> PostActionState { PostActionState(post: post) }
    }

    private func makeAccount(platform: SocialPlatform = .mastodon) -> SocialAccount {
        SocialAccount(
            id: UUID().uuidString,
            username: "tester",
            displayName: "Tester",
            serverURL: nil,
            platform: platform,
            profileImageURL: nil
        )
    }

    private func makePost(platform: SocialPlatform = .mastodon) -> Post {
        Post(
            id: UUID().uuidString,
            content: "Hello",
            authorName: "Tester",
            authorUsername: "tester",
            authorProfilePictureURL: "",
            createdAt: Date(),
            platform: platform,
            originalURL: "https://example.com",
            attachments: []
        )
    }

    func testLikeUpdatesStateViaCoordinator() async throws {
        let store = PostActionStore()
        let mock = MockActionService()
        struct TestDispatcher: PostActionCoordinator.ActionDispatcher {
            func now() -> Date { Date() }
            func schedule(_ operation: @escaping @Sendable () async -> Void) { Task { await operation() } }
        }
        let coordinator = PostActionCoordinator(
            store: store,
            service: mock,
            networkMonitor: SimpleEdgeCaseMonitor.shared,
            staleInterval: 60,
            debounceInterval: 0,
            dispatcher: TestDispatcher()
        )
        let post = makePost()
        // Seed store to establish baseline timestamp
        let initial = store.ensureState(for: post)
        var serverState = PostActionState(post: post)
        serverState.isLiked = true
        serverState.likeCount = initial.likeCount + 1
        // Prime mock immediately before action
        mock.likeQueue = [.success(serverState)]

        // Wait for inflight to start, then to clear
        let started = expectation(description: "inflight started (like)")
        store.$inflightKeys
            .filter { $0.contains(post.stableId) }
            .first()
            .sink { _ in started.fulfill() }
            .store(in: &cancellables)

        coordinator.toggleLike(for: post)

        // Optimistic flip should be immediate
        XCTAssertEqual(store.actions[post.stableId]?.isLiked, true)

        await fulfillment(of: [started], timeout: 4.0)

        let cleared = expectation(description: "inflight cleared (like)")
        store.$inflightKeys
            .filter { !$0.contains(post.stableId) }
            .first()
            .sink { _ in cleared.fulfill() }
            .store(in: &cancellables)

        await fulfillment(of: [cleared], timeout: 4.0)

        // Assert reconciled equals queued
        XCTAssertTrue(store.actions[post.stableId]?.isLiked == true)
        XCTAssertEqual(store.actions[post.stableId]?.likeCount, serverState.likeCount)
        XCTAssertTrue(post.isLiked)
        XCTAssertEqual(post.likeCount, serverState.likeCount)
    }

    func testUnlikeUpdatesStateViaCoordinator() async throws {
        let store = PostActionStore()
        let mock = MockActionService()
        struct TestDispatcher: PostActionCoordinator.ActionDispatcher {
            func now() -> Date { Date() }
            func schedule(_ operation: @escaping @Sendable () async -> Void) { Task { await operation() } }
        }
        let coordinator = PostActionCoordinator(
            store: store,
            service: mock,
            networkMonitor: SimpleEdgeCaseMonitor.shared,
            staleInterval: 60,
            debounceInterval: 0,
            dispatcher: TestDispatcher()
        )
        let post = makePost()
        post.isLiked = true
        post.likeCount = 3
        // Seed store to establish baseline timestamp
        let initial = store.ensureState(for: post)
        var serverState = PostActionState(post: post)
        serverState.isLiked = false
        serverState.likeCount = max(initial.likeCount - 1, 0)
        // Prime mock immediately before action
        mock.unlikeQueue = [.success(serverState)]

        // Wait for inflight to start, then to clear
        let started = expectation(description: "inflight started (unlike)")
        store.$inflightKeys
            .filter { $0.contains(post.stableId) }
            .first()
            .sink { _ in started.fulfill() }
            .store(in: &cancellables)

        coordinator.toggleLike(for: post)

        // Optimistic unlike should be immediate
        XCTAssertEqual(store.actions[post.stableId]?.isLiked, false)

        await fulfillment(of: [started], timeout: 4.0)

        let cleared = expectation(description: "inflight cleared (unlike)")
        store.$inflightKeys
            .filter { !$0.contains(post.stableId) }
            .first()
            .sink { _ in cleared.fulfill() }
            .store(in: &cancellables)

        await fulfillment(of: [cleared], timeout: 4.0)

        // Assert reconciled equals queued
        XCTAssertFalse(store.actions[post.stableId]?.isLiked ?? true)
        XCTAssertEqual(store.actions[post.stableId]?.likeCount, serverState.likeCount)
        XCTAssertFalse(post.isLiked)
        XCTAssertEqual(post.likeCount, serverState.likeCount)
    }
}


import XCTest
import Combine
@testable import SocialFusion

@MainActor
final class PostActionCoordinatorTests: XCTestCase {

    var cancellables: Set<AnyCancellable> = []

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

        func follow(post: Post, shouldFollow: Bool) async throws -> PostActionState {
            var state = dequeueState(for: post) ?? post.makeActionState(timestamp: Date())
            state.isFollowingAuthor = shouldFollow
            return state
        }

        func mute(post: Post, shouldMute: Bool) async throws -> PostActionState {
            var state = dequeueState(for: post) ?? post.makeActionState(timestamp: Date())
            state.isMutedAuthor = shouldMute
            return state
        }

        func block(post: Post, shouldBlock: Bool) async throws -> PostActionState {
            var state = dequeueState(for: post) ?? post.makeActionState(timestamp: Date())
            state.isBlockedAuthor = shouldBlock
            return state
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
        FeatureFlagManager.shared.enableFeature(.postActionsV2)
        SimpleEdgeCaseMonitor.shared.isNetworkAvailable = true
    }

    override func tearDown() {
        cancellables.removeAll()
        SimpleEdgeCaseMonitor.shared.isNetworkAvailable = true
        super.tearDown()
    }

    func testToggleLikeOptimisticallyUpdatesStore() async {
        let store = PostActionStore()
        let service = MockPostActionService()
        struct TestDispatcher: PostActionCoordinator.ActionDispatcher {
            func now() -> Date { Date() }
            func schedule(_ operation: @escaping @Sendable () async -> Void) { Task { await operation() } }
        }
        let coordinator = PostActionCoordinator(
            store: store,
            service: service,
            networkMonitor: SimpleEdgeCaseMonitor.shared,
            staleInterval: 60,
            debounceInterval: 0,
            dispatcher: TestDispatcher()
        )
        let post = makePost()
        // Seed store to establish a stable baseline timestamp
        let seeded = store.ensureState(for: post)
        // Compute expected server state from baseline
        let initial = seeded
        let expectedCount = initial.likeCount + 1
        let expected = PostActionState(
            stableId: post.stableId,
            platform: post.platform,
            isLiked: true,
            isReposted: false,
            isReplied: false,
            isQuoted: false,
            likeCount: expectedCount,
            repostCount: initial.repostCount,
            replyCount: initial.replyCount
        )
        service.queuedStates = [expected]

        // Wait for inflight to start, then to clear (prevents premature fulfillment)
        let started = expectation(description: "inflight started")
        store.$inflightKeys
            .filter { $0.contains(post.stableId) }
            .first()
            .sink { _ in started.fulfill() }
            .store(in: &cancellables)

        // Trigger like toggle
        coordinator.toggleLike(for: post)

        // Optimistic path should flip immediately
        XCTAssertEqual(store.actions[post.stableId]?.isLiked, true)

        await fulfillment(of: [started], timeout: 4.0)

        let cleared = expectation(description: "inflight cleared")
        store.$inflightKeys
            .filter { !$0.contains(post.stableId) }
            .first()
            .sink { _ in cleared.fulfill() }
            .store(in: &cancellables)

        await fulfillment(of: [cleared], timeout: 4.0)

        // Assert reconciled equals queued
        XCTAssertEqual(service.likeCalls, 1)
        XCTAssertEqual(store.actions[post.stableId]?.likeCount, expected.likeCount)
        XCTAssertFalse(store.pendingKeys.contains(post.stableId))
    }

    func testOfflineActionQueuesUntilNetworkReturns() async {
        let store = PostActionStore()
        let service = MockPostActionService()
        struct TestDispatcher: PostActionCoordinator.ActionDispatcher {
            func now() -> Date { Date() }
            func schedule(_ operation: @escaping @Sendable () async -> Void) { Task { await operation() } }
        }
        let coordinator = PostActionCoordinator(
            store: store,
            service: service,
            networkMonitor: SimpleEdgeCaseMonitor.shared,
            staleInterval: 60,
            debounceInterval: 0,
            dispatcher: TestDispatcher()
        )

        let post = makePost()
        SimpleEdgeCaseMonitor.shared.isNetworkAvailable = false

        coordinator.toggleLike(for: post)

        XCTAssertTrue(store.pendingKeys.contains(post.stableId))
        XCTAssertEqual(service.likeCalls, 0)

        SimpleEdgeCaseMonitor.shared.isNetworkAvailable = true
        // Drive flush deterministically
        coordinator.flushQueuedOfflineActions()

        // Wait for pending to clear
        let pendingCleared = expectation(description: "pending cleared")
        store.$pendingKeys
            .filter { !$0.contains(post.stableId) }
            .first()
            .sink { _ in pendingCleared.fulfill() }
            .store(in: &cancellables)
        await fulfillment(of: [pendingCleared], timeout: 2.0)

        // Verify service was invoked
        let invoked = expectation(description: "service invoked")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if service.likeCalls > 0 { invoked.fulfill() }
        }
        await fulfillment(of: [invoked], timeout: 2.0)

        XCTAssertTrue(service.likeCalls > 0)
        XCTAssertFalse(store.pendingKeys.contains(post.stableId))
    }
}


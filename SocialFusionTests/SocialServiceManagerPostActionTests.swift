import XCTest
import Combine
@testable import SocialFusion

@MainActor
final class SocialServiceManagerPostActionTests: XCTestCase {
    var cancellables: Set<AnyCancellable> = []
    private let queueDefaultsKey = "socialfusion_offline_queue"

    override func setUp() {
        super.setUp()
        FeatureFlagManager.shared.enableFeature(.postActionsV2)
        SimpleEdgeCaseMonitor.shared.isNetworkAvailable = true
        cancellables = []
        UserDefaults.standard.removeObject(forKey: queueDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: queueDefaultsKey)
        super.tearDown()
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

    // MARK: - Offline Queue Replay ID Semantics

    func testQueuedActionPrefersPlatformPostIdForReplay() {
        let action = QueuedAction(
            postId: "stable-mastodon-post-id",
            platformPostId: "109876543210",
            platform: .mastodon,
            type: .like
        )

        XCTAssertEqual(action.fetchPostId, "109876543210")
    }

    func testQueuedActionFallsBackToLegacyPostIdWhenPlatformPostIdMissing() throws {
        let legacyJSON = """
        {
          "id": "D7C09D90-67C3-430A-9F84-742E09CC8655",
          "postId": "legacy-post-id",
          "platform": "bluesky",
          "type": "repost",
          "createdAt": "2026-02-14T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let action = try decoder.decode(QueuedAction.self, from: legacyJSON)

        XCTAssertEqual(action.fetchPostId, "legacy-post-id")
    }

    func testQueueStorePersistsPlatformPostId() {
        let store = OfflineQueueStore()

        store.queueAction(
            postId: "stable-id",
            platformPostId: "native-id",
            platform: .mastodon,
            type: .like
        )

        XCTAssertEqual(store.queuedActions.count, 1)
        XCTAssertEqual(store.queuedActions.first?.fetchPostId, "native-id")
    }
}

final class ComposeAutocompleteLatencyTests: XCTestCase {
    private func makeAccount(id: String, platform: SocialPlatform = .mastodon) -> SocialAccount {
        SocialAccount(
            id: id,
            username: "user-\(id)",
            displayName: "User \(id)",
            serverURL: nil,
            platform: platform,
            profileImageURL: nil
        )
    }

    func testServiceKeyIgnoresAccountOrder() {
        let accountA = makeAccount(id: "a", platform: .mastodon)
        let accountB = makeAccount(id: "b", platform: .bluesky)

        let keyOne = ComposeAutocompleteServiceKey.make(
            accounts: [accountA, accountB],
            timelineScope: .unified
        )
        let keyTwo = ComposeAutocompleteServiceKey.make(
            accounts: [accountB, accountA],
            timelineScope: .unified
        )

        XCTAssertEqual(keyOne, keyTwo)
    }

    func testServiceKeyChangesWhenScopeChanges() {
        let account = makeAccount(id: "a", platform: .mastodon)

        let unified = ComposeAutocompleteServiceKey.make(
            accounts: [account],
            timelineScope: .unified
        )
        let thread = ComposeAutocompleteServiceKey.make(
            accounts: [account],
            timelineScope: .thread("post-123")
        )

        XCTAssertNotEqual(unified, thread)
    }

    func testServiceKeyChangesWhenAccountsChange() {
        let accountA = makeAccount(id: "a", platform: .mastodon)
        let accountB = makeAccount(id: "b", platform: .bluesky)

        let oneAccount = ComposeAutocompleteServiceKey.make(
            accounts: [accountA],
            timelineScope: .unified
        )
        let twoAccounts = ComposeAutocompleteServiceKey.make(
            accounts: [accountA, accountB],
            timelineScope: .unified
        )

        XCTAssertNotEqual(oneAccount, twoAccounts)
    }
}

final class PaginationReliabilityTests: XCTestCase {
    func testOutcomeForSuccessfulPaginationWithoutFailures() {
        let outcome = SocialServiceManager._test_resolvePaginationOutcome(
            hadSuccessfulFetch: true,
            hasMorePagesFromSuccess: false,
            failureCount: 0
        )

        XCTAssertEqual(
            outcome,
            SocialServiceManager.PaginationOutcome(
                hasNextPage: false,
                shouldEmitError: false,
                shouldThrow: false
            )
        )
    }

    func testOutcomeForPartialFailureKeepsPaginationRetryable() {
        let outcome = SocialServiceManager._test_resolvePaginationOutcome(
            hadSuccessfulFetch: true,
            hasMorePagesFromSuccess: false,
            failureCount: 1
        )

        XCTAssertEqual(
            outcome,
            SocialServiceManager.PaginationOutcome(
                hasNextPage: true,
                shouldEmitError: true,
                shouldThrow: false
            )
        )
    }

    func testOutcomeForTotalFailureThrowsAndKeepsNextPageTrue() {
        let outcome = SocialServiceManager._test_resolvePaginationOutcome(
            hadSuccessfulFetch: false,
            hasMorePagesFromSuccess: false,
            failureCount: 2
        )

        XCTAssertEqual(
            outcome,
            SocialServiceManager.PaginationOutcome(
                hasNextPage: true,
                shouldEmitError: true,
                shouldThrow: true
            )
        )
    }
}

final class RefreshGenerationGuardTests: XCTestCase {
    func testStaleGenerationIsRejected() {
        XCTAssertFalse(
            SocialServiceManager._test_shouldCommitRefreshGeneration(active: 7, candidate: 6)
        )
    }

    func testCurrentGenerationIsAccepted() {
        XCTAssertTrue(
            SocialServiceManager._test_shouldCommitRefreshGeneration(active: 7, candidate: 7)
        )
    }
}

@MainActor
final class PolishRolloutFeatureFlagTests: XCTestCase {
    override func tearDown() {
        FeatureFlagManager.shared.disableFeature(.refreshGenerationGuard)
        FeatureFlagManager.shared.disableFeature(.timelinePrefetchDiffing)
        super.tearDown()
    }

    func testRefreshGenerationGuardFlagCanBeToggled() {
        FeatureFlagManager.shared.disableFeature(.refreshGenerationGuard)
        XCTAssertFalse(FeatureFlagManager.isEnabled(.refreshGenerationGuard))

        FeatureFlagManager.shared.enableFeature(.refreshGenerationGuard)
        XCTAssertTrue(FeatureFlagManager.isEnabled(.refreshGenerationGuard))
    }

    func testTimelinePrefetchDiffingFlagCanBeToggled() {
        FeatureFlagManager.shared.disableFeature(.timelinePrefetchDiffing)
        XCTAssertFalse(FeatureFlagManager.isEnabled(.timelinePrefetchDiffing))

        FeatureFlagManager.shared.enableFeature(.timelinePrefetchDiffing)
        XCTAssertTrue(FeatureFlagManager.isEnabled(.timelinePrefetchDiffing))
    }
}

@MainActor
final class TimelineIdentityStabilityTests: XCTestCase {
    private func makePost(id: String, platformSpecificId: String, platform: SocialPlatform = .mastodon)
        -> Post
    {
        Post(
            id: id,
            content: "Post \(id)",
            authorName: "Author \(id)",
            authorUsername: "author\(id)",
            authorProfilePictureURL: "",
            createdAt: Date(),
            platform: platform,
            originalURL: "https://example.com/\(id)",
            platformSpecificId: platformSpecificId
        )
    }

    func testStableIdentityDoesNotChangeWhenRepostVisualStateChanges() {
        let post = makePost(id: "wrapper", platformSpecificId: "native-wrapper")
        let original = makePost(id: "original", platformSpecificId: "native-original")
        let baseline = post.stableId

        post.originalPost = original
        post.isReposted = true

        XCTAssertEqual(
            post.stableId,
            baseline,
            "Timeline identity should be immutable and independent from mutable repost state."
        )
    }
}

final class NetworkServiceCancellationTests: XCTestCase {
    private struct ResponsePayload: Decodable {
        let value: String
    }

    private final class BlockingURLProtocol: URLProtocol {
        static var startedExpectation: XCTestExpectation?
        static var cancelledExpectation: XCTestExpectation?
        private static let lock = NSLock()
        private static var cancellationCount: Int = 0

        static func reset() {
            lock.lock()
            startedExpectation = nil
            cancelledExpectation = nil
            cancellationCount = 0
            lock.unlock()
        }

        private var scheduledCompletion: DispatchWorkItem?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.startedExpectation?.fulfill()
            let completion = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let data = #"{"value":"ok"}"#.data(using: .utf8) ?? Data()
                let response = HTTPURLResponse(
                    url: self.request.url ?? URL(string: "https://example.com")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            }
            scheduledCompletion = completion
            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0, execute: completion)
        }

        override func stopLoading() {
            scheduledCompletion?.cancel()
            Self.lock.lock()
            let shouldFulfill = Self.cancellationCount == 0
            Self.cancellationCount += 1
            Self.lock.unlock()
            if shouldFulfill {
                Self.cancelledExpectation?.fulfill()
            }
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
        }
    }

    override func setUp() {
        super.setUp()
        BlockingURLProtocol.reset()
    }

    func testCancelAllRequestsCancelsInFlightWork() async {
        let started = expectation(description: "request started")
        let cancelled = expectation(description: "request cancelled")
        BlockingURLProtocol.startedExpectation = started
        BlockingURLProtocol.cancelledExpectation = cancelled

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BlockingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = NetworkService(session: session)

        let requestTask = Task {
            try? await service.get(
                url: URL(string: "https://example.com/hang")!,
                responseType: ResponsePayload.self
            )
        }

        await fulfillment(of: [started], timeout: 1.5)
        service.cancelAllRequests()
        await fulfillment(of: [cancelled], timeout: 1.5)
        _ = await requestTask.result
    }
}

final class FollowGraphCacheTests: XCTestCase {
    func testCacheEntryExpiresAfterTTL() async {
        let cache = FollowGraphCache(defaultTTL: 0.1)
        let user = CanonicalUserID(
            platform: .mastodon,
            stableID: "123",
            normalizedHandle: "user@example.com"
        )

        await cache.set([user], for: "followed")
        let cachedNow = await cache.value(for: "followed")
        XCTAssertEqual(cachedNow?.count, 1)

        try? await Task.sleep(nanoseconds: 160_000_000)
        let cachedLater = await cache.value(for: "followed")
        XCTAssertNil(cachedLater)
    }

    func testInvalidateAllClearsEntries() async {
        let cache = FollowGraphCache(defaultTTL: 60)
        let user = CanonicalUserID(
            platform: .bluesky,
            stableID: "did:plc:test",
            normalizedHandle: "tester.bsky.social"
        )

        await cache.set([user], for: "followed")
        let cachedBeforeInvalidation = await cache.value(for: "followed")
        XCTAssertNotNil(cachedBeforeInvalidation)

        await cache.invalidateAll()
        let cachedAfterInvalidation = await cache.value(for: "followed")
        XCTAssertNil(cachedAfterInvalidation)
    }
}

final class DraftPersistenceOrderingTests: XCTestCase {
    private func makeDraft(text: String) -> DraftPost {
        DraftPost(
            posts: [ThreadPostDraft(text: text)],
            selectedPlatforms: [.mastodon]
        )
    }

    func testQueuePersistsLatestCoalescedWrite() async throws {
        let queue = DraftPersistenceQueue()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "draft-order-\(UUID().uuidString).json"
        )
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await queue.enqueuePersist(drafts: [makeDraft(text: "first")], destinationURL: tempURL)
        await queue.enqueuePersist(drafts: [makeDraft(text: "second")], destinationURL: tempURL)
        await queue.enqueuePersist(drafts: [makeDraft(text: "latest")], destinationURL: tempURL)

        try? await Task.sleep(nanoseconds: 450_000_000)
        let data = try Data(contentsOf: tempURL)
        let decoded = try JSONDecoder().decode([DraftPost].self, from: data)

        XCTAssertEqual(decoded.first?.posts.first?.text, "latest")
    }
}

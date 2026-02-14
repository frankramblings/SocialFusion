import XCTest
@testable import SocialFusion

@MainActor
final class TimelineRefreshCoordinatorTests: XCTestCase {
    private func makePost(id: String, platform: SocialPlatform, createdAt: Date) -> Post {
        Post(
            id: id,
            content: "Post \(id)",
            authorName: "Author \(id)",
            authorUsername: "author\(id)",
            authorProfilePictureURL: "",
            createdAt: createdAt,
            platform: platform,
            originalURL: "https://example.com/\(id)",
            platformSpecificId: id
        )
    }

    func testForegroundPrefetchBuffersOnly() async {
        var refreshCalls = 0
        let coordinator = TimelineRefreshCoordinator(
            timelineID: "test",
            platforms: [.mastodon],
            isLoading: { false },
            fetchPostsForPlatform: { _ in
                [self.makePost(id: "1", platform: .mastodon, createdAt: Date())]
            },
            filterPosts: { $0 },
            mergeBufferedPosts: { _ in },
            refreshVisibleTimeline: { _ in refreshCalls += 1 },
            visiblePostsProvider: { [] },
            log: { _ in }
        )

        coordinator.setTimelineVisible(true)
        await coordinator.requestPrefetch(trigger: .foreground)

        XCTAssertEqual(coordinator.bufferCount, 1)
        XCTAssertEqual(refreshCalls, 0)
    }

    func testIdlePollingBuffersOnlyWhenIdle() async {
        let coordinator = TimelineRefreshCoordinator(
            timelineID: "test",
            platforms: [.mastodon],
            isLoading: { false },
            fetchPostsForPlatform: { _ in
                [self.makePost(id: "1", platform: .mastodon, createdAt: Date())]
            },
            filterPosts: { $0 },
            mergeBufferedPosts: { _ in },
            refreshVisibleTimeline: { _ in },
            visiblePostsProvider: { [] },
            log: { _ in }
        )

        coordinator.setTimelineVisible(true)
        await coordinator.requestPrefetch(trigger: .idlePolling)

        XCTAssertEqual(coordinator.bufferCount, 1)
    }

    func testAbortOnScrollSuppressesBufferUpdates() async {
        let coordinator = TimelineRefreshCoordinator(
            timelineID: "test",
            platforms: [.mastodon],
            isLoading: { false },
            fetchPostsForPlatform: { _ in
                [self.makePost(id: "1", platform: .mastodon, createdAt: Date())]
            },
            filterPosts: { $0 },
            mergeBufferedPosts: { _ in },
            refreshVisibleTimeline: { _ in },
            visiblePostsProvider: { [] },
            log: { _ in }
        )

        coordinator.setTimelineVisible(true)
        coordinator.scrollInteractionBegan()
        await coordinator.requestPrefetch(trigger: .idlePolling)

        XCTAssertEqual(coordinator.bufferCount, 0)
    }

    func testComposeSuspensionBlocksPrefetch() async {
        let coordinator = TimelineRefreshCoordinator(
            timelineID: "test",
            platforms: [.mastodon],
            isLoading: { false },
            fetchPostsForPlatform: { _ in
                [self.makePost(id: "1", platform: .mastodon, createdAt: Date())]
            },
            filterPosts: { $0 },
            mergeBufferedPosts: { _ in },
            refreshVisibleTimeline: { _ in },
            visiblePostsProvider: { [] },
            log: { _ in }
        )

        coordinator.setTimelineVisible(true)
        coordinator.setComposing(true)
        await coordinator.requestPrefetch(trigger: .foreground)

        XCTAssertEqual(coordinator.bufferCount, 0)
    }

    func testDeepHistoryBlocksIdlePolling() async {
        let coordinator = TimelineRefreshCoordinator(
            timelineID: "test",
            platforms: [.mastodon],
            isLoading: { false },
            fetchPostsForPlatform: { _ in
                [self.makePost(id: "1", platform: .mastodon, createdAt: Date())]
            },
            filterPosts: { $0 },
            mergeBufferedPosts: { _ in },
            refreshVisibleTimeline: { _ in },
            visiblePostsProvider: { [] },
            log: { _ in }
        )

        coordinator.setTimelineVisible(true)
        coordinator.updateScrollState(isNearTop: false, isDeepHistory: true)
        await coordinator.requestPrefetch(trigger: .idlePolling)

        XCTAssertEqual(coordinator.bufferCount, 0)
    }

    func testMergeClearsBuffer() async {
        var mergeCalls = 0
        let coordinator = TimelineRefreshCoordinator(
            timelineID: "test",
            platforms: [.mastodon],
            isLoading: { false },
            fetchPostsForPlatform: { _ in
                [self.makePost(id: "1", platform: .mastodon, createdAt: Date())]
            },
            filterPosts: { $0 },
            mergeBufferedPosts: { _ in mergeCalls += 1 },
            refreshVisibleTimeline: { _ in },
            visiblePostsProvider: { [] },
            log: { _ in }
        )

        coordinator.setTimelineVisible(true)
        await coordinator.requestPrefetch(trigger: .foreground)
        coordinator.mergeBufferedPostsIfNeeded()

        XCTAssertEqual(mergeCalls, 1)
        XCTAssertEqual(coordinator.bufferCount, 0)
    }

    func testDeterministicIdlePollingIntervalIsStableForSameCycle() {
        let first = TimelineRefreshCoordinator._test_deterministicInterval(
            timelineID: "unified",
            platform: .mastodon,
            trigger: .idlePolling,
            cycle: 0
        )
        let second = TimelineRefreshCoordinator._test_deterministicInterval(
            timelineID: "unified",
            platform: .mastodon,
            trigger: .idlePolling,
            cycle: 0
        )

        XCTAssertEqual(first, second, accuracy: 0.0001)
    }

    func testDeterministicIdlePollingIntervalVariesAcrossCycles() {
        let cycleZero = TimelineRefreshCoordinator._test_deterministicInterval(
            timelineID: "unified",
            platform: .bluesky,
            trigger: .idlePolling,
            cycle: 0
        )
        let cycleOne = TimelineRefreshCoordinator._test_deterministicInterval(
            timelineID: "unified",
            platform: .bluesky,
            trigger: .idlePolling,
            cycle: 1
        )

        XCTAssertNotEqual(cycleZero, cycleOne)
    }

    func testDeterministicForegroundIntervalIsStable() {
        let first = TimelineRefreshCoordinator._test_deterministicInterval(
            timelineID: "unified",
            platform: .mastodon,
            trigger: .foreground,
            cycle: 0
        )
        let second = TimelineRefreshCoordinator._test_deterministicInterval(
            timelineID: "unified",
            platform: .mastodon,
            trigger: .foreground,
            cycle: 0
        )

        XCTAssertEqual(first, second, accuracy: 0.0001)
    }
}

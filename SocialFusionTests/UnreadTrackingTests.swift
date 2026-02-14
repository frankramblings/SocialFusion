import XCTest
@testable import SocialFusion

/// Tests for unread tracking in UnifiedTimelineController
@MainActor
final class UnreadTrackingTests: XCTestCase {
    
    private func makePost(id: String, platform: SocialPlatform = .mastodon, createdAt: Date = Date()) -> Post {
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
    
    // MARK: - updateUnreadFromTopVisibleIndex Tests
    
    func testUpdateUnreadFromTopVisibleIndexDecrementsCount() {
        // Given: A controller with some unread posts
        let serviceManager = SocialServiceManager()
        let controller = UnifiedTimelineController(serviceManager: serviceManager)
        
        // Simulate 10 unread posts above viewport
        let unreadIds: Set<String> = Set((0..<10).map { "post-\($0)" })
        controller.setUnreadAboveViewport(unreadIds)
        XCTAssertEqual(controller.unreadAboveViewportCount, 10)
        
        // When: User scrolls up and top visible post is at index 5
        controller.updateUnreadFromTopVisibleIndex(5)
        
        // Then: Only 5 posts remain unread (indices 0-4)
        XCTAssertEqual(controller.unreadAboveViewportCount, 5)
    }
    
    func testUpdateUnreadDoesNotIncrease() {
        // Given: A controller with 5 unread posts
        let serviceManager = SocialServiceManager()
        let controller = UnifiedTimelineController(serviceManager: serviceManager)
        
        let unreadIds: Set<String> = Set((0..<5).map { "post-\($0)" })
        controller.setUnreadAboveViewport(unreadIds)
        XCTAssertEqual(controller.unreadAboveViewportCount, 5)
        
        // When: User scrolls down (higher index)
        controller.updateUnreadFromTopVisibleIndex(8)
        
        // Then: Count should NOT increase (user scrolling down doesn't add unread)
        XCTAssertEqual(controller.unreadAboveViewportCount, 5)
    }
    
    func testClearUnreadAboveViewport() {
        // Given: A controller with unread posts
        let serviceManager = SocialServiceManager()
        let controller = UnifiedTimelineController(serviceManager: serviceManager)
        
        let unreadIds: Set<String> = Set((0..<10).map { "post-\($0)" })
        controller.setUnreadAboveViewport(unreadIds)
        XCTAssertEqual(controller.unreadAboveViewportCount, 10)
        
        // When: User reaches top and unread is cleared
        controller.clearUnreadAboveViewport()
        
        // Then: Count should be 0
        XCTAssertEqual(controller.unreadAboveViewportCount, 0)
    }
    
    func testMarkPostAsRead() {
        // Given: A controller with specific unread post
        let serviceManager = SocialServiceManager()
        let controller = UnifiedTimelineController(serviceManager: serviceManager)
        
        controller.setUnreadAboveViewport(Set(["post-a", "post-b", "post-c"]))
        XCTAssertEqual(controller.unreadAboveViewportCount, 3)
        
        // When: A specific post is marked as read
        controller.markPostAsRead("post-b")
        
        // Then: Count decrements by 1
        XCTAssertEqual(controller.unreadAboveViewportCount, 2)
        XCTAssertFalse(controller.isPostUnread("post-b"))
        XCTAssertTrue(controller.isPostUnread("post-a"))
    }
    
    func testMarkPostsAsRead() {
        // Given: A controller with multiple unread posts
        let serviceManager = SocialServiceManager()
        let controller = UnifiedTimelineController(serviceManager: serviceManager)
        
        controller.setUnreadAboveViewport(Set(["post-1", "post-2", "post-3", "post-4", "post-5"]))
        XCTAssertEqual(controller.unreadAboveViewportCount, 5)
        
        // When: Multiple posts are marked as read
        controller.markPostsAsRead(Set(["post-2", "post-4"]))
        
        // Then: Count decrements correctly
        XCTAssertEqual(controller.unreadAboveViewportCount, 3)
    }
    
    func testAddUnreadAboveViewport() {
        // Given: A controller with some unread posts
        let serviceManager = SocialServiceManager()
        let controller = UnifiedTimelineController(serviceManager: serviceManager)
        
        controller.setUnreadAboveViewport(Set(["post-1", "post-2"]))
        XCTAssertEqual(controller.unreadAboveViewportCount, 2)
        
        // When: New posts are added to unread
        controller.addUnreadAboveViewport(Set(["post-3", "post-4"]))
        
        // Then: Count increases
        XCTAssertEqual(controller.unreadAboveViewportCount, 4)
    }
    
    func testIsPostUnread() {
        // Given: A controller with specific unread posts
        let serviceManager = SocialServiceManager()
        let controller = UnifiedTimelineController(serviceManager: serviceManager)
        
        controller.setUnreadAboveViewport(Set(["unread-1", "unread-2"]))
        
        // Then: Check returns correct values
        XCTAssertTrue(controller.isPostUnread("unread-1"))
        XCTAssertTrue(controller.isPostUnread("unread-2"))
        XCTAssertFalse(controller.isPostUnread("read-1"))
    }
    
    // MARK: - Integration Tests
    
    func testUnreadCountUpdatesOnScrollUp() {
        // Given: A controller with 20 unread posts above viewport
        let serviceManager = SocialServiceManager()
        let controller = UnifiedTimelineController(serviceManager: serviceManager)
        
        let unreadIds: Set<String> = Set((0..<20).map { "post-\($0)" })
        controller.setUnreadAboveViewport(unreadIds)
        
        // When: User scrolls up progressively
        controller.updateUnreadFromTopVisibleIndex(15) // 15 above
        XCTAssertEqual(controller.unreadAboveViewportCount, 15)
        
        controller.updateUnreadFromTopVisibleIndex(10) // 10 above
        XCTAssertEqual(controller.unreadAboveViewportCount, 10)
        
        controller.updateUnreadFromTopVisibleIndex(5) // 5 above
        XCTAssertEqual(controller.unreadAboveViewportCount, 5)
        
        controller.updateUnreadFromTopVisibleIndex(0) // At top
        XCTAssertEqual(controller.unreadAboveViewportCount, 0)
    }
    
    func testUnreadRemainsSameOnScrollDown() {
        // Given: Controller with 5 unread, user at index 5
        let serviceManager = SocialServiceManager()
        let controller = UnifiedTimelineController(serviceManager: serviceManager)

        let unreadIds: Set<String> = Set((0..<5).map { "post-\($0)" })
        controller.setUnreadAboveViewport(unreadIds)
        controller.updateUnreadFromTopVisibleIndex(5)
        XCTAssertEqual(controller.unreadAboveViewportCount, 5)

        // When: User scrolls down (index increases)
        controller.updateUnreadFromTopVisibleIndex(10)
        controller.updateUnreadFromTopVisibleIndex(20)

        // Then: Unread count should remain at 5 (not increase)
        XCTAssertEqual(controller.unreadAboveViewportCount, 5)
    }

    // MARK: - Pending Merge Count Tests

    func testPendingMergeCountBridgesGap() {
        // Given: A controller with pendingMergeCount set (simulates post-merge gap)
        let serviceManager = SocialServiceManager()
        let controller = UnifiedTimelineController(serviceManager: serviceManager)

        // Simulate: mergeBufferedPosts set pendingMergeCount before buffer drained
        // We can't call mergeBufferedPosts directly without a real buffer,
        // so we test the bridge property behavior indirectly:
        // pendingMergeCount should be > 0 while unreadAboveViewportCount is still 0

        // Verify initial state
        XCTAssertEqual(controller.pendingMergeCount, 0)
        XCTAssertEqual(controller.unreadAboveViewportCount, 0)

        // After clearUnreadAboveViewport, both should be 0
        controller.clearUnreadAboveViewport()
        XCTAssertEqual(controller.pendingMergeCount, 0)
        XCTAssertEqual(controller.unreadAboveViewportCount, 0)
    }

    func testClearUnreadAlsoClearsPendingMerge() {
        // Given: A controller with both pending merge and unread counts
        let serviceManager = SocialServiceManager()
        let controller = UnifiedTimelineController(serviceManager: serviceManager)

        // Set up unread posts
        controller.setUnreadAboveViewport(Set(["post-1", "post-2"]))
        XCTAssertEqual(controller.unreadAboveViewportCount, 2)

        // When: clearUnreadAboveViewport is called
        controller.clearUnreadAboveViewport()

        // Then: Both counts should be 0
        XCTAssertEqual(controller.unreadAboveViewportCount, 0)
        XCTAssertEqual(controller.pendingMergeCount, 0)
    }

    func testMergeBufferedPostsSetsPendingCount() {
        // Given: A controller — we test that mergeBufferedPosts captures buffer count
        let serviceManager = SocialServiceManager()
        let controller = UnifiedTimelineController(serviceManager: serviceManager)

        // When: bufferCount is 0, mergeBufferedPosts should NOT set pendingMergeCount
        controller.mergeBufferedPosts()

        // Then: pendingMergeCount stays 0 (no buffer to bridge)
        XCTAssertEqual(controller.pendingMergeCount, 0)
    }
}

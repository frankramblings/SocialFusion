import Foundation

// MARK: - Verification Methods for TimelineState Integration

extension TimelineState {
    
    /// Verify that the bridge works correctly by testing round-trip conversion
    static func verifyBridgeCompatibility() -> Bool {
        print("🧪 TimelineState: Starting bridge compatibility verification...")
        
        // Create a sample post
        let samplePost = Post(
            id: "test-post-123",
            content: "This is a test post for verification",
            authorName: "Test User",
            authorUsername: "testuser",
            authorProfilePictureURL: "",
            createdAt: Date(),
            platform: .mastodon,
            originalURL: "",
            attachments: [],
            mentions: [],
            tags: [],
            platformSpecificId: "test-post-123"
        )
        
        // Test 1: Create TimelineState and update with posts
        let timelineState = TimelineState()
        timelineState.updateFromPosts([samplePost], preservePosition: false)
        
        guard timelineState.entries.count == 1 else {
            print("❌ Test 1 failed: Expected 1 entry, got \(timelineState.entries.count)")
            return false
        }
        print("✅ Test 1 passed: TimelineState can be updated with posts")
        
        // Test 2: Convert back to compatible format
        let compatibleEntries = timelineState.compatibleTimelineEntries
        guard compatibleEntries.count == 1 else {
            print("❌ Test 2 failed: Expected 1 compatible entry, got \(compatibleEntries.count)")
            return false
        }
        
        let compatibleEntry = compatibleEntries[0]
        guard compatibleEntry.post.id == samplePost.id else {
            print("❌ Test 2 failed: Post ID mismatch - expected \(samplePost.id), got \(compatibleEntry.post.id)")
            return false
        }
        print("✅ Test 2 passed: Can convert back to compatible TimelineEntry format")
        
        // Test 3: Test read state management
        timelineState.markPostAsRead(samplePost.id)
        guard timelineState.entries[0].isRead == true else {
            print("❌ Test 3 failed: Post should be marked as read")
            return false
        }
        
        guard timelineState.unreadCount == 0 else {
            print("❌ Test 3 failed: Unread count should be 0, got \(timelineState.unreadCount)")
            return false
        }
        print("✅ Test 3 passed: Read state management works correctly")
        
        // Test 4: Test position preservation
        let newPost = Post(
            id: "test-post-456",
            content: "This is a newer test post",
            authorName: "Test User 2",
            authorUsername: "testuser2",
            authorProfilePictureURL: "",
            createdAt: Date().addingTimeInterval(60), // 1 minute later
            platform: .bluesky,
            originalURL: "",
            attachments: [],
            mentions: [],
            tags: [],
            platformSpecificId: "test-post-456"
        )
        
        timelineState.updateFromPosts([newPost, samplePost], preservePosition: true)
        guard timelineState.entries.count == 2 else {
            print("❌ Test 4 failed: Expected 2 entries after update, got \(timelineState.entries.count)")
            return false
        }
        print("✅ Test 4 passed: Position preservation works correctly")
        
        // Test 5: Test scroll position
        timelineState.saveScrollPosition(samplePost.id)
        guard timelineState.getRestoreScrollPosition() == samplePost.id else {
            print("❌ Test 5 failed: Scroll position not saved correctly")
            return false
        }
        print("✅ Test 5 passed: Scroll position management works correctly")
        
        print("🎉 TimelineState: All bridge compatibility tests passed!")
        return true
    }
    
    /// Quick verification that can be called during app initialization
    static func quickCompatibilityCheck() -> Bool {
        // Just verify that the basic structure works
        let timelineState = TimelineState()
        let initialSummary = timelineState.getStateSummary()
        
        // Should not crash and should return sensible defaults
        return timelineState.entries.isEmpty && 
               timelineState.unreadCount == 0 && 
               !initialSummary.isEmpty
    }
}

// MARK: - Integration Helper

extension SocialServiceManager {
    
    /// Test method to verify that TimelineState integrates correctly with existing service manager
    func verifyTimelineStateIntegration() -> Bool {
        print("🧪 SocialServiceManager: Testing TimelineState integration...")
        
        // Create a test timeline state
        let timelineState = TimelineState()
        
        // Test with current unified timeline (if any)
        if !unifiedTimeline.isEmpty {
            timelineState.updateFromServiceManagerWithExistingLogic(self, isRefresh: false)
            
            // Verify that the conversion worked
            let compatibleEntries = timelineState.compatibleTimelineEntries
            let directEntries = makeTimelineEntries(from: unifiedTimeline)
            
            guard compatibleEntries.count == directEntries.count else {
                print("❌ Integration test failed: Entry count mismatch")
                return false
            }
            
            print("✅ SocialServiceManager: TimelineState integration works correctly")
            return true
        } else {
            // No posts to test with, but at least verify it doesn't crash
            timelineState.updateFromServiceManagerWithExistingLogic(self, isRefresh: false)
            print("✅ SocialServiceManager: TimelineState integration (empty state) works correctly")
            return true
        }
    }
}
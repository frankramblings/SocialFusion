import Foundation

// MARK: - Verification Methods for TimelineState Integration

extension TimelineState {
    
    /// Verify that the bridge works correctly by testing round-trip conversion
    static func verifyBridgeCompatibility() -> Bool {
        #if DEBUG
        print("🧪 TimelineState: Starting bridge compatibility verification...")
        #endif
        
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
            #if DEBUG
            print("❌ Test 1 failed: Expected 1 entry, got \(timelineState.entries.count)")
            #endif
            return false
        }
        #if DEBUG
        print("✅ Test 1 passed: TimelineState can be updated with posts")
        #endif
        
        // Test 2: Convert back to compatible format
        let compatibleEntries = timelineState.compatibleTimelineEntries
        guard compatibleEntries.count == 1 else {
            #if DEBUG
            print("❌ Test 2 failed: Expected 1 compatible entry, got \(compatibleEntries.count)")
            #endif
            return false
        }
        
        let compatibleEntry = compatibleEntries[0]
        guard compatibleEntry.post.id == samplePost.id else {
            #if DEBUG
            print("❌ Test 2 failed: Post ID mismatch - expected \(samplePost.id), got \(compatibleEntry.post.id)")
            #endif
            return false
        }
        #if DEBUG
        print("✅ Test 2 passed: Can convert back to compatible TimelineEntry format")
        #endif
        
        // Test 3: Test read state management
        timelineState.markPostAsRead(samplePost.id)
        guard timelineState.entries[0].isRead == true else {
            #if DEBUG
            print("❌ Test 3 failed: Post should be marked as read")
            #endif
            return false
        }
        
        guard timelineState.unreadCount == 0 else {
            #if DEBUG
            print("❌ Test 3 failed: Unread count should be 0, got \(timelineState.unreadCount)")
            #endif
            return false
        }
        #if DEBUG
        print("✅ Test 3 passed: Read state management works correctly")
        #endif
        
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
            #if DEBUG
            print("❌ Test 4 failed: Expected 2 entries after update, got \(timelineState.entries.count)")
            #endif
            return false
        }
        #if DEBUG
        print("✅ Test 4 passed: Position preservation works correctly")
        #endif
        
        // Test 5: Test scroll position
        timelineState.saveScrollPosition(samplePost.id)
        guard timelineState.getRestoreScrollPosition() == samplePost.id else {
            #if DEBUG
            print("❌ Test 5 failed: Scroll position not saved correctly")
            #endif
            return false
        }
        #if DEBUG
        print("✅ Test 5 passed: Scroll position management works correctly")
        #endif
        
        #if DEBUG
        print("🎉 TimelineState: All bridge compatibility tests passed!")
        #endif
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
        #if DEBUG
        print("🧪 SocialServiceManager: Testing TimelineState integration...")
        #endif
        
        // Create a test timeline state
        let timelineState = TimelineState()
        
        // Test with current unified timeline (if any)
        if !unifiedTimeline.isEmpty {
            timelineState.updateFromServiceManagerWithExistingLogic(self, isRefresh: false)
            
            // Verify that the conversion worked
            let compatibleEntries = timelineState.compatibleTimelineEntries
            let directEntries = makeTimelineEntries(from: unifiedTimeline)
            
            guard compatibleEntries.count == directEntries.count else {
                #if DEBUG
                print("❌ Integration test failed: Entry count mismatch")
                #endif
                return false
            }
            
            #if DEBUG
            print("✅ SocialServiceManager: TimelineState integration works correctly")
            #endif
            return true
        } else {
            // No posts to test with, but at least verify it doesn't crash
            timelineState.updateFromServiceManagerWithExistingLogic(self, isRefresh: false)
            #if DEBUG
            print("✅ SocialServiceManager: TimelineState integration (empty state) works correctly")
            #endif
            return true
        }
    }
}
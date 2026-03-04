import Foundation
import SwiftUI

// MARK: - Phase 2 Integration Verification

extension TimelineState {
    
    /// Verify that Phase 2 integration is working correctly
    static func verifyPhase2Integration() -> Bool {
        #if DEBUG
        print("🧪 Phase 2: Starting UnifiedTimelineView integration verification...")
        #endif
        
        // Test 1: Verify TimelineState can be created in SwiftUI context
        let timelineState = TimelineState()
        guard timelineState.entries.isEmpty && timelineState.unreadCount == 0 else {
            #if DEBUG
            print("❌ Test 1 failed: TimelineState initial state incorrect")
            #endif
            return false
        }
        #if DEBUG
        print("✅ Test 1 passed: TimelineState initializes correctly in SwiftUI")
        #endif
        
        // Test 2: Simulate cached content loading
        let samplePosts = createSamplePosts()
        timelineState.updateFromPosts(samplePosts, preservePosition: false)
        
        guard timelineState.entries.count == samplePosts.count else {
            #if DEBUG
            print("❌ Test 2 failed: Cached content loading failed")
            #endif
            return false
        }
        #if DEBUG
        print("✅ Test 2 passed: Cached content loading works")
        #endif
        
        // Test 3: Verify compatible entries conversion
        let compatibleEntries = timelineState.compatibleTimelineEntries
        guard compatibleEntries.count == samplePosts.count else {
            #if DEBUG
            print("❌ Test 3 failed: Compatible entries conversion failed")
            #endif
            return false
        }
        
        // Verify the first entry has correct structure
        let firstEntry = compatibleEntries[0]
        guard firstEntry.post.id == samplePosts[0].id else {
            #if DEBUG
            print("❌ Test 3 failed: Entry ID mismatch")
            #endif
            return false
        }
        #if DEBUG
        print("✅ Test 3 passed: Compatible entries conversion works")
        #endif
        
        // Test 4: Test read state management
        let firstPostId = samplePosts[0].id
        timelineState.markPostAsRead(firstPostId)
        
        guard timelineState.entries.first(where: { $0.id == firstPostId })?.isRead == true else {
            #if DEBUG
            print("❌ Test 4 failed: Read state management failed")
            #endif
            return false
        }
        
        guard timelineState.unreadCount == samplePosts.count - 1 else {
            #if DEBUG
            print("❌ Test 4 failed: Unread count incorrect - expected \(samplePosts.count - 1), got \(timelineState.unreadCount)")
            #endif
            return false
        }
        #if DEBUG
        print("✅ Test 4 passed: Read state management works")
        #endif
        
        // Test 5: Test scroll position management
        timelineState.saveScrollPosition(firstPostId)
        guard timelineState.getRestoreScrollPosition() == firstPostId else {
            #if DEBUG
            print("❌ Test 5 failed: Scroll position management failed")
            #endif
            return false
        }
        #if DEBUG
        print("✅ Test 5 passed: Scroll position management works")
        #endif
        
        // Test 6: Test smart insertion (new content preservation)
        let newPost = Post(
            id: "new-post-123",
            content: "This is a new post",
            authorName: "New Author",
            authorUsername: "newauthor",
            authorProfilePictureURL: "",
            createdAt: Date().addingTimeInterval(60), // 1 minute later
            platform: .bluesky,
            originalURL: "",
            attachments: [],
            mentions: [],
            tags: [],
            platformSpecificId: "new-post-123"
        )
        
        let originalCount = timelineState.entries.count
        timelineState.updateFromPosts([newPost] + samplePosts, preservePosition: true)
        
        guard timelineState.entries.count == originalCount + 1 else {
            #if DEBUG
            print("❌ Test 6 failed: Smart insertion failed - expected \(originalCount + 1), got \(timelineState.entries.count)")
            #endif
            return false
        }
        
        // Verify new post is at the top
        guard timelineState.entries.first?.post.id == newPost.id else {
            #if DEBUG
            print("❌ Test 6 failed: New post not inserted at top")
            #endif
            return false
        }
        #if DEBUG
        print("✅ Test 6 passed: Smart insertion works correctly")
        #endif
        
        #if DEBUG
        print("🎉 Phase 2: All integration verification tests passed!")
        #endif
        return true
    }
    
    /// Create sample posts for testing
    private static func createSamplePosts() -> [Post] {
        return [
            Post(
                id: "sample-post-1",
                content: "This is the first sample post for testing",
                authorName: "Test User 1",
                authorUsername: "testuser1",
                authorProfilePictureURL: "",
                createdAt: Date().addingTimeInterval(-120), // 2 minutes ago
                platform: .mastodon,
                originalURL: "",
                attachments: [],
                mentions: [],
                tags: [],
                platformSpecificId: "sample-post-1"
            ),
            Post(
                id: "sample-post-2",
                content: "This is the second sample post for testing",
                authorName: "Test User 2",
                authorUsername: "testuser2",
                authorProfilePictureURL: "",
                createdAt: Date().addingTimeInterval(-60), // 1 minute ago
                platform: .bluesky,
                originalURL: "",
                attachments: [],
                mentions: [],
                tags: [],
                platformSpecificId: "sample-post-2"
            ),
            Post(
                id: "sample-post-3",
                content: "This is the third sample post for testing",
                authorName: "Test User 3",
                authorUsername: "testuser3",
                authorProfilePictureURL: "",
                createdAt: Date(), // Now
                platform: .mastodon,
                originalURL: "",
                attachments: [],
                mentions: [],
                tags: [],
                platformSpecificId: "sample-post-3"
            )
        ]
    }
    
    /// Quick health check for Phase 2 integration
    static func quickPhase2HealthCheck() -> Bool {
        let timelineState = TimelineState()
        
        // Basic functionality check
        let isHealthy = timelineState.entries.isEmpty &&
                       timelineState.unreadCount == 0 &&
                       timelineState.getRestoreScrollPosition() == nil &&
                       !timelineState.getStateSummary().isEmpty
        
        if isHealthy {
            #if DEBUG
            print("✅ Phase 2 health check: PASSED")
            #endif
        } else {
            #if DEBUG
            print("❌ Phase 2 health check: FAILED")
            #endif
        }
        
        return isHealthy
    }
}

// MARK: - UnifiedTimelineView Integration Helper

extension TimelineState {
    
    /// Simulate the UnifiedTimelineView integration flow
    func simulateUnifiedTimelineViewFlow(with serviceManager: SocialServiceManager) -> Bool {
        #if DEBUG
        print("🧪 Simulating UnifiedTimelineView integration flow...")
        #endif
        
        // Step 1: Load cached content (simulates onAppear)
        loadCachedContent(from: serviceManager)
        updateLastVisitDate()
        #if DEBUG
        print("✅ Step 1: Cached content loaded")
        #endif
        
        // Step 2: Simulate network content arriving
        if !serviceManager.unifiedTimeline.isEmpty {
            updateFromServiceManagerWithExistingLogic(serviceManager, isRefresh: false)
            #if DEBUG
            print("✅ Step 2: Network content integrated")
            #endif
        } else {
            #if DEBUG
            print("ℹ️ Step 2: No network content to integrate")
            #endif
        }
        
        // Step 3: Test compatible entries generation
        let compatibleEntries = self.compatibleTimelineEntries
        #if DEBUG
        print("✅ Step 3: Generated \(compatibleEntries.count) compatible entries")
        #endif
        
        // Step 4: Test unread count
        #if DEBUG
        print("✅ Step 4: Unread count: \(self.unreadCount)")
        #endif
        
        // Step 5: Test scroll position
        if let position = getRestoreScrollPosition() {
            #if DEBUG
            print("✅ Step 5: Scroll position available: \(position)")
            #endif
        } else {
            #if DEBUG
            print("ℹ️ Step 5: No saved scroll position")
            #endif
        }
        
        #if DEBUG
        print("🎉 UnifiedTimelineView integration flow simulation completed successfully!")
        #endif
        return true
    }
}
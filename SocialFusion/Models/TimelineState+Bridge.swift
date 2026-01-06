import Foundation

// MARK: - Bridge Extensions for Seamless Integration

extension TimelineState {
    
    /// Convert enhanced entries back to regular TimelineEntry for existing UI components
    var compatibleTimelineEntries: [TimelineEntry] {
        return entries.map { enhanced in
            // Determine the kind based on post properties (same logic as SocialServiceManager.makeTimelineEntries)
            let kind: TimelineEntryKind
            if let original = enhanced.post.originalPost {
                // This is a boost/repost - use boostedBy if available, otherwise fall back to authorUsername
                let boostedByHandle = enhanced.post.boostedBy ?? enhanced.post.authorUsername
                kind = .boost(boostedBy: boostedByHandle)
            } else if let parentId = enhanced.post.inReplyToID {
                // This is a reply
                kind = .reply(parentId: parentId)
            } else {
                // Normal post
                kind = .normal
            }
            
            return TimelineEntry(
                id: enhanced.id,
                kind: kind,
                post: enhanced.post,
                createdAt: enhanced.post.createdAt
            )
        }
    }
    
    /// Quick method to get posts in the existing format
    var compatiblePosts: [Post] {
        return entries.map { $0.post }
    }
    
    /// Load cached posts directly (for immediate startup display)
    func loadCachedContent(from serviceManager: SocialServiceManager) {
        guard !isInitialized else { return }
        
        let cachedPosts = serviceManager.cachedPosts
        if !cachedPosts.isEmpty {
            updateFromPosts(cachedPosts, preservePosition: false)
            print("📱 TimelineState: Loaded \(cachedPosts.count) cached posts for immediate display")
        }
    }
    
    /// Update from service manager's unified timeline (preserves scroll position)
    func updateFromServiceManager(_ serviceManager: SocialServiceManager, isRefresh: Bool = false) {
        if isRefresh {
            // For refreshes, insert new content at top
            updateFromPosts(serviceManager.unifiedTimeline, preservePosition: true)
        } else {
            // For initial loads, replace all content
            updateFromPosts(serviceManager.unifiedTimeline, preservePosition: false)
        }
    }
    
    /// Bridge from existing TimelineEntry array to enhanced entries
    func updateFromExistingTimelineEntries(_ timelineEntries: [TimelineEntry], preservePosition: Bool = true) {
        let newEntries = timelineEntries.map { entry in
            EnhancedTimelineEntry(
                from: entry.post,
                isRead: isPostRead(entry.post.id),
                isNew: isPostNew(entry.post)
            )
        }
        
        if preservePosition && isInitialized && !entries.isEmpty {
            insertNewEntriesAtTop(newEntries)
        } else {
            entries = newEntries
            isInitialized = true
        }
        
        updateUnreadCount()
        print("📱 TimelineState: Updated with \(entries.count) entries from existing TimelineEntry array, \(unreadCount) unread")
    }
    
    /// Bridge method that uses the existing SocialServiceManager.makeTimelineEntries method
    /// This ensures 100% compatibility with the existing timeline entry creation logic
    func updateFromServiceManagerWithExistingLogic(_ serviceManager: SocialServiceManager, isRefresh: Bool = false) {
        // Use the existing makeTimelineEntries method to get properly formatted entries
        let timelineEntries = serviceManager.makeTimelineEntries(from: serviceManager.unifiedTimeline)
        
        // Convert these to enhanced entries
        updateFromExistingTimelineEntries(timelineEntries, preservePosition: isRefresh)
        
        print("📱 TimelineState: Updated using existing makeTimelineEntries logic - \(entries.count) entries, \(unreadCount) unread")
    }
}

extension SocialServiceManager {
    
    /// Bridge method - update timeline state when unified timeline changes
    /// This is purely additive and doesn't affect existing functionality
    func updateTimelineStateIfNeeded(_ timelineState: TimelineState?) {
        guard let timelineState = timelineState else { return }
        
        // Only update if we have new content
        if !unifiedTimeline.isEmpty {
            timelineState.updateFromServiceManager(self, isRefresh: timelineState.isInitialized)
        }
    }
    
    /// Helper to create a timeline entry compatible with enhanced system
    func makeEnhancedTimelineEntries(from posts: [Post]) -> [EnhancedTimelineEntry] {
        return posts.map { post in
            EnhancedTimelineEntry(from: post)
        }
    }
    
    /// Bridge method to get TimelineEntry array in the enhanced format
    func makeTimelineEntriesForTimelineState(from posts: [Post]) -> [TimelineEntry] {
        return posts.map { post in
            // Determine the kind based on post properties (same logic as SocialServiceManager.makeTimelineEntries)
            let kind: TimelineEntryKind
            if let original = post.originalPost {
                // This is a boost/repost - use boostedBy if available, otherwise fall back to authorUsername
                let boostedByHandle = post.boostedBy ?? post.authorUsername
                kind = .boost(boostedBy: boostedByHandle)
            } else if let parentId = post.inReplyToID {
                // This is a reply
                kind = .reply(parentId: parentId)
            } else {
                // Normal post
                kind = .normal
            }
            
            return TimelineEntry(
                id: post.id,
                kind: kind,
                post: post,
                createdAt: post.createdAt
            )
        }
    }
    
    /// New bridge method that integrates TimelineState with existing logic
    func updateTimelineStateWithExistingLogic(_ timelineState: TimelineState, isRefresh: Bool = false) {
        timelineState.updateFromServiceManagerWithExistingLogic(self, isRefresh: isRefresh)
    }
}

// MARK: - Convenience Extensions

extension EnhancedTimelineEntry {
    
    /// Convert back to regular TimelineEntry for existing components
    var compatibleTimelineEntry: TimelineEntry {
        // Determine the kind based on post properties (same logic as SocialServiceManager.makeTimelineEntries)
        let kind: TimelineEntryKind
        if let original = post.originalPost {
            // This is a boost/repost - use boostedBy if available, otherwise fall back to authorUsername
            let boostedByHandle = post.boostedBy ?? post.authorUsername
            kind = .boost(boostedBy: boostedByHandle)
        } else if let parentId = post.inReplyToID {
            // This is a reply
            kind = .reply(parentId: parentId)
        } else {
            // Normal post
            kind = .normal
        }
        
        return TimelineEntry(
            id: self.id,
            kind: kind,
            post: self.post,
            createdAt: self.post.createdAt
        )
    }
    
    /// Check if this entry represents a new post that should be highlighted
    var shouldHighlightAsNew: Bool {
        return isNew && !isRead
    }
    
    /// Get display priority (new unread posts should appear first)
    var displayPriority: Int {
        if isNew && !isRead { return 0 }
        if !isRead { return 1 }
        return 2
    }
}

// MARK: - Debug Helpers

extension TimelineState {
    
    /// Print current state for debugging
    func debugPrint() {
        print(getStateSummary())
        
        let newCount = entries.filter { $0.isNew }.count
        let readCount = entries.filter { $0.isRead }.count
        
        print("📊 Breakdown:")
        print("  - New posts: \(newCount)")
        print("  - Read posts: \(readCount)")
        print("  - Unread posts: \(unreadCount)")
        
        if let firstEntry = entries.first {
            print("  - First post: \(firstEntry.post.author.displayName) - \(firstEntry.post.content.prefix(50))...")
        }
        
        if let scrollPos = scrollPosition {
            print("  - Scroll position: \(scrollPos)")
        }
    }
}
import Foundation
import SwiftUI

/// Enhanced timeline entry that includes read state and position tracking
struct EnhancedTimelineEntry: Identifiable, Equatable {
    let id: String
    let post: Post
    var isRead: Bool
    var isNew: Bool
    let insertedAt: Date
    
    init(from timelineEntry: TimelineEntry) {
        self.id = timelineEntry.id
        self.post = timelineEntry.post
        self.isRead = false // Will be updated based on stored state
        self.isNew = true // Will be determined by insertion logic
        self.insertedAt = Date()
    }
    
    init(from post: Post, isRead: Bool = false, isNew: Bool = true) {
        self.id = post.id
        self.post = post
        self.isRead = isRead
        self.isNew = isNew
        self.insertedAt = Date()
    }
    
    static func == (lhs: EnhancedTimelineEntry, rhs: EnhancedTimelineEntry) -> Bool {
        return lhs.id == rhs.id && lhs.isRead == rhs.isRead && lhs.isNew == rhs.isNew
    }
}

/// Timeline state manager that handles position tracking, read state, and unread counting
@Observable
class TimelineState {
    private(set) var entries: [EnhancedTimelineEntry] = []
    private(set) var scrollPosition: String? = nil
    private(set) var unreadCount: Int = 0
    private(set) var lastReadPosition: String? = nil
    private(set) var isInitialized: Bool = false
    
    // Storage keys for persistence
    private let scrollPositionKey = "timeline_scroll_position"
    private let readPostsKey = "timeline_read_posts"
    private let lastVisitKey = "timeline_last_visit"
    
    // In-memory cache of read posts for this session
    private var readPostIds: Set<String> = []
    private var lastVisitDate: Date = Date()
    
    init() {
        loadPersistedState()
    }
    
    // MARK: - Bridge Methods to Existing System
    
    /// Main bridge method - converts existing TimelineEntry array to enhanced entries
    func updateFromTimelineEntries(_ timelineEntries: [TimelineEntry], preservePosition: Bool = true) {
        let newEntries = timelineEntries.map { entry in
            EnhancedTimelineEntry(
                from: entry,
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
        print("📱 TimelineState: Updated with \(entries.count) entries, \(unreadCount) unread")
    }
    
    /// Bridge method - converts Post array to enhanced entries
    func updateFromPosts(_ posts: [Post], preservePosition: Bool = true) {
        let newEntries = posts.map { post in
            EnhancedTimelineEntry(
                from: post,
                isRead: isPostRead(post.id),
                isNew: isPostNew(post)
            )
        }
        
        if preservePosition && isInitialized && !entries.isEmpty {
            insertNewEntriesAtTop(newEntries)
        } else {
            entries = newEntries
            isInitialized = true
        }
        
        updateUnreadCount()
        print("📱 TimelineState: Updated with \(entries.count) posts, \(unreadCount) unread")
    }
    
    // MARK: - Read State Management
    
    func markPostAsRead(_ postId: String) {
        guard !readPostIds.contains(postId) else { return }
        
        readPostIds.insert(postId)
        
        // Update entry if it exists
        if let index = entries.firstIndex(where: { $0.id == postId }) {
            entries[index].isRead = true
            updateUnreadCount()
        }
        
        // Persist read state
        saveReadState()
        print("📱 TimelineState: Marked post \(postId) as read")
    }
    
    func markPostAsUnread(_ postId: String) {
        readPostIds.remove(postId)
        
        // Update entry if it exists
        if let index = entries.firstIndex(where: { $0.id == postId }) {
            entries[index].isRead = false
            updateUnreadCount()
        }
        
        saveReadState()
    }
    
    private func isPostRead(_ postId: String) -> Bool {
        return readPostIds.contains(postId)
    }
    
    private func isPostNew(_ post: Post) -> Bool {
        // Consider a post "new" if it was created after the last visit
        return post.createdAt > lastVisitDate && !isPostRead(post.id)
    }
    
    // MARK: - Scroll Position Management
    
    func saveScrollPosition(_ postId: String) {
        guard scrollPosition != postId else { return }
        
        scrollPosition = postId
        UserDefaults.standard.set(postId, forKey: scrollPositionKey)
        print("📱 TimelineState: Saved scroll position to \(postId)")
    }
    
    func getRestoreScrollPosition() -> String? {
        return scrollPosition
    }
    
    func clearScrollPosition() {
        scrollPosition = nil
        UserDefaults.standard.removeObject(forKey: scrollPositionKey)
    }
    
    // MARK: - Unread Count Management
    
    private func updateUnreadCount() {
        let newUnreadCount = entries.filter { !$0.isRead }.count
        if unreadCount != newUnreadCount {
            unreadCount = newUnreadCount
            print("📱 TimelineState: Unread count updated to \(unreadCount)")
        }
    }
    
    func clearAllUnread() {
        for i in entries.indices {
            entries[i].isRead = true
        }
        readPostIds.formUnion(entries.map { $0.id })
        updateUnreadCount()
        saveReadState()
        print("📱 TimelineState: Cleared all unread posts")
    }
    
    // MARK: - Smart Insertion Logic
    
    private func insertNewEntriesAtTop(_ newEntries: [EnhancedTimelineEntry]) {
        // Find truly new posts (not already in timeline)
        let existingIds = Set(entries.map { $0.id })
        let genuinelyNewEntries = newEntries.filter { !existingIds.contains($0.id) }
        
        if !genuinelyNewEntries.isEmpty {
            // Insert new posts at the top, preserving user's current position
            entries = genuinelyNewEntries + entries
            print("📱 TimelineState: Inserted \(genuinelyNewEntries.count) new entries at top")
        }
        
        // Update existing entries with latest data
        for newEntry in newEntries {
            if let index = entries.firstIndex(where: { $0.id == newEntry.id }) {
                // Preserve read state but update post data
                entries[index] = EnhancedTimelineEntry(
                    from: newEntry.post,
                    isRead: entries[index].isRead,
                    isNew: entries[index].isNew
                )
            }
        }
    }
    
    // MARK: - Persistence
    
    private func loadPersistedState() {
        // Load scroll position
        scrollPosition = UserDefaults.standard.string(forKey: scrollPositionKey)
        
        // Load read posts
        if let savedReadPosts = UserDefaults.standard.array(forKey: readPostsKey) as? [String] {
            readPostIds = Set(savedReadPosts)
        }
        
        // Load last visit date
        if let savedLastVisit = UserDefaults.standard.object(forKey: lastVisitKey) as? Date {
            lastVisitDate = savedLastVisit
        }
        
        print("📱 TimelineState: Loaded persisted state - \(readPostIds.count) read posts, scroll position: \(scrollPosition ?? "none")")
    }
    
    private func saveReadState() {
        UserDefaults.standard.set(Array(readPostIds), forKey: readPostsKey)
    }
    
    func updateLastVisitDate() {
        lastVisitDate = Date()
        UserDefaults.standard.set(lastVisitDate, forKey: lastVisitKey)
    }
    
    // MARK: - Utility Methods
    
    func getTopVisiblePostId(from visibleIds: [String]) -> String? {
        // Find the first visible post in our entries
        return entries.first { visibleIds.contains($0.id) }?.id
    }
    
    /// For debugging - get summary of current state
    func getStateSummary() -> String {
        return """
        📊 TimelineState Summary:
        - Total entries: \(entries.count)
        - Unread count: \(unreadCount)
        - Read posts in session: \(readPostIds.count)
        - Scroll position: \(scrollPosition ?? "none")
        - Initialized: \(isInitialized)
        """
    }
}
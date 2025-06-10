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
    
    // Enhanced Position Management
    private let smartPositionManager = SmartPositionManager()
    private let config = TimelineConfiguration.shared
    
    // Restoration suggestions for user
    @Published var restorationSuggestions: [RestorationSuggestion] = []
    @Published var showRestoreOptions: Bool = false
    
    // Storage keys for persistence
    private let scrollPositionKey = "timeline_scroll_position"
    private let readPostsKey = "timeline_read_posts"
    private let lastVisitKey = "timeline_last_visit"
    
    // In-memory cache of read posts for this session
    private var readPostIds: Set<String> = []
    private var lastVisitDate: Date = Date()
    
    // Auto-save timer for position tracking
    private var autoSaveTimer: Timer?
    
    init() {
        loadPersistedState()
        setupAutoSave()
        
        if config.verboseMode {
            config.logConfiguration()
        }
    }
    
    deinit {
        autoSaveTimer?.invalidate()
    }
    
    // MARK: - Enhanced Position Management
    
    private func setupAutoSave() {
        guard config.isFeatureEnabled(.positionPersistence) else { return }
        
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: config.autoSaveInterval, repeats: true) { [weak self] _ in
            self?.autoSaveCurrentPosition()
        }
    }
    
    private func autoSaveCurrentPosition() {
        guard let currentPosition = scrollPosition else { return }
        
        smartPositionManager.recordPosition(postId: currentPosition)
        
        if config.positionLogging {
            print("💾 Auto-saved position: \(currentPosition)")
        }
    }
    
    /// Smart position restoration with fallback strategies
    func restorePositionIntelligently(fallbackStrategy: FallbackStrategy? = nil) -> (index: Int?, offset: CGFloat) {
        let result = smartPositionManager.restorePosition(
            for: entries,
            targetPostId: scrollPosition,
            fallbackStrategy: fallbackStrategy
        )
        
        // Update restoration suggestions
        updateRestorationSuggestions()
        
        if config.timelineLogging {
            print("🎯 Smart restoration result: index=\(result.index?.description ?? "nil"), offset=\(result.offset)")
        }
        
        return result
    }
    
    /// Update restoration suggestions based on current timeline
    private func updateRestorationSuggestions() {
        restorationSuggestions = smartPositionManager.getRestorationSuggestions(for: entries)
        showRestoreOptions = !restorationSuggestions.isEmpty && config.smartRestorationEnabled
    }
    
    /// Apply a specific restoration suggestion
    func applyRestorationSuggestion(_ suggestion: RestorationSuggestion) {
        saveScrollPosition(suggestion.postId)
        showRestoreOptions = false
        
        if config.verboseMode {
            print("✅ Applied restoration suggestion: \(suggestion.title)")
        }
    }
    
    /// Dismiss restoration suggestions
    func dismissRestorationSuggestions() {
        showRestoreOptions = false
        restorationSuggestions = []
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
        updateRestorationSuggestions()
        
        if config.timelineLogging {
            print("📱 TimelineState: Updated with \(entries.count) entries, \(unreadCount) unread")
        }
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
        updateRestorationSuggestions()
        
        if config.timelineLogging {
            print("📱 TimelineState: Updated with \(entries.count) posts, \(unreadCount) unread")
        }
    }
    
    // MARK: - Read State Management
    
    func markPostAsRead(_ postId: String) {
        guard config.isFeatureEnabled(.unreadTracking) else { return }
        guard !readPostIds.contains(postId) else { return }
        
        readPostIds.insert(postId)
        
        // Update entry if it exists
        if let index = entries.firstIndex(where: { $0.id == postId }) {
            entries[index].isRead = true
            updateUnreadCount()
        }
        
        // Persist read state
        saveReadState()
        
        if config.timelineLogging {
            print("📱 TimelineState: Marked post \(postId) as read")
        }
    }
    
    func markPostAsUnread(_ postId: String) {
        guard config.isFeatureEnabled(.unreadTracking) else { return }
        
        readPostIds.remove(postId)
        
        // Update entry if it exists
        if let index = entries.firstIndex(where: { $0.id == postId }) {
            entries[index].isRead = false
            updateUnreadCount()
        }
        
        saveReadState()
    }
    
    private func isPostRead(_ postId: String) -> Bool {
        guard config.isFeatureEnabled(.unreadTracking) else { return false }
        return readPostIds.contains(postId)
    }
    
    private func isPostNew(_ post: Post) -> Bool {
        // Consider a post "new" if it was created after the last visit
        return post.createdAt > lastVisitDate && !isPostRead(post.id)
    }
    
    // MARK: - Scroll Position Management
    
    func saveScrollPosition(_ postId: String) {
        guard config.isFeatureEnabled(.positionPersistence) else { return }
        guard scrollPosition != postId else { return }
        
        scrollPosition = postId
        UserDefaults.standard.set(postId, forKey: scrollPositionKey)
        
        // Record in smart position manager for cross-session sync
        smartPositionManager.recordPosition(postId: postId)
        
        if config.positionLogging {
            print("📱 TimelineState: Saved scroll position to \(postId)")
        }
    }
    
    func saveScrollPositionWithOffset(_ postId: String, offset: CGFloat) {
        guard config.isFeatureEnabled(.positionPersistence) else { return }
        
        scrollPosition = postId
        UserDefaults.standard.set(postId, forKey: scrollPositionKey)
        
        // Record with offset in smart position manager
        smartPositionManager.recordPosition(postId: postId, scrollOffset: offset)
        
        if config.positionLogging {
            print("📱 TimelineState: Saved position \(postId) with offset \(offset)")
        }
    }
    
    func getRestoreScrollPosition() -> String? {
        guard config.isFeatureEnabled(.positionPersistence) else { return nil }
        return scrollPosition
    }
    
    func clearScrollPosition() {
        scrollPosition = nil
        UserDefaults.standard.removeObject(forKey: scrollPositionKey)
    }
    
    // MARK: - Cross-Session Sync
    
    /// Trigger manual sync with iCloud
    func syncAcrossDevices() async {
        guard config.isFeatureEnabled(.crossSessionSync) else { return }
        
        await smartPositionManager.syncWithiCloud()
        
        // After sync, update restoration suggestions
        updateRestorationSuggestions()
    }
    
    /// Get sync status for UI
    var syncStatus: SyncStatus {
        return smartPositionManager.syncStatus
    }
    
    var lastSyncTime: Date? {
        return smartPositionManager.lastSyncTime
    }
    
    // MARK: - Unread Count Management
    
    private func updateUnreadCount() {
        guard config.isFeatureEnabled(.unreadTracking) else {
            unreadCount = 0
            return
        }
        
        let newUnreadCount = entries.filter { !$0.isRead }.count
        if unreadCount != newUnreadCount {
            unreadCount = newUnreadCount
            
            if config.timelineLogging {
                print("📱 TimelineState: Unread count updated to \(unreadCount)")
            }
        }
    }
    
    func clearAllUnread() {
        guard config.isFeatureEnabled(.unreadTracking) else { return }
        
        for i in entries.indices {
            entries[i].isRead = true
        }
        readPostIds.formUnion(entries.map { $0.id })
        updateUnreadCount()
        saveReadState()
        
        if config.timelineLogging {
            print("📱 TimelineState: Cleared all unread posts")
        }
    }
    
    // MARK: - Smart Insertion Logic
    
    private func insertNewEntriesAtTop(_ newEntries: [EnhancedTimelineEntry]) {
        // Find truly new posts (not already in timeline)
        let existingIds = Set(entries.map { $0.id })
        let genuinelyNewEntries = newEntries.filter { !existingIds.contains($0.id) }
        
        if !genuinelyNewEntries.isEmpty {
            // Insert new posts at the top, preserving user's current position
            entries = genuinelyNewEntries + entries
            
            if config.timelineLogging {
                print("📱 TimelineState: Inserted \(genuinelyNewEntries.count) new entries at top")
            }
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
        if config.isFeatureEnabled(.positionPersistence) {
            scrollPosition = UserDefaults.standard.string(forKey: scrollPositionKey)
        }
        
        // Load read posts
        if config.isFeatureEnabled(.unreadTracking),
           let savedReadPosts = UserDefaults.standard.array(forKey: readPostsKey) as? [String] {
            readPostIds = Set(savedReadPosts)
        }
        
        // Load last visit date
        if let savedLastVisit = UserDefaults.standard.object(forKey: lastVisitKey) as? Date {
            lastVisitDate = savedLastVisit
        }
        
        if config.verboseMode {
            print("📱 TimelineState: Loaded persisted state - \(readPostIds.count) read posts, scroll position: \(scrollPosition ?? "none")")
        }
    }
    
    private func saveReadState() {
        guard config.isFeatureEnabled(.unreadTracking) else { return }
        UserDefaults.standard.set(Array(readPostIds), forKey: readPostsKey)
    }
    
    func updateLastVisitDate() {
        lastVisitDate = Date()
        UserDefaults.standard.set(lastVisitDate, forKey: lastVisitKey)
    }
    
    // MARK: - Memory Management & Performance
    
    /// Clean up old data based on configuration
    func performMaintenance() {
        // Clean up old position history
        smartPositionManager.cleanupOldHistory()
        
        // Limit read posts to prevent unbounded growth
        if readPostIds.count > config.maxUnreadHistory {
            let sortedReadPosts = Array(readPostIds).prefix(config.maxUnreadHistory / 2)
            readPostIds = Set(sortedReadPosts)
            saveReadState()
        }
        
        // Limit entries based on cache size
        if entries.count > config.maxCacheSize {
            let keepCount = config.maxCacheSize
            entries = Array(entries.prefix(keepCount))
        }
        
        if config.verboseMode {
            print("🧹 TimelineState: Performed maintenance - \(entries.count) entries, \(readPostIds.count) read posts")
        }
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
        - Smart restoration: \(config.smartRestorationEnabled)
        - Cross-session sync: \(config.crossSessionSyncEnabled)
        - Sync status: \(syncStatus)
        - Restoration suggestions: \(restorationSuggestions.count)
        """
    }
    
    /// Export state for debugging
    func exportStateForDebugging() -> String {
        let smartPositionData = smartPositionManager.exportPositionHistory()
        
        return """
        📋 Complete TimelineState Debug Export:
        
        \(getStateSummary())
        
        📍 Smart Position History:
        \(smartPositionData)
        
        ⚙️ Configuration:
        \(config.verboseMode ? "Verbose logging enabled" : "Standard logging")
        """
    }
}
import CloudKit
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
        self.isRead = false  // Will be updated based on stored state
        self.isNew = true  // Will be determined by insertion logic
        self.insertedAt = Date()
    }

    init(from timelineEntry: TimelineEntry, isRead: Bool, isNew: Bool) {
        self.id = timelineEntry.id
        self.post = timelineEntry.post
        self.isRead = isRead
        self.isNew = isNew
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
class TimelineState: ObservableObject {
    @Published private(set) var entries: [EnhancedTimelineEntry] = []
    @Published private(set) var scrollPosition: String? = nil
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var lastReadPosition: String? = nil
    @Published private(set) var isInitialized: Bool = false

    /// PHASE 3+: Enhanced sync status with CloudKit integration
    @Published private(set) var syncStatus: SyncStatus = .idle
    @Published private(set) var lastSyncTime: Date? = nil
    @Published var restorationSuggestions: [RestorationSuggestion] = []
    @Published var showRestoreOptions: Bool = false

    // Private state (not published as they don't affect UI directly)
    private var readPostIds: Set<String> = []
    private var lastVisitDate: Date = Date()

    // Enhanced Position Management
    private let smartPositionManager = SmartPositionManager()
    private let config = TimelineConfiguration.shared

    // Auto-save timer for position tracking
    private var autoSaveTimer: Timer?

    // Storage keys for persistence
    private let scrollPositionKey = "timeline_scroll_position"
    private let readPostsKey = "timeline_read_posts"
    private let lastVisitKey = "timeline_last_visit"

    public init() {
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

        autoSaveTimer = Timer.scheduledTimer(
            withTimeInterval: config.autoSaveInterval, repeats: true
        ) { [weak self] _ in
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
    func restorePositionIntelligently(fallbackStrategy: FallbackStrategy? = nil) -> (
        index: Int?, offset: CGFloat
    ) {
        let result = smartPositionManager.restorePosition(
            for: entries,
            targetPostId: scrollPosition,
            fallbackStrategy: fallbackStrategy
        )

        // Update restoration suggestions
        updateRestorationSuggestions()

        if config.timelineLogging {
            print(
                "🎯 Smart restoration result: index=\(result.index?.description ?? "nil"), offset=\(result.offset)"
            )
        }

        return result
    }

    /// Update restoration suggestions based on current timeline
    private func updateRestorationSuggestions() {
        restorationSuggestions = smartPositionManager.getRestorationSuggestions(for: entries)
        // Only show restore options as a fallback when automatic restoration fails
        // The banner will be hidden by dismissRestorationSuggestions() if automatic restoration succeeds
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
    func updateFromTimelineEntries(
        _ timelineEntries: [TimelineEntry], preservePosition: Bool = true
    ) {
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
        let wasFirstLoad = !isInitialized

        let newEntries = posts.map { post in
            let isNew = isPostNew(post)
            let isRead = isPostRead(post.id)
            return EnhancedTimelineEntry(
                from: post,
                isRead: isRead,
                isNew: isNew
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
        // Consider posts "new" if they're not already read
        // On first load, we want some posts to be marked as new so the unread indicator works

        // If this is the very first time using the app (no read posts in history), mark recent posts as new
        if readPostIds.isEmpty {
            // Mark posts from the last 24 hours as "new" on first load
            let oneDayAgo = Date().addingTimeInterval(-24 * 60 * 60)
            let isRecent = post.createdAt > oneDayAgo
            let isNotRead = !isPostRead(post.id)

            if config.verboseMode && isRecent && isNotRead {
                print("📱 TimelineState: Marking post as new (first-time user): \(post.id)")
            }

            return isRecent && isNotRead
        }

        // For subsequent loads, only mark posts newer than last visit as new
        let isNewerThanLastVisit = post.createdAt > lastVisitDate
        let isNotRead = !isPostRead(post.id)

        if config.verboseMode && isNewerThanLastVisit && isNotRead {
            print("📱 TimelineState: Marking post as new (newer than last visit): \(post.id)")
        }

        return isNewerThanLastVisit && isNotRead
    }

    // MARK: - Scroll Position Management

    func saveScrollPosition(_ postId: String) {
        guard config.isFeatureEnabled(.positionPersistence) else { return }
        guard scrollPosition != postId else { return }

        scrollPosition = postId
        UserDefaults.standard.set(postId, forKey: scrollPositionKey)

        // Record in smart position manager for cross-session sync
        smartPositionManager.recordPosition(postId: postId)

    }

    func saveScrollPositionWithOffset(_ postId: String, offset: CGFloat) {
        guard config.isFeatureEnabled(.positionPersistence) else { return }

        scrollPosition = postId
        UserDefaults.standard.set(postId, forKey: scrollPositionKey)

        // Record with offset in smart position manager
        smartPositionManager.recordPosition(postId: postId, scrollOffset: offset)

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

    /// Trigger manual sync with iCloud - DISABLED to prevent startup hangs
    func syncAcrossDevices() async {
        guard config.isFeatureEnabled(.crossSessionSync) else { return }

        // DISABLED: CloudKit sync causing startup hangs
        // await smartPositionManager.syncWithiCloud()

        // Set sync status to idle since we're not actually syncing
        syncStatus = .idle
        lastSyncTime = Date()

        // Still update restoration suggestions using local data
        updateRestorationSuggestions()

    }

    // MARK: - Unread Count Management

    private func updateUnreadCount() {
        guard config.isFeatureEnabled(.unreadTracking) else {
            unreadCount = 0
            return
        }

        // Only count posts that are actually "new" (not all unread posts)
        let newEntries = entries.filter { $0.isNew && !$0.isRead }
        let newUnreadCount = newEntries.count

        if config.verboseMode {
            print(
                "📱 TimelineState: Updating unread count - total entries: \(entries.count), new entries: \(newEntries.count), read posts: \(readPostIds.count)"
            )

            // Log a few example entries for debugging
            for (index, entry) in entries.prefix(5).enumerated() {
                print(
                    "  Entry \(index): isNew=\(entry.isNew), isRead=\(entry.isRead), id=\(entry.post.id)"
                )
            }
        }

        if unreadCount != newUnreadCount {
            unreadCount = newUnreadCount

            if config.timelineLogging {
                print("📱 TimelineState: Unread count updated to \(unreadCount) (new posts only)")
            }
        }
    }

    func clearAllUnread() {
        guard config.isFeatureEnabled(.unreadTracking) else { return }

        // Mark all entries as read and not new
        for i in entries.indices {
            entries[i].isRead = true
            entries[i].isNew = false  // Clear the "new" flag too
        }
        readPostIds.formUnion(entries.map { $0.id })
        updateUnreadCount()
        saveReadState()

    }

    /// Clear unread count only for posts above the current position
    func clearUnreadAbovePosition(_ currentPostId: String) {
        guard config.isFeatureEnabled(.unreadTracking) else { return }

        guard let currentIndex = entries.firstIndex(where: { $0.id == currentPostId }) else {
            return
        }

        // Mark only posts above the current position as read
        for i in 0..<currentIndex {
            entries[i].isRead = true
            entries[i].isNew = false
            readPostIds.insert(entries[i].id)
        }

        updateUnreadCount()
        saveReadState()

    }

    // MARK: - Smart Insertion Logic

    private func insertNewEntriesAtTop(_ newEntries: [EnhancedTimelineEntry]) {
        // Find truly new posts (not already in timeline)
        let existingIds = Set(entries.map { $0.id })
        let genuinelyNewEntries = newEntries.filter { !existingIds.contains($0.id) }

        if !genuinelyNewEntries.isEmpty {
            // Insert new posts at the top, preserving user's current position
            entries = genuinelyNewEntries + entries

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
            let savedReadPosts = UserDefaults.standard.array(forKey: readPostsKey) as? [String]
        {
            readPostIds = Set(savedReadPosts)
        }

        // Load last visit date
        if let savedLastVisit = UserDefaults.standard.object(forKey: lastVisitKey) as? Date {
            lastVisitDate = savedLastVisit
        }

        if config.verboseMode {
            print("📱 TimelineState: Loaded persisted state:")
            print("  - Read posts: \(readPostIds.count)")
            print("  - Scroll position: \(scrollPosition ?? "none")")
            print("  - Last visit date: \(lastVisitDate)")
            print("  - Time since last visit: \(Date().timeIntervalSince(lastVisitDate)) seconds")
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

    /// Debug method to reset read posts and test unread indicators
    func debugResetReadPosts() {
        guard config.verboseMode else { return }

        print("🐛 DEBUG: Resetting read posts to test unread indicators")

        // Clear read posts
        readPostIds.removeAll()
        saveReadState()

        // Set last visit to 1 hour ago so recent posts appear as new
        lastVisitDate = Date().addingTimeInterval(-3600)  // 1 hour ago
        UserDefaults.standard.set(lastVisitDate, forKey: lastVisitKey)

        // Update all entries to be unread and potentially new
        for i in entries.indices {
            entries[i].isRead = false
            entries[i].isNew = isPostNew(entries[i].post)
        }

        // Recalculate unread count
        updateUnreadCount()

        print("🐛 DEBUG: Reset complete - \(unreadCount) posts should now show as unread")
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

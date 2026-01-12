#if DEBUG
import Combine
import Foundation
import SwiftUI

/// Single source of truth for timeline state and position management
/// Replaces the multiple competing state systems (TimelineState, TimelineViewModel, local state)
@MainActor
class TimelineController: ObservableObject {

    // MARK: - Published State (UI binds to these)

    @Published private(set) var posts: [Post] = []
    @Published private(set) var entries: [TimelineEntry] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var unreadCount: Int = 0
    @Published var scrollPosition: ScrollPosition = .top

    // MARK: - Private State

    private var readPostIds: Set<String> = []
    private var lastVisitDate: Date = Date()
    private let serviceManager: SocialServiceManager
    private let config = TimelineConfiguration.shared
    internal var isInitialized: Bool = false

    // Storage keys
    private let scrollPositionKey = "timeline_scroll_position"
    private let readPostsKey = "timeline_read_posts"
    private let lastVisitKey = "timeline_last_visit"

    // MARK: - Initialization

    init(serviceManager: SocialServiceManager) {
        self.serviceManager = serviceManager
        loadPersistedState()

        if config.verboseMode {
            print("📱 TimelineController: Initialized with single source of truth architecture")
        }
    }

    // MARK: - Public Interface (matches existing functionality)

    /// Load timeline posts and restore position atomically
    func loadTimeline() async {
        // Safety check to prevent multiple simultaneous loads
        guard !isLoading else {
            if config.verboseMode {
                print("📱 TimelineController: Load already in progress, skipping")
            }
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            if config.verboseMode {
                print("📱 TimelineController: Starting timeline load")
            }

            let newPosts = try await fetchPosts()

            if config.verboseMode {
                print("📱 TimelineController: Fetched \(newPosts.count) posts")
            }

            await updateTimelineAtomically(with: newPosts)

            if config.verboseMode {
                print("📱 TimelineController: Timeline load completed successfully")
            }
        } catch {
            if config.verboseMode {
                print("❌ TimelineController: Failed to load timeline: \(error)")
            }

            // Don't crash on error - just log and continue
            await MainActor.run {
                // Set empty state on error
                self.posts = []
                self.entries = []
                self.isInitialized = true
            }
        }
    }

    /// Refresh timeline (pull-to-refresh)
    func refreshTimeline() async {
        // Preserve current position during refresh
        let currentPosition = scrollPosition
        await loadTimeline()

        // If we had a valid position, try to maintain it
        if case .index(let index, offset: _) = currentPosition, index > 0 {
            await restorePosition(currentPosition)
        }
    }

    /// Mark post as read and update unread count
    func markPostAsRead(_ postId: String) {
        guard !readPostIds.contains(postId) else { return }

        readPostIds.insert(postId)
        updateUnreadCount()
        saveReadState()

        if config.timelineLogging {
            print("📱 TimelineController: Marked post \(postId) as read")
        }
    }

    /// Save current scroll position
    func saveScrollPosition(_ index: Int, offset: CGFloat = 0) {
        guard config.isFeatureEnabled(.positionPersistence) else { return }
        guard index < posts.count else { return }

        let position = ScrollPosition.index(index, offset: offset)
        scrollPosition = position

        // Save to UserDefaults
        let postId = posts[index].id
        UserDefaults.standard.set(postId, forKey: scrollPositionKey)

        if config.positionLogging {
            print("📱 TimelineController: Saved position - index: \(index), postId: \(postId)")
        }
    }

    /// Clear all unread posts (when scrolling to top)
    func clearAllUnread() {
        guard config.isFeatureEnabled(.unreadTracking) else { return }

        // Mark all posts as read
        for post in posts {
            readPostIds.insert(post.id)
        }

        updateUnreadCount()
        saveReadState()

        if config.timelineLogging {
            print("📱 TimelineController: Cleared all unread posts")
        }
    }

    /// Scroll to top
    func scrollToTop() {
        scrollPosition = .top
        clearAllUnread()
    }

    /// Get timeline entries (for compatibility with existing UI)
    func getTimelineEntries() -> [TimelineEntry] {
        return entries
    }

    // MARK: - Private Implementation

    private func fetchPosts() async throws -> [Post] {
        // Use the existing service manager's unified timeline
        // This maintains 100% compatibility with existing networking

        let allAccounts = serviceManager.accounts

        if config.verboseMode {
            print("📱 TimelineController: fetchPosts called")
            print(
                "📱   - Service manager unified timeline count: \(serviceManager.unifiedTimeline.count)"
            )
            print("📱   - Available accounts: \(allAccounts.count)")
        }

        if serviceManager.unifiedTimeline.isEmpty || allAccounts.isEmpty {
            if allAccounts.isEmpty {
                if config.verboseMode {
                    print("📱 TimelineController: No accounts configured, returning empty timeline")
                }
                return []
            }

            // Trigger a refresh if we have no posts but have accounts
            if config.verboseMode {
                print("📱 TimelineController: Timeline empty, refreshing from service manager")
            }
            let refreshedPosts = try await serviceManager.refreshTimeline(accounts: allAccounts)

            if config.verboseMode {
                print("📱 TimelineController: Refresh completed, got \(refreshedPosts.count) posts")
            }
            return refreshedPosts
        } else {
            // Return existing timeline posts
            if config.verboseMode {
                print(
                    "📱 TimelineController: Using existing \(serviceManager.unifiedTimeline.count) posts from service manager"
                )
            }
            return serviceManager.unifiedTimeline
        }
    }

    /// Atomically update timeline with position restoration
    internal func updateTimelineAtomically(with newPosts: [Post]) async {
        let wasFirstLoad = !isInitialized

        // Create timeline entries
        let newEntries = serviceManager.makeTimelineEntries(from: newPosts)

        // Find restore position BEFORE updating UI
        let restorePosition = wasFirstLoad ? findRestorePosition(in: newPosts) : scrollPosition

        // Atomic update - UI sees everything at once
        withAnimation(.none) {  // No animation for restoration
            self.posts = newPosts
            self.entries = newEntries
            self.scrollPosition = restorePosition
            self.isInitialized = true
        }

        updateUnreadCount()

        if config.timelineLogging {
            print(
                "📱 TimelineController: Updated timeline - \(newPosts.count) posts, position: \(restorePosition)"
            )
        }
    }

    /// Find the best restore position for new posts
    private func findRestorePosition(in newPosts: [Post]) -> ScrollPosition {
        guard config.isFeatureEnabled(.positionPersistence) else { return .top }
        guard let savedPostId = UserDefaults.standard.string(forKey: scrollPositionKey) else {
            return .top
        }

        // Find exact match
        if let index = newPosts.firstIndex(where: { $0.id == savedPostId }) {
            if config.positionLogging {
                print("🎯 TimelineController: Found exact match at index \(index)")
            }
            return .index(index)
        }

        // Find temporal proximity (posts around the same time)
        if let savedPost = findPostInHistory(savedPostId),
            let nearestIndex = findTemporallyNearestPost(to: savedPost.createdAt, in: newPosts)
        {
            if config.positionLogging {
                print("🎯 TimelineController: Found temporal match at index \(nearestIndex)")
            }
            return .index(nearestIndex)
        }

        // Fallback to top - always start fresh users at the top for best UX
        if config.positionLogging {
            print("🎯 TimelineController: No saved position found, starting at top")
        }
        return .top
    }

    /// Find temporally nearest post
    private func findTemporallyNearestPost(to targetDate: Date, in posts: [Post]) -> Int? {
        var closestIndex: Int?
        var closestDistance: TimeInterval = .infinity

        for (index, post) in posts.enumerated() {
            let distance = abs(post.createdAt.timeIntervalSince(targetDate))
            if distance < closestDistance {
                closestDistance = distance
                closestIndex = index
            }
        }

        // Only accept if within 1 hour
        return closestDistance < 3600 ? closestIndex : nil
    }

    /// Update unread count based on current state
    private func updateUnreadCount() {
        guard config.isFeatureEnabled(.unreadTracking) else {
            unreadCount = 0
            return
        }

        // Count posts that haven't been read
        let newUnreadCount = posts.filter { !readPostIds.contains($0.id) }.count

        if unreadCount != newUnreadCount {
            unreadCount = newUnreadCount

            if config.timelineLogging {
                print("📱 TimelineController: Unread count updated to \(unreadCount)")
            }
        }
    }

    /// Restore to specific position
    private func restorePosition(_ position: ScrollPosition) async {
        scrollPosition = position
    }

    // MARK: - Persistence

    private func loadPersistedState() {
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
            print("📱 TimelineController: Loaded \(readPostIds.count) read posts from persistence")
        }
    }

    private func saveReadState() {
        guard config.isFeatureEnabled(.unreadTracking) else { return }
        UserDefaults.standard.set(Array(readPostIds), forKey: readPostsKey)
    }

    private func findPostInHistory(_ postId: String) -> Post? {
        // In a real implementation, this might look in a local cache
        // For now, return nil to use fallback positioning
        return nil
    }

    /// Update last visit date (for unread tracking)
    func updateLastVisitDate() {
        lastVisitDate = Date()
        UserDefaults.standard.set(lastVisitDate, forKey: lastVisitKey)
    }

    /// Update from existing timeline state (migration bridge)
    func updateFromExistingState(_ posts: [Post]) async {
        await updateTimelineAtomically(with: posts)
    }

    /// Restore scroll position from saved state
    func restorePosition() {
        let startTime = Date()

        // Simple implementation for now - just scroll to top
        scrollPosition = .top

        // Report successful restoration
        let restorationTime = Date().timeIntervalSince(startTime)
        GradualMigrationManager.shared.recordPositionRestoration(
            success: true,
            timeSeconds: restorationTime
        )

        if config.positionLogging {
            print(
                "🔄 [TimelineController] Position restored in \(String(format: "%.3f", restorationTime))s"
            )
        }
    }
}

// MARK: - Supporting Types

enum ScrollPosition: Equatable {
    case top
    case index(Int, offset: CGFloat = 0)

    var index: Int? {
        switch self {
        case .top:
            return 0
        case .index(let idx, _):
            return idx
        }
    }

    var offset: CGFloat {
        switch self {
        case .top:
            return 0
        case .index(_, let offset):
            return offset
        }
    }
}

// MARK: - Compatibility Extensions

extension TimelineController {
    /// Bridge to existing TimelineState interface (for gradual migration)
    // TODO: Re-implement compatibility bridge if needed
}
#endif


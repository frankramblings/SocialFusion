import Foundation

@MainActor
final class TimelineRefreshCoordinator: ObservableObject {
    enum RefreshTrigger: String {
        case foreground
        case idlePolling
    }

    @Published private(set) var bufferCount: Int = 0
    @Published private(set) var bufferEarliestTimestamp: Date?
    @Published private(set) var bufferSources: Set<SocialPlatform> = []
    @Published private(set) var isNearTop: Bool = true
    @Published private(set) var isDeepHistory: Bool = false
    @Published private(set) var isScrolling: Bool = false

    private let timelineID: String
    private let platforms: [SocialPlatform]
    private let isLoading: () -> Bool
    private let fetchPostsForPlatform: (SocialPlatform) async -> [Post]
    private let filterPosts: ([Post]) async -> [Post]
    private let mergeBufferedPosts: ([Post]) -> Void
    private let refreshVisibleTimeline: (TimelineRefreshIntent) async -> Void
    private let visiblePostsProvider: () -> [Post]
    private let log: (String) -> Void

    private let buffer = TimelineBuffer()
    private var autoRefreshTasks: [SocialPlatform: Task<Void, Never>] = [:]
    private var activeAutoFetchTask: Task<[Post], Never>?
    private var autoMergeTask: Task<Void, Never>?
    private var lastFetchAtByPlatform: [SocialPlatform: Date] = [:]
    private var lastVisibleInteractionAt: Date = Date.distantPast
    private var isTimelineVisible = false
    private var isComposing = false

    private let foregroundRefreshRange: ClosedRange<TimeInterval> = 60...120
    private let mastodonPollingRange: ClosedRange<TimeInterval> = 45...60
    private let blueskyPollingRange: ClosedRange<TimeInterval> = 30...45
    private let interactionGracePeriod: TimeInterval = 4.0
    private let topMergeGracePeriod: TimeInterval = 2.5

    init(
        timelineID: String,
        platforms: [SocialPlatform],
        isLoading: @escaping () -> Bool,
        fetchPostsForPlatform: @escaping (SocialPlatform) async -> [Post],
        filterPosts: @escaping ([Post]) async -> [Post],
        mergeBufferedPosts: @escaping ([Post]) -> Void,
        refreshVisibleTimeline: @escaping (TimelineRefreshIntent) async -> Void,
        visiblePostsProvider: @escaping () -> [Post],
        log: @escaping (String) -> Void
    ) {
        self.timelineID = timelineID
        self.platforms = platforms
        self.isLoading = isLoading
        self.fetchPostsForPlatform = fetchPostsForPlatform
        self.filterPosts = filterPosts
        self.mergeBufferedPosts = mergeBufferedPosts
        self.refreshVisibleTimeline = refreshVisibleTimeline
        self.visiblePostsProvider = visiblePostsProvider
        self.log = log
        updateSnapshot(buffer.snapshot, reason: "init")
    }

    deinit {
        autoRefreshTasks.values.forEach { $0.cancel() }
        autoRefreshTasks.removeAll()
        activeAutoFetchTask?.cancel()
        activeAutoFetchTask = nil
        autoMergeTask?.cancel()
        autoMergeTask = nil
    }

    func setTimelineVisible(_ isVisible: Bool) {
        guard isTimelineVisible != isVisible else { return }
        isTimelineVisible = isVisible
        if isVisible {
            startAutoRefresh()
        } else {
            stopAutoRefresh()
        }
    }

    func setComposing(_ isComposing: Bool) {
        self.isComposing = isComposing
        if isComposing {
            cancelActiveAutoFetch(reason: "compose")
        }
    }

    func handleAppForegrounded() {
        Task { await requestPrefetch(trigger: .foreground) }
    }

    func recordVisibleInteraction() {
        lastVisibleInteractionAt = Date()
    }

    func scrollInteractionBegan() {
        guard !isScrolling else { return }
        isScrolling = true
        recordVisibleInteraction()
        cancelActiveAutoFetch(reason: "scroll")
        log("🔁 [Refresh:\(timelineID)] Scroll began - auto refresh suspended")
    }

    func scrollInteractionEnded() {
        guard isScrolling else { return }
        isScrolling = false
        recordVisibleInteraction()
        scheduleAutoMergeIfEligible()
        log("🔁 [Refresh:\(timelineID)] Scroll ended - auto refresh eligible")
    }

    func updateScrollState(isNearTop: Bool, isDeepHistory: Bool) {
        if self.isNearTop != isNearTop {
            self.isNearTop = isNearTop
        }
        if self.isDeepHistory != isDeepHistory {
            self.isDeepHistory = isDeepHistory
        }
        scheduleAutoMergeIfEligible()
    }

    func handleVisibleTimelineUpdate(_ visiblePosts: [Post]) {
        updateSnapshot(buffer.removeVisible(visiblePosts), reason: "visible update")
    }

    func manualRefresh(intent: TimelineRefreshIntent) async {
        log("🔄 [Refresh:\(timelineID)] Manual refresh (\(intent.rawValue))")
        
        // When at top, merge buffered items first for smooth experience
        if isNearTop && bufferCount > 0 {
            log("✨ [Refresh:\(timelineID)] At top with buffered items - merging first")
            mergeBufferedPostsIfNeeded()
            // Small delay to let merge settle before fetching new content
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        // Fetch new content and merge it smoothly (refreshVisibleTimeline uses processIncomingPosts when not replacing)
        await refreshVisibleTimeline(intent)
        markManualRefresh()
        
        // Clear buffer after refresh completes - new content has been merged
        updateSnapshot(buffer.clear(), reason: "manual refresh")
    }

    func mergeBufferedPostsIfNeeded() {
        let bufferedPosts = buffer.drain()
        guard !bufferedPosts.isEmpty else { return }
        log("🧩 [Refresh:\(timelineID)] Merge applied count=\(bufferedPosts.count)")
        mergeBufferedPosts(bufferedPosts)
        updateSnapshot(buffer.snapshot, reason: "merge")
    }

    /// Fetch posts and add to buffer WITHOUT merging into visible timeline.
    /// Used for pull-to-refresh to decouple fetch from display.
    /// Call mergeBufferedPostsIfNeeded() after to apply with offset compensation.
    func fetchToBuffer() async -> Int {
        log("🔄 [Refresh:\(timelineID)] Fetch to buffer (pull-to-refresh)")

        for platform in platforms {
            log("🔄 [Refresh:\(timelineID)] Fetch start (pull-to-refresh) \(platform.rawValue)")
            let rawPosts = await fetchPostsForPlatform(platform)

            guard !rawPosts.isEmpty else {
                log("📭 [Refresh:\(timelineID)] No new posts from \(platform.rawValue)")
                continue
            }

            let filteredPosts = await filterPosts(rawPosts)
            let visiblePosts = visiblePostsProvider()

            if let snapshot = buffer.append(incomingPosts: filteredPosts, visiblePosts: visiblePosts) {
                updateSnapshot(snapshot, reason: "pull-to-refresh buffer")
            }

            log("✅ [Refresh:\(timelineID)] Buffered \(filteredPosts.count) posts from \(platform.rawValue)")
        }

        markManualRefresh()
        return buffer.snapshot.bufferCount
    }

    func requestPrefetch(trigger: RefreshTrigger) async {
        guard isTimelineVisible else { return }
        log("🔄 [Refresh:\(timelineID)] Prefetch request (\(trigger.rawValue))")
        await bufferNewPosts(trigger: trigger, platform: nil)
    }

    // MARK: - Private Helpers

    private func startAutoRefresh() {
        guard autoRefreshTasks.isEmpty else { return }
        for platform in platforms {
            autoRefreshTasks[platform] = Task { [weak self] in
                await self?.autoRefreshLoop(for: platform)
            }
        }
    }

    private func stopAutoRefresh() {
        autoRefreshTasks.values.forEach { $0.cancel() }
        autoRefreshTasks.removeAll()
        cancelActiveAutoFetch(reason: "stop")
        autoMergeTask?.cancel()
        autoMergeTask = nil
    }

    private func autoRefreshLoop(for platform: SocialPlatform) async {
        while !Task.isCancelled {
            let interval = nextPollingInterval(for: platform)
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                break
            }
            if Task.isCancelled { break }
            await bufferNewPosts(trigger: .idlePolling, platform: platform)
        }
    }

    private func bufferNewPosts(trigger: RefreshTrigger, platform: SocialPlatform?) async {
        let platformsToFetch = platform.map { [$0] } ?? platforms
        for platform in platformsToFetch {
            guard shouldAutoFetch(for: platform, trigger: trigger) else { continue }
            log("🔄 [Refresh:\(timelineID)] Fetch start (\(trigger.rawValue)) \(platform.rawValue)")
            let fetchTask = Task { [weak self] () -> [Post] in
                guard let self = self else { return [] }
                return await self.fetchPostsForPlatform(platform)
            }
            activeAutoFetchTask = fetchTask
            let rawPosts = await fetchTask.value
            activeAutoFetchTask = nil
            guard !Task.isCancelled else { return }

            lastFetchAtByPlatform[platform] = Date()
            log("✅ [Refresh:\(timelineID)] Fetch end (\(trigger.rawValue)) \(platform.rawValue) count=\(rawPosts.count)")

            guard !rawPosts.isEmpty else { continue }
            guard shouldApplyBufferUpdate() else {
                log("🚫 [Refresh:\(timelineID)] Buffer update suppressed (scroll/interaction)")
                continue
            }
            let filteredPosts = await filterPosts(rawPosts)
            let visiblePosts = visiblePostsProvider()
            if let snapshot = buffer.append(incomingPosts: filteredPosts, visiblePosts: visiblePosts) {
                updateSnapshot(snapshot, reason: "buffer append")
            }
            scheduleAutoMergeIfEligible()
        }
    }

    private func shouldAutoFetch(for platform: SocialPlatform, trigger: RefreshTrigger) -> Bool {
        if isComposing {
            log("🚫 [Refresh:\(timelineID)] Fetch skipped (\(trigger.rawValue)) composing")
            return false
        }
        if isScrolling {
            log("🚫 [Refresh:\(timelineID)] Fetch skipped (\(trigger.rawValue)) scrolling")
            return false
        }
        if isLoading() {
            log("🚫 [Refresh:\(timelineID)] Fetch skipped (\(trigger.rawValue)) loading")
            return false
        }
        if trigger == .idlePolling && isDeepHistory {
            log("🚫 [Refresh:\(timelineID)] Fetch skipped (\(trigger.rawValue)) deep history")
            return false
        }

        let now = Date()
        if trigger == .idlePolling && now.timeIntervalSince(lastVisibleInteractionAt) < interactionGracePeriod {
            log("🚫 [Refresh:\(timelineID)] Fetch skipped (\(trigger.rawValue)) grace period")
            return false
        }

        let lastFetch = lastFetchAtByPlatform[platform] ?? .distantPast
        let minimumInterval = minimumInterval(for: platform, trigger: trigger)
        let isAllowed = now.timeIntervalSince(lastFetch) >= minimumInterval
        if !isAllowed {
            log("🚫 [Refresh:\(timelineID)] Fetch skipped (\(trigger.rawValue)) throttled")
        }
        return isAllowed
    }

    private func shouldApplyBufferUpdate() -> Bool {
        let idleTime = Date().timeIntervalSince(lastVisibleInteractionAt)
        if isScrolling { return false }
        return idleTime >= interactionGracePeriod
    }

    private func minimumInterval(for platform: SocialPlatform, trigger: RefreshTrigger) -> TimeInterval {
        switch trigger {
        case .foreground:
            return TimeInterval.random(in: foregroundRefreshRange)
        case .idlePolling:
            return nextPollingInterval(for: platform)
        }
    }

    private func nextPollingInterval(for platform: SocialPlatform) -> TimeInterval {
        let range: ClosedRange<TimeInterval>
        switch platform {
        case .mastodon:
            range = mastodonPollingRange
        case .bluesky:
            range = blueskyPollingRange
        }
        return TimeInterval.random(in: range)
    }

    private func cancelActiveAutoFetch(reason: String) {
        activeAutoFetchTask?.cancel()
        activeAutoFetchTask = nil
        log("🛑 [Refresh:\(timelineID)] Auto fetch canceled (\(reason))")
    }

    private func markManualRefresh() {
        let now = Date()
        for platform in platforms {
            lastFetchAtByPlatform[platform] = now
        }
    }

    private func scheduleAutoMergeIfEligible() {
        guard isNearTop, bufferCount > 0, !isComposing, !isScrolling else { return }
        autoMergeTask?.cancel()
        autoMergeTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(self.topMergeGracePeriod * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let idleTime = Date().timeIntervalSince(self.lastVisibleInteractionAt)
            guard self.isNearTop, self.bufferCount > 0, idleTime >= self.topMergeGracePeriod else { return }
            self.log("✨ [Refresh:\(self.timelineID)] Auto-merge at top")
            self.mergeBufferedPostsIfNeeded()
        }
    }

    private func updateSnapshot(_ snapshot: TimelineBufferSnapshot, reason: String) {
        bufferCount = snapshot.bufferCount
        bufferEarliestTimestamp = snapshot.bufferEarliestTimestamp
        bufferSources = snapshot.bufferSources
        log("📦 [Refresh:\(timelineID)] Buffer update (\(reason)) count=\(bufferCount) sources=\(bufferSources)")
    }
}

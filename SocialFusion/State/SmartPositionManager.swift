import CloudKit
import Foundation
import SwiftUI

/// Advanced position management with smart restoration and cross-session sync
class SmartPositionManager: ObservableObject {

    // MARK: - Properties

    private let config = TimelineConfiguration.shared
    private let userDefaults = UserDefaults.standard
    private let cloudContainer: CKContainer?

    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncTime: Date?

    // Position History for Smart Restoration
    private var positionHistory: [PositionSnapshot] = []
    private let maxHistorySize: Int

    // Cross-session sync
    private var iCloudSyncTimer: Timer?

    // MARK: - Initialization

    init() {
        self.maxHistorySize = config.maxHistorySize
        // Temporarily disable CloudKit to prevent startup hangs
        self.cloudContainer = nil  // config.iCloudSyncEnabled ? CKContainer.default() : nil

        loadPositionHistory()
        // Disable auto sync to prevent hangs
        // setupAutoSync()

        if config.verboseMode {
            print("📍 SmartPositionManager initialized with:")
            print("  Smart Restoration: \(config.smartRestorationEnabled)")
            print("  Cross-session Sync: \(config.crossSessionSyncEnabled)")
            print("  iCloud Sync: DISABLED (preventing hangs)")
            print("  History Size: \(maxHistorySize)")
        }
    }

    deinit {
        iCloudSyncTimer?.invalidate()
    }

    // MARK: - Smart Position Restoration

    /// Intelligently restore position based on available content
    func restorePosition<T: Identifiable>(
        for entries: [T],
        targetPostId: String? = nil,
        fallbackStrategy: FallbackStrategy? = nil
    ) -> (index: Int?, offset: CGFloat) where T.ID == String {

        guard config.isFeatureEnabled(.smartRestoration) else {
            return restoreBasicPosition(for: entries, targetPostId: targetPostId)
        }

        let strategy = fallbackStrategy ?? config.fallbackStrategy

        if config.positionLogging {
            print(
                "🎯 Smart restoration for \(entries.count) entries, target: \(targetPostId ?? "none"), strategy: \(strategy)"
            )
        }

        // 1. Try exact match first
        if let targetPostId = targetPostId,
            let exactIndex = entries.firstIndex(where: { $0.id == targetPostId })
        {

            let snapshot = PositionSnapshot(
                postId: targetPostId,
                timestamp: Date(),
                scrollOffset: 0,
                restorationMethod: .exactMatch
            )
            recordPositionSnapshot(snapshot)

            return (index: exactIndex, offset: 0)
        }

        // 2. Try smart content-based restoration
        if let smartPosition = findSmartPosition(for: entries, targetPostId: targetPostId) {
            return smartPosition
        }

        // 3. Apply fallback strategy
        return applyFallbackStrategy(strategy, for: entries)
    }

    /// Find smart position based on content similarity and temporal proximity
    private func findSmartPosition<T: Identifiable>(
        for entries: [T],
        targetPostId: String?
    ) -> (index: Int?, offset: CGFloat)? where T.ID == String {

        guard let targetPostId = targetPostId,
            let lastSnapshot = findRelevantSnapshot(for: targetPostId)
        else {
            return nil
        }

        // Look for content posted around the same time
        let targetTime = lastSnapshot.timestamp
        let timeWindow: TimeInterval = 3600  // 1 hour window

        // Try to find posts within temporal proximity
        if let temporalMatch = findTemporalMatch(
            in: entries, around: targetTime, window: timeWindow)
        {

            let snapshot = PositionSnapshot(
                postId: temporalMatch.id,
                timestamp: Date(),
                scrollOffset: 0,
                restorationMethod: .temporalProximity
            )
            recordPositionSnapshot(snapshot)

            return (index: temporalMatch.index, offset: 0)
        }

        // Try similar content match (if we have content similarity data)
        if let similarMatch = findSimilarContent(in: entries, to: targetPostId) {

            let snapshot = PositionSnapshot(
                postId: similarMatch.id,
                timestamp: Date(),
                scrollOffset: 0,
                restorationMethod: .contentSimilarity
            )
            recordPositionSnapshot(snapshot)

            return (index: similarMatch.index, offset: 0)
        }

        return nil
    }

    /// Find posts within temporal proximity
    private func findTemporalMatch<T: Identifiable>(
        in entries: [T],
        around targetTime: Date,
        window: TimeInterval
    ) -> (id: String, index: Int)? where T.ID == String {

        // This would ideally use post creation times, but we'll use a heuristic
        // based on post ID patterns or other available metadata

        let midPoint = entries.count / 2
        let searchRadius = min(10, entries.count / 4)

        let startIndex = max(0, midPoint - searchRadius)
        let endIndex = min(entries.count - 1, midPoint + searchRadius)

        for index in startIndex...endIndex {
            let entry = entries[index]
            // Simple heuristic: assume middle posts are temporally closer
            return (id: entry.id, index: index)
        }

        return nil
    }

    /// Find content with similarity (placeholder for future content analysis)
    private func findSimilarContent<T: Identifiable>(
        in entries: [T],
        to targetPostId: String
    ) -> (id: String, index: Int)? where T.ID == String {

        // Future: Implement content similarity analysis
        // For now, return a reasonable fallback

        if entries.count > 5 {
            let index = entries.count / 3  // Go to upper third
            return (id: entries[index].id, index: index)
        }

        return nil
    }

    /// Apply fallback strategy when smart restoration fails
    private func applyFallbackStrategy<T: Identifiable>(
        _ strategy: FallbackStrategy,
        for entries: [T]
    ) -> (index: Int?, offset: CGFloat) where T.ID == String {

        guard !entries.isEmpty else { return (nil, 0) }

        let result: (index: Int?, offset: CGFloat)

        switch strategy {
        case .nearestContent:
            // Go to middle of timeline as "nearest" content
            result = (index: entries.count / 2, offset: 0)

        case .topOfTimeline:
            result = (index: 0, offset: 0)

        case .lastKnownPosition:
            // Use last known scroll offset from history
            if let lastOffset = getLastKnownScrollOffset() {
                result = (index: nil, offset: lastOffset)
            } else {
                result = (index: 0, offset: 0)
            }

        case .newestPost:
            result = (index: 0, offset: 0)

        case .oldestPost:
            result = (index: entries.count - 1, offset: 0)
        }

        if config.positionLogging {
            print(
                "📋 Applied fallback strategy '\(strategy)': index=\(result.index?.description ?? "nil"), offset=\(result.offset)"
            )
        }

        // Record the fallback position
        if let index = result.index, index < entries.count {
            let snapshot = PositionSnapshot(
                postId: entries[index].id,
                timestamp: Date(),
                scrollOffset: result.offset,
                restorationMethod: .fallback(strategy)
            )
            recordPositionSnapshot(snapshot)
        }

        return result
    }

    /// Basic position restoration (fallback when smart restoration is disabled)
    private func restoreBasicPosition<T: Identifiable>(
        for entries: [T],
        targetPostId: String? = nil
    ) -> (index: Int?, offset: CGFloat) where T.ID == String {

        if let targetPostId = targetPostId,
            let index = entries.firstIndex(where: { $0.id == targetPostId })
        {
            return (index: index, offset: 0)
        }

        return (index: 0, offset: 0)
    }

    // MARK: - Position History Management

    private func recordPositionSnapshot(_ snapshot: PositionSnapshot) {
        positionHistory.append(snapshot)

        // Maintain history size limit
        if positionHistory.count > maxHistorySize {
            positionHistory.removeFirst()
        }

        savePositionHistory()

        if config.positionLogging {
            print(
                "📝 Recorded position snapshot: \(snapshot.postId) (\(snapshot.restorationMethod))")
        }
    }

    private func findRelevantSnapshot(for postId: String) -> PositionSnapshot? {
        return positionHistory.last { $0.postId == postId }
    }

    private func getLastKnownScrollOffset() -> CGFloat? {
        return positionHistory.last?.scrollOffset
    }

    // MARK: - Cross-Session Position Sync

    private func setupAutoSync() {
        guard config.isFeatureEnabled(.crossSessionSync) else { return }

        // Set up periodic sync
        iCloudSyncTimer = Timer.scheduledTimer(
            withTimeInterval: config.autoSaveInterval, repeats: true
        ) { [weak self] _ in
            Task {
                await self?.syncWithiCloud()
            }
        }

        // Sync on app launch
        Task {
            await syncWithiCloud()
        }
    }

    @MainActor
    func syncWithiCloud() async {
        guard config.isFeatureEnabled(.iCloudSync),
            let container = cloudContainer
        else { return }

        syncStatus = .syncing

        do {
            // Upload local position history
            try await uploadPositionHistory(to: container)

            // Download and merge remote position history
            try await downloadPositionHistory(from: container)

            lastSyncTime = Date()
            syncStatus = .success

            if config.verboseMode {
                print("☁️ Position sync completed successfully")
            }

        } catch {
            syncStatus = .error(error)

            if config.verboseMode {
                print("❌ Position sync failed: \(error.localizedDescription)")
            }
        }
    }

    private func uploadPositionHistory(to container: CKContainer) async throws {
        let database = container.privateCloudDatabase

        for snapshot in positionHistory {
            let record = CKRecord(recordType: "PositionSnapshot")
            record["postId"] = snapshot.postId
            record["timestamp"] = snapshot.timestamp
            record["scrollOffset"] = Double(snapshot.scrollOffset)
            record["restorationMethod"] = snapshot.restorationMethod.rawValue
            record["deviceId"] = await UIDevice.current.identifierForVendor?.uuidString

            do {
                _ = try await database.save(record)
            } catch {
                // Continue with other records if one fails
                if config.verboseMode {
                    print("⚠️ Failed to upload snapshot for \(snapshot.postId): \(error)")
                }
            }
        }
    }

    private func downloadPositionHistory(from container: CKContainer) async throws {
        let database = container.privateCloudDatabase

        let query = CKQuery(recordType: "PositionSnapshot", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        let (records, _) = try await database.records(matching: query)

        var remoteSnapshots: [PositionSnapshot] = []

        for (_, result) in records {
            switch result {
            case .success(let record):
                if let snapshot = PositionSnapshot.from(cloudKitRecord: record) {
                    remoteSnapshots.append(snapshot)
                }
            case .failure(let error):
                if config.verboseMode {
                    print("⚠️ Failed to download snapshot: \(error)")
                }
            }
        }

        // Merge remote snapshots with local ones
        mergeRemoteSnapshots(remoteSnapshots)
    }

    private func mergeRemoteSnapshots(_ remoteSnapshots: [PositionSnapshot]) {
        // Simple merge strategy: combine and deduplicate by postId, keeping most recent
        var allSnapshots = positionHistory + remoteSnapshots

        // Sort by timestamp and remove duplicates, keeping most recent
        allSnapshots.sort { $0.timestamp > $1.timestamp }

        var uniqueSnapshots: [PositionSnapshot] = []
        var seenPostIds: Set<String> = []

        for snapshot in allSnapshots {
            if !seenPostIds.contains(snapshot.postId) {
                uniqueSnapshots.append(snapshot)
                seenPostIds.insert(snapshot.postId)
            }
        }

        // Maintain size limit
        if uniqueSnapshots.count > maxHistorySize {
            uniqueSnapshots = Array(uniqueSnapshots.prefix(maxHistorySize))
        }

        positionHistory = uniqueSnapshots
        savePositionHistory()

        if config.verboseMode {
            print("🔄 Merged position history: \(uniqueSnapshots.count) unique snapshots")
        }
    }

    // MARK: - Persistence

    private func savePositionHistory() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(positionHistory) {
            userDefaults.set(data, forKey: "SmartPositionHistory")
        }
    }

    private func loadPositionHistory() {
        guard let data = userDefaults.data(forKey: "SmartPositionHistory"),
            let history = try? JSONDecoder().decode([PositionSnapshot].self, from: data)
        else {
            return
        }

        positionHistory = history

        if config.verboseMode {
            print("📂 Loaded position history: \(history.count) snapshots")
        }
    }

    // MARK: - Public Interface

    /// Record a new position for smart restoration
    func recordPosition(postId: String, scrollOffset: CGFloat = 0) {
        let snapshot = PositionSnapshot(
            postId: postId,
            timestamp: Date(),
            scrollOffset: scrollOffset,
            restorationMethod: .manual
        )
        recordPositionSnapshot(snapshot)
    }

    /// Get restoration suggestions for current timeline
    func getRestorationSuggestions<T: Identifiable>(for entries: [T]) -> [RestorationSuggestion]
    where T.ID == String {
        guard config.smartRestorationEnabled else { return [] }

        var suggestions: [RestorationSuggestion] = []

        // Recent positions
        let recentSnapshots = positionHistory.prefix(3)
        for snapshot in recentSnapshots {
            if let index = entries.firstIndex(where: { $0.id == snapshot.postId }) {
                suggestions.append(
                    RestorationSuggestion(
                        title: "Continue where you left off",
                        description:
                            "Post from \(snapshot.timestamp.formatted(.relative(presentation: .named)))",
                        postId: snapshot.postId,
                        index: index,
                        confidence: 0.9
                    ))
            }
        }

        return suggestions
    }
}

// MARK: - Supporting Types

struct PositionSnapshot: Codable {
    let postId: String
    let timestamp: Date
    let scrollOffset: CGFloat
    let restorationMethod: RestorationMethod

    static func from(cloudKitRecord record: CKRecord) -> PositionSnapshot? {
        guard let postId = record["postId"] as? String,
            let timestamp = record["timestamp"] as? Date,
            let scrollOffset = record["scrollOffset"] as? Double,
            let methodString = record["restorationMethod"] as? String,
            let method = RestorationMethod(rawValue: methodString)
        else {
            return nil
        }

        return PositionSnapshot(
            postId: postId,
            timestamp: timestamp,
            scrollOffset: CGFloat(scrollOffset),
            restorationMethod: method
        )
    }
}

enum RestorationMethod: String, Codable {
    case exactMatch = "exact_match"
    case temporalProximity = "temporal_proximity"
    case contentSimilarity = "content_similarity"
    case fallback = "fallback"
    case manual = "manual"

    var rawValue: String {
        switch self {
        case .exactMatch: return "exact_match"
        case .temporalProximity: return "temporal_proximity"
        case .contentSimilarity: return "content_similarity"
        case .fallback: return "fallback"
        case .manual: return "manual"
        }
    }

    static func fallback(_ strategy: FallbackStrategy) -> RestorationMethod {
        return .fallback
    }
}

struct RestorationSuggestion {
    let title: String
    let description: String
    let postId: String
    let index: Int
    let confidence: Double
}

enum SyncStatus {
    case idle
    case syncing
    case success
    case error(Error)
}

// MARK: - Extensions

extension SmartPositionManager {

    /// Clean up old position history
    func cleanupOldHistory() {
        let cutoffDate = Date().addingTimeInterval(-config.cacheExpiration)

        positionHistory.removeAll { $0.timestamp < cutoffDate }
        savePositionHistory()

        if config.verboseMode {
            print("🧹 Cleaned up position history older than \(cutoffDate)")
        }
    }

    /// Export position history for debugging
    func exportPositionHistory() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(positionHistory),
            let json = String(data: data, encoding: .utf8)
        {
            return json
        }

        return "Failed to export position history"
    }
}

import Foundation
import SwiftUI

/// Configuration manager for Timeline State features
/// Reads settings from Info.plist SocialFusionTimelineConfiguration
class TimelineConfiguration {
    static let shared = TimelineConfiguration()

    private let config: [String: Any]

    private init() {
        guard let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
            let plist = NSDictionary(contentsOfFile: path),
            let timelineConfig = plist["SocialFusionTimelineConfiguration"] as? [String: Any]
        else {
            print("⚠️ Timeline configuration not found in Info.plist, using defaults")
            self.config = [:]
            return
        }

        self.config = timelineConfig
        print("✅ Timeline configuration loaded successfully")
    }

    // MARK: - Position Persistence Settings

    var positionPersistenceEnabled: Bool {
        guard let positionConfig = config["PositionPersistence"] as? [String: Any] else {
            return true
        }
        return positionConfig["Enabled"] as? Bool ?? true
    }

    var smartRestorationEnabled: Bool {
        guard let positionConfig = config["PositionPersistence"] as? [String: Any] else {
            return true
        }
        return positionConfig["SmartRestoration"] as? Bool ?? true
    }

    var maxHistorySize: Int {
        guard let positionConfig = config["PositionPersistence"] as? [String: Any] else {
            return 10
        }
        return positionConfig["MaxHistorySize"] as? Int ?? 10
    }

    var autoSaveInterval: TimeInterval {
        guard let positionConfig = config["PositionPersistence"] as? [String: Any] else {
            return 5.0
        }
        return TimeInterval(positionConfig["AutoSaveInterval"] as? Int ?? 5)
    }

    var crossSessionSyncEnabled: Bool {
        guard let positionConfig = config["PositionPersistence"] as? [String: Any] else {
            return true
        }
        return positionConfig["CrossSessionSync"] as? Bool ?? true
    }

    var iCloudSyncEnabled: Bool {
        guard let positionConfig = config["PositionPersistence"] as? [String: Any] else {
            return true
        }
        return positionConfig["iCloudSyncEnabled"] as? Bool ?? true
    }

    var fallbackStrategy: FallbackStrategy {
        guard let positionConfig = config["PositionPersistence"] as? [String: Any],
            let strategyString = positionConfig["FallbackStrategy"] as? String
        else {
            return .nearestContent
        }
        return FallbackStrategy(rawValue: strategyString) ?? .nearestContent
    }

    // MARK: - Unread Tracking Settings

    var unreadTrackingEnabled: Bool {
        guard let unreadConfig = config["UnreadTracking"] as? [String: Any] else { return true }
        return unreadConfig["Enabled"] as? Bool ?? true
    }

    var readOnViewport: Bool {
        guard let unreadConfig = config["UnreadTracking"] as? [String: Any] else { return true }
        return unreadConfig["ReadOnViewport"] as? Bool ?? true
    }

    var viewportThreshold: Double {
        guard let unreadConfig = config["UnreadTracking"] as? [String: Any] else { return 0.5 }
        return unreadConfig["ViewportThreshold"] as? Double ?? 0.5
    }

    var readDelay: TimeInterval {
        guard let unreadConfig = config["UnreadTracking"] as? [String: Any] else { return 1.0 }
        return unreadConfig["ReadDelay"] as? Double ?? 1.0
    }

    var maxUnreadHistory: Int {
        guard let unreadConfig = config["UnreadTracking"] as? [String: Any] else { return 1000 }
        return unreadConfig["MaxUnreadHistory"] as? Int ?? 1000
    }

    // MARK: - Timeline Cache Settings

    var maxCacheSize: Int {
        guard let cacheConfig = config["TimelineCache"] as? [String: Any] else { return 500 }
        return cacheConfig["MaxCacheSize"] as? Int ?? 500
    }

    var cacheExpiration: TimeInterval {
        guard let cacheConfig = config["TimelineCache"] as? [String: Any] else { return 86400 }
        return TimeInterval(cacheConfig["CacheExpiration"] as? Int ?? 86400)
    }

    var smartCacheEviction: Bool {
        guard let cacheConfig = config["TimelineCache"] as? [String: Any] else { return true }
        return cacheConfig["SmartCacheEviction"] as? Bool ?? true
    }

    var offlineMode: Bool {
        guard let cacheConfig = config["TimelineCache"] as? [String: Any] else { return true }
        return cacheConfig["OfflineMode"] as? Bool ?? true
    }

    // MARK: - Performance Settings

    var lazyLoadingEnabled: Bool {
        guard let perfConfig = config["Performance"] as? [String: Any] else { return true }
        return perfConfig["LazyLoadingEnabled"] as? Bool ?? true
    }

    var scrollBufferSize: Int {
        guard let perfConfig = config["Performance"] as? [String: Any] else { return 20 }
        return perfConfig["ScrollBufferSize"] as? Int ?? 20
    }

    var renderAheadCount: Int {
        guard let perfConfig = config["Performance"] as? [String: Any] else { return 5 }
        return perfConfig["RenderAheadCount"] as? Int ?? 5
    }

    var memoryWarningThreshold: Double {
        guard let perfConfig = config["Performance"] as? [String: Any] else { return 0.8 }
        return perfConfig["MemoryWarningThreshold"] as? Double ?? 0.8
    }

    // MARK: - Debug Settings

    var timelineLogging: Bool {
        guard let debugConfig = config["Debug"] as? [String: Any] else { return true }
        return debugConfig["TimelineLogging"] as? Bool ?? true
    }

    var positionLogging: Bool {
        guard let debugConfig = config["Debug"] as? [String: Any] else { return true }
        return debugConfig["PositionLogging"] as? Bool ?? true
    }

    var performanceLogging: Bool {
        guard let debugConfig = config["Debug"] as? [String: Any] else { return true }
        return debugConfig["PerformanceLogging"] as? Bool ?? true
    }

    var verboseMode: Bool {
        guard let debugConfig = config["Debug"] as? [String: Any] else { return true }
        return debugConfig["VerboseMode"] as? Bool ?? true
    }

    // MARK: - Utility Methods

    func logConfiguration() {
        if verboseMode {
            print("📋 Timeline Configuration:")
            print("  Position Persistence: \(positionPersistenceEnabled)")
            print("  Smart Restoration: \(smartRestorationEnabled)")
            print("  Cross Session Sync: \(crossSessionSyncEnabled)")
            print("  iCloud Sync: \(iCloudSyncEnabled)")
            print("  Fallback Strategy: \(fallbackStrategy)")
            print("  Max Cache Size: \(maxCacheSize)")
            print("  Scroll Buffer: \(scrollBufferSize)")
        }
    }
}

// MARK: - Supporting Types

enum FallbackStrategy: String, CaseIterable {
    case nearestContent = "NearestContent"
    case topOfTimeline = "TopOfTimeline"
    case lastKnownPosition = "LastKnownPosition"
    case newestPost = "NewestPost"
    case oldestPost = "OldestPost"

    var description: String {
        switch self {
        case .nearestContent:
            return "Restore to nearest available content"
        case .topOfTimeline:
            return "Start from top of timeline"
        case .lastKnownPosition:
            return "Use last known scroll position"
        case .newestPost:
            return "Jump to newest post"
        case .oldestPost:
            return "Stay at oldest post"
        }
    }
}

// MARK: - Configuration Extensions

extension TimelineConfiguration {

    /// Check if a feature is enabled based on configuration
    func isFeatureEnabled(_ feature: TimelineFeature) -> Bool {
        switch feature {
        case .positionPersistence:
            return positionPersistenceEnabled
        case .smartRestoration:
            return smartRestorationEnabled && positionPersistenceEnabled
        case .crossSessionSync:
            return crossSessionSyncEnabled && positionPersistenceEnabled
        case .unreadTracking:
            return unreadTrackingEnabled
        case .iCloudSync:
            return iCloudSyncEnabled && crossSessionSyncEnabled
        case .offlineMode:
            return offlineMode
        }
    }
}

enum TimelineFeature {
    case positionPersistence
    case smartRestoration
    case crossSessionSync
    case unreadTracking
    case iCloudSync
    case offlineMode
}

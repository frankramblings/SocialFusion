import Foundation
import SwiftUI

/// Manages feature flags for the application
final class FeatureFlagManager {
    static let shared = FeatureFlagManager()

    // MARK: - Architecture Flags

    /// Controls whether to use the new architecture
    @AppStorage("useNewArchitecture") private(set) var useNewArchitecture = false

    /// Controls whether to use the new post card view
    @AppStorage("useNewPostCard") private(set) var useNewPostCard = false

    /// Controls whether to use the new view model
    @AppStorage("useNewViewModel") private(set) var useNewViewModel = false

    /// Controls whether to use the new Bluesky service
    @AppStorage("useNewBlueskyService") private(set) var useNewBlueskyService = false

    /// Controls whether to use the new social service manager
    @AppStorage("useNewSocialServiceManager") private(set) var useNewSocialServiceManager = false

    // MARK: - Debug Flags

    /// Controls whether debug mode is enabled
    @AppStorage("debugModeEnabled") private(set) var debugModeEnabled = false

    /// Controls whether verbose logging is enabled
    @AppStorage("verboseLogging") private(set) var verboseLogging = false

    /// Controls whether performance tracking is enabled
    @AppStorage("trackPerformance") private(set) var trackPerformance = false

    // MARK: - Analytics

    /// Tracks when features were enabled
    private var featureEnableDates: [String: Date] = [:]

    /// Tracks feature usage counts
    private var featureUsageCounts: [String: Int] = [:]

    private init() {
        // Load analytics data
        loadAnalyticsData()
    }

    // MARK: - Public API

    /// Enable a feature flag
    func enableFeature(_ feature: FeatureFlag) {
        switch feature {
        case .newArchitecture:
            useNewArchitecture = true
        case .newPostCard:
            useNewPostCard = true
        case .newViewModel:
            useNewViewModel = true
        case .newBlueskyService:
            useNewBlueskyService = true
        case .newSocialServiceManager:
            useNewSocialServiceManager = true
        case .debugMode:
            debugModeEnabled = true
        case .verboseLogging:
            verboseLogging = true
        case .performanceTracking:
            trackPerformance = true
        }

        // Track when feature was enabled
        featureEnableDates[feature.rawValue] = Date()
        saveAnalyticsData()
    }

    /// Disable a feature flag
    func disableFeature(_ feature: FeatureFlag) {
        switch feature {
        case .newArchitecture:
            useNewArchitecture = false
        case .newPostCard:
            useNewPostCard = false
        case .newViewModel:
            useNewViewModel = false
        case .newBlueskyService:
            useNewBlueskyService = false
        case .newSocialServiceManager:
            useNewSocialServiceManager = false
        case .debugMode:
            debugModeEnabled = false
        case .verboseLogging:
            verboseLogging = false
        case .performanceTracking:
            trackPerformance = false
        }

        saveAnalyticsData()
    }

    /// Track feature usage
    func trackFeatureUsage(_ feature: FeatureFlag) {
        featureUsageCounts[feature.rawValue, default: 0] += 1
        saveAnalyticsData()
    }

    /// Get feature usage statistics
    func getFeatureStats() -> [String: Any] {
        var stats: [String: Any] = [:]

        // Add enable dates
        stats["enableDates"] = featureEnableDates.mapValues { $0.timeIntervalSince1970 }

        // Add usage counts
        stats["usageCounts"] = featureUsageCounts

        // Add current state
        stats["currentState"] = [
            "newArchitecture": useNewArchitecture,
            "newPostCard": useNewPostCard,
            "newViewModel": useNewViewModel,
            "newBlueskyService": useNewBlueskyService,
            "newSocialServiceManager": useNewSocialServiceManager,
            "debugMode": debugModeEnabled,
            "verboseLogging": verboseLogging,
            "performanceTracking": trackPerformance,
        ]

        return stats
    }

    // MARK: - Private Methods

    private func loadAnalyticsData() {
        if let datesData = UserDefaults.standard.data(forKey: "featureEnableDates"),
            let dates = try? JSONDecoder().decode([String: Date].self, from: datesData)
        {
            featureEnableDates = dates
        }

        if let countsData = UserDefaults.standard.data(forKey: "featureUsageCounts"),
            let counts = try? JSONDecoder().decode([String: Int].self, from: countsData)
        {
            featureUsageCounts = counts
        }
    }

    private func saveAnalyticsData() {
        if let datesData = try? JSONEncoder().encode(featureEnableDates) {
            UserDefaults.standard.set(datesData, forKey: "featureEnableDates")
        }

        if let countsData = try? JSONEncoder().encode(featureUsageCounts) {
            UserDefaults.standard.set(countsData, forKey: "featureUsageCounts")
        }
    }
}

// MARK: - Feature Flag Enum

enum FeatureFlag: String {
    case newArchitecture = "new_architecture"
    case newPostCard = "new_post_card"
    case newViewModel = "new_view_model"
    case newBlueskyService = "new_bluesky_service"
    case newSocialServiceManager = "new_social_service_manager"
    case debugMode = "debug_mode"
    case verboseLogging = "verbose_logging"
    case performanceTracking = "performance_tracking"
}

// MARK: - SwiftUI View Extension

extension View {
    /// Apply a feature flag to a view
    func withFeatureFlag(_ flag: FeatureFlag, @ViewBuilder content: @escaping () -> some View)
        -> some View
    {
        let manager = FeatureFlagManager.shared
        return Group {
            switch flag {
            case .newArchitecture where manager.useNewArchitecture,
                .newPostCard where manager.useNewPostCard,
                .newViewModel where manager.useNewViewModel,
                .newBlueskyService where manager.useNewBlueskyService,
                .newSocialServiceManager where manager.useNewSocialServiceManager,
                .debugMode where manager.debugModeEnabled,
                .verboseLogging where manager.verboseLogging,
                .performanceTracking where manager.trackPerformance:
                content()
            default:
                EmptyView()
            }
        }
    }
}

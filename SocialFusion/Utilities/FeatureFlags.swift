import Foundation

enum FeatureFlags {
    static var enableGIFUnfurling: Bool {
        FeatureFlagManager.shared.enableGIFUnfurling
    }

    static var enableRefreshGenerationGuard: Bool {
        FeatureFlagManager.shared.refreshGenerationGuard
    }

    static var enableTimelinePrefetchDiffing: Bool {
        FeatureFlagManager.shared.timelinePrefetchDiffing
    }
}

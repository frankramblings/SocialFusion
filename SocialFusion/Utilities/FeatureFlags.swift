import Foundation

enum FeatureFlags {
    static var enableGIFUnfurling: Bool {
        FeatureFlagManager.shared.enableGIFUnfurling
    }
}

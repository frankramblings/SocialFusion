import Foundation
import SwiftUI

/// Manages app version tracking to determine when to show launch animation
public final class AppVersionManager: ObservableObject {
    @Published public var shouldShowLaunchAnimation: Bool = false

    private let userDefaults = UserDefaults.standard
    private let lastVersionKey = "LastAppVersion"
    private let lastBuildKey = "LastAppBuild"

    public init() {
        checkForVersionUpdate()
    }

    /// Always show launch animation on app start for beautiful user experience
    private func checkForVersionUpdate() {
        guard let currentVersion = getCurrentAppVersion(),
            let currentBuild = getCurrentBuildNumber()
        else {
            // If we can't get version info, still show animation for great UX
            // Direct assignment to avoid AttributeGraph cycles
            self.shouldShowLaunchAnimation = true
            return
        }

        let lastVersion = userDefaults.string(forKey: lastVersionKey)
        let lastBuild = userDefaults.string(forKey: lastBuildKey)

        // Always show the beautiful launch animation for premium feel
        // Direct assignment to avoid AttributeGraph cycles
        self.shouldShowLaunchAnimation = true

        // Update stored version/build for potential future use
        userDefaults.set(currentVersion, forKey: lastVersionKey)
        userDefaults.set(currentBuild, forKey: lastBuildKey)

        print(
            "AppVersionManager: Current: \(currentVersion) (\(currentBuild)), Last: \(lastVersion ?? "none") (\(lastBuild ?? "none")), Always showing launch animation for premium UX"
        )
    }

    /// Get the current app version from bundle
    private func getCurrentAppVersion() -> String? {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// Get the current build number from bundle
    private func getCurrentBuildNumber() -> String? {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    /// Call this after launch animation completes
    public func markLaunchAnimationCompleted() {
        Task { @MainActor in
            self.shouldShowLaunchAnimation = false
        }
    }

    /// Force show launch animation (for testing purposes)
    public func forceShowLaunchAnimation() {
        Task { @MainActor in
            self.shouldShowLaunchAnimation = true
        }
    }

    /// Reset version tracking (for testing purposes)
    public func resetVersionTracking() {
        userDefaults.removeObject(forKey: lastVersionKey)
        userDefaults.removeObject(forKey: lastBuildKey)
        checkForVersionUpdate()
    }
}

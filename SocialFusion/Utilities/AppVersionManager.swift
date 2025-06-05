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

    /// Check if this is a new version/build and determine if launch animation should show
    private func checkForVersionUpdate() {
        guard let currentVersion = getCurrentAppVersion(),
            let currentBuild = getCurrentBuildNumber()
        else {
            // If we can't get version info, don't show animation
            DispatchQueue.main.async {
                self.shouldShowLaunchAnimation = false
            }
            return
        }

        let lastVersion = userDefaults.string(forKey: lastVersionKey)
        let lastBuild = userDefaults.string(forKey: lastBuildKey)

        // Show animation if:
        // 1. First launch (no stored version)
        // 2. Version changed
        // 3. Build number changed (new development build)
        let isFirstLaunch = lastVersion == nil
        let isVersionUpdate = lastVersion != currentVersion
        let isBuildUpdate = lastBuild != currentBuild

        DispatchQueue.main.async {
            self.shouldShowLaunchAnimation = isFirstLaunch || isVersionUpdate || isBuildUpdate
        }

        // Update stored version/build
        userDefaults.set(currentVersion, forKey: lastVersionKey)
        userDefaults.set(currentBuild, forKey: lastBuildKey)

        print(
            "AppVersionManager: Current: \(currentVersion) (\(currentBuild)), Last: \(lastVersion ?? "none") (\(lastBuild ?? "none")), Show animation: \(shouldShowLaunchAnimation)"
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
        DispatchQueue.main.async {
            self.shouldShowLaunchAnimation = false
        }
    }

    /// Force show launch animation (for testing purposes)
    public func forceShowLaunchAnimation() {
        DispatchQueue.main.async {
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

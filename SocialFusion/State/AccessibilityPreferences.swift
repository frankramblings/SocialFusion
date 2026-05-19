import Combine
import Foundation
import SwiftUI

/// User-controlled accessibility preferences that the OS doesn't expose.
///
/// v1.0 ships one field — `highContrastNetworkIndicators` — which addresses the
/// Six Colors colorblind critique by switching `PlatformLogoBadge` to a
/// filled-vs-outlined dual-coding scheme. The type is structured so additional
/// app-specific accessibility toggles can be added without renames.
///
/// Backed by `UserDefaults`. Injectable for tests via the designated init.
@MainActor
public final class AccessibilityPreferences: ObservableObject {
    public enum Keys {
        public static let highContrastNetworkIndicators = "accessibility.highContrastNetworkIndicators"
    }

    private let defaults: UserDefaults

    /// When `true`, `PlatformLogoBadge` and indicators derived from it render
    /// in a high-contrast filled-vs-outlined scheme. Default `false` so
    /// existing users see no visual change on upgrade.
    @Published public var highContrastNetworkIndicators: Bool {
        didSet {
            defaults.set(highContrastNetworkIndicators,
                         forKey: Keys.highContrastNetworkIndicators)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.highContrastNetworkIndicators =
            defaults.bool(forKey: Keys.highContrastNetworkIndicators)
    }
}

// MARK: - Environment integration

private struct AccessibilityPreferencesKey: EnvironmentKey {
    @MainActor static var defaultValue: AccessibilityPreferences {
        AccessibilityPreferences()
    }
}

public extension EnvironmentValues {
    /// Convenience environment access for views that don't want an explicit
    /// `@EnvironmentObject` (e.g. `PlatformLogoBadge` itself, used in static
    /// previews and snapshot tests where injecting an env object is awkward).
    var accessibilityPreferences: AccessibilityPreferences {
        get { self[AccessibilityPreferencesKey.self] }
        set { self[AccessibilityPreferencesKey.self] = newValue }
    }
}

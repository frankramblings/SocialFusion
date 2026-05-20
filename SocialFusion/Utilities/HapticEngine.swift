import UIKit

/// Centralized haptic feedback engine matching Apple's established patterns.
/// Provides consistent haptic vocabulary across the app for both user actions
/// and system events.
enum HapticEngine {
    // MARK: - User Actions

    /// Light impact for standard button taps
    case tap

    /// Selection feedback for toggles and mode changes
    case selection

    // MARK: - System Events

    /// Success notification - post sent, action completed
    case success

    /// Warning notification - partial success, rate limited
    case warning

    /// Error notification - network failure, auth error
    case error

    // MARK: - Contextual

    /// Pull-to-refresh completion with contextual feedback
    /// - Parameter hasNewContent: If true, plays success; if false, plays subtle tap
    case refreshComplete(hasNewContent: Bool)

    /// Triggers the haptic feedback immediately
    func trigger() {
        switch self {
        case .tap:
            Generators.lightImpact.impactOccurred()
            Generators.lightImpact.prepare()  // keep warm for the next call

        case .selection:
            Generators.selection.selectionChanged()
            Generators.selection.prepare()

        case .success:
            Generators.notification.notificationOccurred(.success)
            Generators.notification.prepare()

        case .warning:
            Generators.notification.notificationOccurred(.warning)
            Generators.notification.prepare()

        case .error:
            Generators.notification.notificationOccurred(.error)
            Generators.notification.prepare()

        case .refreshComplete(let hasNewContent):
            if hasNewContent {
                Generators.notification.notificationOccurred(.success)
                Generators.notification.prepare()
            } else {
                Generators.lightImpact.impactOccurred()
                Generators.lightImpact.prepare()
            }
        }
    }

    /// Pre-warms the haptic generator for latency-sensitive moments.
    /// Call this shortly before you expect to trigger the haptic.
    static func prepare(_ pattern: HapticEngine) {
        switch pattern {
        case .tap:
            Generators.lightImpact.prepare()

        case .selection:
            Generators.selection.prepare()

        case .success, .warning, .error, .refreshComplete:
            Generators.notification.prepare()
        }
    }
}

/// Long-lived generator instances. iOS optimizes haptic engine warm-up only
/// when the generator is retained across calls — previously every trigger
/// allocated a fresh generator, so `prepare()` was effectively a no-op
/// (the prepared instance was released before the next call could use it).
/// Holding singletons cuts first-haptic latency noticeably, especially
/// after the app has been idle.
private enum Generators {
    static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    static let selection = UISelectionFeedbackGenerator()
    static let notification = UINotificationFeedbackGenerator()
}

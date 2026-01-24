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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()

        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)

        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)

        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)

        case .refreshComplete(let hasNewContent):
            if hasNewContent {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    /// Pre-warms the haptic generator for latency-sensitive moments.
    /// Call this shortly before you expect to trigger the haptic.
    static func prepare(_ pattern: HapticEngine) {
        switch pattern {
        case .tap:
            UIImpactFeedbackGenerator(style: .light).prepare()

        case .selection:
            UISelectionFeedbackGenerator().prepare()

        case .success, .warning, .error, .refreshComplete:
            UINotificationFeedbackGenerator().prepare()
        }
    }
}

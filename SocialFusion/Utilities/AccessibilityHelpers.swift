import SwiftUI

/// Utility functions and extensions to support accessibility features
struct AccessibilityHelpers {

    /// Determines if the current Dynamic Type size is considered large
    static func isLargeDynamicType(_ size: DynamicTypeSize) -> Bool {
        return size >= .accessibility1
    }

    /// Determines if the current Dynamic Type size requires compact layouts
    static func requiresCompactLayout(_ size: DynamicTypeSize) -> Bool {
        return size >= .xxLarge
    }

    /// Gets appropriate spacing for the current Dynamic Type size
    static func adaptiveSpacing(for size: DynamicTypeSize, base: CGFloat = 8) -> CGFloat {
        switch size {
        case .xSmall, .small:
            return base * 0.75
        case .medium, .large, .xLarge:
            return base
        case .xxLarge, .xxxLarge:
            return base * 1.25
        case .accessibility1, .accessibility2:
            return base * 1.5
        case .accessibility3, .accessibility4, .accessibility5:
            return base * 2.0
        @unknown default:
            return base
        }
    }

    /// Gets appropriate font size scaling for the current Dynamic Type size
    static func fontScaling(for size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall:
            return 0.8
        case .small:
            return 0.9
        case .medium, .large, .xLarge:
            return 1.0
        case .xxLarge:
            return 1.15
        case .xxxLarge:
            return 1.3
        case .accessibility1:
            return 1.5
        case .accessibility2:
            return 1.75
        case .accessibility3:
            return 2.0
        case .accessibility4:
            return 2.25
        case .accessibility5:
            return 2.5
        @unknown default:
            return 1.0
        }
    }
}

/// View modifier to make buttons more accessible
struct AccessibleButtonStyle: ViewModifier {
    let label: String
    let hint: String?
    let role: ButtonRole?

    init(label: String, hint: String? = nil, role: ButtonRole? = nil) {
        self.label = label
        self.hint = hint
        self.role = role
    }

    func body(content: Content) -> some View {
        content
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(.isButton)
            .if(role == .destructive) { view in
                view.accessibilityAddTraits(.isSelected)
            }
    }
}

/// View modifier to make text more accessible
struct AccessibleTextStyle: ViewModifier {
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    let minimumScaleFactor: CGFloat
    let allowsTightening: Bool

    init(minimumScaleFactor: CGFloat = 0.8, allowsTightening: Bool = true) {
        self.minimumScaleFactor = minimumScaleFactor
        self.allowsTightening = allowsTightening
    }

    func body(content: Content) -> some View {
        content
            .minimumScaleFactor(minimumScaleFactor)
            .allowsTightening(allowsTightening)
            .lineLimit(AccessibilityHelpers.isLargeDynamicType(dynamicTypeSize) ? nil : 3)
    }
}

/// View modifier for adaptive layouts based on Dynamic Type
struct AdaptiveLayout: ViewModifier {
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    let compactThreshold: DynamicTypeSize

    init(compactThreshold: DynamicTypeSize = .xxLarge) {
        self.compactThreshold = compactThreshold
    }

    func body(content: Content) -> some View {
        Group {
            if dynamicTypeSize >= compactThreshold {
                VStack {
                    content
                }
            } else {
                HStack {
                    content
                }
            }
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Applies accessible button styling
    func accessibleButton(label: String, hint: String? = nil, role: ButtonRole? = nil) -> some View
    {
        self.modifier(AccessibleButtonStyle(label: label, hint: hint, role: role))
    }

    /// Applies accessible text styling
    func accessibleText(minimumScaleFactor: CGFloat = 0.8, allowsTightening: Bool = true)
        -> some View
    {
        self.modifier(
            AccessibleTextStyle(
                minimumScaleFactor: minimumScaleFactor, allowsTightening: allowsTightening))
    }

    /// Applies adaptive layout based on Dynamic Type
    func adaptiveLayout(compactThreshold: DynamicTypeSize = .xxLarge) -> some View {
        self.modifier(AdaptiveLayout(compactThreshold: compactThreshold))
    }

    /// Conditional view modifier
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Applies accessibility traits for interactive elements
    func accessibleInteractive(label: String, hint: String? = nil, traits: AccessibilityTraits = [])
        -> some View
    {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(traits)
    }

    /// Hides decorative elements from VoiceOver
    func decorative() -> some View {
        self.accessibilityHidden(true)
    }
}

// MARK: - Accessibility Constants

enum AccessibilityLabels {
    // Timeline
    static let timeline = "Timeline"
    static let timelineHint = "Swipe up and down to navigate posts, pull down to refresh"
    static let refreshTimeline = "Refresh Timeline"
    static let loadingPosts = "Loading more posts"
    static let endOfTimeline = "End of timeline"

    // Posts
    static let post = "Post"
    static let postHint = "Double tap to view full post and replies"
    static let replyButton = "Reply"
    static let repostButton = "Repost"
    static let likeButton = "Like"
    static let shareButton = "Share"
    static let moreOptionsButton = "More options"

    // Navigation
    static let homeTab = "Home"
    static let notificationsTab = "Notifications"
    static let searchTab = "Search"
    static let profileTab = "Profile"
    static let composeButton = "Compose new post"
    static let accountSelector = "Account selector"

    // Media
    static let image = "Image"
    static let video = "Video"
    static let audio = "Audio"
    static let gif = "Animated GIF"
    static let showAltText = "Show image description"
    static let closeFullscreen = "Close fullscreen viewer"
    static let shareMedia = "Share media"
}

enum AccessibilityHints {
    static let tapToCompose = "Tap to compose a new post"
    static let tapToSwitchAccount = "Tap to switch between accounts or view unified timeline"
    static let doubleTapToView = "Double tap to view full content"
    static let swipeToNavigate = "Swipe left or right to navigate"
    static let pullToRefresh = "Pull down to refresh"
    static let longPressForOptions = "Long press for additional options"
}

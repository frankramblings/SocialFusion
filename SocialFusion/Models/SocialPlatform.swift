import Foundation
import SwiftUI

/// Represents supported social media platforms in the app
public enum SocialPlatform: String, Codable, CaseIterable {
    case mastodon
    case bluesky

    /// Returns the platform's color for UI elements
    public var color: String {
        switch self {
        case .mastodon:
            return "#6364FF"
        case .bluesky:
            return "#0085FF"
        }
    }

    /// Returns whether the platform uses an SF Symbol or custom image
    public var usesSFSymbol: Bool {
        return false
    }

    /// Returns the platform-specific icon image name
    public var icon: String {
        switch self {
        case .mastodon:
            return "MastodonLogo"
        case .bluesky:
            return "BlueskyLogo"
        }
    }

    /// Whether the SVG icon should be tinted with the platform color
    public var shouldTintIcon: Bool {
        return true
    }

    /// Fallback system symbol if needed
    public var sfSymbol: String {
        switch self {
        case .mastodon:
            return "bubble.left.and.bubble.right"
        case .bluesky:
            return "cloud"
        }
    }
}

import Foundation
import SwiftUI
import UIKit

/// An enum representing the supported social media platforms
public enum SocialPlatform: String, Codable, CaseIterable, Sendable {
    case mastodon
    case bluesky

    /// Hex color associated with the platform (for consistent branding)
    public var colorHex: String {
        switch self {
        case .mastodon: return "6364FF"
        case .bluesky: return "0085FF"
        }
    }

    /// Whether the platform uses a built-in SF Symbol (currently false; using assets)
    public var usesSFSymbol: Bool { false }

    /// Asset name for the platform icon
    public var icon: String {
        switch self {
        case .mastodon: return "MastodonLogo"
        case .bluesky: return "BlueskyLogo"
        }
    }

    /// Fallback SF Symbol
    public var sfSymbol: String { "person.crop.circle" }

    /// Convenience SwiftUI Color
    public var swiftUIColor: Color { self == .mastodon ? .mastodonColor : .blueskyColor }

    /// Convenience UIKit UIColor
    public var uiColor: UIColor { UIColor(self.swiftUIColor) }
}

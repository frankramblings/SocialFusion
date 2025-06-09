import Foundation
import SwiftUI
import UIKit

// MARK: - Color Extension for Hex Colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch hex.count {
        case 3:  // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - UIColor Extension for Hex Colors
extension UIColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch hex.count {
        case 3:  // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

// MARK: - SocialPlatform Definition
/// An enum representing the supported social media platforms
public enum SocialPlatform: String, Codable, CaseIterable {
    case mastodon
    case bluesky

    /// Returns the platform's color as a hex string for UI elements
    /// This is compatible with iOS 16+
    public var colorHex: String {
        switch self {
        case .mastodon:
            return "6364FF"
        case .bluesky:
            return "0085FF"
        }
    }

    /// DEPRECATED: Returns the platform's color for UI elements
    /// Use colorHex instead and convert as needed
    @available(*, deprecated, message: "Use colorHex instead and convert as needed")
    public var color: String {
        return colorHex
    }

    /// Returns the platform's color as a SwiftUI Color
    public var swiftUIColor: Color {
        switch self {
        case .mastodon:
            return Color(hex: "6364FF")
        case .bluesky:
            return Color(hex: "0085FF")
        }
    }

    /// Returns the platform's color as a UIKit UIColor
    public var uiColor: UIColor {
        switch self {
        case .mastodon:
            return UIColor(hex: "6364FF") ?? .systemBlue
        case .bluesky:
            return UIColor(hex: "0085FF") ?? .systemBlue
        }
    }

    /// Returns whether the platform uses an SF Symbol or custom image
    public var usesSFSymbol: Bool {
        return false
    }

    /// Returns the platform-specific system symbol name
    public var icon: String {
        switch self {
        case .mastodon:
            return "message.fill"
        case .bluesky:
            return "cloud.fill"
        }
    }

    /// Whether the SVG icon should be tinted with the platform color
    public var shouldTintIcon: Bool {
        return false
    }

    /// Fallback system symbol if needed
    public var sfSymbol: String {
        switch self {
        case .mastodon:
            return "m.circle.fill"
        case .bluesky:
            return "cloud.fill"
        }
    }
}

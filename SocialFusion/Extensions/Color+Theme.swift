import SwiftUI

extension Color {
    static var primaryColor: Color {
        Color("PrimaryColor")
    }

    static var secondaryColor: Color {
        Color("SecondaryColor")
    }

    static var textColor: Color {
        Color("TextColor")
    }

    // `accentPurple` and `cardBackground` are auto-generated from the
    // Color asset catalog (GeneratedAssetSymbols.swift) — declaring
    // them manually here would collide. Removed; call sites continue
    // to work since the synthesised symbols have identical shape.

    static var subtleBorder: Color {
        // Canonical iOS separator color — adapts to light/dark mode.
        // Was Color.gray.opacity(0.2), which shifts brown against
        // dark backgrounds. Color(.separator) is the same hairline
        // color UIKit uses for table separators.
        Color(.separator)
    }

    static func adaptiveElementBackground(for colorScheme: ColorScheme) -> Color {
        // Lighter background for reply banners and parent posts
        colorScheme == .dark
            ? Color.white.opacity(0.07)
            :  // Dark mode - lighter overlay
            Color.black.opacity(0.03)  // Light mode - darker overlay
    }

    static func adaptiveElementBorder(for colorScheme: ColorScheme) -> Color {
        // Subtle border color for banners and parent posts
        colorScheme == .dark
            ? Color.white.opacity(0.15)
            :  // Dark mode - light border
            Color.black.opacity(0.08)  // Light mode - dark border
    }

    // For backward compatibility
    static var elementBackground: Color {
        adaptiveElementBackground(for: .dark)
    }

    static var elementBorder: Color {
        adaptiveElementBorder(for: .dark)
    }

    static var elementShadow: Color {
        // Subtle shadow color for elements
        return Color.white.opacity(0.05)
    }

    // Platform-specific brand colors.
    //
    // Mirrors SocialPlatform.colorHex so the brand purple/blue is
    // identical across every surface — whether the call site
    // reaches for `Color.mastodonColor` directly or computes
    // `Color(hex: account.platform.colorHex)`. Previously these
    // resolved to system .purple / .blue, which are visually
    // different from the brand hex values (system purple is more
    // red-violet; brand purple is blue-violet). The result was a
    // subtle inconsistency: dot indicators using the hex value
    // and badges/tints using system .purple read as two slightly
    // different colors side by side.
    static var mastodonColor: Color {
        Color(hex: "6364FF")
    }

    static var blueskyColor: Color {
        Color(hex: "0085FF")
    }

    // Hex color initializer
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

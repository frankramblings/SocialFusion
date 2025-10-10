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

    static var accentPurple: Color {
        Color("AccentPurple")
    }

    static var cardBackground: Color {
        Color("CardBackground")
    }

    static var subtleBorder: Color {
        // Use a more subtle border that adapts to color scheme
        Color.gray.opacity(0.2)
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

    // Platform-specific colors
    static var mastodonColor: Color {
        Color.purple
    }

    static var blueskyColor: Color {
        Color.blue
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

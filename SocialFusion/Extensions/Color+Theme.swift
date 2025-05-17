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
        colorScheme == .dark ? 
            Color.white.opacity(0.07) : // Dark mode - lighter overlay
            Color.black.opacity(0.03)   // Light mode - darker overlay
    }
    
    static func adaptiveElementBorder(for colorScheme: ColorScheme) -> Color {
        // Subtle border color for banners and parent posts
        colorScheme == .dark ? 
            Color.white.opacity(0.15) : // Dark mode - light border
            Color.black.opacity(0.08)   // Light mode - dark border
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
}

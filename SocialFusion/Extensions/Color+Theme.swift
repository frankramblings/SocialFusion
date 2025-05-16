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

    // Platform-specific colors
    static var mastodonColor: Color {
        Color.purple
    }

    static var blueskyColor: Color {
        Color.blue
    }
}

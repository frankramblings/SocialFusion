import SwiftUI

extension Color {
    static let customCardBackground = Color("CardBackground")
    static let subtleBorder = Color.gray.opacity(0.2)

    // Fallback colors if asset colors aren't available
    static var cardBackground: Color {
        if UIColor(named: "CardBackground") != nil {
            return Color("CardBackground")
        } else {
            return Color(.systemBackground)
        }
    }

    static var borderColor: Color {
        return Color.primary.opacity(0.1)
    }
}

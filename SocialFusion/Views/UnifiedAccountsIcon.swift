import SwiftUI

struct UnifiedAccountsIcon: View {
    let mastodonAccounts: [SocialAccount]
    let blueskyAccounts: [SocialAccount]

    @State private var refreshTrigger = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Clean circular background
            Circle()
                .fill(
                    colorScheme == .dark
                        ? Color(UIColor.tertiarySystemBackground)
                        : Color(UIColor.systemGray6)
                )
                .frame(width: 30, height: 30)

            if mastodonAccounts.isEmpty && blueskyAccounts.isEmpty {
                // No accounts, show a placeholder
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.secondary)
            } else {
                // Show a clean multi-account icon
                ZStack {
                    // Base icon
                    Image(systemName: "person.2.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.primary)

                    // Platform indicators in bottom right
                    VStack(spacing: 1) {
                        HStack(spacing: 1) {
                            Spacer()
                            VStack(spacing: 1) {
                                if !mastodonAccounts.isEmpty {
                                    Circle()
                                        .fill(Color(hex: "6364FF"))
                                        .frame(width: 6, height: 6)
                                }
                                if !blueskyAccounts.isEmpty {
                                    Circle()
                                        .fill(Color(hex: "0085FF"))
                                        .frame(width: 6, height: 6)
                                }
                            }
                        }
                        Spacer()
                    }
                    .frame(width: 30, height: 30)
                }
            }
        }
        .id(refreshTrigger)  // Force view refresh when trigger changes
        .onAppear {
            print(
                "UnifiedAccountsIcon appeared with \(mastodonAccounts.count) Mastodon accounts and \(blueskyAccounts.count) Bluesky accounts"
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileImageUpdated)) {
            notification in
            // PHASE 3+: Removed state modification to prevent AttributeGraph cycles
            // Profile image updates will be handled through normal data flow instead
        }
    }
}

// Helper extension for hex colors
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

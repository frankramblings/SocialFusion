import SwiftUI

/// Platform badge to show on account avatars
struct PlatformBadge: View {
    let platform: SocialPlatform

    private func getLogoSystemName(for platform: SocialPlatform) -> String {
        switch platform {
        case .mastodon:
            return "person.crop.circle"
        case .bluesky:
            return "person.crop.circle"
        }
    }

    private func getPlatformColor() -> Color {
        switch platform {
        case .mastodon:
            return Color("PrimaryColor")
        case .bluesky:
            return Color("SecondaryColor")
        }
    }

    var body: some View {
        ZStack {
            // Remove the white circle background
            // Just show the platform logo with a slight shadow for visibility
            Image(systemName: getLogoSystemName(for: platform))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(getPlatformColor())
                .shadow(color: Color.black.opacity(0.4), radius: 1.5, x: 0, y: 0)
        }
        .frame(width: 20, height: 20)
    }
}

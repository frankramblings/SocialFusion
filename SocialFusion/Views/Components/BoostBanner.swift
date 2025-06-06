import SwiftUI

/// "<user> boosted" pill styled like ReplyBanner.
struct BoostBanner: View {
    let handle: String
    let platform: SocialPlatform

    private var platformColor: Color {
        switch platform {
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "repeat")
                .font(.caption2)
                .foregroundColor(platformColor)
            Text("\(handle) boosted")
        }
        .font(.caption2)
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(platformColor.opacity(0.12)))
        .overlay(Capsule().stroke(platformColor, lineWidth: 0.5))
    }
}

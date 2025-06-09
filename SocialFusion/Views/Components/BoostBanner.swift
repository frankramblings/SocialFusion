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
        HStack(spacing: 6) {
            Image(systemName: "repeat")
                .font(.caption)
                .foregroundColor(platformColor)
            Text("\(handle) boosted")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

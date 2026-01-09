import SwiftUI

/// "<user> boosted" pill styled like ReplyBanner.
struct BoostBanner: View {
    let handle: String
    let platform: SocialPlatform
    let emojiMap: [String: String]?  // Emoji for the booster's display name

    // Animation state for subtle interactions
    @State private var isPressed = false
    
    init(handle: String, platform: SocialPlatform, emojiMap: [String: String]? = nil) {
        self.handle = handle
        self.platform = platform
        self.emojiMap = emojiMap
    }

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
                .scaleEffect(isPressed ? 0.95 : 1.0)
            HStack(spacing: 0) {
                EmojiDisplayNameText(
                    handle,
                    emojiMap: emojiMap,
                    font: .caption,
                    fontWeight: .regular,
                    foregroundColor: .secondary,
                    lineLimit: 1
                )
                Text(" boosted")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .opacity(isPressed ? 0.8 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .contentShape(Rectangle())
        .onLongPressGesture(
            minimumDuration: 0, maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            }, perform: {})
    }
}

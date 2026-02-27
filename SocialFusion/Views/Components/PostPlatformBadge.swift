import SwiftUI

/// A view that displays a platform indicator badge
/// Enhanced with Liquid Glass styling
struct PostPlatformBadge: View {
    let platform: SocialPlatform

    var body: some View {
        HStack(spacing: 4) {
            Image(platform.icon)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
                .foregroundColor(platform.swiftUIColor)

            Text(platform == .bluesky ? "Bluesky" : "Mastodon")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(platform.swiftUIColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(platform.swiftUIColor.opacity(0.1))
                .overlay(
                    Capsule()
                        .stroke(platform.swiftUIColor.opacity(0.3), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Preview
struct PostPlatformBadge_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 16) {
            // Bluesky badge
            PostPlatformBadge(platform: .bluesky)

            // Mastodon badge
            PostPlatformBadge(platform: .mastodon)
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}

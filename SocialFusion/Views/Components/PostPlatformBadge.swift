import SwiftUI

/// A view that displays a platform indicator badge
struct PostPlatformBadge: View {
    let platform: SocialPlatform

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: platformIcon)
                .foregroundColor(platformColor)

            Text(platformName)
                .font(.caption)
                .foregroundColor(platformColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(platformColor.opacity(0.1))
        .cornerRadius(8)
    }

    private var platformColor: Color {
        switch platform {
        case .bluesky:
            return .blue
        case .mastodon:
            return .purple
        }
    }

    private var platformIcon: String {
        switch platform {
        case .bluesky:
            return "b.square.fill"
        case .mastodon:
            return "m.square.fill"
        }
    }

    private var platformName: String {
        switch platform {
        case .bluesky:
            return "Bluesky"
        case .mastodon:
            return "Mastodon"
        }
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

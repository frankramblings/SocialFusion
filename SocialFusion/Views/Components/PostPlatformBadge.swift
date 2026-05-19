import SwiftUI

/// Labeled platform indicator badge — small logo + "Mastodon"/"Bluesky"
/// text inside a colored capsule. Used in DM views and other places that
/// need an explicit network label, not just an icon.
///
/// Honors the system high-contrast toggle: under high-contrast the badge's
/// glyph switches to filled-vs-outlined and the capsule chrome neutralizes
/// so the two networks remain visually distinct under colorblind simulation.
struct PostPlatformBadge: View {
    let platform: SocialPlatform

    @Environment(\.accessibilityPreferences) private var prefs

    var body: some View {
        HStack(spacing: 4) {
            PlatformLogoBadge(platform: platform, size: 14, shadowEnabled: false)
            Text(platform.accessibilityLabel)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(capsuleFill)
                .overlay(
                    Capsule()
                        .stroke(capsuleStroke, lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(platform.accessibilityLabel)
    }

    private var isHighContrast: Bool { prefs.highContrastNetworkIndicators }

    private var textColor: Color {
        isHighContrast ? .primary : platform.swiftUIColor
    }

    private var capsuleFill: Color {
        isHighContrast
            ? Color(.systemGray6)
            : platform.swiftUIColor.opacity(0.1)
    }

    private var capsuleStroke: Color {
        isHighContrast
            ? Color.primary.opacity(0.35)
            : platform.swiftUIColor.opacity(0.3)
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

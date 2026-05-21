import SwiftUI

/// A platform logo badge that displays SVG logos as badges on profile pictures
/// with a glass-like effect. Replaces colored dots with actual platform logos.
///
/// **Accessibility:**
/// - Shape-coded by default — uses the platform's silhouette (`MastodonLogo`
///   or `BlueskyLogo` asset) so identification does not depend on color.
/// - When `highContrast` is on (driven by `AccessibilityPreferences` or set
///   explicitly), Bluesky renders as a *filled* colored glyph with a thick
///   black outline, and Mastodon renders as an *outlined* dark glyph with
///   no color fill. This filled-vs-outlined contrast survives deuteranopia,
///   protanopia, and tritanopia simulations where blue and purple collapse.
/// - Sets a VoiceOver label so the network is announced.
struct PlatformLogoBadge: View {
    let platform: SocialPlatform
    var size: CGFloat = 16
    var shadowEnabled: Bool = true

    /// Explicit override. `nil` reads the value from `AccessibilityPreferences`
    /// in the environment.
    var highContrast: Bool? = nil

    @Environment(\.accessibilityPreferences) private var prefs

    private var isHighContrast: Bool {
        highContrast ?? prefs.highContrastNetworkIndicators
    }

    private var logoImageName: String {
        switch platform {
        case .bluesky:  return "BlueskyLogo"
        case .mastodon: return "MastodonLogo"
        }
    }

    private var platformColor: Color { platform.swiftUIColor }

    var body: some View {
        Group {
            if isHighContrast {
                HighContrastBadgeBody(
                    platform: platform,
                    logoImageName: logoImageName,
                    size: size,
                    shadowEnabled: shadowEnabled
                )
            } else {
                standardBody
            }
        }
        .accessibilityElement()
        .accessibilityLabel(platform.accessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }

    /// Original look: tinted logo over a glass-material background.
    private var standardBody: some View {
        Image(logoImageName)
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(platformColor)
            .frame(width: size * 0.66, height: size * 0.66)
            .padding(size * 0.17)
            .background {
                Circle()
                    .fill(.clear)
                    .background(.regularMaterial, in: Circle())
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(shadowEnabled ? 0.15 : 0), radius: 2, x: 0, y: 1)
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.3), lineWidth: 0.5)
            }
    }
}

#Preview {
    HStack(spacing: 20) {
        VStack(spacing: 10) {
            Text("Standard").font(.caption)
            PlatformLogoBadge(platform: .bluesky, size: 24)
            PlatformLogoBadge(platform: .mastodon, size: 24)
        }
        VStack(spacing: 10) {
            Text("High-Contrast").font(.caption)
            PlatformLogoBadge(platform: .bluesky, size: 24, highContrast: true)
            PlatformLogoBadge(platform: .mastodon, size: 24, highContrast: true)
        }
    }
    .padding()
}

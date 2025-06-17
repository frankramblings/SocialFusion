import SwiftUI

/// A platform logo badge that displays SVG logos as badges on profile pictures with glass-like effect
/// This replaces colored dots with actual platform logos for better clarity
struct PlatformLogoBadge: View {
    let platform: SocialPlatform
    var size: CGFloat = 16
    var shadowEnabled: Bool = true

    private var logoImageName: String {
        switch platform {
        case .bluesky:
            return "BlueskyLogo"
        case .mastodon:
            return "MastodonLogo"
        }
    }

    private var platformColor: Color {
        switch platform {
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
        }
    }

    var body: some View {
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
                    .opacity(0.85)
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
            Text("Bluesky")
            PlatformLogoBadge(platform: .bluesky, size: 20)
        }

        VStack(spacing: 10) {
            Text("Mastodon")
            PlatformLogoBadge(platform: .mastodon, size: 20)
        }
    }
    .padding()
    .background(
        AsyncImage(url: URL(string: "https://picsum.photos/300/200")) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(.gray.opacity(0.3))
        }
        .clipped()
    )
}

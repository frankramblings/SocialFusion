import SwiftUI

/// A small dot indicator showing the platform of a post
struct PlatformDot: View {
    let platform: SocialPlatform
    var size: CGFloat = 8

    private var platformColor: Color {
        switch platform {
        case .bluesky:
            return .blue
        case .mastodon:
            return .purple
        }
    }

    var body: some View {
        Circle()
            .fill(platformColor)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 0)
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack {
            Text("Mastodon")
            Spacer()
            PlatformDot(platform: .mastodon)
        }

        HStack {
            Text("Bluesky")
            Spacer()
            PlatformDot(platform: .bluesky)
        }

        HStack {
            Text("Custom Size")
            Spacer()
            PlatformDot(platform: .mastodon, size: 16)
        }
    }
    .padding()
}

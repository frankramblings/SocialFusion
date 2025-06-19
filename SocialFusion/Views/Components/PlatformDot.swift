import SwiftUI

/// A small platform indicator that can show either colored dots or SVG logos
struct PlatformDot: View {
    let platform: SocialPlatform
    var size: CGFloat = 8
    var useLogo: Bool = false  // New option to use SVG logos instead of dots
    var backgroundColor: Color = Color.white

    private var platformColor: Color {
        switch platform {
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
        }
    }

    private var logoImageName: String {
        switch platform {
        case .bluesky:
            return "BlueskyLogo"
        case .mastodon:
            return "MastodonLogo"
        }
    }

    var body: some View {
        if useLogo {
            // SVG logo version with full Liquid Glass
            PlatformLogoBadge(
                platform: platform,
                size: size,
                shadowEnabled: true
            )
        } else {
            // Original colored dot version
            Circle()
                .fill(platformColor)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(backgroundColor, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 0)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        VStack {
            Text("Colored Dots (Original)")
                .font(.headline)

            HStack(spacing: 20) {
                VStack {
                    Text("Mastodon")
                        .font(.caption)
                    PlatformDot(platform: .mastodon, size: 12)
                }

                VStack {
                    Text("Bluesky")
                        .font(.caption)
                    PlatformDot(platform: .bluesky, size: 12)
                }
            }
        }

        Divider()

        VStack {
            Text("SVG Logos (New)")
                .font(.headline)

            HStack(spacing: 20) {
                VStack {
                    Text("Mastodon")
                        .font(.caption)
                    PlatformDot(platform: .mastodon, size: 16, useLogo: true)
                }

                VStack {
                    Text("Bluesky")
                        .font(.caption)
                    PlatformDot(platform: .bluesky, size: 16, useLogo: true)
                }
            }
        }

        VStack {
            Text("Different Sizes")
                .font(.headline)

            HStack(spacing: 20) {
                VStack {
                    Text("Small (12pt)")
                        .font(.caption2)
                    PlatformDot(platform: .mastodon, size: 12, useLogo: true)
                }

                VStack {
                    Text("Medium (16pt)")
                        .font(.caption2)
                    PlatformDot(platform: .bluesky, size: 16, useLogo: true)
                }

                VStack {
                    Text("Large (24pt)")
                        .font(.caption2)
                    PlatformDot(platform: .mastodon, size: 24, useLogo: true)
                }
            }
        }
    }
    .padding()
}

import SwiftUI

/// Avatar view with platform indicator badge using SVG logos
struct PostAuthorImageView: View {
    var platform: SocialPlatform
    var size: CGFloat = 44

    // Capture stable values at init time to prevent AsyncImage cancellation
    private let stableImageURL: URL?

    init(authorProfilePictureURL: String, platform: SocialPlatform, size: CGFloat = 44) {
        self.stableImageURL = URL(string: authorProfilePictureURL)
        self.platform = platform
        self.size = size
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Author avatar using cached image loading with retry logic
            CachedAsyncImage(url: stableImageURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Group {
                            if stableImageURL != nil {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "person.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: size * 0.4))
                            }
                        }
                    )
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color(.systemBackground), lineWidth: 1)
            )

            // Platform indicator badge with SVG logo and full Liquid Glass
            PlatformLogoBadge(
                platform: platform,
                size: max(18, size * 0.38),  // Increased size for better visibility (10% larger)
                shadowEnabled: true
            )
            .offset(x: 2, y: 2)  // Small offset to position badge properly
        }
    }
}

#Preview("Avatar Previews") {
    VStack(spacing: 20) {
        // Different sizes
        HStack(spacing: 16) {
            VStack {
                Text("32pt")
                    .font(.caption2)
                PostAuthorImageView(
                    authorProfilePictureURL: "https://example.com/avatar.jpg",
                    platform: .bluesky,
                    size: 32
                )
            }

            VStack {
                Text("44pt (default)")
                    .font(.caption2)
                PostAuthorImageView(
                    authorProfilePictureURL: "https://example.com/avatar.jpg",
                    platform: .mastodon
                )
            }

            VStack {
                Text("60pt")
                    .font(.caption2)
                PostAuthorImageView(
                    authorProfilePictureURL: "https://example.com/avatar.jpg",
                    platform: .bluesky,
                    size: 60
                )
            }
        }

        // Different platforms
        HStack(spacing: 16) {
            PostAuthorImageView(
                authorProfilePictureURL: "https://example.com/avatar.jpg",
                platform: .bluesky
            )

            PostAuthorImageView(
                authorProfilePictureURL: "https://example.com/avatar.jpg",
                platform: .mastodon
            )
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

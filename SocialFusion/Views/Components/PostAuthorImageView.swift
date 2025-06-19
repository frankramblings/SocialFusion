import SwiftUI

/// Avatar view with platform indicator for Bluesky
struct PostAuthorImageView: View {
    var platform: SocialPlatform
    var size: CGFloat = 44

    // Bluesky blue color
    private let blueskyBlue = Color(red: 0, green: 122 / 255, blue: 255 / 255)

    // Capture stable values at init time to prevent AsyncImage cancellation
    private let stableImageURL: URL?

    init(authorProfilePictureURL: String, platform: SocialPlatform, size: CGFloat = 44) {
        self.stableImageURL = URL(string: authorProfilePictureURL)
        self.platform = platform
        self.size = size
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Author avatar using completely stable URL
            AsyncImage(url: stableImageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure(_):
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.white)
                                .font(.system(size: size * 0.4))
                        )
                case .empty:
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.7)
                        )
                @unknown default:
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color(.systemBackground), lineWidth: 1)
            )
            .id(stableImageURL?.absoluteString ?? "no-url")

            // Platform indicator - small circle in bottom right
            if platform == .bluesky {
                Circle()
                    .fill(blueskyBlue)
                    .frame(width: size * 0.2, height: size * 0.2)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.3), lineWidth: 0.5)
                    )
                    .offset(x: 1, y: 1)
            } else if platform == .mastodon {
                Circle()
                    .fill(Color.purple)
                    .frame(width: size * 0.2, height: size * 0.2)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.3), lineWidth: 0.5)
                    )
                    .offset(x: 1, y: 1)
            }
        }
    }
}

#Preview("Avatar Previews") {
    VStack(spacing: 20) {
        PostAuthorImageView(
            authorProfilePictureURL: "https://example.com/avatar.jpg",
            platform: .bluesky
        )

        PostAuthorImageView(
            authorProfilePictureURL: "https://example.com/avatar.jpg",
            platform: .mastodon
        )
    }
    .padding()
    .background(Color.black)
}

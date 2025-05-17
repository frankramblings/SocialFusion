import SwiftUI

/// Avatar view with platform indicator for Bluesky
struct PostAuthorImageView: View {
    var authorProfilePictureURL: String
    var platform: SocialPlatform
    var size: CGFloat = 44

    // Bluesky blue color
    private let blueskyBlue = Color(red: 0, green: 122 / 255, blue: 255 / 255)

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Author avatar
            AsyncImage(url: URL(string: authorProfilePictureURL)) { phase in
                if let image = phase.image {
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Circle().fill(Color.gray.opacity(0.3))
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())

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

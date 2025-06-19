import SwiftUI

/// A view that displays a user's avatar
struct PostAvatar: View {
    let imageURL: String
    let platform: SocialPlatform
    let size: CGFloat

    var body: some View {
        StabilizedAsyncImage(
            url: URL(string: imageURL),
            idealHeight: size,
            aspectRatio: 1.0,
            contentMode: .fill,
            cornerRadius: size / 2
        )
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .stroke(platformColor, lineWidth: 2)
        )
    }

    private var placeholderView: some View {
        Image(systemName: "person.fill")
            .font(.system(size: size * 0.6))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(platformColor)
    }

    private var platformColor: Color {
        switch platform {
        case .bluesky:
            return .blue
        case .mastodon:
            return .purple
        }
    }
}

// MARK: - Preview
struct PostAvatar_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 16) {
            // Bluesky avatar with image
            PostAvatar(
                imageURL: "https://example.com/avatar.jpg",
                platform: .bluesky,
                size: 40
            )

            // Mastodon avatar with image
            PostAvatar(
                imageURL: "https://example.com/avatar.jpg",
                platform: .mastodon,
                size: 40
            )

            // Bluesky avatar without image
            PostAvatar(
                imageURL: "",
                platform: .bluesky,
                size: 40
            )

            // Mastodon avatar without image
            PostAvatar(
                imageURL: "",
                platform: .mastodon,
                size: 40
            )

            // Different sizes
            PostAvatar(
                imageURL: "",
                platform: .bluesky,
                size: 32
            )

            PostAvatar(
                imageURL: "",
                platform: .bluesky,
                size: 48
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}

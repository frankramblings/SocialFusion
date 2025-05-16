import SwiftUI

/// Avatar view with platform indicator
struct PostAuthorImageView: View {
    var authorProfilePictureURL: String
    var platform: SocialPlatform
    var size: CGFloat = 40

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Author avatar
            AsyncImage(url: URL(string: authorProfilePictureURL)) { phase in
                if let image = phase.image {
                    image.resizable()
                } else {
                    Circle().fill(Color.gray.opacity(0.3))
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())

            // Platform indicator
            PlatformDot(platform: platform, size: size * 0.3)
                .offset(x: 2, y: 2)
        }
    }
}

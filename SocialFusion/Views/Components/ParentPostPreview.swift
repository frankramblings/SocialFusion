import SwiftUI

// Parent post preview component
struct ParentPostPreview: View {
    let post: Post
    var onTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Author avatar with platform indicator
                ZStack(alignment: .bottomTrailing) {
                    // Author avatar
                    AsyncImage(url: URL(string: post.authorProfilePictureURL)) { phase in
                        if let image = phase.image {
                            image.resizable()
                        } else {
                            Circle().fill(Color.gray.opacity(0.3))
                        }
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())

                    // Platform indicator
                    PlatformDot(platform: post.platform, size: 10)
                        .offset(x: 2, y: 2)
                }

                // Author info
                VStack(alignment: .leading, spacing: 0) {
                    Text(post.authorName)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("@\(post.authorUsername)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Post content
            post.contentView(lineLimit: 3)
        }
        .padding(8)
        .contentShape(Rectangle())
        .onTapGesture {
            if let onTap = onTap {
                onTap()
            }
        }
    }
}

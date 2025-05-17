import SwiftUI

// Parent post preview component with styling to match the Bluesky design
struct ParentPostPreview: View {
    let post: Post
    var onTap: (() -> Void)? = nil

    // Maximum characters before content is trimmed
    private let maxCharacters = 500

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                    .frame(width: 36, height: 36)
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

                // Time ago
                Text(post.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Post content with conditional line limit
            post.contentView(lineLimit: post.content.count > maxCharacters ? 8 : nil)
                .font(.system(size: 14))  // Smaller size for parent posts
                .padding(.leading, 4)
                .padding(.trailing, 8)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if let onTap = onTap {
                onTap()
            }
        }
    }
}

#Preview {
    VStack {
        ParentPostPreview(post: Post.samplePosts[0])
    }
    .padding()
    .background(Color.black)
}

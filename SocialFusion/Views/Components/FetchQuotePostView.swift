import SwiftUI

/// Fetches and displays a quoted post from a URL
struct FetchQuotePostView: View {
    let url: URL
    @State private var quotedPost: Post? = nil
    @State private var isLoading = true
    @State private var error: Error? = nil
    @EnvironmentObject private var serviceManager: SocialServiceManager

    var body: some View {
        VStack {
            if let post = quotedPost {
                QuotedPostView(post: post)
            } else if isLoading {
                ProgressView()
                    .padding()
            } else if error != nil {
                LinkPreview(url: url)
            }
        }
        .onAppear {
            fetchPost()
        }
    }

    private func fetchPost() {
        // In a real implementation, this would fetch the post from the appropriate service
        isLoading = false
    }
}

/// A compact view of a quoted post
private struct QuotedPostView: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Author info
            HStack {
                AsyncImage(url: URL(string: post.authorProfilePictureURL)) { phase in
                    if let image = phase.image {
                        image.resizable()
                    } else {
                        Circle().fill(Color.gray.opacity(0.3))
                    }
                }
                .frame(width: 24, height: 24)
                .clipShape(Circle())

                Text(post.authorName)
                    .font(.footnote)
                    .fontWeight(.semibold)

                Spacer()

                PlatformDot(platform: post.platform, size: 4)
            }

            // Post content
            post.contentView(lineLimit: 4)

            // Quoted post media (if any)
            if !post.attachments.isEmpty {
                AsyncImage(url: URL(string: post.attachments[0].url)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 100)
                            .clipped()
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

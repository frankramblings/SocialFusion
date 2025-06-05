import SwiftUI

struct QuotePostView: View {
    @ObservedObject var viewModel: PostViewModel

    var body: some View {
        let post = viewModel.post
        VStack(alignment: .leading, spacing: 8) {
            // Author info
            HStack(alignment: .center) {
                AsyncImage(url: URL(string: post.authorProfilePictureURL)) { phase in
                    if let image = phase.image {
                        image.resizable()
                    } else if phase.error != nil {
                        Color.gray.opacity(0.3)
                    } else {
                        Color.gray.opacity(0.1)
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("@\(post.authorUsername)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                PlatformDot(platform: post.platform)
            }

            // Post content
            Text(post.content)
                .font(.body)
                .padding(.vertical, 4)

            // Media attachments
            if !post.attachments.isEmpty {
                MediaGridView(attachments: post.attachments)
                    .padding(.vertical, 4)
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

#Preview {
    QuotePostView(viewModel: PostViewModel.preview)
}

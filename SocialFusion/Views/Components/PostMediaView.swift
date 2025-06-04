import SwiftUI

/// A view that displays media attachments in a post
struct PostMediaView: View {
    let attachments: [Post.Attachment]
    let onMediaTap: (Post.Attachment) -> Void

    var body: some View {
        if attachments.isEmpty {
            EmptyView()
        } else if attachments.count == 1 {
            singleMediaView(attachments[0])
        } else {
            mediaGrid(attachments)
        }
    }

    private func singleMediaView(_ attachment: Post.Attachment) -> some View {
        Button(action: { onMediaTap(attachment) }) {
            AsyncImage(url: URL(string: attachment.url)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                ProgressView()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func mediaGrid(_ attachments: [Post.Attachment]) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 4),
            GridItem(.flexible(), spacing: 4),
        ]

        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(attachments.prefix(4), id: \.url) { attachment in
                Button(action: { onMediaTap(attachment) }) {
                    AsyncImage(url: URL(string: attachment.url)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

/// A view that displays a single media item
private struct MediaItemView: View {
    let attachment: Post.Attachment

    var body: some View {
        Group {
            switch attachment.type {
            case .image:
                AsyncImage(url: URL(string: attachment.previewURL ?? attachment.url)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.2)
                }

            case .video:
                ZStack {
                    AsyncImage(url: URL(string: attachment.previewURL ?? attachment.url)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.2)
                    }

                    Image(systemName: "play.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                }

            case .gif:
                AsyncImage(url: URL(string: attachment.previewURL ?? attachment.url)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
                .overlay(
                    Text("GIF")
                        .font(.caption)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .padding(8),
                    alignment: .topTrailing
                )
            }
        }
    }
}

// MARK: - Preview
struct PostMediaView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Single image
            PostMediaView(
                attachments: [
                    Post.Attachment(
                        type: .image,
                        url: "https://example.com/image.jpg",
                        previewURL: "https://example.com/preview.jpg",
                        altText: "Test image"
                    )
                ],
                onMediaTap: { _ in }
            )

            // Multiple images
            PostMediaView(
                attachments: [
                    Post.Attachment(
                        type: .image,
                        url: "https://example.com/image1.jpg",
                        previewURL: "https://example.com/preview1.jpg",
                        altText: "Test image 1"
                    ),
                    Post.Attachment(
                        type: .image,
                        url: "https://example.com/image2.jpg",
                        previewURL: "https://example.com/preview2.jpg",
                        altText: "Test image 2"
                    ),
                    Post.Attachment(
                        type: .image,
                        url: "https://example.com/image3.jpg",
                        previewURL: "https://example.com/preview3.jpg",
                        altText: "Test image 3"
                    ),
                    Post.Attachment(
                        type: .image,
                        url: "https://example.com/image4.jpg",
                        previewURL: "https://example.com/preview4.jpg",
                        altText: "Test image 4"
                    ),
                ],
                onMediaTap: { _ in }
            )

            // No attachments
            PostMediaView(
                attachments: [],
                onMediaTap: { _ in }
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}

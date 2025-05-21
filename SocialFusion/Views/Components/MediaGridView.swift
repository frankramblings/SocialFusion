import SwiftUI

/// A view that displays media attachments in a grid layout
struct MediaGridView: View {
    let attachments: [Post.Attachment]
    @State private var selectedMedia: Post.Attachment?
    @State private var showFullscreen = false
    var maxHeight: CGFloat? = nil

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            switch attachments.count {
            case 0:
                EmptyView()

            case 1:
                // Single attachment fills card width, fits aspect ratio
                singleAttachmentView(attachment: attachments[0], width: width)
                    .padding(.horizontal, 2)

            case 2:
                HStack(spacing: 2) {
                    singleAttachmentView(attachment: attachments[0], width: width / 2 - 2)
                    singleAttachmentView(attachment: attachments[1], width: width / 2 - 2)
                }
                .padding(.horizontal, 2)

            case 3:
                HStack(spacing: 2) {
                    singleAttachmentView(attachment: attachments[0], width: width * 0.66 - 2)
                    VStack(spacing: 2) {
                        singleAttachmentView(attachment: attachments[1], width: width * 0.34 - 2)
                        singleAttachmentView(attachment: attachments[2], width: width * 0.34 - 2)
                    }
                }
                .padding(.horizontal, 2)

            case 4:
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        singleAttachmentView(attachment: attachments[0], width: width / 2 - 2)
                        singleAttachmentView(attachment: attachments[1], width: width / 2 - 2)
                    }
                    HStack(spacing: 2) {
                        singleAttachmentView(attachment: attachments[2], width: width / 2 - 2)
                        singleAttachmentView(attachment: attachments[3], width: width / 2 - 2)
                    }
                }
                .padding(.horizontal, 2)

            default:
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        singleAttachmentView(attachment: attachments[0], width: width / 2 - 2)
                        singleAttachmentView(attachment: attachments[1], width: width / 2 - 2)
                    }
                    HStack(spacing: 2) {
                        singleAttachmentView(attachment: attachments[2], width: width / 2 - 2)
                        ZStack {
                            singleAttachmentView(attachment: attachments[3], width: width / 2 - 2)
                            if attachments.count > 4 {
                                Rectangle()
                                    .fill(Color.black.opacity(0.6))
                                    .cornerRadius(14)
                                Text("+\(attachments.count - 4) more")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .frame(maxHeight: maxHeight)
        .sheet(isPresented: $showFullscreen) {
            if let media = selectedMedia {
                FullscreenMediaView(media: media, allMedia: attachments)
            }
        }
    }

    private func singleAttachmentView(attachment: Post.Attachment, width: CGFloat) -> some View {
        // Check for valid URL
        guard let url = URL(string: attachment.url), !attachment.url.isEmpty else {
            return AnyView(
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: width, height: width * 0.75)
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                }
            )
        }
        return AnyView(
            Button(action: {
                selectedMedia = attachment
                showFullscreen = true
            }) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: attachments.count == 1 ? .fit : .fill)
                            .frame(width: width)
                            .cornerRadius(14)
                            .accessibilityLabel(attachment.altText ?? "Image")
                    } else if phase.error != nil {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: width, height: width * 0.75)
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        }
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: width, height: width * 0.75)
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        }
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
        )
    }
}

struct MediaGridView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleAttachments = [
            Post.Attachment(
                url: "https://picsum.photos/400",
                type: .image,
                altText: "Sample image 1"
            ),
            Post.Attachment(
                url: "https://picsum.photos/401",
                type: .image,
                altText: "Sample image 2"
            ),
            Post.Attachment(
                url: "https://picsum.photos/402",
                type: .image,
                altText: "Sample image 3"
            ),
            Post.Attachment(
                url: "https://picsum.photos/403",
                type: .image,
                altText: "Sample image 4"
            ),
        ]

        Group {
            MediaGridView(attachments: Array(sampleAttachments.prefix(1)))
                .frame(width: 300, height: 300)
                .previewDisplayName("1 Image")

            MediaGridView(attachments: Array(sampleAttachments.prefix(2)))
                .frame(width: 300, height: 150)
                .previewDisplayName("2 Images")

            MediaGridView(attachments: Array(sampleAttachments.prefix(3)))
                .frame(width: 300, height: 200)
                .previewDisplayName("3 Images")

            MediaGridView(attachments: Array(sampleAttachments.prefix(4)))
                .frame(width: 300, height: 300)
                .previewDisplayName("4 Images")

            MediaGridView(attachments: sampleAttachments + [sampleAttachments[0]])
                .frame(width: 300, height: 300)
                .previewDisplayName("5+ Images")
        }
        .padding()
        .background(Color(.systemGray6))
        .previewLayout(.sizeThatFits)
    }
}

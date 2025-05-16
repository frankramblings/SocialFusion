import SwiftUI

/// A view that displays media attachments in a grid layout
struct MediaGridView: View {
    let attachments: [MediaAttachment]
    @State private var selectedMedia: MediaAttachment?
    @State private var showFullscreen = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            switch attachments.count {
            case 0:
                EmptyView()

            case 1:
                // Single attachment gets full width
                singleAttachmentView(attachment: attachments[0], size: width)

            case 2:
                // Two attachments side by side
                HStack(spacing: 2) {
                    singleAttachmentView(attachment: attachments[0], size: width / 2 - 1)
                    singleAttachmentView(attachment: attachments[1], size: width / 2 - 1)
                }

            case 3:
                // One large on left, two stacked on right
                HStack(spacing: 2) {
                    singleAttachmentView(attachment: attachments[0], size: width * 0.66 - 1)

                    VStack(spacing: 2) {
                        singleAttachmentView(attachment: attachments[1], size: width * 0.33 - 1)
                        singleAttachmentView(attachment: attachments[2], size: width * 0.33 - 1)
                    }
                }

            case 4:
                // 2x2 grid
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        singleAttachmentView(attachment: attachments[0], size: width / 2 - 1)
                        singleAttachmentView(attachment: attachments[1], size: width / 2 - 1)
                    }
                    HStack(spacing: 2) {
                        singleAttachmentView(attachment: attachments[2], size: width / 2 - 1)
                        singleAttachmentView(attachment: attachments[3], size: width / 2 - 1)
                    }
                }

            default:
                // 2x2 grid with "+X more" overlay on last item
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        singleAttachmentView(attachment: attachments[0], size: width / 2 - 1)
                        singleAttachmentView(attachment: attachments[1], size: width / 2 - 1)
                    }
                    HStack(spacing: 2) {
                        singleAttachmentView(attachment: attachments[2], size: width / 2 - 1)

                        ZStack {
                            singleAttachmentView(attachment: attachments[3], size: width / 2 - 1)

                            if attachments.count > 4 {
                                Rectangle()
                                    .fill(Color.black.opacity(0.6))

                                Text("+\(attachments.count - 4) more")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
            }
        }
        .aspectRatio(contentMode: .fit)
        .sheet(
            isPresented: $showFullscreen,
            content: {
                if let media = selectedMedia {
                    FullscreenMediaView(media: media, allMedia: attachments)
                }
            })
    }

    private func singleAttachmentView(attachment: MediaAttachment, size: CGFloat) -> some View {
        Button(action: {
            selectedMedia = attachment
            showFullscreen = true
        }) {
            AsyncImage(url: attachment.url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if phase.error != nil {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        )
                }
            }
            .frame(width: size, height: size)
            .clipped()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct MediaGridView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleAttachments = [
            MediaAttachment(
                id: "1",
                url: URL(string: "https://picsum.photos/400")!,
                altText: "Sample image 1"
            ),
            MediaAttachment(
                id: "2",
                url: URL(string: "https://picsum.photos/401")!,
                altText: "Sample image 2"
            ),
            MediaAttachment(
                id: "3",
                url: URL(string: "https://picsum.photos/402")!,
                altText: "Sample image 3"
            ),
            MediaAttachment(
                id: "4",
                url: URL(string: "https://picsum.photos/403")!,
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

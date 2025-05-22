import SwiftUI

struct UnifiedMediaGridView: View {
    let attachments: [Post.Attachment]
    var maxHeight: CGFloat = 300
    @State private var selectedAttachment: Post.Attachment? = nil
    @State private var showFullscreen = false

    var body: some View {
        Group {
            switch attachments.count {
            case 0:
                EmptyView()
            case 1:
                SingleImageView(
                    attachment: attachments[0],
                    onTap: {
                        selectedAttachment = attachments[0]
                        showFullscreen = true
                    }
                )
            case 2...4:
                MultiImageGridView(
                    attachments: attachments,
                    onTap: { att in
                        selectedAttachment = att
                        showFullscreen = true
                    }
                )
            default:
                MultiImageGridView(
                    attachments: Array(attachments.prefix(4)),
                    onTap: { att in
                        selectedAttachment = att
                        showFullscreen = true
                    },
                    extraCount: attachments.count - 4
                )
            }
        }
        .sheet(isPresented: $showFullscreen) {
            if let selected = selectedAttachment {
                FullscreenMediaView(media: selected, allMedia: attachments)
            }
        }
    }
}

private struct SingleImageView: View {
    let attachment: Post.Attachment
    let onTap: () -> Void
    var body: some View {
        ZStack(alignment: .topLeading) {
            AsyncImage(url: URL(string: attachment.url)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .onTapGesture { onTap() }
                } else if phase.error != nil {
                    Color.gray
                        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 400)
                        .overlay(Image(systemName: "exclamationmark.triangle").font(.largeTitle))
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 400)
                }
            }
            if let alt = attachment.altText, !alt.isEmpty {
                AltBadge()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(
                Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
    }
}

private struct MultiImageGridView: View {
    let attachments: [Post.Attachment]
    let onTap: (Post.Attachment) -> Void
    var extraCount: Int = 0
    private let gridSize: CGFloat = 120
    private let spacing: CGFloat = 4

    var body: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(attachments.prefix(4)) { att in
                ZStack(alignment: .topLeading) {
                    AsyncImage(url: URL(string: att.url)) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: gridSize, height: gridSize)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(
                                        Color.secondary.opacity(0.12), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
                                .clipped()
                                .onTapGesture { onTap(att) }
                        } else if phase.error != nil {
                            Color.gray
                                .frame(width: gridSize, height: gridSize)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(Image(systemName: "exclamationmark.triangle").font(.title))
                        } else {
                            ProgressView()
                                .frame(width: gridSize, height: gridSize)
                        }
                    }
                    if let alt = att.altText, !alt.isEmpty {
                        AltBadge()
                    }
                }
            }
            if extraCount > 0 {
                ZStack {
                    Color.black.opacity(0.5)
                        .frame(width: gridSize, height: gridSize)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text("+\(extraCount)")
                        .font(.title)
                        .foregroundColor(.white)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AltBadge: View {
    var body: some View {
        Text("ALT")
            .font(.caption2).bold()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.7))
            .foregroundColor(.white)
            .clipShape(Capsule())
            .padding(8)
    }
}

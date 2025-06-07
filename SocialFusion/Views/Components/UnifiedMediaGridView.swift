import SwiftUI

private class MediaSelectionModel: ObservableObject {
    @Published var selectedAttachment: Post.Attachment? = nil
    @Published var showFullscreen: Bool = false
}

struct UnifiedMediaGridView: View {
    let attachments: [Post.Attachment]
    var maxHeight: CGFloat = 300
    @StateObject private var selection = MediaSelectionModel()

    var body: some View {
        Group {
            switch attachments.count {
            case 0:
                EmptyView()
            case 1:
                SingleImageView(
                    attachment: attachments[0],
                    onTap: {
                        selection.selectedAttachment = attachments[0]
                        selection.showFullscreen = true
                    }
                )
            case 2...4:
                MultiImageGridView(
                    attachments: attachments,
                    onTap: { att in
                        selection.selectedAttachment = att
                        selection.showFullscreen = true
                    }
                )
            default:
                MultiImageGridView(
                    attachments: Array(attachments.prefix(4)),
                    onTap: { att in
                        selection.selectedAttachment = att
                        selection.showFullscreen = true
                    },
                    extraCount: attachments.count - 4
                )
            }
        }
        .sheet(isPresented: $selection.showFullscreen) {
            SheetDebugWrapper(
                selectedAttachment: selection.selectedAttachment, attachments: attachments
            ) {
                if let selected = selection.selectedAttachment {
                    AnyView(FullscreenMediaView(media: selected, allMedia: attachments))
                } else {
                    AnyView(Color.black)  // fallback
                }
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
                        .onTapGesture {
                            onTap()
                        }
                } else if phase.error != nil {
                    Color.gray
                        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 400)
                        .overlay(Image(systemName: "exclamationmark.triangle").font(.largeTitle))
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 400)
                }
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(
                    Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 2)
            if let alt = attachment.altText, !alt.isEmpty {
                GlassyAltBadge()
            }
        }
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
                                .frame(height: gridSize)
                                .frame(maxWidth: .infinity)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(
                                        Color.secondary.opacity(0.12), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
                                .clipped()
                                .onTapGesture {
                                    onTap(att)
                                }
                        } else if phase.error != nil {
                            Color.gray
                                .frame(height: gridSize)
                                .frame(maxWidth: .infinity)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(Image(systemName: "exclamationmark.triangle").font(.title))
                        } else {
                            ProgressView()
                                .frame(height: gridSize)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if let alt = att.altText, !alt.isEmpty {
                        GlassyAltBadge()
                    }
                }
            }
            if extraCount > 0 {
                ZStack {
                    Color.black.opacity(0.5)
                        .frame(height: gridSize)
                        .frame(maxWidth: .infinity)
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

private struct GlassyAltBadge: View {
    var body: some View {
        Text("ALT")
            .font(.caption2).bold()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial)
            .foregroundColor(.white)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 2, x: 0, y: 1)
            .padding(8)
    }
}

private struct SheetDebugWrapper<Content: View>: View {
    let selectedAttachment: Post.Attachment?
    let attachments: [Post.Attachment]
    let content: () -> Content

    var body: some View {
        content()
            .onAppear {
                print(
                    "Sheet is being presented. selectedAttachment: \(String(describing: selectedAttachment)), attachments.count: \(attachments.count)"
                )
                if let selected = selectedAttachment {
                    print(
                        "Presenting FullscreenMediaView with selected.url=\(selected.url), attachments.count=\(attachments.count)"
                    )
                } else {
                    print("Sheet presented but selectedAttachment is nil")
                }
            }
    }
}

import SwiftUI

private class MediaSelectionModel: ObservableObject {
    @Published var selectedAttachment: Post.Attachment? = nil
    @Published var showFullscreen: Bool = false
    @Published var showAltTextInitially: Bool = false
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
                        selection.showAltTextInitially = false
                        selection.showFullscreen = true
                    },
                    onAltTap: { att in
                        selection.selectedAttachment = att
                        selection.showAltTextInitially = true
                        selection.showFullscreen = true
                    }
                )
            case 2...4:
                MultiImageGridView(
                    attachments: attachments,
                    onTap: { att in
                        selection.selectedAttachment = att
                        selection.showAltTextInitially = false
                        selection.showFullscreen = true
                    },
                    onAltTap: { att in
                        selection.selectedAttachment = att
                        selection.showAltTextInitially = true
                        selection.showFullscreen = true
                    }
                )
            default:
                MultiImageGridView(
                    attachments: Array(attachments.prefix(4)),
                    onTap: { att in
                        selection.selectedAttachment = att
                        selection.showAltTextInitially = false
                        selection.showFullscreen = true
                    },
                    onAltTap: { att in
                        selection.selectedAttachment = att
                        selection.showAltTextInitially = true
                        selection.showFullscreen = true
                    },
                    extraCount: attachments.count - 4
                )
            }
        }
        .sheet(isPresented: $selection.showFullscreen) {
            if let selected = selection.selectedAttachment {
                FullscreenMediaView(
                    media: selected, allMedia: attachments,
                    showAltTextInitially: selection.showAltTextInitially)
            } else {
                Color.black  // fallback
            }
        }
        .onChange(of: selection.showFullscreen) { isPresented in
            if !isPresented {
                // Reset alt text flag when sheet is dismissed
                selection.showAltTextInitially = false
            }
        }
    }
}

private struct SingleImageView: View {
    let attachment: Post.Attachment
    let onTap: () -> Void
    let onAltTap: ((Post.Attachment) -> Void)?

    // Capture stable URL at init time
    private let stableURL: URL?

    init(
        attachment: Post.Attachment, onTap: @escaping () -> Void,
        onAltTap: ((Post.Attachment) -> Void)? = nil
    ) {
        self.attachment = attachment
        self.onTap = onTap
        self.onAltTap = onAltTap
        self.stableURL = URL(string: attachment.url)
        print("🖼️ [SingleImageView] Loading image URL: \(attachment.url)")
        print("🖼️ [SingleImageView] Parsed URL: \(String(describing: stableURL))")
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: stableURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: 500)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .onAppear {
                            print(
                                "✅ [SingleImageView] Successfully loaded image from: \(String(describing: stableURL))"
                            )
                        }
                case .failure(let error):
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(maxWidth: .infinity)
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "photo")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("Image unavailable")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        )
                        .onAppear {
                            print(
                                "❌ [SingleImageView] Failed to load image from: \(String(describing: stableURL)) - Error: \(error)"
                            )
                        }
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(maxWidth: .infinity)
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            ProgressView()
                                .scaleEffect(1.2)
                        )
                        .onAppear {
                            print(
                                "⏳ [SingleImageView] Loading image from: \(String(describing: stableURL))"
                            )
                        }
                @unknown default:
                    EmptyView()
                }
            }
            .onTapGesture {
                onTap()
            }

            if let alt = attachment.altText, !alt.isEmpty {
                GlassyAltBadge()
                    .padding(.bottom, 8)
                    .padding(.trailing, 8)
                    .onTapGesture {
                        onAltTap?(attachment)
                    }
            }
        }
    }
}

private struct MultiImageGridView: View {
    let attachments: [Post.Attachment]
    let onTap: (Post.Attachment) -> Void
    let onAltTap: ((Post.Attachment) -> Void)?
    var extraCount: Int = 0
    private let gridSize: CGFloat = 150
    private let spacing: CGFloat = 6

    var body: some View {
        HStack {
            Spacer()

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: spacing),
                    GridItem(.flexible()),
                ],
                spacing: spacing
            ) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    GridImageView(
                        attachment: attachment,
                        gridSize: gridSize,
                        onTap: onTap,
                        extraCount: extraCount,
                        isLast: attachment.id == attachments.last?.id,
                        onAltTap: onAltTap
                    )
                }
            }
            .frame(width: gridSize * 2 + spacing)

            Spacer()
        }
    }
}

private struct GridImageView: View {
    let attachment: Post.Attachment
    let gridSize: CGFloat
    let onTap: (Post.Attachment) -> Void
    let extraCount: Int
    let isLast: Bool
    let onAltTap: ((Post.Attachment) -> Void)?

    // Capture stable URL at init time
    private let stableURL: URL?

    init(
        attachment: Post.Attachment, gridSize: CGFloat, onTap: @escaping (Post.Attachment) -> Void,
        extraCount: Int, isLast: Bool, onAltTap: ((Post.Attachment) -> Void)? = nil
    ) {
        self.attachment = attachment
        self.gridSize = gridSize
        self.onTap = onTap
        self.extraCount = extraCount
        self.isLast = isLast
        self.onAltTap = onAltTap
        self.stableURL = URL(string: attachment.url)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: stableURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: gridSize, height: gridSize)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                case .failure(_):
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: gridSize, height: gridSize)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        )
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.08))
                        .frame(width: gridSize, height: gridSize)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            ProgressView()
                                .scaleEffect(1.0)
                        )
                @unknown default:
                    EmptyView()
                }
            }
            .onTapGesture {
                onTap(attachment)
            }

            if let alt = attachment.altText, !alt.isEmpty {
                GlassyAltBadge()
                    .padding(.bottom, 4)
                    .padding(.trailing, 4)
                    .onTapGesture {
                        onAltTap?(attachment)
                    }
            }

            // Show "+X more" overlay on the last item if there are extra items
            if extraCount > 0 && isLast {
                Rectangle()
                    .fill(Color.black.opacity(0.7))
                    .frame(width: gridSize, height: gridSize)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        Text("+\(extraCount)")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    )
            }
        }
    }
}

// Helper badge for alt text indication
private struct GlassyAltBadge: View {
    var body: some View {
        Text("ALT")
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)  // Force dark appearance for glass effect
            .scaleEffect(1.1)  // 10% larger
    }
}

// Extension to make Post.Attachment identifiable if it's not already
// (Remove this since Post.Attachment already conforms to Identifiable in the main model)

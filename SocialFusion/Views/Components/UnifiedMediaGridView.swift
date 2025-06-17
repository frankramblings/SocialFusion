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
            if let selected = selection.selectedAttachment {
                FullscreenMediaView(media: selected, allMedia: attachments)
            } else {
                Color.black  // fallback
            }
        }
    }
}

private struct SingleImageView: View {
    let attachment: Post.Attachment
    let onTap: () -> Void

    // Capture stable URL at init time
    private let stableURL: URL?

    init(attachment: Post.Attachment, onTap: @escaping () -> Void) {
        self.attachment = attachment
        self.onTap = onTap
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
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 500)
                        .clipped()
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
            .cornerRadius(12)
            .clipped()
            .onTapGesture {
                onTap()
            }

            if let alt = attachment.altText, !alt.isEmpty {
                GlassyAltBadge()
                    .padding(.bottom, 8)
                    .padding(.trailing, 8)
            }
        }
    }
}

private struct MultiImageGridView: View {
    let attachments: [Post.Attachment]
    let onTap: (Post.Attachment) -> Void
    var extraCount: Int = 0
    private let gridSize: CGFloat = 150
    private let spacing: CGFloat = 6

    @State private var currentIndex: Int = 0

    var body: some View {
        VStack(spacing: 8) {
            // Swipeable TabView for media navigation
            TabView(selection: $currentIndex) {
                ForEach(0..<attachmentPages.count, id: \.self) { pageIndex in
                    HStack {
                        Spacer()
                        // Single image per page for swiping
                        let attachment = attachmentPages[pageIndex][0]
                        GridImageView(
                            attachment: attachment,
                            gridSize: gridSize * 1.8,  // Make swipeable images larger
                            onTap: onTap,
                            extraCount: extraCount,
                            isLast: attachment.id == attachments.last?.id)
                        Spacer()
                    }
                    .contentShape(Rectangle())  // Make entire page area respond to gestures
                    .tag(pageIndex)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .frame(height: gridSize * 1.8)

            // Custom page indicators (only show if multiple images)
            if attachments.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<attachments.count, id: \.self) { index in
                        Circle()
                            .fill(
                                index == currentIndex
                                    ? Color.primary : Color.secondary.opacity(0.3)
                            )
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // Split attachments into pages (1 image per page for swiping)
    private var attachmentPages: [[Post.Attachment]] {
        // Create individual pages for each image to enable swiping
        return attachments.map { [$0] }
    }
}

private struct GridImageView: View {
    let attachment: Post.Attachment
    let gridSize: CGFloat
    let onTap: (Post.Attachment) -> Void
    let extraCount: Int
    let isLast: Bool

    // Capture stable URL at init time
    private let stableURL: URL?

    init(
        attachment: Post.Attachment, gridSize: CGFloat, onTap: @escaping (Post.Attachment) -> Void,
        extraCount: Int, isLast: Bool
    ) {
        self.attachment = attachment
        self.gridSize = gridSize
        self.onTap = onTap
        self.extraCount = extraCount
        self.isLast = isLast
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
                        .clipped()
                case .failure(_):
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: gridSize, height: gridSize)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        )
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.08))
                        .frame(width: gridSize, height: gridSize)
                        .overlay(
                            ProgressView()
                                .scaleEffect(1.0)
                        )
                @unknown default:
                    EmptyView()
                }
            }
            .cornerRadius(12)
            .clipped()
            .onTapGesture {
                onTap(attachment)
            }

            if let alt = attachment.altText, !alt.isEmpty {
                GlassyAltBadge()
                    .padding(.bottom, 4)
                    .padding(.trailing, 4)
            }

            // Show "+X more" overlay on the last item if there are extra items
            if extraCount > 0 && isLast {
                Rectangle()
                    .fill(Color.black.opacity(0.7))
                    .frame(width: gridSize, height: gridSize)
                    .cornerRadius(12)
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

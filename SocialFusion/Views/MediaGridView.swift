import AVKit
import SwiftUI

// Media Grid View for displaying multiple attachments in a grid layout
struct MediaGridView: View {
    let attachments: [Post.Attachment]
    let onTapAttachment: (Post.Attachment) -> Void
    // Allow explicit height control with a default
    var maxHeight: CGFloat = 240

    var body: some View {
        VStack(spacing: 8) {
            // Different layouts based on the number of attachments
            if attachments.count == 1 {
                // Single attachment - full width
                MediaView(
                    attachment: attachments[0],
                    showFullscreen: { onTapAttachment(attachments[0]) },
                    maxHeight: min(maxHeight, 220)  // Limit single image height
                )
                .clipped()  // Ensure image doesn't overflow bounds
            } else if attachments.count == 2 {
                // Two attachments - side by side
                HStack(spacing: 4) {
                    MediaView(
                        attachment: attachments[0],
                        showFullscreen: { onTapAttachment(attachments[0]) },
                        maxHeight: maxHeight
                    )
                    .frame(maxWidth: .infinity)
                    .clipped()

                    MediaView(
                        attachment: attachments[1],
                        showFullscreen: { onTapAttachment(attachments[1]) },
                        maxHeight: maxHeight
                    )
                    .frame(maxWidth: .infinity)
                    .clipped()
                }
                .frame(height: min(maxHeight, 180))  // Set explicit height for row
            } else if attachments.count == 3 {
                // Three attachments - one on left, two stacked on right
                HStack(spacing: 4) {
                    // First image takes left half
                    MediaView(
                        attachment: attachments[0],
                        showFullscreen: { onTapAttachment(attachments[0]) },
                        maxHeight: maxHeight
                    )
                    .frame(maxWidth: .infinity)
                    .clipped()

                    // Second and third stacked on right half
                    VStack(spacing: 4) {
                        MediaView(
                            attachment: attachments[1],
                            showFullscreen: { onTapAttachment(attachments[1]) },
                            maxHeight: (maxHeight / 2) - 2  // Account for spacing
                        )
                        .frame(maxWidth: .infinity)
                        .clipped()

                        MediaView(
                            attachment: attachments[2],
                            showFullscreen: { onTapAttachment(attachments[2]) },
                            maxHeight: (maxHeight / 2) - 2  // Account for spacing
                        )
                        .frame(maxWidth: .infinity)
                        .clipped()
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: min(maxHeight, 180))  // Set explicit height for row
            } else if attachments.count >= 4 {
                // Four or more attachments - 2x2 grid with "more" indicator if needed
                VStack(spacing: 4) {
                    // Top row - 2 images
                    HStack(spacing: 4) {
                        MediaView(
                            attachment: attachments[0],
                            showFullscreen: { onTapAttachment(attachments[0]) },
                            maxHeight: (maxHeight / 2) - 2  // Account for spacing
                        )
                        .frame(maxWidth: .infinity, maxHeight: (maxHeight / 2) - 2)
                        .clipped()

                        MediaView(
                            attachment: attachments[1],
                            showFullscreen: { onTapAttachment(attachments[1]) },
                            maxHeight: (maxHeight / 2) - 2  // Account for spacing
                        )
                        .frame(maxWidth: .infinity, maxHeight: (maxHeight / 2) - 2)
                        .clipped()
                    }
                    .frame(height: (maxHeight / 2) - 2)

                    // Bottom row - 2 images
                    HStack(spacing: 4) {
                        // Third image
                        MediaView(
                            attachment: attachments[2],
                            showFullscreen: { onTapAttachment(attachments[2]) },
                            maxHeight: (maxHeight / 2) - 2  // Account for spacing
                        )
                        .frame(maxWidth: .infinity, maxHeight: (maxHeight / 2) - 2)
                        .clipped()

                        // Fourth image with counter if there are more
                        if attachments.count > 4 {
                            ZStack {
                                MediaView(
                                    attachment: attachments[3],
                                    showFullscreen: { onTapAttachment(attachments[3]) },
                                    maxHeight: (maxHeight / 2) - 2  // Account for spacing
                                )
                                .frame(maxWidth: .infinity, maxHeight: (maxHeight / 2) - 2)
                                .clipped()

                                // Overlay with count of additional images
                                Rectangle()
                                    .fill(Color.black.opacity(0.6))

                                Text("+\(attachments.count - 4)")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .cornerRadius(12)
                            .frame(maxWidth: .infinity, maxHeight: (maxHeight / 2) - 2)
                            .onTapGesture {
                                onTapAttachment(attachments[3])
                            }
                        } else {
                            // Just the fourth image if there are exactly 4
                            MediaView(
                                attachment: attachments[3],
                                showFullscreen: { onTapAttachment(attachments[3]) },
                                maxHeight: (maxHeight / 2) - 2  // Account for spacing
                            )
                            .frame(maxWidth: .infinity, maxHeight: (maxHeight / 2) - 2)
                            .clipped()
                        }
                    }
                    .frame(height: (maxHeight / 2) - 2)
                }
                .frame(height: maxHeight)  // Set explicit height for the entire grid
            }
        }
        .cornerRadius(10)  // Reduced corner radius for better visual harmony
        .frame(maxHeight: maxHeight)  // Explicitly set max height for the whole grid
    }
}

// Media view for individual attachments
struct MediaView: View {
    let attachment: Post.Attachment
    let showFullscreen: () -> Void
    // Add max height parameter with default value
    var maxHeight: CGFloat = 240

    @State private var aspectRatio: CGFloat = 16 / 9  // Default aspect ratio
    @State private var isLoading: Bool = true
    @State private var loadError: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if attachment.type == .image {
                    AsyncImage(url: URL(string: attachment.url)) { phase in
                        switch phase {
                        case .empty:
                            // Loading state
                            Rectangle()
                                .fill(Color(UIColor.secondarySystemBackground))
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(1.2)
                                )

                        case .success(let image):
                            // Success state
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .onAppear {
                                    // Calculate aspect ratio asynchronously
                                    if let url = URL(string: attachment.url) {
                                        Task {
                                            do {
                                                let (data, _) = try await URLSession.shared.data(
                                                    from: url)
                                                if let uiImage = UIImage(data: data) {
                                                    DispatchQueue.main.async {
                                                        let imageSize = uiImage.size
                                                        // Ensure we never set a NaN or invalid aspect ratio
                                                        if imageSize.width > 0
                                                            && imageSize.height > 0
                                                            && imageSize.width.isFinite
                                                            && imageSize.height.isFinite
                                                        {
                                                            withAnimation(.easeInOut(duration: 0.2))
                                                            {
                                                                aspectRatio =
                                                                    imageSize.width
                                                                    / imageSize.height
                                                                isLoading = false
                                                            }
                                                        }
                                                    }
                                                }
                                            } catch {
                                                print("Error loading image dimensions: \(error)")
                                                DispatchQueue.main.async {
                                                    loadError = true
                                                    isLoading = false
                                                }
                                            }
                                        }
                                    }
                                }

                        case .failure(_):
                            // Error state
                            Rectangle()
                                .fill(Color(UIColor.secondarySystemBackground))
                                .overlay(
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo")
                                            .font(.system(size: 30))
                                            .foregroundColor(.gray)
                                        Text("Image unavailable")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                )
                                .onAppear {
                                    loadError = true
                                    isLoading = false
                                }

                        @unknown default:
                            Rectangle()
                                .fill(Color(UIColor.secondarySystemBackground))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())

                } else if attachment.type == .video {
                    ZStack {
                        if let url = URL(string: attachment.url) {
                            VideoPlayer(player: AVPlayer(url: url))
                                .cornerRadius(12)
                                .onAppear {
                                    isLoading = false
                                }
                        } else {
                            Rectangle()
                                .fill(Color(UIColor.secondarySystemBackground))
                                .overlay(
                                    VStack(spacing: 8) {
                                        Image(systemName: "video.slash")
                                            .font(.system(size: 30))
                                            .foregroundColor(.gray)
                                        Text("Video unavailable")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                )
                                .cornerRadius(12)
                                .onAppear {
                                    loadError = true
                                    isLoading = false
                                }
                        }

                        // Play button overlay for videos
                        if !loadError {
                            Image(systemName: "play.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 0)
                                .opacity(isLoading ? 0 : 0.8)
                        }
                    }
                }

                // Alt text indicator if available
                if let altText = attachment.altText, !altText.isEmpty {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "text.bubble")
                                .font(.caption)
                                .padding(6)
                                .background(Color.black.opacity(0.6))
                                .foregroundColor(.white)
                                .clipShape(Circle())
                                .padding(8)
                        }
                    }
                }

                // Transparent overlay for tap handling
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showFullscreen()
                    }
            }
            .frame(
                width: geometry.size.width,
                height: min(calculateHeight(width: geometry.size.width), maxHeight)
            )
        }
        .frame(height: min(calculateHeight(width: UIScreen.main.bounds.width - 32), maxHeight))
    }

    // Calculate appropriate height based on aspect ratio with min/max constraints
    private func calculateHeight(width: CGFloat) -> CGFloat {
        let calculatedHeight = width / max(aspectRatio, 0.1)
        // Apply reasonable min/max constraints - reduced min height
        return min(max(calculatedHeight, 90), maxHeight)
    }
}

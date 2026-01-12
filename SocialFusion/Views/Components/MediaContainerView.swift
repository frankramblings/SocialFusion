import SwiftUI

/// Container view for media with fixed aspect ratio to prevent reflow
/// Height is computed from width and aspect ratio, never from image size
struct MediaContainerView: View {
  let attachment: Post.Attachment
  let aspectRatio: CGFloat?
  let maxHeight: CGFloat
  let cornerRadius: CGFloat
  let onTap: () -> Void
  
  @State private var containerWidth: CGFloat = 0
  
  init(
    attachment: Post.Attachment,
    aspectRatio: CGFloat?,
    maxHeight: CGFloat = 600,
    cornerRadius: CGFloat = 8,
    onTap: @escaping () -> Void = {}
  ) {
    self.attachment = attachment
    self.aspectRatio = aspectRatio
    self.maxHeight = maxHeight
    self.cornerRadius = cornerRadius
    self.onTap = onTap
  }
  
  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      let effectiveAspectRatio = aspectRatio ?? MediaBlockSnapshot.defaultAspectRatio
      let height = min(width / effectiveAspectRatio, maxHeight)
      
      ZStack {
        if aspectRatio != nil {
          // We have aspect ratio - show media
          SmartMediaView(
            attachment: attachment,
            contentMode: .fit,
            maxWidth: width,
            maxHeight: height,
            cornerRadius: cornerRadius,
            heroID: "media-\(attachment.id)",
            mediaNamespace: Namespace().wrappedValue,  // Note: For single image, namespace may not be needed
            onTap: onTap
          )
          .frame(width: width, height: height)
        } else {
          // No aspect ratio - show placeholder with fixed height
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.gray.opacity(0.1))
            .frame(width: width, height: MediaBlockSnapshot.placeholderHeight)
            .overlay(
              ProgressView()
                .scaleEffect(0.8)
            )
        }
      }
      .onAppear {
        containerWidth = width
      }
      .onChange(of: width) { newWidth in
        containerWidth = newWidth
      }
    }
    .frame(height: aspectRatio != nil ? nil : MediaBlockSnapshot.placeholderHeight)
    .aspectRatio(aspectRatio, contentMode: .fit)
    .clipped()
  }
}

/// Grid container for multiple media items with stable layout
struct MediaGridContainerView: View {
  let attachments: [Post.Attachment]
  let mediaBlocks: [MediaBlockSnapshot]
  let maxHeight: CGFloat
  let onMediaTap: (Post.Attachment) -> Void
  
  @EnvironmentObject private var mediaCoordinator: FullscreenMediaCoordinator
  @Namespace private var mediaNamespace
  
  var body: some View {
    Group {
      switch attachments.count {
      case 0:
        EmptyView()
      case 1:
        if let block = mediaBlocks.first {
          MediaContainerView(
            attachment: attachments[0],
            aspectRatio: block.aspectRatio,
            maxHeight: maxHeight,
            onTap: {
              mediaCoordinator.present(
                media: attachments[0],
                allMedia: attachments,
                showAltTextInitially: false,
                mediaNamespace: mediaNamespace,
                thumbnailFrames: [:]
              )
            }
          )
        }
      case 2...4:
        // Multi-image grid with stable heights
        MultiImageStableGrid(
          attachments: attachments,
          mediaBlocks: mediaBlocks,
          mediaNamespace: mediaNamespace,
          isFullscreenPresented: mediaCoordinator.showFullscreen,
          selectedAttachmentID: mediaCoordinator.selectedMedia?.id,
          onTap: { att in
            mediaCoordinator.present(
              media: att,
              allMedia: attachments,
              showAltTextInitially: false,
              mediaNamespace: mediaNamespace,
              thumbnailFrames: [:]
            )
          }
        )
      default:
        MultiImageStableGrid(
          attachments: Array(attachments.prefix(4)),
          mediaBlocks: Array(mediaBlocks.prefix(4)),
          mediaNamespace: mediaNamespace,
          isFullscreenPresented: mediaCoordinator.showFullscreen,
          selectedAttachmentID: mediaCoordinator.selectedMedia?.id,
          onTap: { att in
            mediaCoordinator.present(
              media: att,
              allMedia: attachments,
              showAltTextInitially: false,
              mediaNamespace: mediaNamespace,
              thumbnailFrames: [:]
            )
          },
          extraCount: attachments.count - 4
        )
      }
    }
  }
}

/// Stable multi-image grid that doesn't reflow
private struct MultiImageStableGrid: View {
  let attachments: [Post.Attachment]
  let mediaBlocks: [MediaBlockSnapshot]
  let mediaNamespace: Namespace.ID
  let isFullscreenPresented: Bool
  let selectedAttachmentID: String?
  let onTap: (Post.Attachment) -> Void
  var extraCount: Int = 0
  
  private let gridSize: CGFloat = 150
  private let spacing: CGFloat = 4
  
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
          if index < mediaBlocks.count {
            let block = mediaBlocks[index]
            StableGridImageView(
              attachment: attachment,
              aspectRatio: block.aspectRatio,
              gridSize: gridSize,
              mediaNamespace: mediaNamespace,
              isFullscreenPresented: isFullscreenPresented,
              selectedAttachmentID: selectedAttachmentID,
              onTap: onTap,
              extraCount: extraCount,
              isLast: attachment.id == attachments.last?.id
            )
          }
        }
      }
      .frame(maxWidth: gridSize * 2 + spacing)
      
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }
}

/// Stable grid image view with fixed size
private struct StableGridImageView: View {
  let attachment: Post.Attachment
  let aspectRatio: CGFloat?
  let gridSize: CGFloat
  let mediaNamespace: Namespace.ID
  let isFullscreenPresented: Bool
  let selectedAttachmentID: String?
  let onTap: (Post.Attachment) -> Void
  let extraCount: Int
  let isLast: Bool
  
  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      if aspectRatio != nil {
        SmartMediaView(
          attachment: attachment,
          contentMode: .fill,
          maxWidth: gridSize,
          maxHeight: gridSize,
          cornerRadius: 8,
          heroID: "media-\(attachment.id)",
          mediaNamespace: mediaNamespace,
          onTap: { onTap(attachment) }
        )
        .frame(width: gridSize, height: gridSize)
        .clipped()
      } else {
        // Placeholder
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.gray.opacity(0.1))
          .frame(width: gridSize, height: gridSize)
          .overlay(ProgressView().scaleEffect(0.8))
      }
      
      if let alt = attachment.altText, !alt.isEmpty {
        AltTextBadge()
          .padding(4)
          .onTapGesture {
            // Handle alt text tap
          }
      }
      
      if extraCount > 0 && isLast {
        Rectangle()
          .fill(Color.black.opacity(0.7))
          .frame(width: gridSize, height: gridSize)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

/// Helper badge for alt text indication
private struct AltTextBadge: View {
  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: "text.bubble.fill")
        .font(.system(size: 11, weight: .semibold))
      Text("ALT")
        .font(.system(size: 12, weight: .semibold))
    }
    .foregroundColor(.white)
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(
      Capsule()
        .fill(Color.black.opacity(0.3))
        .overlay(
          Capsule()
            .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
        )
    )
    .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 1.5)
    .environment(\.colorScheme, .dark)
  }
}

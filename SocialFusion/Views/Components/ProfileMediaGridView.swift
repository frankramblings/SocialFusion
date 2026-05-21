import SwiftUI

/// A 3-column grid of media thumbnails for the profile Media tab.
/// Displays the first visual attachment from each post that contains media,
/// with a small badge in the corner indicating multi-image posts and a play
/// indicator on video thumbnails — same convention Instagram and the
/// official Bluesky/Mastodon apps use.
struct ProfileMediaGridView: View {
  let posts: [Post]
  var onPostTap: ((Post) -> Void)?

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

  var body: some View {
    LazyVGrid(columns: columns, spacing: 2) {
      ForEach(mediaPosts) { post in
        if let firstMedia = post.attachments.first(where: { $0.type != .audio }) {
          MediaGridCell(
            post: post,
            firstMedia: firstMedia,
            additionalCount: max(0, post.attachments.filter { $0.type != .audio }.count - 1),
            onTap: { onPostTap?(post) }
          )
        }
      }
    }
  }

  /// Posts that contain at least one visual (non-audio) attachment.
  private var mediaPosts: [Post] {
    posts.filter { post in
      post.attachments.contains { $0.type != .audio }
    }
  }
}

/// A single tappable thumbnail in the media grid.
private struct MediaGridCell: View {
  let post: Post
  let firstMedia: Post.Attachment
  let additionalCount: Int
  let onTap: () -> Void

  @State private var isPressed = false

  var body: some View {
    Button {
      HapticEngine.tap.trigger()
      onTap()
    } label: {
      ZStack {
        mediaThumbnail(for: firstMedia)
          .aspectRatio(1, contentMode: .fill)
          .clipped()

        // Bottom gradient for legibility of corner indicators
        if hasOverlayContent {
          LinearGradient(
            colors: [
              Color.clear,
              Color.black.opacity(0.35),
            ],
            startPoint: .center,
            endPoint: .bottom
          )
        }

        // Corner indicators
        VStack {
          HStack {
            Spacer()
            if additionalCount > 0 {
              indicatorPill(systemName: "square.on.square.fill", text: "+\(additionalCount)")
            }
          }
          Spacer()
          HStack {
            if firstMedia.type == .video {
              indicatorPill(systemName: "play.fill", text: nil)
            } else if firstMedia.type == .gifv || firstMedia.type == .animatedGIF {
              indicatorPill(systemName: "play.rectangle.fill", text: "GIF")
            }
            Spacer()
          }
        }
        .padding(6)
      }
      .contentShape(Rectangle())
      .scaleEffect(isPressed ? 0.96 : 1.0)
      .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.78), value: isPressed)
    }
    .buttonStyle(.plain)
    .onLongPressGesture(
      minimumDuration: 0, maximumDistance: .infinity,
      pressing: { pressing in isPressed = pressing },
      perform: {}
    )
    .accessibilityLabel(accessibilityLabel)
  }

  private var hasOverlayContent: Bool {
    additionalCount > 0
      || firstMedia.type == .video
      || firstMedia.type == .gifv
      || firstMedia.type == .animatedGIF
  }

  private var accessibilityLabel: String {
    var parts: [String] = []
    switch firstMedia.type {
    case .video: parts.append("Video")
    case .gifv, .animatedGIF: parts.append("Animated image")
    case .image: parts.append("Photo")
    case .audio: parts.append("Audio")
    }
    if additionalCount > 0 {
      parts.append("\(additionalCount + 1) items")
    }
    if let alt = firstMedia.altText, !alt.isEmpty {
      parts.append(alt)
    }
    return parts.joined(separator: ", ")
  }

  /// A compact pill in the corner — semi-transparent black background that
  /// reads on any thumbnail, white symbol/text for contrast.
  private func indicatorPill(systemName: String, text: String?) -> some View {
    HStack(spacing: 3) {
      Image(systemName: systemName)
        .font(.system(size: 10, weight: .bold))
      if let text {
        Text(text)
          .font(.caption2.weight(.semibold))
      }
    }
    .foregroundColor(.white)
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .background(
      Capsule()
        .fill(Color.black.opacity(0.55))
    )
  }

  /// Renders a square thumbnail for a given attachment, preferring the thumbnail URL.
  @ViewBuilder
  private func mediaThumbnail(for attachment: Post.Attachment) -> some View {
    let urlString = attachment.thumbnailURL ?? attachment.url
    if let url = URL(string: urlString) {
      AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        case .failure:
          placeholderView(systemName: iconName(for: attachment.type))
        default:
          // systemGray6 adapts to light/dark; Color.gray.opacity
          // shifts brown against dark backgrounds.
          Rectangle()
            .fill(Color(.systemGray6))
        }
      }
    } else {
      placeholderView(systemName: iconName(for: attachment.type))
    }
  }

  private func placeholderView(systemName: String) -> some View {
    Rectangle()
      .fill(Color(.systemGray5))
      .overlay(
        Image(systemName: systemName)
          .foregroundStyle(.secondary)
      )
  }

  private func iconName(for type: Post.Attachment.AttachmentType) -> String {
    switch type {
    case .video: return "video.fill"
    case .gifv, .animatedGIF: return "play.rectangle.fill"
    case .image: return "photo"
    case .audio: return "waveform"
    }
  }
}

#Preview {
  ProfileMediaGridView(posts: [])
}

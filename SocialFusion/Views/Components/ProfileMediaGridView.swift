import SwiftUI

/// A 3-column grid of media thumbnails for the profile Media tab.
/// Displays the first visual attachment from each post that contains media.
struct ProfileMediaGridView: View {
  let posts: [Post]
  var onPostTap: ((Post) -> Void)?

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

  var body: some View {
    LazyVGrid(columns: columns, spacing: 2) {
      ForEach(mediaPosts) { post in
        if let firstMedia = post.attachments.first(where: { $0.type != .audio }) {
          Button {
            HapticEngine.tap.trigger()
            onPostTap?(post)
          } label: {
            mediaThumbnail(for: firstMedia)
              .aspectRatio(1, contentMode: .fill)
              .clipped()
          }
          .accessibilityLabel(accessibilityLabel(for: firstMedia, post: post))
          .accessibilityHint("Opens the post.")
        }
      }
    }
  }

  /// Composed label: alt text when available (most informative), media-type
  /// fallback otherwise. Includes the post excerpt so VoiceOver users get
  /// context for the visual content they can't see.
  private func accessibilityLabel(for attachment: Post.Attachment, post: Post) -> String {
    var parts: [String] = []
    if let alt = attachment.altText, !alt.isEmpty {
      parts.append(alt)
    } else {
      switch attachment.type {
      case .video:                    parts.append("Video")
      case .gifv, .animatedGIF:       parts.append("Animated image")
      case .image:                    parts.append("Image")
      case .audio:                    parts.append("Audio")
      }
    }
    // Strip HTML + entities so a Mastodon post's "<p>…</p>" wrapper
    // doesn't leak into the VoiceOver announcement. Same path used by
    // ReplyRow's accessibility label and the canonical post-body
    // renderers.
    let excerpt = post.content
      .strippingHTMLTags
      .decodingHTMLEntities
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !excerpt.isEmpty {
      parts.append("from post: \"\(excerpt.prefix(100))\"")
    }
    return parts.joined(separator: ", ")
  }

  // MARK: - Helpers

  /// Posts that contain at least one visual (non-audio) attachment.
  private var mediaPosts: [Post] {
    posts.filter { post in
      post.attachments.contains { $0.type != .audio }
    }
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
          Rectangle()
            .fill(Color.gray.opacity(0.1))
        }
      }
    } else {
      placeholderView(systemName: iconName(for: attachment.type))
    }
  }

  /// A placeholder rectangle with a centered SF Symbol icon.
  private func placeholderView(systemName: String) -> some View {
    Rectangle()
      .fill(Color.gray.opacity(0.2))
      .overlay(
        Image(systemName: systemName)
          .foregroundStyle(.secondary)
      )
  }

  /// Returns an appropriate SF Symbol name for the attachment type.
  private func iconName(for type: Post.Attachment.AttachmentType) -> String {
    switch type {
    case .video:
      return "video.fill"
    case .gifv, .animatedGIF:
      return "play.rectangle.fill"
    case .image:
      return "photo"
    case .audio:
      return "waveform"
    }
  }
}

#Preview {
  ProfileMediaGridView(posts: [])
}

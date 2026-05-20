import SwiftUI

/// Row view for displaying a tag in search results. The hashtag glyph is
/// tinted to give it presence, and the usage count is surfaced when available
/// so the row tells a small story.
struct SearchTagRow: View {
  let tag: SearchTag
  let onTap: () -> Void

  var body: some View {
    Button {
      HapticEngine.tap.trigger()
      onTap()
    } label: {
      HStack(spacing: 14) {
        // Tinted hashtag badge — gives the row a visual anchor
        ZStack {
          Circle()
            .fill(Color.accentColor.opacity(0.12))
            .frame(width: 40, height: 40)

          Image(systemName: "number")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.accentColor)
        }

        VStack(alignment: .leading, spacing: 2) {
          Text("#\(tag.name)")
            .font(.headline)
            .foregroundColor(.primary)
            .lineLimit(1)

          if let formatted = tag.formattedUsageCount {
            Text("\(formatted) post\(formatted == "1" ? "" : "s")")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }

        Spacer()

        // Platform indicator
        PlatformIndicator(platform: tag.platform)
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 16)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(searchTagAccessibilityLabel)
  }

  /// VoiceOver label: 'Hashtag <name>' plus an optional post-count
  /// suffix that uses the singular form for exactly one post.
  /// Without this, '1 post' would read as '1 posts' for solo-post tags.
  private var searchTagAccessibilityLabel: String {
    var label = "Hashtag \(tag.name)"
    if let count = tag.usageCount, count > 0 {
      let displayed = tag.formattedUsageCount ?? "\(count)"
      label += ", \(displayed) post\(count == 1 ? "" : "s")"
    }
    return label
  }
}

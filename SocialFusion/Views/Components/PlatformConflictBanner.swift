import SwiftUI

/// Shows warnings when features don't map cleanly across platforms.
struct PlatformConflictBanner: View {
  let conflicts: [PlatformConflict]
  let onTap: () -> Void

  var body: some View {
    if !conflicts.isEmpty {
      Button {
        HapticEngine.tap.trigger()
        onTap()
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(Color.orange.gradient)
            .font(.caption.weight(.semibold))
            .symbolRenderingMode(.hierarchical)

          VStack(alignment: .leading, spacing: 2) {
            Text(conflicts.first?.message ?? "Some features may not apply to all platforms")
              .font(.caption.weight(.medium))
              .foregroundColor(.primary)
              .lineLimit(2)

            if conflicts.count > 1 {
              Text("\(conflicts.count - 1) more — tap for details")
                .font(.caption2)
                .foregroundColor(.secondary)
            }
          }

          Spacer(minLength: 4)

          if conflicts.count > 1 {
            Image(systemName: "chevron.right")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.tertiary)
              .accessibilityHidden(true)
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.orange.opacity(0.10))
            .overlay(
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.22), lineWidth: 0.5)
            )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
      .buttonStyle(.plain)
      .accessibilityHint(conflicts.count > 1 ? "Double tap to see all conflicts" : "")
    }
  }
}

/// Represents a platform conflict
struct PlatformConflict: Identifiable {
  let id = UUID()
  let feature: String
  let platforms: [SocialPlatform]
  
  var message: String {
    let platformNames = platforms.map { $0.rawValue.capitalized }.joined(separator: ", ")
    return "\(feature) will not apply to: \(platformNames)"
  }
}

import SwiftUI

/// Badge component showing "Follows you" or "Mutuals" indicator.
/// "Mutuals" gets a subtle accent tint — a quiet acknowledgement that the
/// relationship goes both ways. "Follows you" stays neutral.
struct FollowsYouBadge: View {
  let isMutual: Bool
  let isFollowedBy: Bool

  var body: some View {
    Group {
      if isMutual {
        badge(
          symbol: "person.2.fill",
          text: "Mutuals",
          tint: Color.accentColor,
          isTinted: true
        )
      } else if isFollowedBy {
        badge(
          symbol: nil,
          text: "Follows you",
          tint: .secondary,
          isTinted: false
        )
      }
    }
  }

  @ViewBuilder
  private func badge(symbol: String?, text: String, tint: Color, isTinted: Bool) -> some View {
    HStack(spacing: 4) {
      if let symbol {
        Image(systemName: symbol)
          .font(.system(size: 9, weight: .semibold))
      }
      Text(text)
        .font(.caption)
        .fontWeight(.medium)
    }
    .foregroundColor(isTinted ? tint : .secondary)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
      Capsule()
        .fill(isTinted ? tint.opacity(0.12) : Color(.secondarySystemBackground))
        .overlay(
          Capsule()
            .strokeBorder(
              isTinted ? tint.opacity(0.22) : Color.clear,
              lineWidth: 0.5
            )
        )
    )
    .accessibilityLabel(text)
  }
}

#Preview {
  HStack(spacing: 12) {
    FollowsYouBadge(isMutual: false, isFollowedBy: true)
    FollowsYouBadge(isMutual: true, isFollowedBy: true)
  }
  .padding()
}

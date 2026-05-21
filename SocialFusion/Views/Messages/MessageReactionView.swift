import SwiftUI

struct MessageReaction: Identifiable {
  let emoji: String
  let senderIds: Set<String>
  var count: Int { senderIds.count }
  var id: String { emoji }

  func isFromMe(myIds: Set<String>) -> Bool {
    !senderIds.isDisjoint(with: myIds)
  }
}

struct MessageReactionView: View {
  let reactions: [MessageReaction]
  let platform: SocialPlatform
  let myAccountIds: Set<String>
  let onTap: (String, Bool) -> Void

  /// Brand-tinted color via SocialPlatform.swiftUIColor.
  private var platformColor: Color { platform.swiftUIColor }

  var body: some View {
    FlowLayout(spacing: 4) {
      ForEach(reactions) { reaction in
        let isFromMe = reaction.isFromMe(myIds: myAccountIds)
        ReactionPill(
          reaction: reaction,
          isFromMe: isFromMe,
          tint: platformColor,
          onTap: { onTap(reaction.emoji, isFromMe) }
        )
      }
    }
  }

  private func accessibilityLabel(for reaction: MessageReaction, isFromMe: Bool) -> String {
    let countPart = reaction.count == 1
      ? "\(reaction.emoji), 1 person"
      : "\(reaction.emoji), \(reaction.count) people"
    return isFromMe ? "\(countPart), including you" : countPart
  }
}

/// A single reaction pill that scales on press and updates its count smoothly.
private struct ReactionPill: View {
  let reaction: MessageReaction
  let isFromMe: Bool
  let tint: Color
  let onTap: () -> Void

  @State private var isPressed = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button {
      HapticEngine.selection.trigger()
      if !reduceMotion {
        // Brief bounce on tap to acknowledge the toggle
        withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
          isPressed = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
          withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            isPressed = false
          }
        }
      }
      onTap()
    } label: {
      HStack(spacing: 3) {
        Text(reaction.emoji)
          .font(.caption)
        if reaction.count > 1 {
          Text("\(reaction.count)")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundColor(isFromMe ? .white : .primary.opacity(0.75))
            .contentTransition(.numericText(value: Double(reaction.count)))
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.82), value: reaction.count)
        }
      }
      .padding(.horizontal, 7)
      .padding(.vertical, 4)
      .background(
        Capsule()
          .fill(isFromMe ? tint.opacity(0.85) : Color(.systemGray5))
      )
      .overlay(
        Capsule()
          .strokeBorder(
            isFromMe ? tint : Color.primary.opacity(0.05),
            lineWidth: isFromMe ? 1 : 0.5
          )
      )
      .scaleEffect(isPressed ? 1.12 : 1.0)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(reaction.emoji), \(reaction.count) reaction\(reaction.count == 1 ? "" : "s")\(isFromMe ? ", yours" : "")")
    .accessibilityHint(isFromMe ? "Removes your reaction" : "Adds your reaction")
    .accessibilityAddTraits(isFromMe ? .isSelected : [])
  }
}

struct FlowLayout: Layout {
  var spacing: CGFloat = 4

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let result = arrangeSubviews(in: proposal.width ?? 0, subviews: subviews)
    return result.size
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let result = arrangeSubviews(in: bounds.width, subviews: subviews)
    for (index, position) in result.positions.enumerated() {
      subviews[index].place(
        at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
        proposal: .unspecified
      )
    }
  }

  private struct LayoutResult {
    var positions: [CGPoint]
    var size: CGSize
  }

  private func arrangeSubviews(in maxWidth: CGFloat, subviews: Subviews) -> LayoutResult {
    var positions: [CGPoint] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var maxX: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x + size.width > maxWidth && x > 0 {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      positions.append(CGPoint(x: x, y: y))
      rowHeight = max(rowHeight, size.height)
      x += size.width + spacing
      maxX = max(maxX, x)
    }

    return LayoutResult(positions: positions, size: CGSize(width: maxX, height: y + rowHeight))
  }
}

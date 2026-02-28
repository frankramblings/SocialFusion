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

  private var platformColor: Color {
    platform == .bluesky ? .blue : .purple
  }

  var body: some View {
    FlowLayout(spacing: 4) {
      ForEach(reactions) { reaction in
        let isFromMe = reaction.isFromMe(myIds: myAccountIds)
        Button {
          onTap(reaction.emoji, isFromMe)
        } label: {
          HStack(spacing: 2) {
            Text(reaction.emoji)
              .font(.caption)
            if reaction.count > 1 {
              Text("\(reaction.count)")
                .font(.caption2)
                .foregroundColor(isFromMe ? .white : .primary)
            }
          }
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
          .background(
            Capsule()
              .fill(isFromMe ? platformColor.opacity(0.8) : Color(.systemGray5))
          )
          .overlay(
            Capsule()
              .stroke(isFromMe ? platformColor : Color.clear, lineWidth: 1)
          )
        }
        .buttonStyle(.plain)
      }
    }
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

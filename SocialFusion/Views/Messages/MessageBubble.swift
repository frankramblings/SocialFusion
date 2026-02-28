import SwiftUI

// MARK: - Bubble Shape

struct BubbleShape: Shape {
  let isFromMe: Bool
  let hasTail: Bool

  func path(in rect: CGRect) -> Path {
    let radius: CGFloat = 18
    let tailSize: CGFloat = 6

    var path = Path()

    if hasTail {
      if isFromMe {
        path.addRoundedRect(
          in: CGRect(x: rect.minX, y: rect.minY,
                     width: rect.width - tailSize, height: rect.height),
          cornerSize: CGSize(width: radius, height: radius)
        )
        let tailX = rect.maxX - tailSize
        let tailY = rect.maxY - radius
        path.move(to: CGPoint(x: tailX, y: tailY))
        path.addQuadCurve(
          to: CGPoint(x: rect.maxX, y: rect.maxY),
          control: CGPoint(x: tailX + tailSize * 0.5, y: rect.maxY)
        )
        path.addQuadCurve(
          to: CGPoint(x: tailX, y: rect.maxY),
          control: CGPoint(x: tailX, y: rect.maxY)
        )
      } else {
        path.addRoundedRect(
          in: CGRect(x: rect.minX + tailSize, y: rect.minY,
                     width: rect.width - tailSize, height: rect.height),
          cornerSize: CGSize(width: radius, height: radius)
        )
        let tailX = rect.minX + tailSize
        let tailY = rect.maxY - radius
        path.move(to: CGPoint(x: tailX, y: tailY))
        path.addQuadCurve(
          to: CGPoint(x: rect.minX, y: rect.maxY),
          control: CGPoint(x: tailX - tailSize * 0.5, y: rect.maxY)
        )
        path.addQuadCurve(
          to: CGPoint(x: tailX, y: rect.maxY),
          control: CGPoint(x: tailX, y: rect.maxY)
        )
      }
    } else {
      path.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius))
    }

    return path
  }
}

// MARK: - Message Bubble

struct MessageBubble: View {
  let message: UnifiedChatMessage
  let isFromMe: Bool
  let platform: SocialPlatform
  let isFirstInGroup: Bool
  let isLastInGroup: Bool
  let showAvatar: Bool
  let avatarURL: String?
  var showSeenIndicator: Bool = false

  private var bubbleColor: Color {
    if isFromMe {
      return platform == .bluesky ? .blue : .purple
    }
    return Color(.systemGray5)
  }

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      if !isFromMe {
        if showAvatar && isLastInGroup {
          asyncAvatar
        } else {
          Color.clear.frame(width: 28, height: 28)
        }
      }

      if isFromMe { Spacer(minLength: 60) }

      VStack(alignment: isFromMe ? .trailing : .leading, spacing: 2) {
        messageContent
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(bubbleColor)
          .foregroundColor(isFromMe ? .white : .primary)
          .clipShape(BubbleShape(isFromMe: isFromMe, hasTail: isLastInGroup))

        if isLastInGroup {
          HStack(spacing: 4) {
            Text(message.sentAt, style: .time)
              .font(.caption2)
              .foregroundColor(.secondary)
            if showSeenIndicator {
              Text("Seen")
                .font(.caption2)
                .foregroundColor(.secondary)
            }
          }
          .padding(.horizontal, 4)
        }
      }

      if !isFromMe { Spacer(minLength: 60) }
    }
  }

  @ViewBuilder
  private var messageContent: some View {
    if message.text.isEmpty || message.text == "(Empty message)" {
      Text("(Empty message)")
        .italic()
        .foregroundColor(isFromMe ? .white.opacity(0.7) : .secondary)
    } else {
      Text(message.text)
    }
  }

  @ViewBuilder
  private var asyncAvatar: some View {
    if let urlString = avatarURL, let url = URL(string: urlString) {
      CachedAsyncImage(url: url, priority: .low) { image in
        image.resizable().aspectRatio(contentMode: .fill)
      } placeholder: {
        Circle().fill(Color.gray.opacity(0.3))
      }
      .frame(width: 28, height: 28)
      .clipShape(Circle())
    } else {
      Circle().fill(Color.gray.opacity(0.3))
        .frame(width: 28, height: 28)
    }
  }
}

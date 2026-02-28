import SwiftUI
import UIKit

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
  var senderName: String?
  var showSeenIndicator: Bool = false
  var reactions: [MessageReaction] = []
  var myAccountIds: Set<String> = []
  var onReactionTap: ((String, Bool) -> Void)?
  var onReactionAdd: ((String) -> Void)?
  var onDelete: (() -> Void)?
  var onEdit: (() -> Void)?

  private static let quickReactions = ["\u{2764}\u{FE0F}", "\u{1F44D}", "\u{1F602}", "\u{1F62E}", "\u{1F622}", "\u{1F525}"]

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
        if let name = senderName, isFirstInGroup {
          Text(name)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
        }
        messageContent
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(bubbleColor)
          .foregroundColor(isFromMe ? .white : .primary)
          .clipShape(BubbleShape(isFromMe: isFromMe, hasTail: isLastInGroup))
          .contextMenu {
            if platform == .bluesky {
              Section("React") {
                ForEach(Self.quickReactions, id: \.self) { emoji in
                  Button {
                    onReactionAdd?(emoji)
                  } label: {
                    Text(emoji)
                  }
                }
              }
            }

            if isFromMe {
              if platform == .mastodon {
                Button {
                  onEdit?()
                } label: {
                  Label("Edit Message", systemImage: "pencil")
                }
              }
              Button(role: .destructive) {
                onDelete?()
              } label: {
                Label("Delete Message", systemImage: "trash")
              }
            }

            Button {
              UIPasteboard.general.string = message.text
            } label: {
              Label("Copy Text", systemImage: "doc.on.doc")
            }
          }

        if !reactions.isEmpty {
          MessageReactionView(
            reactions: reactions,
            platform: platform,
            myAccountIds: myAccountIds
          ) { emoji, isFromMe in
            onReactionTap?(emoji, isFromMe)
          }
          .frame(maxWidth: 200)
        }

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
    VStack(alignment: .leading, spacing: 6) {
      if message.hasMedia {
        mediaPreview
      }
      if message.text.isEmpty || message.text == "(Empty message)" {
        if !message.hasMedia {
          Text("(Empty message)")
            .italic()
            .foregroundColor(isFromMe ? .white.opacity(0.7) : .secondary)
        }
      } else {
        Text(message.text)
      }
    }
  }

  @ViewBuilder
  private var mediaPreview: some View {
    let attachments = message.mediaAttachments.filter { $0.type == .image || $0.type == .gifv }
    if attachments.count == 1, let attachment = attachments.first {
      singleMediaImage(attachment)
    } else if attachments.count > 1 {
      let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]
      LazyVGrid(columns: columns, spacing: 4) {
        ForEach(attachments.prefix(4)) { attachment in
          singleMediaImage(attachment)
        }
      }
    }
  }

  @ViewBuilder
  private func singleMediaImage(_ attachment: Post.Attachment) -> some View {
    let urlString = attachment.thumbnailURL ?? attachment.url
    if let url = URL(string: urlString) {
      CachedAsyncImage(url: url, priority: .normal) { image in
        image
          .resizable()
          .aspectRatio(contentMode: .fill)
      } placeholder: {
        RoundedRectangle(cornerRadius: 8)
          .fill(Color(.systemGray4))
          .overlay(ProgressView().scaleEffect(0.6))
      }
      .frame(maxWidth: 200)
      .frame(height: 150)
      .clipShape(RoundedRectangle(cornerRadius: 8))
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

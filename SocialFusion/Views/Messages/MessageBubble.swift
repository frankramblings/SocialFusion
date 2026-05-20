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

  @State private var hasAppeared = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Brand-tinted color for "from me" bubbles. Uses the same hex values as the
  /// rest of the app for visual consistency.
  private var brandColor: Color {
    switch platform {
    case .bluesky:
      return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
    case .mastodon:
      return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
    }
  }

  /// "From me" bubbles use a subtle gradient — slightly brighter at top, the
  /// brand color at bottom — for that iMessage-style sense of depth without
  /// stealing focus from the text.
  @ViewBuilder
  private var bubbleFill: some View {
    if isFromMe {
      LinearGradient(
        colors: [
          brandColor.opacity(0.96),
          brandColor,
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    } else {
      LinearGradient(
        colors: [
          Color(.systemGray5),
          Color(.systemGray5).opacity(0.92),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    }
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
          .background(bubbleFill)
          .foregroundColor(isFromMe ? .white : .primary)
          .clipShape(BubbleShape(isFromMe: isFromMe, hasTail: isLastInGroup))
          .scaleEffect(hasAppeared ? 1.0 : 0.92, anchor: isFromMe ? .bottomTrailing : .bottomLeading)
          .opacity(hasAppeared ? 1.0 : 0.0)
          .onAppear {
            if reduceMotion {
              hasAppeared = true
            } else {
              withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                hasAppeared = true
              }
            }
          }
          .contextMenu {
            if platform == .bluesky {
              Section("React") {
                ForEach(Self.quickReactions, id: \.self) { emoji in
                  Button {
                    HapticEngine.success.trigger()
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
                  HapticEngine.tap.trigger()
                  onEdit?()
                } label: {
                  Label("Edit Message", systemImage: "pencil")
                }
              }
              Button(role: .destructive) {
                HapticEngine.warning.trigger()
                onDelete?()
              } label: {
                Label("Delete Message", systemImage: "trash")
              }
            }

            Button {
              HapticEngine.tap.trigger()
              UIPasteboard.general.string = message.text
              ToastManager.shared.show("Message copied", severity: .success, duration: 1.4)
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
              // Separator dot + Seen — visually parses as two facts about
              // this bubble (when it was sent, that it was read), not one
              // mashed-together stamp.
              Text("\u{00B7}")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.5))
              HStack(spacing: 3) {
                Image(systemName: "checkmark")
                  .font(.system(size: 8, weight: .bold))
                  // One-shot bounce when the message first gets marked
                  // seen — a tiny acknowledgement that the recipient
                  // looked at it. iOS 17+ handles the gesture; on older
                  // OS the symbol just appears with the parent transition.
                  .modifier(SymbolBounceModifier(value: showSeenIndicator))
                Text("Seen")
                  .font(.caption2)
              }
              .foregroundColor(.secondary)
              .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
            }
          }
          .padding(.horizontal, 4)
          .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showSeenIndicator)
          .accessibilityElement(children: .combine)
          .accessibilityLabel(showSeenIndicator
            ? "Sent at \(message.sentAt.formatted(date: .omitted, time: .shortened)), read"
            : "Sent at \(message.sentAt.formatted(date: .omitted, time: .shortened))"
          )
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
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color(.systemGray4))
          .overlay(ProgressView().scaleEffect(0.6))
      }
      .frame(maxWidth: 200)
      .frame(height: 150)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
  }

  @ViewBuilder
  private var asyncAvatar: some View {
    let initial = senderName?.first.map { String($0) } ?? "?"
    if let urlString = avatarURL, let url = URL(string: urlString) {
      CachedAsyncImage(url: url, priority: .low) { image in
        image.resizable().aspectRatio(contentMode: .fill)
      } placeholder: {
        initialPlaceholder(initial)
      }
      .frame(width: 28, height: 28)
      .clipShape(Circle())
    } else {
      initialPlaceholder(initial)
        .frame(width: 28, height: 28)
    }
  }

  /// Initials-fallback avatar for chats — circle with the first letter
  /// of the sender's name. Matches the pattern used in DMConversationRow
  /// and NewConversationView so every message-related avatar reads with
  /// a consistent identity affordance.
  private func initialPlaceholder(_ letter: String) -> some View {
    Circle()
      .fill(Color(.systemGray5))
      .overlay(
        Text(letter.uppercased())
          .font(.caption.weight(.semibold))
          .foregroundColor(Color(.systemGray))
      )
  }
}

/// Applies a one-shot SF Symbol bounce when `value` changes (iOS 17+).
/// On older OS versions, the modifier is a no-op and the existing
/// transition handles the visual.
private struct SymbolBounceModifier<V: Equatable>: ViewModifier {
  let value: V

  func body(content: Content) -> some View {
    if #available(iOS 17.0, *) {
      content.symbolEffect(.bounce, value: value)
    } else {
      content
    }
  }
}

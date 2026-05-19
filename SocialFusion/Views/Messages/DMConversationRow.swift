import SwiftUI

struct DMConversationRow: View {
  let conversation: DMConversation

  var body: some View {
    HStack(spacing: 12) {
      avatarView

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          if conversation.isGroup, let title = conversation.title {
            Text(title)
              .font(.headline)
              .fontWeight(.semibold)
              .foregroundColor(.primary)
              .lineLimit(1)
          } else {
            EmojiDisplayNameText(
              conversation.participant.displayName ?? conversation.participant.username,
              emojiMap: conversation.participant.displayNameEmojiMap,
              font: .headline,
              fontWeight: .semibold,
              foregroundColor: .primary,
              lineLimit: 1
            )
          }

          Spacer()

          PostPlatformBadge(platform: conversation.platform)
            .scaleEffect(0.85)
        }

        HStack(spacing: 4) {
          if conversation.isGroup {
            Text("\(conversation.participants.count) members")
              .font(.subheadline)
              .foregroundColor(.secondary)
              .lineLimit(1)
          } else {
            Text("@\(conversation.participant.username)")
              .font(.subheadline)
              .foregroundColor(.secondary)
              .lineLimit(1)
          }

          Text("\u{00B7}")
            .font(.subheadline)
            .foregroundColor(.secondary)

          Text(conversation.lastMessage.createdAt, style: .relative)
            .font(.subheadline)
            .foregroundColor(.secondary)

          if conversation.isMuted {
            Image(systemName: "speaker.slash.fill")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }

        HStack {
          if conversation.isGroup {
            // Decode entities in the sender chunk — Mastodon DMs may
            // pre-pend a display name with raw HTML entities. The
            // content body already arrives plain-text from the
            // MastodonService DM normalizer (HTMLString.plainText),
            // so only the prefixed name needs the decode pass.
            let senderName = (conversation.lastMessage.sender.displayName
                              ?? conversation.lastMessage.sender.username).decodingHTMLEntities
            Text("\(senderName): \(conversation.lastMessage.content)")
              .font(.subheadline)
              .foregroundColor(.secondary)
              .lineLimit(2)
          } else {
            Text(conversation.lastMessage.content)
              .font(.subheadline)
              .foregroundColor(.secondary)
              .lineLimit(2)
          }

          Spacer()

          if conversation.unreadCount > 0 {
            Circle()
              .fill(Color.blue)
              .frame(width: 10, height: 10)
          }
        }
      }
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(combinedLabel)
  }

  /// Combined VoiceOver label so a conversation row reads as one chunk:
  /// "Group: Foo, 5 members, last message Bar said 'hi', 2 minutes ago,
  ///  3 unread, on Mastodon".
  /// Without this, the row fragmented into 6-8 sub-elements per row in
  /// a list with many conversations.
  private var combinedLabel: String {
    var parts: [String] = []
    if conversation.isGroup, let title = conversation.title {
      // Title is built from participant displayNames; decode at the
      // VoiceOver boundary so it doesn't read entities verbatim.
      parts.append("Group: \(title.decodingHTMLEntities)")
      parts.append("\(conversation.participants.count) members")
    } else {
      parts.append((conversation.participant.displayName ?? conversation.participant.username).decodingHTMLEntities)
      parts.append("@\(conversation.participant.username)")
    }
    let lastMessageBody: String
    if conversation.isGroup {
      let senderName = (conversation.lastMessage.sender.displayName
                        ?? conversation.lastMessage.sender.username).decodingHTMLEntities
      lastMessageBody = "\(senderName): \(conversation.lastMessage.content)"
    } else {
      lastMessageBody = conversation.lastMessage.content
    }
    if !lastMessageBody.isEmpty {
      parts.append("Last message: \(lastMessageBody)")
    }
    let relative = RelativeDateTimeFormatter()
    parts.append(relative.localizedString(for: conversation.lastMessage.createdAt, relativeTo: Date()))
    if conversation.unreadCount > 0 {
      parts.append("\(conversation.unreadCount) unread")
    }
    if conversation.isMuted {
      parts.append("Muted")
    }
    parts.append("on \(conversation.platform.accessibilityLabel)")
    return parts.joined(separator: ", ")
  }

  @ViewBuilder
  private var avatarView: some View {
    if conversation.isGroup {
      GroupAvatarStack(participants: conversation.participants, size: 48)
    } else if let avatarURL = conversation.participant.avatarURL,
       let url = URL(string: avatarURL) {
      CachedAsyncImage(url: url, priority: .high) { image in
        image.resizable()
          .aspectRatio(contentMode: .fill)
      } placeholder: {
        Circle().fill(Color.gray.opacity(0.3))
          .overlay(ProgressView().scaleEffect(0.5))
      }
      .frame(width: 48, height: 48)
      .clipShape(Circle())
    } else {
      Circle().fill(Color.gray.opacity(0.3))
        .frame(width: 48, height: 48)
        .overlay(
          Text(String((conversation.participant.displayName ?? conversation.participant.username).prefix(1)).uppercased())
            .font(.title3.bold())
            .foregroundColor(.gray)
        )
    }
  }
}

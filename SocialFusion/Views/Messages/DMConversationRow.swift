import SwiftUI

struct DMConversationRow: View {
  let conversation: DMConversation

  /// Brand-tinted color used for the unread indicator.
  private var platformColor: Color {
    switch conversation.platform {
    case .bluesky:
      return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
    case .mastodon:
      return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
    }
  }

  private var hasUnread: Bool { conversation.unreadCount > 0 }

  /// VoiceOver utterance for the whole row — composed from name,
  /// platform, last message, time, mute, and unread count so the user
  /// hears one cohesive summary per row.
  private var rowAccessibilityLabel: String {
    var parts: [String] = []
    let titleText: String
    if conversation.isGroup, let title = conversation.title {
      titleText = title
    } else {
      titleText = conversation.participant.displayName ?? conversation.participant.username
    }
    parts.append(titleText)
    parts.append(conversation.platform.rawValue.capitalized)
    if conversation.isMuted { parts.append("Muted") }
    if hasUnread {
      parts.append("\(conversation.unreadCount) unread message\(conversation.unreadCount == 1 ? "" : "s")")
    }
    parts.append(conversation.lastMessage.content)
    // Natural-language timestamp — the visible row shows '5m', but
    // VoiceOver should hear the full form so the recency reads as a
    // recognizable English phrase, not a cryptic abbreviation.
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    parts.append(formatter.localizedString(for: conversation.lastMessage.createdAt, relativeTo: Date()))
    return parts.joined(separator: ", ")
  }

  var body: some View {
    HStack(spacing: 12) {
      avatarView

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          if conversation.isGroup, let title = conversation.title {
            Text(title)
              .font(.headline)
              .fontWeight(hasUnread ? .bold : .semibold)
              .foregroundColor(.primary)
              .lineLimit(1)
          } else {
            EmojiDisplayNameText(
              conversation.participant.displayName ?? conversation.participant.username,
              emojiMap: conversation.participant.displayNameEmojiMap,
              font: .headline,
              fontWeight: hasUnread ? .bold : .semibold,
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

        HStack(alignment: .top, spacing: 8) {
          Group {
            if conversation.isGroup {
              Text("\(conversation.lastMessage.sender.displayName ?? conversation.lastMessage.sender.username): \(conversation.lastMessage.content)")
            } else {
              Text(conversation.lastMessage.content)
            }
          }
          .font(.subheadline)
          // Unread messages get a slightly stronger preview to match the bold title
          .foregroundColor(hasUnread ? .primary.opacity(0.78) : .secondary)
          .lineLimit(2)

          Spacer(minLength: 0)

          if hasUnread {
            UnreadIndicator(tint: platformColor)
          }
        }
      }
    }
    .padding(.vertical, 4)
    // Whole row reads as one summary for VoiceOver — see
    // rowAccessibilityLabel above. The NavigationLink wrapping this
    // row applies the button trait + 'opens chat' hint at the link
    // level, so the row just needs the cohesive description.
    .accessibilityElement(children: .combine)
    .accessibilityLabel(rowAccessibilityLabel)
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
        // Initials while loading rather than a spinner — feels more
        // present, less 'something is happening here'. Same identity
        // shows whether or not the network resolves.
        Circle().fill(Color(.systemGray5))
          .overlay(
            Text(String((conversation.participant.displayName ?? conversation.participant.username).prefix(1)).uppercased())
              .font(.title3.bold())
              .foregroundColor(Color(.systemGray))
          )
      }
      .frame(width: 48, height: 48)
      .clipShape(Circle())
    } else {
      Circle().fill(Color(.systemGray5))
        .frame(width: 48, height: 48)
        .overlay(
          Text(String((conversation.participant.displayName ?? conversation.participant.username).prefix(1)).uppercased())
            .font(.title3.bold())
            .foregroundColor(Color(.systemGray))
        )
    }
  }
}

/// Platform-tinted unread indicator dot with a soft outer halo — feels alive
/// without animating constantly (animation would be noise in a long list).
private struct UnreadIndicator: View {
  let tint: Color

  var body: some View {
    ZStack {
      Circle()
        .fill(tint.opacity(0.18))
        .frame(width: 18, height: 18)

      Circle()
        .fill(tint)
        .frame(width: 9, height: 9)
        .shadow(color: tint.opacity(0.4), radius: 3, x: 0, y: 1)
    }
    .frame(width: 18, height: 18)
    .padding(.top, 2)  // align with text baseline
  }
}

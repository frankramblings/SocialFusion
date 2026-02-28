import SwiftUI

struct DMConversationRow: View {
  let conversation: DMConversation

  var body: some View {
    HStack(spacing: 12) {
      avatarView

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          EmojiDisplayNameText(
            conversation.participant.displayName ?? conversation.participant.username,
            emojiMap: conversation.participant.displayNameEmojiMap,
            font: .headline,
            fontWeight: .semibold,
            foregroundColor: .primary,
            lineLimit: 1
          )

          Spacer()

          PostPlatformBadge(platform: conversation.platform)
            .scaleEffect(0.85)
        }

        HStack(spacing: 4) {
          Text("@\(conversation.participant.username)")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .lineLimit(1)

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
          Text(conversation.lastMessage.content)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .lineLimit(2)

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
  }

  @ViewBuilder
  private var avatarView: some View {
    if let avatarURL = conversation.participant.avatarURL,
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

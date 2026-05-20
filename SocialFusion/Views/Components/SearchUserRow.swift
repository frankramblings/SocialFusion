import SwiftUI

/// Row view for displaying a user in search results
struct SearchUserRow: View {
  let user: SearchUser
  let onTap: () -> Void

  var body: some View {
    Button {
      HapticEngine.tap.trigger()
      onTap()
    } label: {
      HStack(spacing: 12) {
        // Avatar
        if let avatarURL = user.avatarURL, let url = URL(string: avatarURL) {
          AsyncImage(url: url) { image in
            image
              .resizable()
              .aspectRatio(contentMode: .fill)
          } placeholder: {
            Circle()
              .fill(Color(.systemGray5))
              .overlay(
                ProgressView()
                  .scaleEffect(0.5)
              )
          }
          .frame(width: 40, height: 40)
          .clipShape(Circle())
        } else {
          Circle()
            .fill(Color(.systemGray5))
            .frame(width: 40, height: 40)
            .overlay(
              Text(user.username.prefix(1).uppercased())
                .font(.headline.weight(.semibold))
                .foregroundColor(.secondary)
            )
        }
        
        // User info
        VStack(alignment: .leading, spacing: 2) {
          EmojiDisplayNameText(
            user.displayName ?? user.username,
            emojiMap: user.displayNameEmojiMap,
            font: .headline,
            fontWeight: .regular,
            foregroundColor: .primary,
            lineLimit: 1
          )
          
          Text("@\(user.username)")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
        
        Spacer()
        
        // Platform indicator
        PlatformIndicator(platform: user.platform)
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 16)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

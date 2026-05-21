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
        let initial = String((user.displayName ?? user.username).prefix(1)).uppercased()
        if let avatarURL = user.avatarURL, let url = URL(string: avatarURL) {
          AsyncImage(url: url) { image in
            image
              .resizable()
              .aspectRatio(contentMode: .fill)
          } placeholder: {
            // Initials placeholder (matches the avatar-initials pattern
            // from iters 69-73) — feels more present than a spinner.
            initialsCircle(initial)
          }
          .frame(width: 40, height: 40)
          .clipShape(Circle())
        } else {
          initialsCircle(initial)
            .frame(width: 40, height: 40)
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
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(user.displayName ?? user.username), @\(user.username), on \(user.platform.rawValue.capitalized)")
    .accessibilityHint("Opens this user's profile")
  }

  /// Initials-fallback avatar matching the pattern from iters 69-73.
  private func initialsCircle(_ initial: String) -> some View {
    Circle()
      .fill(Color(.systemGray5))
      .overlay(
        Text(initial)
          .font(.headline.weight(.semibold))
          .foregroundColor(Color(.systemGray))
      )
  }
}

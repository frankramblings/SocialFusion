import SwiftUI

/// Row view for displaying a user in search results
struct SearchUserRow: View {
  let user: SearchUser
  let onTap: () -> Void
  
  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 12) {
        // Avatar
        if let avatarURL = user.avatarURL, let url = URL(string: avatarURL) {
          AsyncImage(url: url) { image in
            image
              .resizable()
              .aspectRatio(contentMode: .fill)
          } placeholder: {
            Circle()
              .fill(Color.gray.opacity(0.3))
              .overlay(
                ProgressView()
                  .scaleEffect(0.5)
              )
          }
          .frame(width: 40, height: 40)
          .clipShape(Circle())
        } else {
          Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 40, height: 40)
            .overlay(
              Text(user.username.prefix(1).uppercased())
                .font(.headline)
                .foregroundColor(.secondary)
            )
        }
        
        // User info
        VStack(alignment: .leading, spacing: 2) {
          Text(user.displayName ?? user.username)
            .font(.headline)
            .foregroundColor(.primary)
            .lineLimit(1)
          
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
    }
    .buttonStyle(PlainButtonStyle())
  }
}

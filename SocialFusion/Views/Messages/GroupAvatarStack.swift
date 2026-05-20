import SwiftUI

struct GroupAvatarStack: View {
  let avatars: [(url: String?, initial: String)]
  let size: CGFloat

  init(participants: [NotificationAccount], size: CGFloat = 40) {
    self.avatars = participants.prefix(3).map { participant in
      let initial = String((participant.displayName ?? participant.username).prefix(1)).uppercased()
      return (url: participant.avatarURL, initial: initial.isEmpty ? "?" : initial)
    }
    self.size = size
  }

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      ForEach(Array(avatars.prefix(3).enumerated()), id: \.offset) { index, avatar in
        avatarImage(urlString: avatar.url, initial: avatar.initial)
          .frame(width: avatarSize, height: avatarSize)
          .clipShape(Circle())
          .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
          .offset(x: xOffset(for: index), y: yOffset(for: index))
      }
    }
    .frame(width: size, height: size)
  }

  private var avatarSize: CGFloat { size * 0.65 }

  @ViewBuilder
  private func avatarImage(urlString: String?, initial: String) -> some View {
    if let urlString, let url = URL(string: urlString) {
      CachedAsyncImage(url: url, priority: .low) { image in
        image.resizable().aspectRatio(contentMode: .fill)
      } placeholder: {
        initialCircle(initial)
      }
    } else {
      initialCircle(initial)
    }
  }

  private func initialCircle(_ letter: String) -> some View {
    Circle()
      .fill(Color(.systemGray5))
      .overlay(
        Text(letter)
          .font(.system(size: max(8, avatarSize * 0.4), weight: .semibold))
          .foregroundColor(Color(.systemGray))
          .minimumScaleFactor(0.6)
      )
  }

  private func xOffset(for index: Int) -> CGFloat {
    guard avatars.count > 1 else { return 0 }
    switch index {
    case 0: return -size * 0.15
    case 1: return size * 0.15
    default: return 0
    }
  }

  private func yOffset(for index: Int) -> CGFloat {
    guard avatars.count > 2 else { return 0 }
    switch index {
    case 0, 1: return -size * 0.1
    case 2: return size * 0.15
    default: return 0
    }
  }
}

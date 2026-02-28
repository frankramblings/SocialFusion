import SwiftUI

struct GroupAvatarStack: View {
  let avatarURLs: [String?]
  let size: CGFloat

  init(participants: [NotificationAccount], size: CGFloat = 40) {
    self.avatarURLs = participants.prefix(3).map(\.avatarURL)
    self.size = size
  }

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      ForEach(Array(avatarURLs.prefix(3).enumerated()), id: \.offset) { index, urlString in
        avatarImage(urlString: urlString)
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
  private func avatarImage(urlString: String?) -> some View {
    if let urlString, let url = URL(string: urlString) {
      CachedAsyncImage(url: url, priority: .low) { image in
        image.resizable().aspectRatio(contentMode: .fill)
      } placeholder: {
        Circle().fill(Color.gray.opacity(0.3))
      }
    } else {
      Circle().fill(Color.gray.opacity(0.3))
    }
  }

  private func xOffset(for index: Int) -> CGFloat {
    guard avatarURLs.count > 1 else { return 0 }
    switch index {
    case 0: return -size * 0.15
    case 1: return size * 0.15
    default: return 0
    }
  }

  private func yOffset(for index: Int) -> CGFloat {
    guard avatarURLs.count > 2 else { return 0 }
    switch index {
    case 0, 1: return -size * 0.1
    case 2: return size * 0.15
    default: return 0
    }
  }
}

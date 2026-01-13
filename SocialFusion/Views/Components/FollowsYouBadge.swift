import SwiftUI

/// Badge component showing "Follows you" or "Mutuals" indicator
struct FollowsYouBadge: View {
  let isMutual: Bool
  let isFollowedBy: Bool
  
  var body: some View {
    if isMutual {
      Text("Mutuals")
        .font(.caption)
        .fontWeight(.medium)
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    } else if isFollowedBy {
      Text("Follows you")
        .font(.caption)
        .fontWeight(.medium)
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }
  }
}

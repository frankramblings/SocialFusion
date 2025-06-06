import SwiftUI

/// "<user> boosted" pill styled like ReplyBanner.
struct BoostBanner: View {
    let handle: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.2.squarepath")
                .font(.caption2)
            Text("\(handle) boosted")
        }
        .font(.caption2)
        .foregroundColor(.purple)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.purple.opacity(0.12)))
        .overlay(Capsule().stroke(Color.purple, lineWidth: 0.5))
    }
}

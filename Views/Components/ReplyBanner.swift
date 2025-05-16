import SwiftUI

/// “Replying to …” pill above a reply chain.
struct ReplyBanner: View {
    let handle: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.caption2)
            Text("Replying to \(handle)")
        }
        .font(.caption2)
        .foregroundColor(.accentPurple)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.accentPurple.opacity(0.12)))
        .overlay(Capsule().stroke(Color.accentPurple, lineWidth: 0.5))
    }
}

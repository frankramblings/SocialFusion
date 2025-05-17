import SwiftUI

/// "Replying to …" banner for reply posts
struct ReplyBanner: View {
    let handle: String
    var onTap: (() -> Void)?

    // Bluesky blue color matching the screenshot
    private let blueskyBlue = Color(red: 0, green: 122 / 255, blue: 255 / 255)

    var body: some View {
        Button(action: {
            if let onTap = onTap {
                onTap()
            }
        }) {
            HStack {
                Image(systemName: "arrow.turn.up.left")
                    .font(.caption)
                    .foregroundColor(blueskyBlue)

                Text("Replying to ")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    + Text("@\(handle)")
                    .font(.footnote)
                    .foregroundColor(blueskyBlue)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.systemGray6).opacity(0.3))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview("Reply Banner") {
    VStack(spacing: 12) {
        ReplyBanner(handle: "joshuajfriedman.com")
        ReplyBanner(handle: "amybrown.xyz")
        ReplyBanner(handle: "nora.zone")
    }
    .padding()
    .background(Color.black)
}

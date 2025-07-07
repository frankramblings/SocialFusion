import SwiftUI

/// A view that displays a button for reposting a post
struct PostRepostButton: View {
    let post: Post
    let repostCount: Int
    let isReposted: Bool
    let onTap: () -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: {
            // Add haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()

            onTap()
        }) {
            HStack(spacing: 4) {
                Image(systemName: isReposted ? "arrow.2.squarepath.fill" : "arrow.2.squarepath")
                    .foregroundColor(isReposted ? .green : .secondary)
                    .scaleEffect(isReposted ? 1.1 : 1.0)
                    .animation(
                        .spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0.1),
                        value: isReposted)

                if repostCount > 0 {
                    Text(formatCount(repostCount))
                        .font(.subheadline)
                        .foregroundColor(isReposted ? .green : .secondary)
                        .animation(
                            .spring(response: 0.35, dampingFraction: 0.7, blendDuration: 0.1),
                            value: isReposted)
                }
            }
        }
        .scaleEffect(isPressed ? 0.88 : 1.0)
        .opacity(isPressed ? 0.75 : 1.0)
        .animation(
            .interactiveSpring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.05),
            value: isPressed
        )
        .onLongPressGesture(
            minimumDuration: 0, maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(
                    .interactiveSpring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.05)
                ) {
                    isPressed = pressing
                }
            }, perform: {}
        )
        .buttonStyle(PlainButtonStyle())
    }

    private var platformColor: Color {
        switch post.platform {
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}

// MARK: - Preview
struct PostRepostButton_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 16) {
            // Bluesky post with reposts
            PostRepostButton(
                post: Post(
                    id: "1",
                    content: "Test post",
                    authorName: "Test User",
                    authorUsername: "testuser",
                    authorProfilePictureURL: "",
                    createdAt: Date(),
                    platform: .bluesky,
                    originalURL: "",
                    attachments: []
                ),
                repostCount: 42,
                isReposted: false,
                onTap: {}
            )

            // Mastodon post with reposts
            PostRepostButton(
                post: Post(
                    id: "2",
                    content: "Test post",
                    authorName: "Test User",
                    authorUsername: "testuser",
                    authorProfilePictureURL: "",
                    createdAt: Date(),
                    platform: .mastodon,
                    originalURL: "",
                    attachments: []
                ),
                repostCount: 1234,
                isReposted: true,
                onTap: {}
            )

            // Post without reposts
            PostRepostButton(
                post: Post(
                    id: "3",
                    content: "Test post",
                    authorName: "Test User",
                    authorUsername: "testuser",
                    authorProfilePictureURL: "",
                    createdAt: Date(),
                    platform: .bluesky,
                    originalURL: "",
                    attachments: []
                ),
                repostCount: 0,
                isReposted: false,
                onTap: {}
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}

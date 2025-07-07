import SwiftUI

/// A view that displays a button for sharing a post
struct PostShareButton: View {
    let post: Post
    let onTap: () -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: {
            // Add haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()

            onTap()
        }) {
            Image(systemName: "square.and.arrow.up")
                .foregroundColor(.secondary)
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
}

// MARK: - Preview
struct PostShareButton_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 16) {
            // Bluesky post share button
            PostShareButton(
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
                onTap: {}
            )

            // Mastodon post share button
            PostShareButton(
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
                onTap: {}
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}

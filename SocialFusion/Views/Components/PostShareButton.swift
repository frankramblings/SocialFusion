import SwiftUI

/// A view that displays a button for sharing a post
struct PostShareButton: View {
    let post: Post
    let onTap: () -> Void

    @State private var isPressed: Bool = false
    @State private var showConfirmation: Bool = false

    var body: some View {
        Button(action: {
            // Add haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()

            // Show brief visual confirmation
            withAnimation(.easeInOut(duration: 0.2)) {
                showConfirmation = true
            }
            
            // Hide confirmation after 1.5 seconds
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showConfirmation = false
                    }
                }
            }

            onTap()
        }) {
            Image(systemName: showConfirmation ? "checkmark" : "square.and.arrow.up")
                .foregroundColor(showConfirmation ? .green : .secondary)
                .scaleEffect(showConfirmation ? 1.1 : 1.0)
        }
        .scaleEffect(isPressed ? 0.88 : 1.0)
        .opacity(isPressed ? 0.75 : 1.0)
        .animation(
            .interactiveSpring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.05),
            value: isPressed
        )
        .animation(
            .spring(response: 0.2, dampingFraction: 0.7, blendDuration: 0.05),
            value: showConfirmation
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

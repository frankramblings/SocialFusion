import Foundation
import SwiftUI

// Parent post preview component with styling to match the Bluesky design
struct ParentPostPreview: View {
    let post: Post
    var onTap: (() -> Void)? = nil

    // Animation state for smooth interactions
    @State private var isPressed = false

    // Maximum characters before content is trimmed
    private let maxCharacters = 500

    // Formatter for relative timestamps
    private func formatRelativeTime(from date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date, to: now)

        if let year = components.year, year > 0 {
            return "\(year)y"
        } else if let month = components.month, month > 0 {
            return "\(month)mo"
        } else if let day = components.day, day > 0 {
            if day < 7 {
                return "\(day)d"
            } else {
                let week = day / 7
                return "\(week)w"
            }
        } else if let hour = components.hour, hour > 0 {
            return "\(hour)h"
        } else if let minute = components.minute, minute > 0 {
            return "\(minute)m"
        } else {
            return "now"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Author avatar with platform indicator
                ZStack(alignment: .bottomTrailing) {
                    // Author avatar with proper frame constraints
                    StabilizedAsyncImage(
                        url: URL(string: post.authorProfilePictureURL),
                        idealHeight: 36,
                        aspectRatio: 1.0,
                        contentMode: .fill,
                        cornerRadius: 18
                    )
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .stroke(Color(.systemBackground), lineWidth: 1.5)
                    )
                    .scaleEffect(isPressed ? 0.95 : 1.0)

                    // Platform indicator with subtle animation
                    PlatformDot(platform: post.platform, size: 10)
                        .offset(x: 2, y: 2)
                        .scaleEffect(isPressed ? 0.9 : 1.0)
                }
                .frame(width: 36, height: 36)  // Explicit container frame to prevent layout shifts

                // Author info with refined typography
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text("@\(post.authorUsername)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .opacity(isPressed ? 0.8 : 1.0)

                Spacer()

                // Time ago with refined styling
                Text(formatRelativeTime(from: post.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .opacity(isPressed ? 0.7 : 1.0)
            }

            // Post content with conditional line limit and refined styling
            post.contentView(
                lineLimit: post.content.count > maxCharacters ? 8 : nil,
                showLinkPreview: false,
                font: .callout  // Explicitly set font for parent post text
            )
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .opacity(isPressed ? 0.85 : 1.0)
        }
        .padding(.vertical, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onLongPressGesture(
            minimumDuration: 0, maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            },
            perform: {
                // Provide subtle haptic feedback on tap
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.prepare()
                impactFeedback.impactOccurred()

                onTap?()
            })
    }
}

#Preview {
    VStack {
        ParentPostPreview(post: Post.samplePosts[0])
    }
    .padding()
    .background(Color.black)
}

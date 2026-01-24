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

                    // Platform indicator with enhanced visibility and subtle animation
                    PlatformDot(
                        platform: post.platform, size: 16, useLogo: true  // Increased from 14 to 16 for better visibility
                    )
                    .background(
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.1), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    )
                    .offset(x: 3, y: 3)
                    .scaleEffect(isPressed ? 0.9 : 1.0)
                }
                .frame(width: 36, height: 36)  // Explicit container frame to prevent layout shifts

                // Author info with refined typography
                VStack(alignment: .leading, spacing: 2) {
                    EmojiDisplayNameText(
                        post.authorName,
                        emojiMap: post.authorEmojiMap,
                        font: .subheadline,
                        fontWeight: .semibold,
                        foregroundColor: .primary,
                        lineLimit: 1
                    )

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

            // Post content with no line limit to show full content
            post.contentView(
                lineLimit: nil,  // No line limit - show full content
                showLinkPreview: false,
                font: .callout,  // Explicitly set font for parent post text
                allowTruncation: false  // Parent posts should show full content
            )
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .opacity(isPressed ? 0.85 : 1.0)

            // Media attachments if present
            if !post.attachments.isEmpty {
                ParentPostMediaView(attachments: post.attachments)
                    .padding(.leading, 6)
                    .padding(.trailing, 8)
                    .padding(.top, 6)
                    .opacity(isPressed ? 0.85 : 1.0)
            }
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

// MARK: - Parent Post Media View
struct ParentPostMediaView: View {
    let attachments: [Post.Attachment]
    private let maxHeight: CGFloat = 200  // Maximum height for parent post media

    var body: some View {
        // Support all attachment types, not just images
        if !attachments.isEmpty {
            ZStack(alignment: .bottom) {
                mediaContent(for: attachments)
                    .frame(maxHeight: maxHeight)
                    .clipped()

                // Only show gradient fade when content is actually truncated
                if shouldShowGradientFade(for: attachments) {
                    VStack(spacing: 0) {
                        Spacer()

                        // Gradient fade to transparency for truncated content
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color(.systemBackground).opacity(0.1),
                                Color(.systemBackground).opacity(0.3),
                                Color(.systemBackground).opacity(0.6),
                                Color(.systemBackground),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 50)
                    }
                }
            }
            .frame(maxHeight: maxHeight)
            .clipped()
        }
    }

    @ViewBuilder
    private func mediaContent(for allAttachments: [Post.Attachment]) -> some View {
        // Separate image and non-image attachments
        let imageAttachments = allAttachments.filter { $0.type == .image }
        let nonImageAttachments = allAttachments.filter { $0.type != .image }

        VStack(spacing: 6) {
            // Handle non-image media first (videos, GIFs, audio)
            if !nonImageAttachments.isEmpty {
                ForEach(nonImageAttachments.prefix(2), id: \.id) { attachment in
                    // ZERO LAYOUT SHIFT: Pass stableAspectRatio to prevent height changes after load
                    SmartMediaView(
                        attachment: attachment,
                        contentMode: .fill,
                        maxWidth: .infinity,
                        maxHeight: maxHeight,
                        cornerRadius: 8,
                        stableAspectRatio: attachment.stableAspectRatio,
                        onTap: nil
                    )
                    .frame(maxHeight: maxHeight)
                }
            }

            // Then handle image attachments with existing grid layout
            if !imageAttachments.isEmpty {
                switch imageAttachments.count {
                case 1:
                    SingleParentImage(attachment: imageAttachments[0], maxHeight: maxHeight)
                case 2:
                    HStack(spacing: 4) {
                        ForEach(imageAttachments.prefix(2), id: \.id) { attachment in
                            ParentImageView(attachment: attachment)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: min(120, maxHeight))
                case 3:
                    HStack(spacing: 4) {
                        ParentImageView(attachment: imageAttachments[0])
                            .frame(maxWidth: .infinity)

                        VStack(spacing: 4) {
                            ForEach(imageAttachments[1...2], id: \.id) { attachment in
                                ParentImageView(attachment: attachment)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: min(120, maxHeight))
                default:
                    // 4+ images: show first 3 with a "+X more" overlay on the last one
                    HStack(spacing: 4) {
                        ParentImageView(attachment: imageAttachments[0])
                            .frame(maxWidth: .infinity)

                        VStack(spacing: 4) {
                            ParentImageView(attachment: imageAttachments[1])

                            ZStack {
                                ParentImageView(attachment: imageAttachments[2])

                                // Overlay for additional images
                                Rectangle()
                                    .fill(Color.black.opacity(0.6))
                                    .overlay(
                                        Text("+\(imageAttachments.count - 3)")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                    )
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: min(120, maxHeight))
                }
            }
        }
    }

    private func shouldShowGradientFade(for allAttachments: [Post.Attachment]) -> Bool {
        // Show gradient fade for single media items that might be truncated
        // For multiple items or grid layouts, they're sized to fit within bounds so no truncation
        let imageAttachments = allAttachments.filter { $0.type == .image }
        let nonImageAttachments = allAttachments.filter { $0.type != .image }

        // Show fade if we have a single image or any non-image media (which uses full height)
        return imageAttachments.count == 1 || !nonImageAttachments.isEmpty
    }

}

// MARK: - Single Parent Image
struct SingleParentImage: View {
    let attachment: Post.Attachment
    let maxHeight: CGFloat

    var body: some View {
        StabilizedAsyncImage(
            url: URL(string: attachment.url),
            idealHeight: maxHeight,
            aspectRatio: nil,
            contentMode: .fill,
            cornerRadius: 8
        )
        .frame(maxHeight: maxHeight)
        .clipped()
    }
}

// MARK: - Parent Image View
struct ParentImageView: View {
    let attachment: Post.Attachment

    var body: some View {
        StabilizedAsyncImage(
            url: URL(string: attachment.url),
            idealHeight: 58,
            aspectRatio: 1.0,
            contentMode: .fill,
            cornerRadius: 6
        )
        .frame(height: 58)
        .clipped()
    }
}

#Preview {
    VStack {
        ParentPostPreview(post: Post.samplePosts[0])
    }
    .padding()
    .background(Color.black)
}

import Foundation
import SwiftUI

// Parent post preview component with styling to match the Bluesky design
struct ParentPostPreview: View {
    let post: Post
    var onTap: (() -> Void)? = nil

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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Author avatar with platform indicator
                ZStack(alignment: .bottomTrailing) {
                    // Author avatar
                    AsyncImage(url: URL(string: post.authorProfilePictureURL)) { phase in
                        if let image = phase.image {
                            image.resizable()
                        } else {
                            Circle().fill(Color.gray.opacity(0.3))
                        }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())

                    // Platform indicator
                    PlatformDot(platform: post.platform, size: 10)
                        .offset(x: 2, y: 2)
                }

                // Author info
                VStack(alignment: .leading, spacing: 0) {
                    Text(post.authorName)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("@\(post.authorUsername)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Time ago
                Text(formatRelativeTime(from: post.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Post content with conditional line limit
            post.contentView(
                lineLimit: post.content.count > maxCharacters ? 8 : nil,
                showLinkPreview: false,
                font: .callout  // Explicitly set font for parent post text
            )
            .padding(.leading, 4)
            .padding(.trailing, 8)
        }
        .padding(.vertical, 4)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if let onTap = onTap {
                onTap()
            }
        }
    }
}

#Preview {
    VStack {
        ParentPostPreview(post: Post.samplePosts[0])
    }
    .padding()
    .background(Color.black)
}

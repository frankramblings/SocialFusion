import SwiftUI

/// A compact view of a quoted post - styled like ParentPostPreview
public struct QuotePostView: View {
    public let post: Post
    public var onTap: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var navigationEnvironment: PostNavigationEnvironment

    // Maximum characters before content is trimmed
    private let maxCharacters = 300

    public init(post: Post, onTap: (() -> Void)? = nil) {
        self.post = post
        self.onTap = onTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            authorHeader
            postContent
            if !post.attachments.isEmpty {
                postMedia
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(backgroundStyle)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(borderOverlay)
        .shadow(
            color: colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02),
            radius: 0.5, x: 0, y: 0
        )
        .shadow(
            color: colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05),
            radius: 1, y: 1
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let onTap = onTap {
                onTap()
            } else {
                navigationEnvironment.navigateToPost(post)
            }
        }
    }

    // MARK: - View Components

    private var authorHeader: some View {
        HStack {
            authorAvatar
            authorInfo
            Spacer()
            timestamp
        }
    }

    private var authorAvatar: some View {
        Button(action: {
            navigationEnvironment.navigateToUser(from: post)
        }) {
            ZStack(alignment: .bottomTrailing) {
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
                        .stroke(Color(.systemBackground), lineWidth: 1)
                )

                PlatformDot(
                    platform: post.platform, size: 16, useLogo: true  // Increased from 14 to 16 for better visibility
                )
                .background(
                    Circle()
                        .fill(Color(.systemBackground))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .stroke(
                                    colorScheme == .dark
                                        ? Color.white.opacity(0.2) : Color.black.opacity(0.1),
                                    lineWidth: 0.5)
                        )
                        .shadow(
                            color: .black.opacity(colorScheme == .dark ? 0.3 : 0.15), radius: 2, x: 0,
                            y: 1)
                )
                .offset(x: 3, y: 3)
            }
            .frame(width: 36, height: 36)  // Explicit container frame to prevent layout shifts
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var authorInfo: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                navigationEnvironment.navigateToUser(from: post)
            }) {
                Text(post.authorName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: {
                navigationEnvironment.navigateToUser(from: post)
            }) {
                Text("@\(post.authorUsername)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var timestamp: some View {
        Text(formatRelativeTime(from: post.createdAt))
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private var postContent: some View {
        let lineLimit = post.content.count > maxCharacters ? 4 : nil
        return post.contentView(
            lineLimit: lineLimit, showLinkPreview: true, allowTruncation: false
        )
        .font(.callout)
        .padding(.horizontal, 4)
        // Prevent nested quotes in quote cards
        .environment(\.preventNestedQuotes, true)
    }

    private var postMedia: some View {
        UnifiedMediaGridView(
            attachments: post.attachments,
            maxHeight: 220
        )
        .clipShape(RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous))
        .padding(.top, 4)
    }

    private var errorMediaView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(maxWidth: .infinity, maxHeight: 220)
            .cornerRadius(14)
            .overlay(
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            )
    }

    private var loadingMediaView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.1))
            .frame(maxWidth: .infinity, maxHeight: 220)
            .cornerRadius(14)
            .overlay(
                ProgressView()
            )
    }

    private var backgroundStyle: some View {
        (colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.03))
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(
                colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08),
                lineWidth: 0.5)
    }

    // MARK: - Helper Functions

    private func formatRelativeTime(from date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date, to: now)

        if let year = components.year, year > 0 {
            return "\(year)y"
        } else if let month = components.month, month > 0 {
            return "\(month)mo"
        } else if let day = components.day, day > 0 {
            return day >= 7 ? "\(day/7)w" : "\(day)d"
        } else if let hour = components.hour, hour > 0 {
            return "\(hour)h"
        } else if let minute = components.minute, minute > 0 {
            return "\(minute)m"
        } else {
            return "now"
        }
    }
}

#Preview {
    let samplePost = Post(
        id: "preview-1",
        content: "This is a sample quoted post",
        authorName: "John Doe",
        authorUsername: "johndoe",
        authorProfilePictureURL: "",
        createdAt: Date(),
        platform: .mastodon,
        originalURL: "",
        attachments: [],
        mentions: [],
        tags: []
    )
    return QuotePostView(post: samplePost)
}

import SwiftUI

/// A compact view of a quoted post - styled like ParentPostPreview
public struct QuotePostView: View {
    public let post: Post
    @Environment(\.colorScheme) private var colorScheme

    // Maximum characters before content is trimmed
    private let maxCharacters = 300

    public init(post: Post) {
        self.post = post
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
            radius: 1, y: 1)
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
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: URL(string: post.authorProfilePictureURL)) { phase in
                if let image = phase.image {
                    image.resizable()
                } else {
                    Circle().fill(Color.gray.opacity(0.3))
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            PlatformDot(platform: post.platform, size: 10)
                .offset(x: 2, y: 2)
        }
    }

    private var authorInfo: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(post.authorName)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("@\(post.authorUsername)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var timestamp: some View {
        Text(formatRelativeTime(from: post.createdAt))
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private var postContent: some View {
        let lineLimit = post.content.count > maxCharacters ? 4 : nil
        return post.contentView(lineLimit: lineLimit, showLinkPreview: false)
            .font(.callout)
            .padding(.horizontal, 4)
    }

    private var postMedia: some View {
        AsyncImage(url: URL(string: post.attachments[0].url)) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .cornerRadius(14)
                    .clipped()
            } else if phase.error != nil {
                errorMediaView
            } else {
                loadingMediaView
            }
        }
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
    let serviceManager = SocialServiceManager()
    return QuotePostView(post: samplePost)
}

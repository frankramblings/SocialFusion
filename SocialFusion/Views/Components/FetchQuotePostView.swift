import SwiftUI

/// Fetches and displays a quoted post from a URL
struct FetchQuotePostView: View {
    let url: URL
    @State private var quotedPost: Post? = nil
    @State private var isLoading = true
    @State private var error: Error? = nil
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @Environment(\.colorScheme) private var colorScheme

    private var isProbablyBluesky: Bool {
        return url.absoluteString.contains("bsky.app") || url.absoluteString.contains("bsky.social")
    }

    private var platform: SocialPlatform {
        return isProbablyBluesky ? .bluesky : .mastodon
    }

    // Helper to determine if a post has meaningful content
    private func hasMeaningfulContent(_ post: Post) -> Bool {
        let hasText = !post.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasMedia = !post.attachments.isEmpty
        let hasAuthor = !post.authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || hasMedia || hasAuthor
    }

    var body: some View {
        VStack {
            if let post = quotedPost, hasMeaningfulContent(post) {
                QuotedPostView(post: post)
            } else if isLoading {
                LoadingQuoteView(platform: platform)
            } else if error != nil {
                // Fallback to regular link preview if we can't fetch the post
                LinkPreview(url: url)
            }
        }
        .onAppear {
            Task {
                await fetchPost()
            }
        }
    }

    private func fetchPost() async {
        // Extract post ID from URL based on platform
        if isProbablyBluesky {
            // Extract Bluesky post ID
            let components = url.path.split(separator: "/")
            if components.count >= 4, components[components.count - 2] == "post" {
                let postID = String(components[components.count - 1])

                do {
                    quotedPost = try await serviceManager.fetchBlueskyPostByID(postID)
                    isLoading = false
                } catch {
                    self.error = error
                    isLoading = false
                    print("Error fetching Bluesky post: \(error)")
                }
            } else {
                isLoading = false
                error = NSError(
                    domain: "FetchQuotePostView", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid post URL"])
            }
        } else {
            // Extract Mastodon post ID
            let components = url.path.split(separator: "/")
            if components.count >= 2 {
                let postID = String(components[components.count - 1])

                // Find a Mastodon account to use
                if let account = serviceManager.accounts.first(where: { $0.platform == .mastodon })
                {
                    do {
                        quotedPost = try await serviceManager.fetchMastodonStatus(
                            id: postID, account: account)
                        isLoading = false
                    } catch {
                        self.error = error
                        isLoading = false
                        print("Error fetching Mastodon post: \(error)")
                    }
                } else {
                    isLoading = false
                    error = NSError(
                        domain: "FetchQuotePostView", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "No Mastodon account available"])
                }
            } else {
                isLoading = false
                error = NSError(
                    domain: "FetchQuotePostView", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid post URL"])
            }
        }
    }
}

/// A compact view of a quoted post - styled like ParentPostPreview
private struct QuotedPostView: View {
    let post: Post
    @Environment(\.colorScheme) private var colorScheme

    // Maximum characters before content is trimmed
    private let maxCharacters = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Author row
            HStack {
                // Author avatar with platform indicator
                ZStack(alignment: .bottomTrailing) {
                    // Avatar
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
                RelativeTimeView(date: post.createdAt)
            }

            // Post content
            let lineLimit = post.content.count > maxCharacters ? 4 : nil
            post.contentView(lineLimit: lineLimit, showLinkPreview: false)
                .font(.callout)
                .padding(.horizontal, 4)

            // If post has media, show first attachment
            if !post.attachments.isEmpty {
                PostAttachmentView(attachment: post.attachments[0])
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08),
                    lineWidth: 0.5)
        )
        .shadow(
            color: colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02),
            radius: 0.5, x: 0, y: 0
        )
        .shadow(
            color: colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05),
            radius: 1, y: 1)
    }
}

/// Helper to display relative time
private struct RelativeTimeView: View {
    let date: Date

    var body: some View {
        Text(formatRelativeTime(from: date))
            .font(.caption)
            .foregroundColor(.secondary)
    }

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

/// Helper to display post attachment
private struct PostAttachmentView: View {
    let attachment: Post.Attachment

    var body: some View {
        AsyncImage(url: URL(string: attachment.url)) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .cornerRadius(14)
                    .clipped()
            } else if phase.error != nil {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .cornerRadius(14)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    )
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .cornerRadius(14)
                    .overlay(
                        ProgressView()
                    )
            }
        }
    }
}

/// Loading state that matches the style of ParentPostPreview
private struct LoadingQuoteView: View {
    let platform: SocialPlatform
    @Environment(\.colorScheme) private var colorScheme

    private var platformColor: Color {
        switch platform {
        case .bluesky:
            return Color(red: 0, green: 122 / 255, blue: 255 / 255)
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(platformColor)

            Text("Loading post...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 8)
        .background(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08),
                    lineWidth: 0.5)
        )
        .shadow(
            color: colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05),
            radius: 1, y: 1)
    }
}

// We use hardcoded values instead of the Color extension methods that are defined in PostCardView.swift

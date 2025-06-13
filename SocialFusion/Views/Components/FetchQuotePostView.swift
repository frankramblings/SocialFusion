import SwiftUI

/// A compact view of a quoted post - styled like ParentPostPreview
public struct QuotedPostView: View {
    public let post: Post
    @Environment(\.colorScheme) private var colorScheme

    // Maximum characters before content is trimmed
    private let maxCharacters = 300

    public init(post: Post) {
        self.post = post
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Author row
            authorHeader

            // Post content
            postContent

            // Attachments (if any)
            if !post.attachments.isEmpty {
                postAttachment
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(backgroundStyle)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(borderOverlay)
        .shadow(color: shadowColor, radius: 1, x: 0, y: 1)
    }

    // MARK: - View Components

    private var authorHeader: some View {
        HStack(spacing: 8) {
            // Author avatar with platform indicator
            ZStack(alignment: .bottomTrailing) {
                let stableImageURL = URL(string: post.authorProfilePictureURL)
                AsyncImage(url: stableImageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                    case .failure(_), .empty:
                        Circle().fill(Color.gray.opacity(0.3))
                    @unknown default:
                        Circle().fill(Color.gray.opacity(0.3))
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .id(stableImageURL?.absoluteString ?? "no-url")

                PlatformDot(platform: post.platform, size: 8)
                    .offset(x: 1, y: 1)
            }

            // Author info
            VStack(alignment: .leading, spacing: 1) {
                Text(post.authorName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text("@\(post.authorUsername)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Time ago
            RelativeTimeView(date: post.createdAt)
        }
    }

    private var postContent: some View {
        let lineLimit = post.content.count > maxCharacters ? 4 : nil
        return post.contentView(lineLimit: lineLimit, showLinkPreview: false)
            .font(.callout)
            .padding(.horizontal, 4)
    }

    private var postAttachment: some View {
        PostAttachmentView(attachment: post.attachments[0])
            .padding(.top, 4)
    }

    private var backgroundStyle: some View {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.04)
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                colorScheme == .dark
                    ? Color.white.opacity(0.15)
                    : Color.black.opacity(0.1),
                lineWidth: 0.5
            )
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.02)
            : Color.black.opacity(0.05)
    }
}

/// Fetches and displays a quoted post from a URL with improved stability
struct FetchQuotePostView: View {
    let url: URL
    @State private var quotedPost: Post? = nil
    @State private var isLoading = true
    @State private var error: Error? = nil
    @State private var retryCount = 0
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @Environment(\.colorScheme) private var colorScheme

    private let maxRetries = 2

    private var platform: SocialPlatform {
        if url.absoluteString.contains("bsky.app") || url.absoluteString.contains("bsky.social") {
            return .bluesky
        }
        return .mastodon
    }

    var body: some View {
        Group {
            if let post = quotedPost, hasMeaningfulContent(post) {
                QuotedPostView(post: post)
            } else if isLoading {
                LoadingQuoteView(platform: platform)
            } else {
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

    // Helper to determine if a post has meaningful content
    private func hasMeaningfulContent(_ post: Post) -> Bool {
        let hasText = !post.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasMedia = !post.attachments.isEmpty
        let hasAuthor = !post.authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || hasMedia || hasAuthor
    }

    private func fetchPost() async {
        guard retryCount <= maxRetries else {
            await MainActor.run {
                isLoading = false
                error = NSError(
                    domain: "FetchQuotePostView",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Maximum retries exceeded"]
                )
            }
            return
        }

        await MainActor.run {
            isLoading = true
        }

        do {
            let post = try await fetchPostForPlatform()
            await MainActor.run {
                self.quotedPost = post
                self.isLoading = false
                self.error = nil
            }
        } catch {
            print("Error fetching \(platform) post: \(error)")

            await MainActor.run {
                self.error = error

                // Retry for transient errors
                if retryCount < maxRetries && isTransientError(error) {
                    retryCount += 1
                    Task {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
                        await fetchPost()
                    }
                } else {
                    self.isLoading = false
                }
            }
        }
    }

    private func fetchPostForPlatform() async throws -> Post? {
        switch platform {
        case .bluesky:
            return try await fetchBlueskyPost()
        case .mastodon:
            return try await fetchMastodonPost()
        }
    }

    private func fetchBlueskyPost() async throws -> Post? {
        let components = url.path.split(separator: "/")
        guard components.count >= 4,
            components[components.count - 2] == "post"
        else {
            throw NSError(
                domain: "FetchQuotePostView",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Bluesky post URL format"]
            )
        }

        let postID = String(components[components.count - 1])

        guard let account = serviceManager.accounts.first(where: { $0.platform == .bluesky }) else {
            throw NSError(
                domain: "FetchQuotePostView",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No Bluesky account available"]
            )
        }

        return try await serviceManager.fetchBlueskyPostByID(postID)
    }

    private func fetchMastodonPost() async throws -> Post? {
        let components = url.path.split(separator: "/")
        guard components.count >= 2 else {
            throw NSError(
                domain: "FetchQuotePostView",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Mastodon post URL format"]
            )
        }

        let postID = String(components[components.count - 1])

        guard let account = serviceManager.accounts.first(where: { $0.platform == .mastodon })
        else {
            throw NSError(
                domain: "FetchQuotePostView",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No Mastodon account available"]
            )
        }

        return try await serviceManager.fetchMastodonStatus(id: postID, account: account)
    }

    private func isTransientError(_ error: Error) -> Bool {
        let nsError = error as NSError
        // Network errors that might be worth retrying
        return nsError.domain == NSURLErrorDomain
            && (nsError.code == NSURLErrorTimedOut
                || nsError.code == NSURLErrorNetworkConnectionLost
                || nsError.code == NSURLErrorNotConnectedToInternet)
    }
}

/// Improved loading view for quote posts
struct LoadingQuoteView: View {
    let platform: SocialPlatform
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Author placeholder
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .fill(platformColor.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .offset(x: 10, y: 10)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 80, height: 12)
                        .cornerRadius(4)

                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 60, height: 10)
                        .cornerRadius(4)
                }

                Spacer()

                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 40, height: 10)
                    .cornerRadius(4)
            }

            // Content placeholder
            VStack(alignment: .leading, spacing: 4) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(maxWidth: .infinity)
                    .frame(height: 12)
                    .cornerRadius(4)

                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(maxWidth: 200)
                    .frame(height: 12)
                    .cornerRadius(4)
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(backgroundStyle)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(borderOverlay)
        .shadow(color: shadowColor, radius: 1, x: 0, y: 1)
        .redacted(reason: .placeholder)
    }

    private var platformColor: Color {
        switch platform {
        case .bluesky:
            return .blue
        case .mastodon:
            return .purple
        }
    }

    private var backgroundStyle: some View {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.04)
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                colorScheme == .dark
                    ? Color.white.opacity(0.15)
                    : Color.black.opacity(0.1),
                lineWidth: 0.5
            )
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.02)
            : Color.black.opacity(0.05)
    }
}

/// Helper to display relative time
struct RelativeTimeView: View {
    let date: Date

    var body: some View {
        Text(formatRelativeTime(from: date))
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private func formatRelativeTime(from date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date,
            to: now
        )

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
        let stableImageURL = URL(string: attachment.url)
        AsyncImage(url: stableImageURL) { phase in
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
        .id(stableImageURL?.absoluteString ?? "no-url")
    }
}

#Preview {
    let samplePost = Post(
        id: "preview-1",
        content: "This is a sample quoted post with some longer content to test the display",
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

    return VStack(spacing: 16) {
        QuotedPostView(post: samplePost)
        LoadingQuoteView(platform: .bluesky)
        LoadingQuoteView(platform: .mastodon)
    }
    .padding()
}

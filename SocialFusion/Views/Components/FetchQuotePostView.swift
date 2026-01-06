import SwiftUI

/// A compact view of a quoted post - styled like ParentPostPreview
public struct QuotedPostView: View {
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
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }

    // MARK: - View Components

    private var authorHeader: some View {
        HStack(spacing: 8) {
            // Author avatar with platform indicator
            Button(action: {
                navigationEnvironment.navigateToUser(from: post)
            }) {
                ZStack(alignment: .bottomTrailing) {
                    let stableImageURL = URL(string: post.authorProfilePictureURL)
                    CachedAsyncImage(url: stableImageURL, priority: .high) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle().fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .id(stableImageURL?.absoluteString ?? "no-url")

                    PlatformDot(
                        platform: post.platform, size: 14, useLogo: true  // Increased from 12 to 14 for better visibility
                    )
                    .background(
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.1), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    )
                    .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Author info
            VStack(alignment: .leading, spacing: 1) {
                Button(action: {
                    navigationEnvironment.navigateToUser(from: post)
                }) {
                    Text(post.authorName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: {
                    navigationEnvironment.navigateToUser(from: post)
                }) {
                    Text("@\(post.authorUsername)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .buttonStyle(PlainButtonStyle())
            }

            Spacer()

            // Time ago
            RelativeTimeView(date: post.createdAt)
        }
    }

    private var postContent: some View {
        let lineLimit = post.content.count > maxCharacters ? 4 : nil
        return post.contentView(
            lineLimit: lineLimit, showLinkPreview: false, allowTruncation: false
        )
        .font(.callout)
        .padding(.horizontal, 4)
        // Prevent nested quotes in quote cards
        .environment(\.preventNestedQuotes, true)
    }

    private var postAttachment: some View {
        UnifiedMediaGridView(
            attachments: post.attachments,
            maxHeight: 220
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
    var onQuotePostTap: ((Post) -> Void)? = nil
    @State private var quotedPost: Post? = nil
    @State private var isLoading = true
    @State private var error: Error? = nil
    @State private var retryCount = 0
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @EnvironmentObject private var navigationEnvironment: PostNavigationEnvironment
    @Environment(\.colorScheme) private var colorScheme

    private let maxRetries = 2

    private var platform: SocialPlatform {
        let urlString = url.absoluteString.lowercased()
        // Check for Bluesky URLs (various formats)
        if urlString.contains("bsky.app") || 
           urlString.contains("bsky.social") ||
           url.scheme == "at" ||
           urlString.contains("at://") {
            return .bluesky
        }
        // Default to Mastodon for other social media URLs
        return .mastodon
    }

    var body: some View {
        Group {
            if let post = quotedPost, hasMeaningfulContent(post) {
                QuotedPostView(post: post) {
                    print("🔗 [FetchQuotePostView] Quote post tapped: \(post.id)")
                    if let onQuotePostTap = onQuotePostTap {
                        print("🔗 [FetchQuotePostView] Using provided onQuotePostTap callback")
                        onQuotePostTap(post)
                    } else {
                        print("🔗 [FetchQuotePostView] Using navigationEnvironment.navigateToPost")
                        navigationEnvironment.navigateToPost(post)
                    }
                }
            } else if isLoading {
                LoadingQuoteView(platform: platform)
            } else if error != nil && retryCount <= maxRetries {
                // Show error state with retry option (only if we haven't exceeded max retries)
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Failed to load quote")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Retry") {
                            retryCount = 0  // Reset retry count for manual retry
                            Task {
                                await fetchPost()
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                // Fallback to regular link preview if we can't fetch the post
                // This ensures something always displays, preventing posts from disappearing
                LinkPreview(url: url)
            }
        }
        .onAppear {
            print("🔗 [FetchQuotePostView] Starting fetch for URL: \(url)")
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
        
        let isValid = hasText || hasMedia || hasAuthor
        
        if !isValid {
            print("🔗 [FetchQuotePostView] Post has no meaningful content - text: \(hasText), media: \(hasMedia), author: \(hasAuthor)")
        } else {
            print("🔗 [FetchQuotePostView] Post has meaningful content - text: \(hasText), media: \(hasMedia) (\(post.attachments.count) attachments), author: \(hasAuthor)")
        }
        
        return isValid
    }

    private func fetchPost() async {
        guard retryCount <= maxRetries else {
            print("🔗 [FetchQuotePostView] Max retries exceeded for URL: \(url)")
            isLoading = false
            error = NSError(
                domain: "FetchQuotePostView",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Maximum retries exceeded"]
            )
            return
        }

        print("🔗 [FetchQuotePostView] Fetching post for URL: \(url) (attempt \(retryCount + 1))")

        isLoading = true
        error = nil

        do {
            let post: Post?

            // Determine platform based on URL
            let urlString = url.absoluteString.lowercased()
            let isBluesky = urlString.contains("bsky.app") || 
                           urlString.contains("bsky.social") ||
                           url.scheme == "at" ||
                           urlString.contains("at://")
            
            if isBluesky {
                post = try await fetchBlueskyPost()
            } else if url.host?.contains("mastodon") == true || 
                      url.host?.contains("social") == true ||
                      urlString.contains("/statuses/") ||
                      urlString.contains("/@") {
                post = try await fetchMastodonPost()
            } else {
                print("🔗 [FetchQuotePostView] Unsupported platform for URL: \(url)")
                throw NSError(
                    domain: "FetchQuotePostView",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Unsupported platform for URL: \(url.absoluteString)"]
                )
            }

            if let post = post {
                // Validate that the post has meaningful content before setting it
                if hasMeaningfulContent(post) {
                    await MainActor.run {
                        self.quotedPost = post
                        self.isLoading = false
                        self.error = nil
                    }
                } else {
                    // Post was fetched but has no meaningful content - fallback to LinkPreview
                    // Don't throw error, just don't set the quotedPost
                    print("🔗 [FetchQuotePostView] Post fetched but has no meaningful content, falling back to LinkPreview: \(url)")
                    await MainActor.run {
                        self.isLoading = false
                        self.error = nil
                        // Leave quotedPost as nil so it falls through to LinkPreview
                    }
                }
            } else {
                // Post fetch returned nil - fallback to LinkPreview instead of error
                // This ensures the post still displays even if quote fetch fails
                print("🔗 [FetchQuotePostView] Post fetch returned nil, falling back to LinkPreview: \(url)")
                await MainActor.run {
                    self.isLoading = false
                    self.error = nil
                    // Leave quotedPost as nil so it falls through to LinkPreview
                }
            }

        } catch {
            print("🔗 [FetchQuotePostView] Error fetching post: \(error)")
            await MainActor.run {
                self.retryCount += 1
                self.isLoading = false
                self.error = error
            }

            // Retry with exponential backoff
            if retryCount <= maxRetries {
                let delay = min(pow(2.0, Double(retryCount)), 30.0)
                print("🔗 [FetchQuotePostView] Retrying in \(delay) seconds...")

                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await fetchPost()
            } else {
                // After max retries, fallback to LinkPreview instead of showing error
                // This ensures the post still displays
                print("🔗 [FetchQuotePostView] Max retries exceeded, falling back to LinkPreview")
                await MainActor.run {
                    self.isLoading = false
                    self.error = nil  // Clear error so it falls through to LinkPreview
                }
            }
        }
    }

    private func fetchBlueskyPost() async throws -> Post? {
        let components = url.path.split(separator: "/")
        
        // Bluesky URLs can be in different formats:
        // - https://bsky.app/profile/handle/post/postid (4+ components)
        // - https://handle.bsky.social/post/postid (2 components)
        // - at://did:plc:xxx/... (AT Protocol URI)
        
        var postID: String?
        
        // Try to find "post" in the path and get the ID after it
        if let postIndex = components.firstIndex(where: { $0 == "post" }),
           postIndex + 1 < components.count {
            postID = String(components[postIndex + 1])
        } else if components.count >= 2 {
            // Fallback: try last component as post ID
            postID = String(components[components.count - 1])
        }
        
        // Handle AT Protocol URIs (at://did:plc:xxx/app.bsky.feed.post/xxx)
        if url.scheme == "at" {
            let uriString = url.absoluteString
            if let postIdRange = uriString.range(of: "/app.bsky.feed.post/") {
                let postIdStart = uriString.index(postIdRange.upperBound, offsetBy: 0)
                postID = String(uriString[postIdStart...])
            }
        }
        
        guard let postID = postID, !postID.isEmpty else {
            print("🔗 [FetchQuotePostView] Could not extract post ID from URL: \(url)")
            throw NSError(
                domain: "FetchQuotePostView",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Bluesky post URL format: \(url.absoluteString)"]
            )
        }
        
        print("🔗 [FetchQuotePostView] Extracted Bluesky post ID: \(postID) from URL: \(url)")
        return try await serviceManager.fetchBlueskyPostByID(postID)
    }

    private func fetchMastodonPost() async throws -> Post? {
        let components = url.path.split(separator: "/")
        guard components.count >= 2 else {
            print("🔗 [FetchQuotePostView] Invalid Mastodon URL format: \(url)")
            throw NSError(
                domain: "FetchQuotePostView",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Mastodon post URL format: \(url.absoluteString)"]
            )
        }

        // Mastodon URLs are typically: /@handle/statuses/postid or /web/statuses/postid
        // The post ID is usually the last component
        let postID = String(components[components.count - 1])
        
        print("🔗 [FetchQuotePostView] Extracted Mastodon post ID: \(postID) from URL: \(url)")

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

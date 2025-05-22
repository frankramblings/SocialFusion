import AVKit
import Foundation
import LinkPresentation
import SwiftUI
import UIKit

// MARK: - Post Detail View
/// A detailed view for viewing a post with rich interactive elements
struct PostDetailView: View {
    let post: Post
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) private var colorScheme
    @State private var replyText = ""
    @State private var selectedMedia: Post.Attachment? = nil
    @State private var showMediaFullscreen = false
    @State private var replies: [Post] = []
    @State private var showingComposeSheet = false
    @State private var detectedLinks: [URL] = []
    @State private var isLoadingReplies = true
    @EnvironmentObject var serviceManager: SocialServiceManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Main post
                    VStack(alignment: .leading, spacing: 16) {
                        // Header
                        HStack(spacing: 12) {
                            PostAuthorImageView(
                                authorProfilePictureURL: post.authorProfilePictureURL,
                                platform: post.platform
                            )
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(post.authorName)
                                    .font(.headline)
                                    .fontWeight(.bold)

                                Text("@\(post.authorUsername)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            // Platform badge
                            PlatformBadge(platform: post.platform)
                        }
                        .padding(.horizontal)
                        .padding(.top)

                        // Created at date
                        Text(formattedDate)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        // Content
                        Text(attributedPostContent)
                            .font(.body)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.vertical, 8)

                        // Link previews
                        if !detectedLinks.isEmpty {
                            VStack(spacing: 12) {
                                // Filter out self-referential links
                                let filteredLinks = removeSelfReferences(
                                    links: detectedLinks, postURL: post.originalURL)

                                ForEach(filteredLinks, id: \.absoluteString) { url in
                                    if URLServiceWrapper.shared.isBlueskyPostURL(url)
                                        || URLServiceWrapper.shared.isMastodonPostURL(url)
                                    {
                                        // Show as quote post if it's a social media post URL
                                        FetchQuotePostView(url: url)
                                    } else {
                                        // Regular link preview
                                        LinkPreview(url: url)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }

                        // Media grid for attachments
                        if !post.attachments.isEmpty {
                            UnifiedMediaGridView(
                                attachments: post.attachments,
                                maxHeight: 220
                            )
                            .padding(.horizontal)
                            .padding(.bottom, 8)  // Add bottom padding
                        }

                        // Stats row (likes, reposts)
                        if post.likeCount > 0 || post.repostCount > 0 {
                            HStack(spacing: 24) {
                                if post.repostCount > 0 {
                                    HStack(spacing: 4) {
                                        Text("\(post.repostCount)")
                                            .font(.subheadline)
                                            .fontWeight(.medium)

                                        Text(post.repostCount == 1 ? "Repost" : "Reposts")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                if post.likeCount > 0 {
                                    HStack(spacing: 4) {
                                        Text("\(post.likeCount)")
                                            .font(.subheadline)
                                            .fontWeight(.medium)

                                        Text(post.likeCount == 1 ? "Like" : "Likes")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.top, 4)
                        }

                        // Action buttons row
                        HStack(spacing: 0) {
                            // Reply
                            Spacer()
                            Button(action: {
                                showingComposeSheet = true
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "bubble.left")
                                        .font(.system(size: 18))
                                    Text("Reply")
                                        .font(.caption)
                                }
                                .foregroundColor(.secondary)
                            }
                            Spacer()

                            // Repost
                            Button(action: {
                                Task {
                                    do {
                                        try await serviceManager.repostPost(post)
                                    } catch {
                                        print("Failed to repost: \(error)")
                                    }
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Image(
                                        systemName: post.isReposted
                                            ? "arrow.triangle.2.circlepath.fill"
                                            : "arrow.triangle.2.circlepath"
                                    )
                                    .font(.system(size: 18))
                                    Text("Repost")
                                        .font(.caption)
                                }
                                .foregroundColor(post.isReposted ? .green : .secondary)
                            }
                            Spacer()

                            // Like
                            Button(action: {
                                Task {
                                    do {
                                        try await serviceManager.likePost(post)
                                    } catch {
                                        print("Failed to like: \(error)")
                                    }
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: post.isLiked ? "heart.fill" : "heart")
                                        .font(.system(size: 18))
                                    Text("Like")
                                        .font(.caption)
                                }
                                .foregroundColor(post.isLiked ? .red : .secondary)
                            }
                            Spacer()

                            // Share
                            Button(action: {
                                if let url = URL(string: post.originalURL) {
                                    let av = UIActivityViewController(
                                        activityItems: [url], applicationActivities: nil)

                                    // Find the current window scene
                                    if let windowScene = UIApplication.shared.connectedScenes.first
                                        as? UIWindowScene,
                                        let rootVC = windowScene.windows.first?.rootViewController
                                    {
                                        av.popoverPresentationController?.sourceView = rootVC.view
                                        rootVC.present(av, animated: true)
                                    }
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 18))
                                    Text("Share")
                                        .font(.caption)
                                }
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            colorScheme == .dark
                                ? Color(UIColor.systemBackground)
                                : Color(UIColor.secondarySystemBackground)
                        )
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                    .background(
                        colorScheme == .dark
                            ? Color(UIColor.secondarySystemBackground).opacity(0.7) : Color.white
                    )
                    .cornerRadius(16)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)

                    // Visual separator between posts
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 12)

                    // Replies section with improved UI
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Replies")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top, 16)

                            Spacer()

                            if isLoadingReplies {
                                ProgressView()
                                    .padding(.trailing)
                            }
                        }

                        if replies.isEmpty {
                            if isLoadingReplies {
                                // Loading state already shown above
                                EmptyView()
                            } else {
                                // No replies state
                                VStack(spacing: 20) {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                colorScheme == .dark
                                                    ? Color(UIColor.tertiarySystemBackground)
                                                    : Color(UIColor.secondarySystemBackground)
                                            )
                                            .frame(width: 80, height: 80)

                                        Image(systemName: "bubble.left")
                                            .font(.system(size: 30))
                                            .foregroundColor(.gray)
                                    }

                                    Text("No replies yet")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)

                                    Button(action: {
                                        showingComposeSheet = true
                                    }) {
                                        Text("Be the first to reply")
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(Color.blue)
                                            .cornerRadius(16)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 30)
                            }
                        } else {
                            ForEach(replies) { reply in
                                ReplyView(reply: reply)
                                    .padding(.horizontal)
                                    .padding(.bottom, 8)
                            }
                        }
                    }
                    .background(
                        colorScheme == .dark
                            ? Color(UIColor.secondarySystemBackground).opacity(0.3)
                            : Color(UIColor.secondarySystemBackground).opacity(0.2)
                    )
                    .cornerRadius(16)
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 20)
            }
            .navigationBarTitle("Post", displayMode: .inline)
            .navigationBarItems(
                leading: Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(.primary)
                }
            )
            .onAppear {
                detectLinks()
                loadReplies()
            }
            .fullScreenCover(isPresented: $showMediaFullscreen) {
                if let selectedAttachment = selectedMedia {
                    if !post.attachments.isEmpty,
                        let selectedIndex = post.attachments.firstIndex(where: {
                            $0.url == selectedAttachment.url
                        })
                    {
                        // Pass all attachments and the selected index to create a gallery view
                        FullscreenMediaView(
                            attachments: post.attachments,
                            initialIndex: selectedIndex
                        )
                    } else {
                        // Fallback to single attachment view if index not found
                        FullscreenMediaView(attachment: selectedAttachment)
                    }
                }
            }
            .sheet(isPresented: $showingComposeSheet) {
                ComposeView(replyingTo: post)
                    .environmentObject(serviceManager)
            }
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: post.createdAt)
    }

    private var attributedPostContent: AttributedString {
        // Handle Mastodon HTML content differently
        if post.platform == .mastodon {
            // Use our contentView's HTML handling
            let htmlString = HTMLString(raw: post.content)
            var attributedString = htmlString.attributedStringFromHTML()

            // Ensure proper foreground color
            attributedString.foregroundColor = .primary

            // Use Dynamic Type styling
            attributedString.font = .body

            return attributedString
        }

        // For other platforms like Bluesky
        var attributedString = AttributedString(post.content)
        attributedString.foregroundColor = .primary

        // Use Dynamic Type styling
        attributedString.font = .body

        // Make mentions blue
        for mention in post.mentions {
            if let range = attributedString.range(of: "@\(mention)") {
                attributedString[range].foregroundColor = .blue
                attributedString[range].link = URL(string: "https://example.com/\(mention)")
            }
        }

        // Make hashtags green
        for tag in post.tags {
            if let range = attributedString.range(of: "#\(tag)") {
                attributedString[range].foregroundColor = .green
                attributedString[range].link = URL(string: "https://example.com/tag/\(tag)")
            }
        }

        return attributedString
    }

    private func detectLinks() {
        // Use the safer plainTextContent method for all posts
        let contentToSearch = post.plainTextContent

        // Parse content for clickable links
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        if let detector = detector,
            let matches = detector.matches(
                in: contentToSearch, options: [],
                range: NSRange(location: 0, length: contentToSearch.utf16.count))
                as? [NSTextCheckingResult]
        {
            detectedLinks = matches.compactMap { match -> URL? in
                if let url = match.url {
                    return url
                }
                return nil
            }
        }
    }

    private func loadReplies() {
        // This is a placeholder for actual reply loading logic
        isLoadingReplies = true

        // Simulate loading replies with a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isLoadingReplies = false
            // In a real implementation, this would fetch replies from the API
            // replies = fetchedReplies
        }
    }

    // Removes links that reference the post itself to avoid self-referential previews
    private func removeSelfReferences(links: [URL], postURL: String) -> [URL] {
        guard let postURL = URL(string: postURL) else { return links }

        return links.filter { url in
            // Don't show link preview for URLs that match the post itself
            let isSameURL =
                url.absoluteString.contains(postURL.absoluteString)
                || postURL.absoluteString.contains(url.absoluteString)

            return !isSameURL
        }
    }
}

// A compact view for replies
struct ReplyView: View {
    let reply: Post
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Author info
            HStack(spacing: 10) {
                PostAuthorImageView(
                    authorProfilePictureURL: reply.authorProfilePictureURL,
                    platform: reply.platform
                )
                .frame(width: 36, height: 36)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(reply.authorName)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("@\(reply.authorUsername)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(timeAgo(from: reply.createdAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Reply content
            reply.contentView(lineLimit: nil, showLinkPreview: false)
                .font(.body)  // Use system Dynamic Type
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            // Actions row
            HStack(spacing: 20) {
                Button(action: {}) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left")
                            .font(.caption2)
                        Text("Reply")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }

                Button(action: {}) {
                    HStack(spacing: 4) {
                        Image(systemName: reply.isLiked ? "heart.fill" : "heart")
                            .font(.caption2)
                        Text("Like")
                            .font(.caption2)
                    }
                    .foregroundColor(reply.isLiked ? .red : .secondary)
                }

                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    colorScheme == .dark
                        ? Color(UIColor.tertiarySystemBackground)
                        : Color(UIColor.secondarySystemBackground))
        )
    }
}

// Helper function for relative time
func timeAgo(from date: Date) -> String {
    let now = Date()
    let components = Calendar.current.dateComponents(
        [.second, .minute, .hour, .day, .weekOfYear, .month, .year], from: date, to: now)

    if let years = components.year, years > 0 {
        return years == 1 ? "1y" : "\(years)y"
    }

    if let months = components.month, months > 0 {
        return months == 1 ? "1mo" : "\(months)mo"
    }

    if let weeks = components.weekOfYear, weeks > 0 {
        return weeks == 1 ? "1w" : "\(weeks)w"
    }

    if let days = components.day, days > 0 {
        return days == 1 ? "1d" : "\(days)d"
    }

    if let hours = components.hour, hours > 0 {
        return hours == 1 ? "1h" : "\(hours)h"
    }

    if let minutes = components.minute, minutes > 0 {
        return minutes == 1 ? "1m" : "\(minutes)m"
    }

    if let seconds = components.second, seconds > 0 {
        return seconds == 1 ? "1s" : "\(seconds)s"
    }

    return "now"
}

// Link Preview Component
struct LinkPreview: View {
    let url: URL
    @State private var metadata: LPLinkMetadata?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var errorMessage: String? = nil
    @State private var validatedURL: URL
    @Environment(\.colorScheme) private var colorScheme
    @State private var isCancelled = false

    // Track cancellable task for better lifecycle management
    @State private var loadTask: Task<Void, Never>? = nil

    init(url: URL) {
        self.url = url
        // Validate and fix URL on initialization using the real URLService
        self._validatedURL = State(initialValue: URLService.shared.validateURL(url))
    }

    var body: some View {
        if isLoading {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 100)
                .frame(maxWidth: .infinity)
                .overlay(
                    ProgressView()
                )
                .onAppear {
                    loadMetadata()
                }
                .onDisappear {
                    // Cancel loading when view disappears
                    isCancelled = true
                    loadTask?.cancel()
                }
                .padding(.vertical, 4)
        } else if let metadata = metadata {
            Link(destination: validatedURL) {
                VStack(alignment: .leading, spacing: 8) {
                    // Image if available
                    if let imageProvider = metadata.imageProvider {
                        AsyncImageFromProvider(imageProvider: imageProvider)
                            .frame(height: 140)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .cornerRadius(8)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        // Title
                        if let title = metadata.title, !title.isEmpty {
                            Text(title)
                                .font(.callout)
                                .fontWeight(.medium)
                                .lineLimit(2)
                                .foregroundColor(.primary)
                        }

                        // Link URL as subtitle
                        Text(validatedURL.host ?? validatedURL.absoluteString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            colorScheme == .dark
                                ? Color(UIColor.secondarySystemBackground)
                                : Color(UIColor.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        } else if loadFailed {
            // Error state - simplified fallback
            Link(destination: validatedURL) {
                HStack(spacing: 12) {
                    Image(systemName: "link")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Color.gray.opacity(0.1))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(validatedURL.host ?? validatedURL.absoluteString)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Link")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            colorScheme == .dark
                                ? Color(UIColor.secondarySystemBackground)
                                : Color(UIColor.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // Helper to load metadata with improved error handling
    private func loadMetadata() {
        // Check if URL is valid for requests
        guard URLService.shared.isValidURLForRequest(validatedURL) else {
            markAsFailed(with: "Invalid or unsupported URL")
            return
        }

        // Create and store the loading task
        loadTask = Task {
            // First check if already cancelled
            if isCancelled {
                return
            }

            // Create a provider with shorter timeout
            let provider = LPMetadataProvider()
            provider.timeout = 5.0

            do {
                // Try to fetch metadata with timeout protection
                let metadata = try await withCheckedThrowingContinuation { continuation in
                    // Set up backup timeout
                    let timeoutWork = DispatchWorkItem {
                        if isLoading && !isCancelled {
                            continuation.resume(
                                throwing: NSError(
                                    domain: "com.socialfusion.link",
                                    code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Request timed out"]
                                ))
                        }
                    }

                    // Schedule timeout
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6.5, execute: timeoutWork)

                    // Start the actual fetch
                    provider.startFetchingMetadata(for: validatedURL) { metadata, error in
                        // Cancel timeout work since we got a response
                        timeoutWork.cancel()

                        if let error = error {
                            continuation.resume(throwing: error)
                            return
                        }

                        if let metadata = metadata {
                            continuation.resume(returning: metadata)
                        } else {
                            continuation.resume(
                                throwing: NSError(
                                    domain: "com.socialfusion.link",
                                    code: -2,
                                    userInfo: [NSLocalizedDescriptionKey: "No metadata available"]
                                ))
                        }
                    }
                }

                // If we reach here, we have metadata - update UI
                if !Task.isCancelled && !isCancelled {
                    await MainActor.run {
                        self.metadata = metadata
                        self.isLoading = false
                    }
                }
            } catch {
                if !Task.isCancelled && !isCancelled {
                    await MainActor.run {
                        markAsFailed(with: URLService.shared.friendlyErrorMessage(for: error))
                    }
                }
            }
        }
    }

    private func markAsFailed(with message: String? = nil) {
        isLoading = false
        loadFailed = true
        errorMessage = message
    }
}

struct PostDetailView_Previews: PreviewProvider {
    static var previews: some View {
        PostDetailView(post: Post.samplePosts[0])
            .environmentObject(SocialServiceManager())
    }
}

// Wrapper for URLService to access the methods needed in this file
private struct URLServiceWrapper {
    static let shared = URLServiceWrapper()

    private init() {}

    func isBlueskyPostURL(_ url: URL) -> Bool {
        guard let host = url.host else { return false }

        // Match bsky.app and bsky.social URLs
        let isBlueskyDomain = host.contains("bsky.app") || host.contains("bsky.social")

        // Check if it's a post URL pattern: /profile/{username}/post/{postId}
        let path = url.path
        let isPostURL = path.contains("/profile/") && path.contains("/post/")

        return isBlueskyDomain && isPostURL
    }

    func isMastodonPostURL(_ url: URL) -> Bool {
        guard let host = url.host else { return false }

        // Check for common Mastodon instances or pattern
        let isMastodonInstance =
            host.contains("mastodon.social") || host.contains("mastodon.online")
            || host.contains("mas.to") || host.contains("mastodon.world")
            || host.contains(".social")

        // Check if it matches Mastodon post URL pattern: /@username/postID
        let path = url.path
        let isPostURL = path.contains("/@") && path.split(separator: "/").count >= 3

        return isMastodonInstance && isPostURL
    }

    func validateURL(_ urlString: String) -> URL? {
        // First, try to create URL as-is
        guard var url = URL(string: urlString) else {
            // If initial creation fails, try percent encoding the string
            let encodedString = urlString.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed)
            return URL(string: encodedString ?? "")
        }

        return validateURL(url)
    }

    func validateURL(_ url: URL) -> URL {
        var fixedURL = url

        // Fix URLs with missing schemes
        if url.scheme == nil {
            if let urlWithScheme = URL(string: "https://" + url.absoluteString) {
                fixedURL = urlWithScheme
            }
        }

        // Fix the "www" hostname issue
        if url.host == "www" {
            if let correctedURL = URL(string: "https://www." + (url.path.trimmingPrefix("/"))) {
                return correctedURL
            }
        }

        // Fix "www/" hostname issue
        if let host = url.host, host.contains("www/") {
            let fixedHost = host.replacingOccurrences(of: "www/", with: "www.")
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.host = fixedHost
            if let fixedURL = components?.url {
                return fixedURL
            }
        }

        return fixedURL
    }

    func friendlyErrorMessage(for error: Error) -> String {
        let errorDescription = error.localizedDescription

        if errorDescription.contains("App Transport Security") {
            return "Site security issue"
        } else if errorDescription.contains("cancelled") {
            return "Request cancelled"
        } else if errorDescription.contains("network connection") {
            return "Network error"
        } else if errorDescription.contains("hostname could not be found") {
            return "Invalid hostname"
        } else if errorDescription.contains("timed out") {
            return "Request timed out"
        } else {
            // Truncate error message if too long
            let message = errorDescription
            return message.count > 40 ? message.prefix(40) + "..." : message
        }
    }
}

import Foundation
import SwiftUI
import UIKit  // Required for NSAttributedString
import WebKit

// Use the shared HTMLString and EmojiTextApp from Utilities/HTMLString.swift

// Add extension to String for repairedUTF8 (can be removed since we're not using it)
// extension String {
//     var repairedUTF8: String {
//         return self
//     }
// }

extension Post {
    /// Extract first URL from post content
    public var firstURL: URL? {
        let htmlString = HTMLString(raw: content)
        return htmlString.extractFirstURL
    }

    /// Extract plain text from HTML content for Mastodon posts
    public var plainTextContent: String {
        if platform == .mastodon {
            let htmlString = HTMLString(raw: content)
            return htmlString.plainText
        }
        return content
    }

    /// Creates an AttributedString with links for URLs and hashtags
    fileprivate func createTextWithLinks(from text: String) -> AttributedString {
        var attributedString = AttributedString(text)

        // Apply default styling that's guaranteed to be visible
        attributedString.font = .body
        attributedString.foregroundColor = .primary

        // Add link detection for URLs
        if let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue)
        {
            let nsString = text as NSString
            let matches = detector.matches(
                in: text, options: [],
                range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                if let url = match.url {
                    // Extract the URL text
                    let urlText = nsString.substring(with: match.range)

                    // Find this text in our AttributedString and make it a link
                    if let range = attributedString.range(of: urlText) {
                        attributedString[range].link = url
                        attributedString[range].foregroundColor = .accentColor
                    }
                }
            }
        }

        // Add hashtag detection
        let hashtagPattern = "#[\\w]+"
        if let regex = try? NSRegularExpression(pattern: hashtagPattern, options: []) {
            let nsString = text as NSString
            let matches = regex.matches(
                in: text, options: [],
                range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                // Extract the hashtag
                let hashtag = nsString.substring(with: match.range)
                let tagName = String(hashtag.dropFirst())  // Remove # symbol

                // Create a URL for the hashtag
                if let tagURL = URL(string: "socialfusion://tag/\(tagName)") {
                    // Find this hashtag in our AttributedString
                    if let range = attributedString.range(of: hashtag) {
                        attributedString[range].link = tagURL
                        attributedString[range].foregroundColor = .accentColor
                    }
                }
            }
        }

        // Add mention detection for Mastodon
        let mentionPattern = "@[\\w.]+"
        if let regex = try? NSRegularExpression(pattern: mentionPattern, options: []) {
            let nsString = text as NSString
            let matches = regex.matches(
                in: text, options: [],
                range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                // Extract the mention
                let mention = nsString.substring(with: match.range)
                let username = String(mention.dropFirst())  // Remove @ symbol

                // Create a URL for the mention
                if let mentionURL = URL(string: "socialfusion://user/\(username)") {
                    // Find this mention in our AttributedString
                    if let range = attributedString.range(of: mention) {
                        attributedString[range].link = mentionURL
                        attributedString[range].foregroundColor = .accentColor
                    }
                }
            }
        }

        return attributedString
    }

    /// Renders post content, handling Mastodon HTML & custom emoji.
    @ViewBuilder
    public func contentView(
        lineLimit: Int? = nil,
        showLinkPreview: Bool = true,
        font: Font = .body,
        onQuotePostTap: ((Post) -> Void)? = nil,
        allowTruncation: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ExpandableTextView(
                content: content,
                platform: platform,
                customEmoji: customEmoji,
                mentions: mentions,
                tags: tags,
                font: font,
                lineLimit: lineLimit,
                showLinkPreview: showLinkPreview,
                onQuotePostTap: onQuotePostTap,
                allowTruncation: allowTruncation,
                createTextWithLinksCallback: { text in
                    self.createTextWithLinks(from: text)
                },
                post: self
            )
        }
    }

    // MARK: - Private Views

    @ViewBuilder
    fileprivate func quotePostViews(onQuotePostTap: ((Post) -> Void)? = nil) -> some View {
        // 1. First check if we have a fully hydrated quoted post
        if let quotedPost = quotedPost {
            QuotedPostView(post: quotedPost) {
                if let onQuotePostTap = onQuotePostTap {
                    onQuotePostTap(quotedPost)
                }
            }
            .padding(.top, 8)
            .onAppear {
                print("🔗 [Post+ContentView] Displaying hydrated quoted post: \(quotedPost.id)")
                print("🔗 [Post+ContentView] Quoted post content: \(quotedPost.content.prefix(100))")
                print(
                    "🔗 [Post+ContentView] Quoted post attachments: \(quotedPost.attachments.count)")
                for (index, attachment) in quotedPost.attachments.enumerated() {
                    print(
                        "🔗 [Post+ContentView] Quote attachment \(index): \(attachment.url) (type: \(attachment.type))"
                    )
                }
            }
        }
        // 2. If no hydrated quote but have quote metadata, fetch it
        else if let quotedPostURL = (self as? BlueskyQuotedPostProvider)?.quotedPostURL {
            FetchQuotePostView(
                url: quotedPostURL,
                onQuotePostTap: onQuotePostTap
            )
            .padding(.top, 8)
            .onAppear {
                print("🔗 [Post+ContentView] Using FetchQuotePostView for URL: \(quotedPostURL)")
                print("🔗 [Post+ContentView] Parent post ID: \(self.id)")
                print("🔗 [Post+ContentView] quotedPostUri: \(self.quotedPostUri ?? "nil")")
                print(
                    "🔗 [Post+ContentView] quotedPostAuthorHandle: \(self.quotedPostAuthorHandle ?? "nil")"
                )
            }
        }
        // 3. Check for social media links that should be displayed as quotes
        else {
            let plainText = platform == .mastodon ? HTMLString(raw: content).plainText : content
            let allLinks = URLService.shared.extractLinks(from: plainText)
            let socialMediaLinks = allLinks.filter { URLService.shared.isSocialMediaPostURL($0) }

            if let firstSocialLink = socialMediaLinks.first {
                FetchQuotePostView(
                    url: firstSocialLink,
                    onQuotePostTap: onQuotePostTap
                )
                .padding(.top, 8)
                .onAppear {
                    print(
                        "🔗 [Post+ContentView] Displaying social media link as quote: \(firstSocialLink)"
                    )
                }
            } else {
                // Debug: Check if we have quote metadata but no URL
                EmptyView()
                    .onAppear {
                        // Enhanced debug logging for all posts
                        print(
                            "🔗 [Post+ContentView] DEBUG: Post \(self.id) - platform: \(self.platform)"
                        )
                        print(
                            "🔗 [Post+ContentView] DEBUG: quotedPost: \(self.quotedPost != nil ? "YES" : "NO")"
                        )
                        print(
                            "🔗 [Post+ContentView] DEBUG: quotedPostUri: \(self.quotedPostUri ?? "nil")"
                        )
                        print(
                            "🔗 [Post+ContentView] DEBUG: quotedPostAuthorHandle: \(self.quotedPostAuthorHandle ?? "nil")"
                        )
                        print(
                            "🔗 [Post+ContentView] DEBUG: content preview: \(self.content.prefix(100))"
                        )
                        print("🔗 [Post+ContentView] DEBUG: allLinks count: \(allLinks.count)")
                        print(
                            "🔗 [Post+ContentView] DEBUG: socialMediaLinks count: \(socialMediaLinks.count)"
                        )

                        // Debug logging for quote metadata issues (console only)
                        if self.platform == .bluesky {
                            if let uri = self.quotedPostUri,
                                let handle = self.quotedPostAuthorHandle
                            {
                                print(
                                    "🔗 [Post+ContentView] DEBUG: Have quote metadata but no URL - uri: \(uri), handle: \(handle)"
                                )
                            } else if self.quotedPostUri != nil
                                || self.quotedPostAuthorHandle != nil
                            {
                                print(
                                    "🔗 [Post+ContentView] DEBUG: Partial quote metadata - uri: \(self.quotedPostUri ?? "nil"), handle: \(self.quotedPostAuthorHandle ?? "nil")"
                                )
                            }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    fileprivate var regularLinkPreviewsOnly: some View {
        // Don't show link previews if the post has media attachments
        // This matches the behavior of Ivory, Bluesky, and other social apps
        if self.attachments.isEmpty {
            let plainText = platform == .mastodon ? HTMLString(raw: content).plainText : content
            let allLinks = URLService.shared.extractLinks(from: plainText)
            let socialMediaLinks = allLinks.filter { URLService.shared.isSocialMediaPostURL($0) }
            let youtubeLinks = allLinks.filter { URLService.shared.isYouTubeURL($0) }
            let regularLinks = allLinks.filter {
                !URLService.shared.isSocialMediaPostURL($0) && !URLService.shared.isYouTubeURL($0)
            }
            let firstYouTubeLink = youtubeLinks.first

            // Show first YouTube video as inline player
            if let firstYouTubeLink = firstYouTubeLink,
                let videoID = URLService.shared.extractYouTubeVideoID(from: firstYouTubeLink)
            {
                YouTubeVideoPreview(
                    url: firstYouTubeLink, videoID: videoID, idealHeight: 200, fullScreenHeight: 500
                )
                .padding(.top, 8)
                .onAppear {
                    print("🔗   Showing YouTube video: \(firstYouTubeLink)")
                }
            }

            // Show remaining links as previews (limit to first 2 for performance)
            // Exclude social media links and YouTube links as they're handled separately
            let excludedLinks = [socialMediaLinks.first, firstYouTubeLink].compactMap { $0 }
            let previewLinks = regularLinks.filter { link in
                !excludedLinks.contains(link)
            }

            ForEach(Array(previewLinks.prefix(2)), id: \.absoluteString) { url in
                StabilizedLinkPreview(url: url, idealHeight: 200)
                    .padding(.top, 8)
                    .onAppear {
                        print("🔗   Creating StabilizedLinkPreview for: \(url)")
                    }
            }
            .onAppear {
                // Debug logging for link detection
                print("🔗 [regularLinkPreviewsOnly] Post \(self.id) link analysis:")
                print("🔗   Platform: \(self.platform)")
                print("🔗   Content length: \(self.content.count)")
                print("🔗   Plain text length: \(plainText.count)")
                print("🔗   Content preview: '\(self.content.prefix(200))'")
                print("🔗   Plain text preview: '\(plainText.prefix(200))'")
                print("🔗   All links found: \(allLinks.count)")
                for (index, link) in allLinks.enumerated() {
                    print("🔗     [\(index)] \(link.absoluteString)")
                }
                print("🔗   Social media links: \(socialMediaLinks.count)")
                print("🔗   YouTube links: \(youtubeLinks.count)")
                print("🔗   Regular links: \(regularLinks.count)")
                print("🔗   Preview links after filtering: \(previewLinks.count)")
                for (index, link) in previewLinks.enumerated() {
                    print("🔗     Preview [\(index)] \(link.absoluteString)")
                }
            }
        } else {
            EmptyView()
                .onAppear {
                    print(
                        "🔗 [regularLinkPreviewsOnly] Post \(self.id) has \(self.attachments.count) attachments - suppressing link previews"
                    )
                }
        }
    }

    @ViewBuilder
    private var linkAndQuotePostViews: some View {
        // This method is now deprecated in favor of the separated approach above
        EmptyView()
    }
}

// Protocol for Bluesky official quote detection
private protocol BlueskyQuotedPostProvider {
    var quotedPostURL: URL? { get }
}

// MARK: - Bluesky Quoted Post Provider Implementation
extension Post: BlueskyQuotedPostProvider {
    var quotedPostURL: URL? {
        guard platform == .bluesky,
            let uri = quotedPostUri,
            let handle = quotedPostAuthorHandle
        else {
            if platform == .bluesky {
                print(
                    "🔗 [BlueskyQuotedPostProvider] Missing quote data - uri: \(quotedPostUri ?? "nil"), handle: \(quotedPostAuthorHandle ?? "nil")"
                )
            }
            return nil
        }

        let postId = uri.split(separator: "/").last ?? ""
        let urlString = "https://bsky.app/profile/\(handle)/post/\(postId)"
        print("🔗 [BlueskyQuotedPostProvider] Generated quote URL: \(urlString)")
        return URL(string: urlString)
    }
}

// MARK: - YouTube Video Preview Component

/// A component that displays YouTube videos as playable inline previews with enhanced UX
struct YouTubeVideoPreview: View {
    let url: URL
    let videoID: String
    let idealHeight: CGFloat
    let fullScreenHeight: CGFloat

    @State private var thumbnailURL: URL?
    @State private var isPlaying = false
    @State private var showWebView = false
    @State private var videoTitle: String?
    @State private var channelName: String?
    @State private var duration: String?
    @State private var viewCount: String?
    @State private var isLoadingMetadata = true
    @State private var thumbnailLoadFailed = false
    @Environment(\.colorScheme) private var colorScheme

    init(url: URL, videoID: String, idealHeight: CGFloat = 220, fullScreenHeight: CGFloat = 320) {
        self.url = url
        self.videoID = videoID
        self.idealHeight = idealHeight
        self.fullScreenHeight = fullScreenHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            if showWebView {
                ZStack(alignment: .topTrailing) {
                    YouTubeWebView(videoID: videoID, isPlaying: $isPlaying)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(height: idealHeight)
                        .cornerRadius(12)
                        .clipped()

                    // Enhanced close button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showWebView = false
                            isPlaying = false
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 32, height: 32)

                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(12)
                }
                .animation(.easeInOut(duration: 0.3), value: showWebView)
            } else {
                enhancedThumbnailView
                    .frame(height: idealHeight)
                    .cornerRadius(12)
                    .onTapGesture {
                        playVideo()
                    }
            }
        }
        .onAppear {
            loadVideoData()
        }
    }

    // MARK: - Enhanced Views

    private var enhancedThumbnailView: some View {
        ZStack {
            // Background thumbnail
            Group {
                if let thumbnailURL = thumbnailURL, !thumbnailLoadFailed {
                    AsyncImage(url: thumbnailURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure(let error):
                            fallbackThumbnail
                                .onAppear {
                                    thumbnailLoadFailed = true
                                    print(
                                        "[YouTube] AsyncImage failed for \(videoID): \(error.localizedDescription)"
                                    )
                                }
                        case .empty:
                            loadingThumbnail
                        @unknown default:
                            fallbackThumbnail
                                .onAppear {
                                    print("[YouTube] Unknown AsyncImage state for \(videoID)")
                                }
                        }
                    }
                } else if thumbnailURL == nil {
                    // Still testing thumbnail URLs
                    loadingThumbnail
                        .onAppear {
                            print("[YouTube] Testing thumbnail qualities for \(videoID)...")
                        }
                } else {
                    // All thumbnail qualities failed or thumbnailLoadFailed is true
                    fallbackThumbnail
                        .onAppear {
                            print("[YouTube] Using fallback thumbnail for \(videoID)")
                        }
                }
            }
            .clipped()

            // Enhanced gradient overlay for better text readability across more area
            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.1),
                    Color.black.opacity(0.4),
                    Color.black.opacity(0.7),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Content overlay
            VStack {
                Spacer()

                // Video info overlay with improved text layout
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        // YouTube logo
                        Image(systemName: "play.rectangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)

                        Text("YouTube")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 0.5)

                        Spacer()

                        // Duration badge
                        if let duration = duration {
                            Text(duration)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.7))
                                .cornerRadius(4)
                        }
                    }

                    // Video title with improved spacing and constraints
                    if let title = videoTitle {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .lineLimit(3)  // Increased from 2 to 3 lines
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)  // Allow text to expand vertically
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)  // Text shadow for better readability
                    } else if isLoadingMetadata {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.white)
                            Text("Loading video info...")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }

                    // Channel and view count
                    HStack {
                        if let channelName = channelName {
                            Text(channelName)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(1)
                                .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 0.5)
                        }

                        if let viewCount = viewCount {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 0.5)

                            Text(viewCount)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(1)
                                .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 0.5)
                        }
                    }
                }
                .padding(.horizontal, 16)  // Increased from 12 to 16 for better margins
                .padding(.vertical, 16)  // Increased vertical padding and made it symmetric
                .background(
                    // Dedicated text area gradient for maximum readability
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.1),
                            Color.black.opacity(0.6),
                            Color.black.opacity(0.9),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            // Play button overlay
            Button(action: playVideo) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 60, height: 60)

                    Image(systemName: "play.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.primary)
                        .offset(x: 2)  // Slight offset to center the play icon visually
                }
            }
            .scaleEffect(isPlaying ? 0.8 : 1.0)
            .opacity(isPlaying ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isPlaying)

            // Action buttons overlay (top-right)
            VStack {
                HStack {
                    Spacer()

                    Menu {
                        Button(action: openInYouTube) {
                            Label("Open in YouTube", systemImage: "arrow.up.right.square")
                        }

                        Button(action: shareVideo) {
                            Label("Share Video", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 32, height: 32)

                            Image(systemName: "ellipsis")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(12)

                Spacer()
            }
        }
        .background(Color.gray.opacity(0.2))
    }

    private var loadingThumbnail: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.2))

            VStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(1.2)

                Text("Loading video...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var fallbackThumbnail: some View {
        ZStack {
            // YouTube-themed gradient background
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.red.opacity(0.8),
                            Color.red.opacity(0.6),
                            Color.red.opacity(0.4),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 12) {
                // YouTube play button design
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 60, height: 60)

                    Image(systemName: "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.red)
                        .offset(x: 2)  // Slight offset for visual centering
                }

                VStack(spacing: 4) {
                    Text("YouTube Video")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    if let title = videoTitle {
                        Text(title)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(3)  // Increased from 2 to 3 lines for consistency
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)  // Allow text to expand vertically
                            .padding(.horizontal, 20)  // Slightly more padding for better readability
                    }

                    if let channelName = channelName {
                        Text(channelName)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.top, 2)
                    }
                }
            }
        }
    }

    // MARK: - Enhanced Functions

    private func loadVideoData() {
        // Load thumbnail with cascading fallback quality system
        loadThumbnailWithFallback()

        // Load enhanced video metadata
        loadEnhancedVideoMetadata()
    }

    private func loadThumbnailWithFallback() {
        // Try multiple thumbnail qualities in order of preference
        let qualities: [YouTubeThumbnailQuality] = [.high, .medium, .standard, .default]

        func tryNextQuality(_ index: Int = 0) {
            guard index < qualities.count else {
                // All qualities failed, use fallback
                print("[YouTube] All thumbnail qualities failed for video: \(videoID)")
                return
            }

            let quality = qualities[index]
            guard
                let testURL = URLService.shared.getYouTubeThumbnailURL(
                    videoID: videoID, quality: quality)
            else {
                tryNextQuality(index + 1)
                return
            }

            // Test if this thumbnail URL actually exists
            var request = URLRequest(url: testURL)
            request.httpMethod = "HEAD"  // Only check headers, don't download image data
            request.timeoutInterval = 5.0

            URLSession.shared.dataTask(with: request) { _, response, error in
                DispatchQueue.main.async {
                    if let httpResponse = response as? HTTPURLResponse,
                        httpResponse.statusCode == 200
                    {
                        // This quality works, use it
                        self.thumbnailURL = testURL
                        print(
                            "[YouTube] Using \(quality) quality thumbnail for video: \(self.videoID)"
                        )
                    } else {
                        // This quality failed, try next one
                        print(
                            "[YouTube] \(quality) quality failed for video: \(self.videoID), trying next..."
                        )
                        tryNextQuality(index + 1)
                    }
                }
            }.resume()
        }

        // Start the fallback process
        tryNextQuality()
    }

    private func loadEnhancedVideoMetadata() {
        // Use YouTube oEmbed API to get comprehensive video info
        let oEmbedURL = "https://www.youtube.com/oembed?url=\(url.absoluteString)&format=json"

        guard let apiURL = URL(string: oEmbedURL) else { return }

        URLSession.shared.dataTask(with: apiURL) { data, response, error in
            DispatchQueue.main.async {
                isLoadingMetadata = false

                guard let data = data,
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    // Fallback metadata
                    videoTitle = "YouTube Video"
                    channelName = "YouTube"
                    return
                }

                videoTitle = json["title"] as? String ?? "YouTube Video"
                channelName = json["author_name"] as? String ?? "YouTube"

                // Extract duration from thumbnail URL if available
                if let thumbnailUrl = json["thumbnail_url"] as? String {
                    // Sometimes duration info is embedded in the response
                    duration = extractDurationFromMetadata(json)
                }
            }
        }.resume()
    }

    private func extractDurationFromMetadata(_ json: [String: Any]) -> String? {
        // This is a simplified duration extraction
        // In a real app, you might want to use YouTube Data API for more detailed info
        return nil  // Placeholder - would need YouTube Data API key for accurate duration
    }

    private func playVideo() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showWebView = true
            isPlaying = true
        }
    }

    private func openInYouTube() {
        // Try to open in YouTube app first, then fallback to web
        let youtubeAppURL = URL(string: "youtube://watch?v=\(videoID)")

        if let youtubeAppURL = youtubeAppURL, UIApplication.shared.canOpenURL(youtubeAppURL) {
            UIApplication.shared.open(youtubeAppURL)
        } else {
            UIApplication.shared.open(url)
        }
    }

    private func shareVideo() {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first,
            let rootVC = window.rootViewController
        {

            // For iPad, set up popover presentation
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(
                    x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }

            rootVC.present(activityVC, animated: true)
        }
    }
}

/// Enhanced WebView for playing YouTube videos inline
struct YouTubeWebView: UIViewRepresentable {
    let videoID: String
    @Binding var isPlaying: Bool

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Enhanced configuration for better performance
        configuration.preferences.javaScriptEnabled = true
        configuration.allowsAirPlayForMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url == nil else { return }

        let embedHTML = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
                <style>
                    body { 
                        margin: 0; 
                        padding: 0; 
                        background: #000; 
                        overflow: hidden;
                    }
                    .video-container { 
                        position: relative; 
                        width: 100%; 
                        height: 100vh; 
                        display: flex;
                        align-items: center;
                        justify-content: center;
                    }
                    iframe { 
                        width: 100%; 
                        height: 100%; 
                        border: none; 
                        border-radius: 12px;
                    }
                </style>
            </head>
            <body>
                <div class="video-container">
                    <iframe 
                        src="https://www.youtube.com/embed/\(videoID)?autoplay=1&playsinline=1&rel=0&modestbranding=1&controls=1&showinfo=0&fs=1"
                        frameborder="0" 
                        allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" 
                        allowfullscreen>
                    </iframe>
                </div>
            </body>
            </html>
            """

        webView.loadHTMLString(embedHTML, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: YouTubeWebView

        init(_ parent: YouTubeWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isPlaying = true
        }

        func webView(
            _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
        ) {
            print("YouTube WebView failed to load: \(error.localizedDescription)")
            parent.isPlaying = false
        }
    }
}

// MARK: - Expandable Text View

struct ExpandableTextView: View {
    let content: String
    let platform: SocialPlatform
    let customEmoji: [String: URL]?
    let mentions: [String]?
    let tags: [String]?
    let font: Font
    let lineLimit: Int?
    let showLinkPreview: Bool
    let onQuotePostTap: ((Post) -> Void)?
    let allowTruncation: Bool
    let createTextWithLinksCallback: (String) -> AttributedString
    let post: Post

    @State private var isExpanded: Bool = false

    private var shouldTruncate: Bool {
        // Never truncate if allowTruncation is false (anchor post)
        guard allowTruncation else { return false }

        let plainText = platform == .mastodon ? HTMLString(raw: content).plainText : content
        return plainText.count > 500
    }

    private var displayContent: String {
        if shouldTruncate && !isExpanded {
            let plainText = platform == .mastodon ? HTMLString(raw: content).plainText : content
            let truncatedText = String(plainText.prefix(500))
            return platform == .mastodon ? truncatedText : truncatedText
        }
        return content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Use different text rendering based on platform
            if platform == .mastodon {
                // Mastodon: Use EmojiTextApp for HTML content with existing links
                EmojiTextApp(
                    htmlString: HTMLString(raw: displayContent),
                    customEmoji: customEmoji ?? [:],
                    font: font,
                    foregroundColor: .primary,
                    lineLimit: shouldTruncate && !isExpanded ? nil : lineLimit,
                    mentions: mentions ?? [],
                    tags: tags ?? []
                )
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                // Bluesky: Use createTextWithLinks for plain text with URL detection
                Text(createTextWithLinksCallback(displayContent))
                    .font(font)
                    .foregroundColor(.primary)
                    .lineLimit(shouldTruncate && !isExpanded ? nil : lineLimit)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Show More button
            if shouldTruncate && !isExpanded {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = true
                    }
                }) {
                    Text("SHOW MORE")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .textCase(.uppercase)
                        .tracking(0.3)
                }
                .buttonStyle(.plain)
            }

            // Always show quote posts, but respect showLinkPreview for other content
            post.quotePostViews(onQuotePostTap: onQuotePostTap)

            if showLinkPreview {
                post.regularLinkPreviewsOnly
            }
        }
    }
}

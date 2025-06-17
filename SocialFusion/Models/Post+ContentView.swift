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
    private func createTextWithLinks(from text: String) -> AttributedString {
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
        onQuotePostTap: ((Post) -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            EmojiTextApp(
                htmlString: HTMLString(raw: content),
                customEmoji: customEmoji,
                font: font,
                foregroundColor: .primary,
                lineLimit: lineLimit,
                mentions: mentions,
                tags: tags
            )
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)

            // Always show quote posts, but respect showLinkPreview for other content
            quotePostViews(onQuotePostTap: onQuotePostTap)

            if showLinkPreview {
                regularLinkPreviewsOnly
            }
        }
    }

    // MARK: - Private Views

    @ViewBuilder
    private func quotePostViews(onQuotePostTap: ((Post) -> Void)? = nil) -> some View {
        // 1. First check if we have a fully hydrated quoted post
        if let quotedPost = quotedPost {
            QuotedPostView(post: quotedPost) {
                if let onQuotePostTap = onQuotePostTap {
                    onQuotePostTap(quotedPost)
                }
            }
            .padding(.top, 8)
        }
        // 2. If no hydrated quote but have quote metadata, fetch it
        else if let quotedPostURL = (self as? BlueskyQuotedPostProvider)?.quotedPostURL {
            FetchQuotePostView(
                url: quotedPostURL,
                onQuotePostTap: onQuotePostTap
            )
            .padding(.top, 8)
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
    private var regularLinkPreviewsOnly: some View {
        let plainText = platform == .mastodon ? HTMLString(raw: content).plainText : content
        let allLinks = URLService.shared.extractLinks(from: plainText)
        let socialMediaLinks = allLinks.filter { URLService.shared.isSocialMediaPostURL($0) }
        let youtubeLinks = allLinks.filter { URLService.shared.isYouTubeURL($0) }
        let regularLinks = allLinks.filter {
            !URLService.shared.isSocialMediaPostURL($0) && !URLService.shared.isYouTubeURL($0)
        }
        let firstYouTubeLink = youtubeLinks.first

        // Debug logging
        EmptyView()
            .onAppear {
                print("🔗 [regularLinkPreviewsOnly] DEBUG for post: \(self.id)")
                print("🔗 [regularLinkPreviewsOnly] Platform: \(self.platform)")
                print("🔗 [regularLinkPreviewsOnly] Content: \(self.content)")
                print("🔗 [regularLinkPreviewsOnly] PlainText: \(plainText)")
                print("🔗 [regularLinkPreviewsOnly] All links: \(allLinks)")
                print("🔗 [regularLinkPreviewsOnly] Social media links: \(socialMediaLinks)")
                print("🔗 [regularLinkPreviewsOnly] YouTube links: \(youtubeLinks)")
                print("🔗 [regularLinkPreviewsOnly] Regular links: \(regularLinks)")
            }

        // Show first YouTube video as inline player
        if let firstYouTubeLink = firstYouTubeLink,
            let videoID = URLService.shared.extractYouTubeVideoID(from: firstYouTubeLink)
        {
            YouTubeVideoPreview(
                url: firstYouTubeLink, videoID: videoID, idealHeight: 200, fullScreenHeight: 500
            )
            .padding(.top, 8)
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
                    print("🔗 [regularLinkPreviewsOnly] Showing link preview for: \(url)")
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

    init(url: URL, videoID: String, idealHeight: CGFloat = 200, fullScreenHeight: CGFloat = 300) {
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
                        case .failure(_):
                            fallbackThumbnail
                                .onAppear { thumbnailLoadFailed = true }
                        case .empty:
                            loadingThumbnail
                        @unknown default:
                            fallbackThumbnail
                        }
                    }
                } else {
                    fallbackThumbnail
                }
            }
            .clipped()

            // Gradient overlay for better text readability
            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.3),
                    Color.black.opacity(0.6),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Content overlay
            VStack {
                Spacer()

                // Video info overlay
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        // YouTube logo
                        Image(systemName: "play.rectangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)

                        Text("YouTube")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)

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

                    // Video title
                    if let title = videoTitle {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
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
                        }

                        if let viewCount = viewCount {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))

                            Text(viewCount)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
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
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.red.opacity(0.3), Color.red.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 8) {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 40))
                    .foregroundColor(.red)

                Text("YouTube Video")
                    .font(.headline)
                    .foregroundColor(.primary)

                if let title = videoTitle {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Enhanced Functions

    private func loadVideoData() {
        // Load high-quality thumbnail
        thumbnailURL =
            URLService.shared.getYouTubeThumbnailURL(videoID: videoID, quality: .maxres)
            ?? URLService.shared.getYouTubeThumbnailURL(videoID: videoID, quality: .high)

        // Load enhanced video metadata
        loadEnhancedVideoMetadata()
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

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
    public func contentView(lineLimit: Int? = nil, showLinkPreview: Bool = true, font: Font = .body)
        -> some View
    {
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

            // Simplified quote post and link preview logic
            if showLinkPreview {
                linkAndQuotePostViews
            }
        }
    }

    // MARK: - Private Views

    @ViewBuilder
    private var linkAndQuotePostViews: some View {
        // 1. First check if we have a fully hydrated quoted post
        if let quotedPost = quotedPost {
            QuotedPostView(post: quotedPost)
                .padding(.top, 8)
        }
        // 2. If no hydrated quote but have quote metadata, fetch it
        else if let quotedPostURL = (self as? BlueskyQuotedPostProvider)?.quotedPostURL {
            FetchQuotePostView(url: quotedPostURL)
                .padding(.top, 8)
        }
        // 3. Otherwise, check for post links and regular links in content
        else {
            contentLinksView
        }
    }

    @ViewBuilder
    private var contentLinksView: some View {
        let plainText = platform == .mastodon ? HTMLString(raw: content).plainText : content
        let allLinks = URLService.shared.extractLinks(from: plainText)
        let socialMediaLinks = allLinks.filter { URLService.shared.isSocialMediaPostURL($0) }
        let youtubeLinks = allLinks.filter { URLService.shared.isYouTubeURL($0) }
        let regularLinks = allLinks.filter {
            !URLService.shared.isSocialMediaPostURL($0) && !URLService.shared.isYouTubeURL($0)
        }
        let firstSocialLink = socialMediaLinks.first
        let firstYouTubeLink = youtubeLinks.first

        // Show first social media post as quote
        if let firstSocialLink = firstSocialLink {
            FetchQuotePostView(url: firstSocialLink)
                .padding(.top, 8)
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
        // Exclude the first social link and first YouTube link if they were already shown
        let excludedLinks = [firstSocialLink, firstYouTubeLink].compactMap { $0 }
        let previewLinks = regularLinks.filter { link in
            !excludedLinks.contains(link)
        }

        ForEach(Array(previewLinks.prefix(2)), id: \.absoluteString) { url in
            StabilizedLinkPreview(url: url, idealHeight: 200)
                .padding(.top, 8)
        }
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
            return nil
        }

        let postId = uri.split(separator: "/").last ?? ""
        return URL(string: "https://bsky.app/profile/\(handle)/post/\(postId)")
    }
}

// MARK: - YouTube Video Preview Component

/// A component that displays YouTube videos as playable inline previews
struct YouTubeVideoPreview: View {
    let url: URL
    let videoID: String
    let idealHeight: CGFloat
    let fullScreenHeight: CGFloat

    @State private var thumbnailURL: URL?
    @State private var isPlaying = false
    @State private var showWebView = false
    @State private var videoTitle: String?
    @State private var isLoadingMetadata = true
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

                    // Close button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showWebView = false
                            isPlaying = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding(8)
                }
                .animation(.easeInOut(duration: 0.3), value: showWebView)
            } else {
                thumbnailView
                    .frame(height: idealHeight)
                    .cornerRadius(12)
                    .onTapGesture {
                        playVideo()
                    }
            }

            if let title = videoTitle {
                videoInfoView(title: title)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
        .onAppear {
            loadVideoData()
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack {
            // Thumbnail image
            if let thumbnailURL = thumbnailURL {
                AsyncImage(url: thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(16 / 9, contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: idealHeight)
                            .clipped()
                    case .failure(_):
                        thumbnailPlaceholder
                    case .empty:
                        thumbnailPlaceholder
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.8)
                            )
                    @unknown default:
                        thumbnailPlaceholder
                    }
                }
            } else {
                thumbnailPlaceholder
            }

            // Play button overlay
            playButtonOverlay
        }
    }

    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .overlay(
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
            )
    }

    private var playButtonOverlay: some View {
        ZStack {
            // Semi-transparent background
            Circle()
                .fill(Color.black.opacity(0.7))
                .frame(width: 60, height: 60)

            // YouTube-style play button
            Image(systemName: "play.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .offset(x: 2)  // Slight offset to center the triangle visually
        }
        .scaleEffect(isPlaying ? 0.9 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPlaying)
    }

    private func videoInfoView(title: String) -> some View {
        HStack(spacing: 8) {
            // YouTube logo
            Image(systemName: "play.rectangle.fill")
                .foregroundColor(.red)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundColor(.primary)

                Text("YouTube")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // External link indicator
            Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.clear)
        .onTapGesture {
            openInYouTube()
        }
    }

    private func loadVideoData() {
        // Load thumbnail
        thumbnailURL = URLService.shared.getYouTubeThumbnailURL(videoID: videoID, quality: .high)

        // Load video metadata (title, etc.)
        loadVideoMetadata()
    }

    private func loadVideoMetadata() {
        // Use YouTube oEmbed API to get video title
        let oEmbedURL = "https://www.youtube.com/oembed?url=\(url.absoluteString)&format=json"

        guard let apiURL = URL(string: oEmbedURL) else { return }

        URLSession.shared.dataTask(with: apiURL) { data, response, error in
            DispatchQueue.main.async {
                isLoadingMetadata = false

                guard let data = data,
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let title = json["title"] as? String
                else {
                    // Fallback title
                    videoTitle = "YouTube Video"
                    return
                }

                videoTitle = title
            }
        }.resume()
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
}

/// WebView for playing YouTube videos inline
struct YouTubeWebView: UIViewRepresentable {
    let videoID: String
    @Binding var isPlaying: Bool

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
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
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <style>
                    body { margin: 0; padding: 0; background: transparent; }
                    .video-container { position: relative; width: 100%; height: 100%; }
                    iframe { width: 100%; height: 100%; border: none; }
                </style>
            </head>
            <body>
                <div class="video-container">
                    <iframe 
                        src="https://www.youtube.com/embed/\(videoID)?autoplay=1&playsinline=1&rel=0&modestbranding=1"
                        frameborder="0" 
                        allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" 
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
    }
}

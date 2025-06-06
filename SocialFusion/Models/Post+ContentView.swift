import Foundation
import SwiftUI
import UIKit  // Required for NSAttributedString

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
                .padding(.top, 4)
        }
        // 2. If no hydrated quote but have quote metadata, fetch it
        else if let quotedPostURL = (self as? BlueskyQuotedPostProvider)?.quotedPostURL {
            FetchQuotePostView(url: quotedPostURL)
                .padding(.top, 4)
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
        let regularLinks = allLinks.filter { !URLService.shared.isSocialMediaPostURL($0) }
        let firstSocialLink = socialMediaLinks.first

        // Show first social media post as quote
        if let firstSocialLink = firstSocialLink {
            FetchQuotePostView(url: firstSocialLink)
                .padding(.top, 4)
        }

        // Show remaining links as previews (limit to first 2 for performance)
        let previewLinks =
            firstSocialLink != nil ? Array(regularLinks.prefix(2)) : Array(allLinks.prefix(2))

        ForEach(previewLinks, id: \.absoluteString) { url in
            LinkPreview(url: url)
                .padding(.top, 4)
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

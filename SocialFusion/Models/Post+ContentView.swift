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

            // --- Quote Post Logic (Priority Order) ---
            if showLinkPreview {
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
                // 3. Otherwise, check for post links in content and fetch the first one
                else {
                    let htmlString = HTMLString(raw: content)
                    let allLinks = extractAllLinks(from: htmlString.plainText)
                    let postLinks = allLinks.filter {
                        isSocialMediaPostURL($0) && !isHashtagOrMentionURL($0)
                    }
                    if let firstPostLink = postLinks.first {
                        FetchQuotePostView(url: firstPostLink)
                            .padding(.top, 4)
                    }

                    // 4. Render all other links as regular link previews
                    let previewLinks = allLinks.filter { url in
                        !isHashtagOrMentionURL(url) && !postLinks.contains(url)
                    }
                    ForEach(previewLinks, id: \.absoluteString) { url in
                        LinkPreview(url: url)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }

    /// Helper method to determine if a URL is a hashtag or mention
    private func isHashtagOrMentionURL(_ url: URL) -> Bool {
        // Check for our custom socialfusion scheme for hashtags and mentions
        if url.scheme == "socialfusion" {
            return url.host == "tag" || url.host == "user"
        }

        // Check for URLs that are just fragment identifiers
        let urlString = url.absoluteString.lowercased()
        if urlString.hasPrefix("#") || urlString.hasPrefix("@") {
            return true
        }

        // Check for Mastodon/Bluesky profile URLs
        // Examples:
        // - https://instance.social/@username
        // - https://instance.social/users/username
        // - https://bsky.app/profile/username
        let path = url.path.lowercased()
        if path.hasPrefix("/@") || path.hasPrefix("/users/") || path.hasPrefix("/profile/") {
            return true
        }

        // Check for Mastodon-style hashtag URLs
        if url.pathComponents.contains("tags") || url.pathComponents.contains("tag")
            || url.path.contains("/hashtag/")
        {
            return true
        }

        // Additional check for hashtag domains that might be mistakenly treated as URLs
        if let host = url.host?.lowercased() {
            let commonHashtagWords = [
                "workingclass", "laborhistory", "genocide", "dictatorship",
                "humanrights", "freespeech", "uprising", "actuallyautistic",
                "germany", "gaza", "mastodon",
            ]
            for word in commonHashtagWords {
                if host == word || host.hasPrefix(word + ".") {
                    return true
                }
            }
        }
        return false
    }

    /// Helper method to determine if a URL is a social media post
    private func isSocialMediaPostURL(_ url: URL) -> Bool {
        let urlString = url.absoluteString.lowercased()
        let path = url.path

        // Check for Bluesky post URLs (must have both profile and post components)
        if urlString.contains("bsky.app") || urlString.contains("bsky.social") {
            // Must contain both profile and post in the path: /profile/{username}/post/{postId}
            let hasProfileAndPost = path.contains("/profile/") && path.contains("/post/")

            // Don't treat it as a post URL if it's just a profile
            if path.contains("/profile/") && !path.contains("/post/") {
                return false
            }

            return hasProfileAndPost
        }

        // Check for Mastodon post URLs - this requires a numeric ID at the end
        if url.host?.contains(".social") == true || url.host?.contains("mastodon") == true
            || url.host?.contains("mas.to") == true
        {
            // Must match pattern: /@username/numeric_status_id or /users/username/statuses/numeric_id
            let components = path.split(separator: "/")

            // Don't treat it as a post URL if it's just a profile
            if path.contains("/@") && components.count < 3 {
                return false
            }

            // Check if last component is numeric (status ID)
            if components.count >= 3 {
                // Last component should be a numeric ID
                let lastComponent = components.last!
                return lastComponent.allSatisfy { $0.isNumber }
            }
        }

        return false
    }

    // Helper to extract all links from text (preserves hashtag filtering)
    private func extractAllLinks(from text: String) -> [URL] {
        let hashtagRegex = try? NSRegularExpression(pattern: "#\\w+", options: [])
        var processedText = text
        if let regex = hashtagRegex {
            processedText = regex.stringByReplacingMatches(
                in: processedText,
                options: [],
                range: NSRange(location: 0, length: processedText.utf16.count),
                withTemplate: ""
            )
        }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches =
            detector?.matches(
                in: processedText,
                options: [],
                range: NSRange(location: 0, length: processedText.utf16.count)
            ) ?? []
        // Gather mention and tag URLs from the API (if available)
        let mentionURLs = mentions.compactMap { URL(string: $0) }
        let tagURLs = tags.compactMap { URL(string: $0) }
        return matches.compactMap { match in
            guard let url = match.url else { return nil }
            // Only allow http/https
            guard url.scheme == "http" || url.scheme == "https" else { return nil }
            // Exclude if this URL matches any mention or tag from the API
            if mentionURLs.contains(url) || tagURLs.contains(url) {
                return nil
            }
            // Exclude handles, hashtags, and any mention/profile/hashtag URL
            if isHashtagOrMentionURL(url) {
                return nil
            }
            return url
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
        guard platform == .bluesky, let uri = quotedPostUri, let handle = quotedPostAuthorHandle
        else { return nil }
        let postId = uri.split(separator: "/").last ?? ""
        return URL(string: "https://bsky.app/profile/\(handle)/post/\(postId)")
    }
}

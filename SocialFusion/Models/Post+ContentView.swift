import SwiftUI
import UIKit  // Required for NSAttributedString

// MARK: - HTML String Handling
/// A utility class to handle HTML string content from social media posts
private class HTMLString {
    /// The raw HTML content
    let raw: String

    /// Repaired UTF8 version of the raw content
    var repairedUTF8: String {
        return raw
    }

    /// Plain text version with HTML tags removed but preserving line breaks
    var plainText: String {
        // First replace <br> and <p> tags with proper line breaks
        let withLineBreaks =
            raw
            .replacingOccurrences(of: "<br\\s*/*>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<p>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "<span[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "</span>", with: "", options: .regularExpression)

        // Clean up anchor tags but preserve the text content
        // Extract href URLs for later use if needed
        var cleanedText = withLineBreaks
        let anchorPattern = "<a[^>]*href=[\"']([^\"']*)[\"'][^>]*>(.*?)</a>"
        if let regex = try? NSRegularExpression(
            pattern: anchorPattern, options: [.dotMatchesLineSeparators])
        {
            let range = NSRange(cleanedText.startIndex..<cleanedText.endIndex, in: cleanedText)
            cleanedText = regex.stringByReplacingMatches(
                in: cleanedText,
                options: [],
                range: range,
                withTemplate: "$2"
            )
        }

        // Then strip remaining HTML tags
        cleanedText = cleanedText.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression)

        // Clean up HTML entities
        return
            cleanedText
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            // Clean up excess newlines
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract the first URL from the HTML content
    var extractFirstURL: URL? {
        // Look for href in the HTML first
        let hrefPattern = "href=[\"']([^\"']*)[\"']"
        if let regex = try? NSRegularExpression(pattern: hrefPattern, options: []) {
            let nsString = raw as NSString
            let matches = regex.matches(
                in: raw, options: [],
                range: NSRange(location: 0, length: nsString.length))

            // Return the first href URL that's not a hashtag
            for match in matches where match.numberOfRanges > 1 {
                let urlRange = match.range(at: 1)
                let urlString = nsString.substring(with: urlRange)

                // Skip obvious hashtag URLs
                if urlString.contains("/tags/") || urlString.contains("/tag/")
                    || urlString.hasPrefix("#") || urlString.contains("/hashtag/")
                {
                    continue
                }

                if let url = URL(string: urlString) {
                    // Skip if it's a hashtag URL
                    if isHashtagOrMentionURL(url) {
                        continue
                    }
                    return url
                }
            }
        }

        // Fallback to plain text URL detection
        if let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue)
        {
            let plainText = self.plainText
            let matches = detector.matches(
                in: plainText, options: [], range: NSRange(location: 0, length: plainText.count))

            // Skip any hashtags first
            let hashtags = getHashtags(from: plainText)

            // Process all detected URLs
            for match in matches {
                if let url = match.url {
                    // Skip if the URL is one of our hashtags
                    let urlString = url.absoluteString.lowercased()
                    if hashtags.contains(where: { urlString.contains($0.lowercased()) }) {
                        continue
                    }

                    // Skip if it's a hashtag URL
                    if isHashtagOrMentionURL(url) {
                        continue
                    }

                    return url
                }
            }
        }

        return nil
    }

    /// Extract hashtags from text
    private func getHashtags(from text: String) -> [String] {
        let hashtagPattern = "#[\\w]+"
        var hashtags: [String] = []

        if let regex = try? NSRegularExpression(pattern: hashtagPattern, options: []) {
            let nsString = text as NSString
            let matches = regex.matches(
                in: text, options: [],
                range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                let hashtagRange = match.range
                let hashtag = nsString.substring(with: hashtagRange)
                hashtags.append(hashtag)
            }
        }

        return hashtags
    }

    /// Convert HTML to AttributedString for proper rendering
    func attributedStringFromHTML() -> AttributedString {
        // Clean the HTML
        let cleanHTML = cleanHTMLForRendering(raw)

        // Convert to NSAttributedString using native HTML parser
        guard let data = cleanHTML.data(using: .utf8) else {
            return AttributedString(raw)
        }

        do {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ]

            let attributedString = try NSAttributedString(
                data: data, options: options, documentAttributes: nil)

            // Convert to AttributedString
            var result = AttributedString(attributedString)

            // Let the system handle Dynamic Type instead of hardcoding
            result.font = .body

            return result
        } catch {
            print("Error parsing HTML: \(error)")
            return AttributedString(plainText)
        }
    }

    /// Helper function to clean HTML content for rendering
    private func cleanHTMLForRendering(_ html: String) -> String {
        // Handle common HTML tags and styling
        var cleanHTML =
            html
            .replacingOccurrences(of: "<p>", with: "<div>")
            .replacingOccurrences(of: "</p>", with: "</div>")

        // Get system color scheme to decide text color - ensure this happens on main thread
        let isDarkMode: Bool
        if Thread.isMainThread {
            isDarkMode = UITraitCollection.current.userInterfaceStyle == .dark
        } else {
            // When called from background thread, use a safer default
            // or dispatch to main for UI trait access
            var darkMode = false
            DispatchQueue.main.sync {
                darkMode = UITraitCollection.current.userInterfaceStyle == .dark
            }
            isDarkMode = darkMode
        }

        let textColor = isDarkMode ? "white" : "black"
        let linkColor = isDarkMode ? "#1DA1F2" : "#1DA1F2"  // Keep links blue regardless of theme

        // Improve link styling and ensure they're clickable
        cleanHTML =
            cleanHTML
            .replacingOccurrences(
                of: "<a href=",
                with: "<a style=\"color: \(linkColor); text-decoration: underline;\" href="
            )

        // Wrap in a div with styling for proper rendering - we don't set explicit font size
        // to allow Dynamic Type to control sizing through the AttributedString
        cleanHTML =
            "<div style=\"font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: \(textColor);\">\(cleanHTML)</div>"

        return cleanHTML
    }

    /// Initialize with raw HTML content
    init(raw: String) {
        self.raw = raw
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

        // Check for Mastodon-style hashtag URLs
        // Examples:
        // - https://instance.social/tags/hashtag
        // - https://mastodon.social/tags/trending
        if url.pathComponents.contains("tags") || url.pathComponents.contains("tag")
            || url.path.contains("/hashtag/")
        {
            return true
        }

        // Check for profile URLs which should be treated as mentions
        if url.path.contains("/profile/") || url.path.contains("/@") || url.path.contains("/users/")
        {
            return true
        }

        // Additional check for hashtag domains that might be mistakenly treated as URLs
        if let host = url.host?.lowercased() {
            // Common words that often appear in hashtags but shouldn't be treated as domains
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
}

// Add extension to String for repairedUTF8 (can be removed since we're not using it)
// extension String {
//     var repairedUTF8: String {
//         return self
//     }
// }

/// A custom text component for rendering HTML content with emoji support
private struct EmojiTextApp: View {
    let htmlString: HTMLString
    let customEmoji: [String: URL]?
    var font: Font = .body
    var foregroundColor: Color = .primary
    private var lineLimit: Int?

    init(htmlString: HTMLString, customEmoji: [String: URL]? = nil) {
        self.htmlString = htmlString
        self.customEmoji = customEmoji
    }

    /// Set font for the text
    func font(_ font: Font) -> EmojiTextApp {
        var copy = self
        copy.font = font
        return copy
    }

    /// Set text color
    func foregroundColor(_ color: Color) -> EmojiTextApp {
        var copy = self
        copy.foregroundColor = color
        return copy
    }

    /// Set line limit
    func lineLimit(_ limit: Int?) -> EmojiTextApp {
        var copy = self
        copy.lineLimit = limit
        return copy
    }

    var body: some View {
        // Basic implementation that uses plainText as fallback
        Text(htmlString.plainText)
            .font(font)
            .foregroundColor(foregroundColor)
            .lineLimit(lineLimit)
    }
}

extension Post {
    fileprivate var customEmoji: [String: URL]? {
        // For now, we return nil, but in a full implementation
        // this would return platform-specific emoji mappings
        return nil
    }

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
    public func contentView(lineLimit: Int? = nil, showLinkPreview: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch platform {
            case .mastodon:
                // Use built-in HTML to AttributedString conversion for Mastodon
                let htmlString = HTMLString(raw: content)
                let attributedContent = htmlString.attributedStringFromHTML()

                Text(attributedContent)
                    .font(.body)  // Use Dynamic Type instead of hardcoded size
                    .foregroundColor(.primary)
                    .lineLimit(lineLimit)
                    // Prevent automatic dynamic type adjustments which could cause threading issues
                    .fixedSize(horizontal: false, vertical: true)
            default:
                // For Bluesky and other platforms
                let attributed = createTextWithLinks(from: content)
                Text(attributed)
                    .font(.body)  // Use Dynamic Type instead of hardcoded size
                    .foregroundColor(.primary)
                    .lineLimit(lineLimit)
                    // Prevent automatic dynamic type adjustments which could cause threading issues
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Show link preview if enabled and URL exists
            if showLinkPreview, let url = firstURL, !isHashtagOrMentionURL(url) {
                // Check if it's a social media post URL
                if isSocialMediaPostURL(url) {
                    // For social media posts, show a quote post view
                    FetchQuotePostView(url: url)
                        .padding(.top, 4)
                } else {
                    // For regular links, show the standard link preview
                    LinkPreview(url: url)
                        .padding(.top, 4)
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

        // Check for Mastodon-style hashtag URLs
        // Examples:
        // - https://instance.social/tags/hashtag
        // - https://mastodon.social/tags/trending
        if url.pathComponents.contains("tags") || url.pathComponents.contains("tag")
            || url.path.contains("/hashtag/")
        {
            return true
        }

        // Check for profile URLs which should be treated as mentions
        if url.path.contains("/profile/") || url.path.contains("/@") || url.path.contains("/users/")
        {
            return true
        }

        // Additional check for hashtag domains that might be mistakenly treated as URLs
        if let host = url.host?.lowercased() {
            // Common words that often appear in hashtags but shouldn't be treated as domains
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
}

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
        // First replace <br> and </p> with markers
        let withLineBreaks =
            raw
            .replacingOccurrences(of: "<br\\s*/*>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)

        // Then strip remaining HTML tags
        return
            withLineBreaks
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            // Clean up HTML entities
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
        // Use NSDataDetector to find URLs in the plain text
        if let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue)
        {
            let plainText = self.plainText
            let matches = detector.matches(
                in: plainText, options: [], range: NSRange(location: 0, length: plainText.count))

            // Return the first detected URL
            if let match = matches.first, let url = match.url {
                return url
            }
        }
        return nil
    }

    /// Initialize with raw HTML content
    init(raw: String) {
        self.raw = raw
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

        return attributedString
    }

    /// Renders post content, handling Mastodon HTML & custom emoji.
    @ViewBuilder
    public func contentView(lineLimit: Int? = nil, showLinkPreview: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch platform {
            case .mastodon:
                // Get plain text with line breaks preserved
                let plainText = HTMLString(raw: content).plainText

                // Create AttributedString with clickable links and hashtags
                let attributed = createTextWithLinks(from: plainText)

                Text(attributed)
                    .font(.body)
                    .foregroundColor(.primary)  // Reinforces visible text
                    .lineLimit(lineLimit)
            default:
                Text(content)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(lineLimit)
            }

            // Show link preview if enabled and URL exists
            if showLinkPreview, let url = firstURL {
                LinkPreview(url: url)
                    .padding(.top, 4)
            }
        }
    }
}

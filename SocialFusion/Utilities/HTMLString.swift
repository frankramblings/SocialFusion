import Foundation
import SwiftUI
import UIKit
import EmojiText

/// A utility class to handle HTML string content from social media posts
public class HTMLString {
    /// The raw HTML content
    public let raw: String

    /// UTF8 encoding corrected version of the raw string
    public var repairedUTF8: Data {
        return Data(raw.utf8)
    }

    /// Plain text version with HTML tags removed
    public var plainText: String {
        // Robust HTML tag stripping for fallback
        return raw.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression, range: nil
        )
        .replacingOccurrences(of: "&nbsp;", with: " ")
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
    }

    /// Initialize with raw HTML content
    public init(raw: String) {
        self.raw = raw
    }

    /// Returns the first URL found in the raw HTML string
    public var extractFirstURL: URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(
            in: raw, options: [], range: NSRange(location: 0, length: raw.utf16.count))

        let firstURL = matches?.compactMap { $0.url }.first
        return firstURL
    }

    /// Returns an AttributedString representation of the HTML
    public func attributedStringFromHTML() -> AttributedString {
        guard let data = raw.data(using: .utf16) else {
            return AttributedString(raw)
        }
        if let nsAttr = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf16.rawValue,
            ], documentAttributes: nil)
        {
            return AttributedString(nsAttr)
        } else {
            return AttributedString(raw)
        }
    }
}

/// A custom text component for rendering HTML content with emoji support
public struct EmojiTextApp: View {
    let htmlString: HTMLString
    let customEmoji: [String: URL]?
    var font: Font = .body
    var foregroundColor: Color = .primary
    var lineLimit: Int? = nil
    var mentions: [String] = []
    var tags: [String] = []

    public init(
        htmlString: HTMLString, customEmoji: [String: URL]? = nil, font: Font = .body,
        foregroundColor: Color = .primary, lineLimit: Int? = nil, mentions: [String] = [],
        tags: [String] = []
    ) {
        self.htmlString = htmlString
        self.customEmoji = customEmoji
        self.font = font
        self.foregroundColor = foregroundColor
        self.lineLimit = lineLimit
        self.mentions = mentions
        self.tags = tags
    }

    /// Set font for the text
    public func font(_ font: Font) -> EmojiTextApp {
        var copy = self
        copy.font = font
        return copy
    }

    /// Set text color
    public func foregroundColor(_ color: Color) -> EmojiTextApp {
        var copy = self
        copy.foregroundColor = color
        return copy
    }

    /// Set line limit
    public func lineLimit(_ limit: Int?) -> EmojiTextApp {
        var copy = self
        copy.lineLimit = limit
        return copy
    }

    public var body: some View {
        // Use EmojiText library for proper inline emoji rendering
        CachedEmojiTextView(
            htmlString: htmlString,
            customEmoji: customEmoji,
            font: font,
            foregroundColor: foregroundColor,
            mentions: mentions,
            tags: tags,
            lineLimit: lineLimit
        )
    }

    // Build AttributedString with robust mention/tag/web link handling (no emoji processing - handled by EmojiText library)
    static func buildAttributedString(
        htmlString: HTMLString, font: Font, foregroundColor: Color,
        mentions: [String], tags: [String]
    ) -> AttributedString {
        let processedHTML = htmlString.raw
        
        // Parse HTML and build AttributedString
        guard let data = processedHTML.data(using: .utf8), !data.isEmpty else {
            return AttributedString(htmlString.plainText)
        }
        
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        
        var nsAttr: NSAttributedString?
        let htmlStringValue = String(data: data, encoding: .utf8) ?? ""
        
        if !htmlStringValue.isEmpty && htmlStringValue.count < 100_000 {
            let hasValidHTMLTags = htmlStringValue.contains("<") && htmlStringValue.contains(">")
            let hasBalancedTags = htmlStringValue.components(separatedBy: "<").count == htmlStringValue.components(separatedBy: ">").count
            
            if hasValidHTMLTags && hasBalancedTags {
                do {
                    nsAttr = try NSAttributedString(data: data, options: options, documentAttributes: nil)
                } catch {
                    nsAttr = nil
                }
            }
        }
        
        let fallbackText = htmlString.plainText
        var attributed = AttributedString(nsAttr ?? NSAttributedString(string: fallbackText))

        // Gather mention/tag URLs
        let mentionURLs = mentions.compactMap { URL(string: $0) }
        let tagURLs = tags.compactMap { URL(string: $0) }

        // Detect URLs in plain text (for Bluesky posts without HTML links)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let fullText = String(attributed.characters)
            let nsString = fullText as NSString
            let matches = detector.matches(in: fullText, options: [], range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                if let url = match.url {
                    let urlText = nsString.substring(with: match.range)
                    if let range = attributed.range(of: urlText) {
                        attributed[range].link = url
                        attributed[range].foregroundColor = Color.accentColor
                    }
                }
            }
        }

        // Walk all runs and reassign links as needed
        for run in attributed.runs {
            if let url = run.link {
                if mentionURLs.contains(url) {
                    let username = url.lastPathComponent
                    attributed[run.range].link = URL(string: "socialfusion://user/\(username)")
                    attributed[run.range].foregroundColor = .accentColor
                } else if tagURLs.contains(url) {
                    let tag = url.lastPathComponent
                    attributed[run.range].link = URL(string: "socialfusion://tag/\(tag)")
                    attributed[run.range].foregroundColor = .accentColor
                } else {
                    attributed[run.range].foregroundColor = .accentColor
                }
                attributed[run.range].font = font
            } else {
                attributed[run.range].font = font
                attributed[run.range].foregroundColor = foregroundColor
            }
        }
        return attributed
    }
}

private func makeRemoteEmojis(from emojiMap: [String: URL]) -> [RemoteEmoji] {
    var remoteEmojis: [RemoteEmoji] = []
    remoteEmojis.reserveCapacity(emojiMap.count * 2)

    for (shortcode, url) in emojiMap {
        guard !shortcode.isEmpty else { continue }
        remoteEmojis.append(RemoteEmoji(shortcode: shortcode, url: url))

        let colonWrapped = ":\(shortcode):"
        if shortcode != colonWrapped {
            remoteEmojis.append(RemoteEmoji(shortcode: colonWrapped, url: url))
        }
    }

    return remoteEmojis
}

/// View that uses the EmojiText library for proper inline custom emoji rendering
/// Caches the parsed AttributedString and uses RemoteEmoji for async emoji loading
private struct CachedEmojiTextView: View {
    let htmlString: HTMLString
    let customEmoji: [String: URL]?
    let font: Font
    let foregroundColor: Color
    let mentions: [String]
    let tags: [String]
    let lineLimit: Int?

    @State private var attributedString: AttributedString?

    var body: some View {
        Group {
            if let attributed = attributedString {
                // Convert custom emoji to RemoteEmoji format for EmojiText library
                let remoteEmojis: [RemoteEmoji] = makeRemoteEmojis(from: customEmoji ?? [:])
                
                if remoteEmojis.isEmpty {
                    // No custom emoji - render attributed string directly
                    Text(attributed)
                        .lineLimit(lineLimit)
                        .textSelection(.enabled)
                        .environment(\.layoutDirection, .leftToRight)
                } else {
                    // Use EmojiText library for inline emoji rendering
                    // The library handles remote loading, caching, and inline display
                    EmojiText(String(attributed.characters), emojis: remoteEmojis)
                        .lineLimit(lineLimit)
                        .environment(\.layoutDirection, .leftToRight)
                }
            } else {
                // Show plain text while parsing
                Text(htmlString.plainText)
                    .lineLimit(lineLimit)
                    .textSelection(.enabled)
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
        .task {
            // Parse HTML asynchronously (emoji loading is handled by EmojiText library)
            let attributed = await Task.detached(priority: .userInitiated) {
                await EmojiTextApp.buildAttributedString(
                    htmlString: htmlString,
                    font: font,
                    foregroundColor: foregroundColor,
                    mentions: mentions,
                    tags: tags
                )
            }.value
            self.attributedString = attributed
        }
    }
}

/// A reusable view for rendering display names with custom emoji support
/// Used for author names, booster names, and other short text with potential emoji
public struct EmojiDisplayNameText: View {
    let text: String
    let emojiMap: [String: URL]?
    var font: Font = .subheadline
    var fontWeight: Font.Weight = .semibold
    var foregroundColor: Color = .primary
    var lineLimit: Int = 1
    
    public init(
        _ text: String,
        emojiMap: [String: String]?,
        font: Font = .subheadline,
        fontWeight: Font.Weight = .semibold,
        foregroundColor: Color = .primary,
        lineLimit: Int = 1
    ) {
        self.text = text
        // Convert [String: String] to [String: URL]
        if let map = emojiMap {
            var urlMap: [String: URL] = [:]
            for (shortcode, urlString) in map {
                if let url = URL(string: urlString) {
                    urlMap[shortcode] = url
                }
            }
            self.emojiMap = urlMap.isEmpty ? nil : urlMap
        } else {
            self.emojiMap = nil
        }
        self.font = font
        self.fontWeight = fontWeight
        self.foregroundColor = foregroundColor
        self.lineLimit = lineLimit
    }
    
    public var body: some View {
        if let emojiMap = emojiMap, !emojiMap.isEmpty {
            // Convert to RemoteEmoji for EmojiText library
            let remoteEmojis: [RemoteEmoji] = makeRemoteEmojis(from: emojiMap)
            
            EmojiText(text, emojis: remoteEmojis)
                .font(font)
                .fontWeight(fontWeight)
                .foregroundColor(foregroundColor)
                .lineLimit(lineLimit)
        } else {
            // No emoji - render plain text
            Text(text)
                .font(font)
                .fontWeight(fontWeight)
                .foregroundColor(foregroundColor)
                .lineLimit(lineLimit)
        }
    }
}

extension Post {
    /// Returns a dictionary of custom emoji shortcodes to URLs for this post
    public var customEmoji: [String: URL]? {
        guard let emojiMap = customEmojiMap, !emojiMap.isEmpty else {
            // For boosted/reposted posts, check the original post
            if let original = originalPost {
                return original.customEmoji
            }
            return nil
        }
        
        // Convert [String: String] to [String: URL]
        var result: [String: URL] = [:]
        for (shortcode, urlString) in emojiMap {
            if let url = URL(string: urlString) {
                result[shortcode] = url
            }
        }
        return result.isEmpty ? nil : result
    }
}

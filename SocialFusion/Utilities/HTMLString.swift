import Foundation
import SwiftUI
import UIKit

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
        return matches?.compactMap { $0.url }.first
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
        let attributed = Self.buildAttributedString(
            htmlString: htmlString,
            customEmoji: customEmoji,
            font: font,
            foregroundColor: foregroundColor,
            mentions: mentions,
            tags: tags
        )
        Text(attributed)
            .lineLimit(lineLimit)
            .textSelection(.enabled)
            .allowsTightening(false)
            .environment(\.layoutDirection, .leftToRight)
    }

    // Build AttributedString with robust mention/tag/web link handling
    static func buildAttributedString(
        htmlString: HTMLString, customEmoji: [String: URL]?, font: Font, foregroundColor: Color,
        mentions: [String], tags: [String]
    ) -> AttributedString {
        // Parse HTML and build AttributedString
        guard let data = htmlString.raw.data(using: .utf8) else {
            return AttributedString(htmlString.plainText)
        }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        let nsAttr = try? NSMutableAttributedString(
            data: data, options: options, documentAttributes: nil)
        var attributed = AttributedString(
            nsAttr ?? NSAttributedString(string: htmlString.plainText))

        // Gather mention/tag URLs
        let mentionURLs = mentions.compactMap { URL(string: $0) }
        let tagURLs = tags.compactMap { URL(string: $0) }

        // Walk all runs and reassign links as needed
        for run in attributed.runs {
            if let url = run.link {
                // If this is a mention or tag, convert to custom scheme
                if mentionURLs.contains(url) {
                    let username = url.lastPathComponent
                    attributed[run.range].link = URL(string: "socialfusion://user/\(username)")
                    attributed[run.range].foregroundColor = .accentColor
                } else if tagURLs.contains(url) {
                    let tag = url.lastPathComponent
                    attributed[run.range].link = URL(string: "socialfusion://tag/\(tag)")
                    attributed[run.range].foregroundColor = .accentColor
                } else {
                    // Real web link: style as link
                    attributed[run.range].foregroundColor = .accentColor
                }
            }
            // Always apply font and color
            attributed[run.range].font = font
            attributed[run.range].foregroundColor = foregroundColor
        }
        return attributed
    }
}

extension Post {
    /// Returns a dictionary of custom emoji shortcodes to URLs for this post
    public var customEmoji: [String: URL]? {
        // For now, we return nil, but in a full implementation
        // this would return platform-specific emoji mappings
        return nil
    }
}

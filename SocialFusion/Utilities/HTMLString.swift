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
        // Basic HTML tag stripping for fallback
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
}

/// A custom text component for rendering HTML content with emoji support
public struct EmojiTextApp: View {
    let htmlString: HTMLString
    let customEmoji: [String: URL]?
    var font: Font = .body
    var foregroundColor: Color = .primary
    private var lineLimit: Int?

    public init(htmlString: HTMLString, customEmoji: [String: URL]? = nil) {
        self.htmlString = htmlString
        self.customEmoji = customEmoji
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
        // Basic implementation that uses plainText as fallback
        Text(htmlString.plainText)
            .font(font)
            .foregroundColor(foregroundColor)
            .lineLimit(lineLimit)
        // In a real implementation, we would parse HTML and render with emojis
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

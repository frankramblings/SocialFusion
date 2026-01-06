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

    // Build AttributedString with robust mention/tag/web link handling and custom emoji support
    static func buildAttributedString(
        htmlString: HTMLString, customEmoji: [String: URL]?, font: Font, foregroundColor: Color,
        mentions: [String], tags: [String]
    ) -> AttributedString {
        // First, process HTML to replace emoji img tags and shortcodes BEFORE parsing
        var processedHTML = htmlString.raw
        
        // Replace custom emoji shortcodes with images BEFORE HTML parsing
        if let emojiMap = customEmoji, !emojiMap.isEmpty {
            print("🎨 [Emoji] Processing \(emojiMap.count) custom emoji: \(Array(emojiMap.keys).prefix(5))")
            processedHTML = replaceEmojiInHTML(html: processedHTML, emojiMap: emojiMap)
        } else {
            print("⚠️ [Emoji] No custom emoji map provided")
        }
        
        // Parse HTML and build AttributedString
        // CRITICAL: Add robust error handling to prevent SIGABRT crashes
        guard let data = processedHTML.data(using: .utf8) else {
            return AttributedString(htmlString.plainText)
        }
        
        // Validate data is not empty and contains valid UTF-8
        guard !data.isEmpty else {
            return AttributedString(htmlString.plainText)
        }
        
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        
        // CRITICAL: Wrap NSMutableAttributedString initialization to prevent SIGABRT crashes
        // NSMutableAttributedString can throw Objective-C exceptions that Swift's do-catch can't catch
        // Use a safer approach: validate HTML and use NSAttributedString instead of NSMutableAttributedString
        var nsAttr: NSAttributedString?
        
        // Validate HTML contains valid characters and isn't empty
        let htmlStringValue = String(data: data, encoding: .utf8) ?? ""
        if !htmlStringValue.isEmpty && htmlStringValue.count < 100_000 {
            // CRITICAL FIX: Use a safer HTML parsing approach to prevent SIGABRT crashes
            // NSAttributedString can throw Objective-C exceptions that Swift's do-catch can't catch
            // Validate HTML structure before parsing to reduce crash risk
            let hasValidHTMLTags = htmlStringValue.contains("<") && htmlStringValue.contains(">")
            let hasBalancedTags = htmlStringValue.components(separatedBy: "<").count == htmlStringValue.components(separatedBy: ">").count
            
            if hasValidHTMLTags && hasBalancedTags {
                do {
                    // Use NSAttributedString instead of NSMutableAttributedString for safer parsing
                    // This is less likely to crash on malformed HTML
                    nsAttr = try NSAttributedString(
                        data: data, options: options, documentAttributes: nil)
                } catch {
                    // If parsing fails, fall back to plain text
                    print("⚠️ [EmojiTextApp] Failed to parse HTML: \(error.localizedDescription)")
                    nsAttr = nil
                }
            } else {
                // HTML structure appears invalid - fall back to plain text
                print("⚠️ [EmojiTextApp] HTML structure invalid, using plain text")
                nsAttr = nil
            }
        } else {
            // HTML too large or invalid - fall back to plain text
            print("⚠️ [EmojiTextApp] HTML too large or invalid, using plain text")
            nsAttr = nil
        }
        
        // Fallback to plain text if parsing failed - use the HTMLString parameter's plainText property
        let fallbackText = htmlString.plainText
        var attributed = AttributedString(
            nsAttr ?? NSAttributedString(string: fallbackText))
        
        // Also replace any remaining :shortcode: patterns in the parsed text
        if let emojiMap = customEmoji, !emojiMap.isEmpty {
            attributed = replaceCustomEmoji(in: attributed, emojiMap: emojiMap, font: font)
        }

        // Gather mention/tag URLs
        let mentionURLs = mentions.compactMap { URL(string: $0) }
        let tagURLs = tags.compactMap { URL(string: $0) }

        // First, detect URLs in plain text (for Bluesky posts without HTML links)
        if let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue)
        {
            let fullText = String(attributed.characters)
            let nsString = fullText as NSString
            let matches = detector.matches(
                in: fullText, options: [],
                range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                if let url = match.url {
                    let urlText = nsString.substring(with: match.range)

                    // Find this URL text in our AttributedString and make it a link
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
                    // Real web link: style as link (keep existing accent color)
                    attributed[run.range].foregroundColor = .accentColor
                }
                // Apply font but preserve link color
                attributed[run.range].font = font
            } else {
                // Non-link text: apply font and standard color
                attributed[run.range].font = font
                attributed[run.range].foregroundColor = foregroundColor
            }
        }
        return attributed
    }
    
    /// Replaces emoji img tags and :shortcode: patterns in HTML with data URI img tags
    private static func replaceEmojiInHTML(html: String, emojiMap: [String: URL]) -> String {
        var processedHTML = html
        
        // Pattern 1: Replace <img> tags that reference emoji (Mastodon sends these)
        // Mastodon sends: <img src="..." alt=":shortcode:" class="emoji" />
        let imgPattern = #"<img[^>]*alt=":([a-zA-Z0-9_-]+):"[^>]*>"#
        if let regex = try? NSRegularExpression(pattern: imgPattern, options: []) {
            let nsString = processedHTML as NSString
            let matches = regex.matches(
                in: processedHTML, options: [],
                range: NSRange(location: 0, length: nsString.length)
            )
            
            // Process in reverse to preserve indices
            for match in matches.reversed() {
                guard match.numberOfRanges >= 2 else { continue }
                let shortcodeRange = match.range(at: 1)
                
                guard shortcodeRange.location != NSNotFound,
                      let shortcode = nsString.substring(with: shortcodeRange) as String?,
                      let emojiURL = emojiMap[shortcode]
                else { continue }
                
                // Load image and convert to data URI for reliable rendering
                if let imageData = try? Data(contentsOf: emojiURL),
                   let image = UIImage(data: imageData),
                   let pngData = image.pngData() {
                    let base64 = pngData.base64EncodedString()
                    let dataURI = "data:image/png;base64,\(base64)"
                    let replacement = #"<img src="\#(dataURI)" alt=":\#(shortcode):" class="emoji" style="width: 20px; height: 20px; vertical-align: middle;" />"#
                    let fullRange = match.range(at: 0)
                    processedHTML = (processedHTML as NSString).replacingCharacters(in: fullRange, with: replacement)
                } else {
                    // Fallback: use the URL directly (might not work in all cases)
                    let replacement = #"<img src="\#(emojiURL.absoluteString)" alt=":\#(shortcode):" class="emoji" style="width: 20px; height: 20px; vertical-align: middle;" />"#
                    let fullRange = match.range(at: 0)
                    processedHTML = (processedHTML as NSString).replacingCharacters(in: fullRange, with: replacement)
                }
            }
        }
        
        // Pattern 2: Replace :shortcode: text patterns with img tags using data URIs
        let shortcodePattern = #":([a-zA-Z0-9_-]+):"#
        if let regex = try? NSRegularExpression(pattern: shortcodePattern, options: []) {
            let nsString = processedHTML as NSString
            let matches = regex.matches(
                in: processedHTML, options: [],
                range: NSRange(location: 0, length: nsString.length)
            )
            
            // Process in reverse to preserve indices
            for match in matches.reversed() {
                guard match.numberOfRanges >= 2 else { continue }
                let shortcodeRange = match.range(at: 1)
                
                guard shortcodeRange.location != NSNotFound,
                      let shortcode = nsString.substring(with: shortcodeRange) as String?,
                      let emojiURL = emojiMap[shortcode]
                else { continue }
                
                // Check if this shortcode is already inside an img tag (skip it)
                let fullRange = match.range(at: 0)
                let beforeStart = max(0, fullRange.location - 20)
                let afterEnd = min(nsString.length, fullRange.location + fullRange.length + 20)
                let contextRange = NSRange(location: beforeStart, length: afterEnd - beforeStart)
                let context = nsString.substring(with: contextRange)
                
                // Skip if already in an img tag
                if context.contains("<img") {
                    continue
                }
                
                // Load image and convert to data URI
                if let imageData = try? Data(contentsOf: emojiURL),
                   let image = UIImage(data: imageData),
                   let pngData = image.pngData() {
                    let base64 = pngData.base64EncodedString()
                    let dataURI = "data:image/png;base64,\(base64)"
                    let replacement = #"<img src="\#(dataURI)" alt=":\#(shortcode):" class="emoji" style="width: 20px; height: 20px; vertical-align: middle;" />"#
                    processedHTML = (processedHTML as NSString).replacingCharacters(in: fullRange, with: replacement)
                } else {
                    // Fallback: use URL directly
                    let replacement = #"<img src="\#(emojiURL.absoluteString)" alt=":\#(shortcode):" class="emoji" style="width: 20px; height: 20px; vertical-align: middle;" />"#
                    processedHTML = (processedHTML as NSString).replacingCharacters(in: fullRange, with: replacement)
                }
            }
        }
        
        return processedHTML
    }
    
    /// Replaces :shortcode: patterns in AttributedString with custom emoji images
    private static func replaceCustomEmoji(
        in attributed: AttributedString, emojiMap: [String: URL], font: Font
    ) -> AttributedString {
        // Convert to NSMutableAttributedString for easier manipulation
        let nsMutable = NSMutableAttributedString(attributed)
        let fullText = nsMutable.string
        
        // Pattern to match :shortcode: (allowing alphanumeric, underscore, and hyphen)
        // Mastodon emoji shortcodes can contain letters, numbers, underscores, and hyphens
        let emojiPattern = #":([a-zA-Z0-9_-]+):"#
        
        guard let regex = try? NSRegularExpression(pattern: emojiPattern, options: []) else {
            return attributed
        }
        
        let nsString = fullText as NSString
        let matches = regex.matches(
            in: fullText, options: [],
            range: NSRange(location: 0, length: nsString.length)
        )
        
        // Process matches in reverse order to preserve indices
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else { continue }
            let fullRange = match.range(at: 0)  // Full match including colons
            let shortcodeRange = match.range(at: 1)  // Just the shortcode
            
            guard shortcodeRange.location != NSNotFound,
                  let shortcode = nsString.substring(with: shortcodeRange) as String?,
                  let emojiURL = emojiMap[shortcode]
            else { continue }
            
            // Create NSTextAttachment with emoji image
            let attachment = NSTextAttachment()
            
            // Load emoji image synchronously
            // Note: In production, you'd want to cache these and load asynchronously
            do {
                let imageData = try Data(contentsOf: emojiURL)
                if let image = UIImage(data: imageData) {
                    // Use a reasonable emoji size (typically 20-24 points)
                    // This matches common emoji rendering sizes
                    let emojiSize: CGFloat = 20
                    let scaledImage = image.scaled(to: CGSize(width: emojiSize, height: emojiSize))
                    attachment.image = scaledImage
                    
                    // Adjust vertical alignment to center with text baseline
                    let fontDescender: CGFloat = -4  // Approximate descender for body font
                    attachment.bounds = CGRect(
                        x: 0,
                        y: fontDescender,
                        width: emojiSize,
                        height: emojiSize
                    )
                    
                    // Replace the :shortcode: text with the image attachment
                    let attachmentString = NSAttributedString(attachment: attachment)
                    nsMutable.replaceCharacters(in: fullRange, with: attachmentString)
                } else {
                    print("⚠️ [Emoji] Failed to create UIImage from data for \(shortcode)")
                }
            } catch {
                print("⚠️ [Emoji] Failed to load emoji image for \(shortcode) from \(emojiURL): \(error)")
            }
        }
        
        return AttributedString(nsMutable)
    }
}

extension UIImage {
    /// Scales an image to the specified size while maintaining aspect ratio
    func scaled(to size: CGSize) -> UIImage {
        let aspectRatio = self.size.width / self.size.height
        var targetSize = size
        
        if aspectRatio > 1 {
            // Wider than tall
            targetSize.height = size.width / aspectRatio
        } else {
            // Taller than wide or square
            targetSize.width = size.height * aspectRatio
        }
        
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
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

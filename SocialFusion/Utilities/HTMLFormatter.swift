/*
 * DEPRECATED: This file is no longer used.
 * Please use the String+HTML.swift and Text+HTML.swift extensions instead.
 * The extensions are more modular and avoid importing issues.
 */

// This file can be safely deleted after confirming the new extensions work properly.

import Foundation
import SwiftUI
import UIKit

class HTMLFormatter {
    /// Sanitize content for display - helps prevent showing raw HTML tags
    static func sanitizeContentForDisplay(_ content: String) -> String {
        // Check if content contains raw HTML that might have escaped normal parsing
        var sanitized = content

        // Check for raw HTML tag patterns that might appear in the content
        if content.contains("<p>") && content.contains("</p>") && content.contains("<a href=") {
            // This might be raw HTML that wasn't properly parsed
            sanitized =
                sanitized
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
        }

        return sanitized
    }

    /// Convert HTML string to attributed string for proper display
    static func attributedStringFromHTML(html: String, fontSize: CGFloat = 15.0)
        -> NSAttributedString
    {
        // Define the font
        let font = UIFont.systemFont(ofSize: fontSize)
        let fontDescriptor = font.fontDescriptor

        // Clean HTML: Replace common problematic HTML tags and handle Mastodon-specific formatting
        var cleanHTML =
            html
            .replacingOccurrences(of: "<p>", with: "<div>")
            .replacingOccurrences(of: "</p>", with: "</div>")

        // Improve code styling
        cleanHTML =
            cleanHTML
            .replacingOccurrences(
                of: "<code>",
                with:
                    "<code style=\"font-family: monospace; background-color: #f1f1f1; padding: 2px 4px; border-radius: 3px;\">"
            )

        // Improve link styling and ensure they're clickable
        cleanHTML =
            cleanHTML
            .replacingOccurrences(
                of: "<a href=",
                with: "<a style=\"color: #1DA1F2; text-decoration: underline;\" href=")

        // Wrap in a div with styling for proper rendering
        cleanHTML =
            "<div style=\"font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #000000;\">\(cleanHTML)</div>"

        // Create attributed string from HTML
        guard let data = cleanHTML.data(using: .utf8) else {
            return NSAttributedString(string: html)
        }

        do {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ]

            let attributedString = try NSAttributedString(
                data: data, options: options, documentAttributes: nil)

            // Apply our font to the whole string while preserving other attributes
            let mutableString = NSMutableAttributedString(attributedString: attributedString)
            mutableString.beginEditing()

            // Apply font but preserve other attributes like links
            mutableString.enumerateAttribute(
                .font, in: NSRange(location: 0, length: mutableString.length), options: []
            ) { value, range, _ in
                if let oldFont = value as? UIFont {
                    // Preserve font traits from the HTML (bold, italic, etc.)
                    let newFontDescriptor = fontDescriptor.addingAttributes(
                        oldFont.fontDescriptor.fontAttributes
                    )
                    let newFont = UIFont(descriptor: newFontDescriptor, size: fontSize)
                    mutableString.addAttribute(.font, value: newFont, range: range)
                } else {
                    mutableString.addAttribute(.font, value: font, range: range)
                }
            }
            mutableString.endEditing()

            return mutableString
        } catch {
            print("Error parsing HTML: \(error)")
            return NSAttributedString(string: html)
        }
    }
}

// UIKit AttributedString to SwiftUI Text converter
extension Text {
    static func fromHTML(_ html: String, fontSize: CGFloat = 15.0) -> Text {
        let attributedString = HTMLFormatter.attributedStringFromHTML(
            html: html, fontSize: fontSize)
        return Text(AttributedString(attributedString))
    }
}

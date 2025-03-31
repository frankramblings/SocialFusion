import SwiftUI
import UIKit

extension Text {
    /// Creates a Text view from HTML content
    static func html(_ html: String, fontSize: CGFloat = 15.0) -> Text {
        guard let data = cleanHTML(html).data(using: .utf8) else {
            return Text(html)
        }

        do {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ]

            let attributedString = try NSAttributedString(
                data: data, options: options, documentAttributes: nil)
            return Text(AttributedString(attributedString))
        } catch {
            print("Error parsing HTML: \(error)")
            return Text(html)
        }
    }

    /// Helper function to clean HTML content
    private static func cleanHTML(_ html: String) -> String {
        // Handle common HTML tags and styling
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

        return cleanHTML
    }
}

import Foundation

extension String {
    /// Converts common HTML entities to their character equivalents
    var decodingHTMLEntities: String {
        var result = self

        // Replace common HTML entities
        let entities = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&nbsp;": " ",
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        return result
    }

    /// Removes all HTML tags from a string
    var strippingHTMLTags: String {
        return self.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
    }
}

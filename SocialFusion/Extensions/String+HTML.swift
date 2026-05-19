import Foundation

extension String {
    /// Converts common HTML entities to their character equivalents.
    /// Includes smart-quote numeric entities (`&#8216;`, `&#8217;`,
    /// `&#8220;`, `&#8221;`) and `&apos;` because Mastodon's HTML
    /// emitter uses them for typographic quotes; previously
    /// `PostNormalizerImpl` carried its own private superset.
    var decodingHTMLEntities: String {
        var result = self

        // Replace common HTML entities
        let entities = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&#39;": "'",
            "&nbsp;": " ",
            // Smart quotes — these show up in real Mastodon posts.
            "&#8216;": "\u{2018}",  // left single quote
            "&#8217;": "\u{2019}",  // right single quote / apostrophe
            "&#8220;": "\u{201C}",  // left double quote
            "&#8221;": "\u{201D}",  // right double quote
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

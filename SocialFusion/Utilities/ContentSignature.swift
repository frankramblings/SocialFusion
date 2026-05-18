import Foundation

/// Produces a normalized fingerprint of post text for cross-network matching.
///
/// Strips cross-poster artifacts that differ between networks without
/// changing semantic content: trailing hashtags, trailing handles/mentions,
/// URL fragments and trailing slashes, and whitespace differences.
public enum ContentSignature {
    /// Returns a stable, normalized fingerprint suitable for equality comparison.
    public static func fingerprint(for text: String) -> String {
        var s = text

        // 1. Normalize URLs: strip fragments and trailing slashes.
        s = normalizeURLs(in: s)

        // 2. Strip trailing mentions (@user, @user@host) and hashtags.
        s = stripTrailingTokens(in: s)

        // 3. Collapse whitespace and trim.
        s = s
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // 4. Lowercase for case-insensitive matching.
        return s.lowercased()
    }

    private static func normalizeURLs(in text: String) -> String {
        let pattern = #"https?://[^\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange).reversed()
        var result = text
        for match in matches {
            guard let range = Range(match.range, in: result) else { continue }
            var url = String(result[range])
            if let fragmentStart = url.firstIndex(of: "#") {
                url = String(url[..<fragmentStart])
            }
            while url.hasSuffix("/") {
                url.removeLast()
            }
            result.replaceSubrange(range, with: url)
        }
        return result
    }

    private static func stripTrailingTokens(in text: String) -> String {
        var tokens = text.split(separator: " ", omittingEmptySubsequences: true)
        while let last = tokens.last {
            let s = String(last)
            if s.hasPrefix("@") || s.hasPrefix("#") {
                tokens.removeLast()
            } else {
                break
            }
        }
        return tokens.joined(separator: " ")
    }
}

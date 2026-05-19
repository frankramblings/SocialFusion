import Foundation

/// Produces a normalized fingerprint of post text for cross-network matching.
///
/// Strips cross-poster artifacts that differ between networks without
/// changing semantic content: trailing hashtags, trailing handles/mentions,
/// URL fragments and trailing slashes, URL trailing punctuation, and
/// whitespace differences (including newline-separated trailing tokens).
public enum ContentSignature {
    /// Returns a stable, normalized fingerprint suitable for equality comparison.
    public static func fingerprint(for text: String) -> String {
        var s = text

        // 1. Normalize URLs: strip trailing punctuation, fragments, and trailing slashes.
        s = normalizeURLs(in: s)

        // 2. Collapse whitespace and trim. Runs BEFORE token-strip so newline-separated
        //    trailing hashtags become space-separated and get stripped correctly.
        s = s
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // 3. Strip trailing mentions (@user, @user@host) and hashtags.
        s = stripTrailingTokens(in: s)

        // 4. Lowercase for case-insensitive matching.
        return s.lowercased()
    }

    /// Punctuation characters that should be treated as outside the URL when they
    /// appear at the end. Cross-posters disagree on whether trailing punctuation
    /// belongs to the URL or the surrounding prose.
    private static let urlTrailingPunctuation: Set<Character> = [
        ".", ",", ";", ":", "!", "?", ")", "]", "}"
    ]

    private static func normalizeURLs(in text: String) -> String {
        let pattern = #"https?://[^\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange).reversed()
        var result = text
        for match in matches {
            guard let range = Range(match.range, in: result) else { continue }
            var url = String(result[range])

            // Strip trailing punctuation first so it doesn't shield a trailing
            // slash or fragment from later steps. Bracket-aware: a trailing
            // `)`, `]`, or `}` is kept if its matching opener appears earlier
            // in the URL — Wikipedia-style paths like `Macintosh_(computer)`
            // were being mangled by a naive greedy strip.
            while let last = url.last, urlTrailingPunctuation.contains(last) {
                if Self.bracketIsBalanced(in: url, closer: last) {
                    break
                }
                url.removeLast()
            }

            // Drop URL fragment if present.
            if let fragmentStart = url.firstIndex(of: "#") {
                url = String(url[..<fragmentStart])
            }

            // Drop trailing slashes.
            while url.hasSuffix("/") {
                url.removeLast()
            }

            result.replaceSubrange(range, with: url)
        }
        return result
    }

    /// True if the trailing `closer` character is part of a balanced bracket
    /// pair within `url`. Counts openers vs closers across the whole URL —
    /// when the count of openers ≥ closers, the final closer is structural
    /// and we should NOT strip it.
    private static func bracketIsBalanced(in url: String, closer: Character) -> Bool {
        let opener: Character
        switch closer {
        case ")": opener = "("
        case "]": opener = "["
        case "}": opener = "{"
        default: return false
        }
        var openers = 0
        var closers = 0
        for ch in url {
            if ch == opener { openers += 1 }
            if ch == closer { closers += 1 }
        }
        return openers >= closers
    }

    /// Removes contiguous `@mention` and `#hashtag` tokens from the end of the text.
    /// Does not touch mentions/hashtags interleaved with prose. Expects input to
    /// already have whitespace collapsed to single spaces.
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

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

        // 0. Fold smart-punctuation variants to their ASCII equivalents.
        //    iOS's "Smart Punctuation" keyboard setting + various
        //    cross-poster pipelines auto-substitute curly quotes,
        //    em/en dashes, and ellipses inconsistently between
        //    networks. Equality should survive that round-trip.
        s = foldSmartPunctuation(in: s)

        // 1. Normalize URLs: strip trailing punctuation, fragments, and trailing slashes.
        s = normalizeURLs(in: s)

        // 2. Collapse whitespace and trim. Runs BEFORE token-strip so newline-separated
        //    trailing hashtags become space-separated and get stripped correctly.
        s = s
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // 3. Strip leading mentions (@user, @user@host). Cross-posters that
        //    convert a Mastodon-style @-prefix into a Bluesky mention often
        //    add the recipient handle on one side but not the other.
        s = stripLeadingMentions(in: s)

        // 4. Strip trailing mentions (@user, @user@host) and hashtags.
        s = stripTrailingTokens(in: s)

        // 5. Strip trailing terminal punctuation (period, exclamation, etc.)
        //    so "Welcome." and "Welcome" match. Crossposters often drop the
        //    period when one network's character count is tight.
        s = stripTrailingPunctuation(in: s)

        // 6. Lowercase for case-insensitive matching.
        return s.lowercased()
    }

    /// Smart-punctuation → ASCII map. Folding before any other pass so the
    /// downstream normalizers don't have to know about Unicode variants.
    /// `\u{2019}` (right single quotation mark) is the most common offender
    /// — iOS substitutes it for `'` by default, but cross-posters and copy
    /// pipelines disagree on whether to preserve it. Same for the
    /// double-quote pair (`\u{201C}` / `\u{201D}`), en/em dashes, and
    /// the ellipsis character.
    private static let smartPunctuationFolds: [Character: Character] = [
        "\u{2018}": "'",  // left single quotation mark
        "\u{2019}": "'",  // right single quotation mark / typographic apostrophe
        "\u{201C}": "\"", // left double quotation mark
        "\u{201D}": "\"", // right double quotation mark
        "\u{2013}": "-",  // en dash
        "\u{2014}": "-",  // em dash
    ]

    private static func foldSmartPunctuation(in text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for ch in text {
            if let folded = smartPunctuationFolds[ch] {
                result.append(folded)
            } else if ch == "\u{2026}" {  // horizontal ellipsis → three dots
                result.append("...")
            } else {
                result.append(ch)
            }
        }
        return result
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

    /// Removes contiguous `@mention` tokens from the START of the text. Mirrors
    /// `stripTrailingTokens` but only handles mentions — leading `#hashtag` is
    /// less common as cross-poster noise and is semantically meaningful when it
    /// appears at the beginning (e.g., `#protip Don't forget…`). Does NOT
    /// touch mid-text mentions.
    private static func stripLeadingMentions(in text: String) -> String {
        var tokens = text.split(separator: " ", omittingEmptySubsequences: true)
        while let first = tokens.first {
            if first.hasPrefix("@") {
                tokens.removeFirst()
            } else {
                break
            }
        }
        return tokens.joined(separator: " ")
    }

    /// Trailing terminal punctuation that cross-posters frequently drop on
    /// one network but keep on the other. Question marks and exclamations
    /// included — they're semantically meaningful but cross-posters
    /// occasionally trim them for character-count reasons; the small risk
    /// of a content-signature collision between a question and a statement
    /// is worth the recall gain.
    private static let trailingTextPunctuation: Set<Character> = [
        ".", "!", "?", "…"
    ]

    private static func stripTrailingPunctuation(in text: String) -> String {
        var s = text
        while let last = s.last, trailingTextPunctuation.contains(last) {
            s.removeLast()
        }
        return s
    }
}

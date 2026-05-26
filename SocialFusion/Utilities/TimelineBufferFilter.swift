import Foundation

/// Pure in-memory filter over an array of `Post`. Used by timeline search
/// for its client-side layer. Must complete a 500-post scan in <100ms
/// (see `TimelineSearchPerformanceTests`).
public enum TimelineBufferFilter {

    /// Returns posts that match the given query, preserving input order.
    public static func filter(_ posts: [Post], query: String) -> [Post] {
        let tokens = tokenize(query)
        guard !tokens.isEmpty else { return [] }

        return posts.filter { post in
            tokens.allSatisfy { token in matches(post: post, token: token) }
        }
    }

    // MARK: - Tokenization

    /// Parsed token with a hint of where it must match.
    private struct Token {
        let needle: String              // lowercased, stripped of any sigil
        let restriction: Restriction
    }

    private enum Restriction {
        case any        // content, author, or tags
        case authorOnly // @ prefix
        case tagOnly    // # prefix
    }

    private static func tokenize(_ raw: String) -> [Token] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap { rawPart -> Token? in
                var s = String(rawPart)
                guard !s.isEmpty else { return nil }
                if s.hasPrefix("@") {
                    s.removeFirst()
                    guard !s.isEmpty else { return nil }
                    return Token(needle: s.lowercased(), restriction: .authorOnly)
                }
                if s.hasPrefix("#") {
                    s.removeFirst()
                    guard !s.isEmpty else { return nil }
                    return Token(needle: s.lowercased(), restriction: .tagOnly)
                }
                return Token(needle: s.lowercased(), restriction: .any)
            }
    }

    // MARK: - Matching

    private static func matches(post: Post, token: Token) -> Bool {
        let needle = token.needle
        switch token.restriction {
        case .authorOnly:
            return post.authorName.lowercased().contains(needle)
                || post.authorUsername.lowercased().contains(needle)
        case .tagOnly:
            return post.tags.contains(where: { $0.lowercased().contains(needle) })
        case .any:
            return post.content.lowercased().contains(needle)
                || post.authorName.lowercased().contains(needle)
                || post.authorUsername.lowercased().contains(needle)
                || post.tags.contains(where: { $0.lowercased().contains(needle) })
        }
    }
}

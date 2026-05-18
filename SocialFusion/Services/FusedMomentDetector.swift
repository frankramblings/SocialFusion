import Foundation

/// Detects pairs of posts that represent the same moment from the same author
/// posted to both Mastodon and Bluesky.
public final class FusedMomentDetector: Sendable {
    /// Maximum time delta between two posts to consider them a fusion candidate.
    public let timeWindow: TimeInterval

    /// Minimum confidence required to emit a `FusedMoment`.
    public let minConfidence: Double

    /// Confidence-scoring constants. Tunable; see `computeConfidence(...)`.
    private static let baselineConfidence: Double = 0.85
    private static let shortContentPenalty: Double = 0.20
    private static let shortContentThreshold: Int = 20
    private static let longContentBonus: Double = 0.05
    private static let longContentThreshold: Int = 80
    private static let exactLengthMatchBonus: Double = 0.05

    public init(timeWindow: TimeInterval = 10 * 60, minConfidence: Double = 0.75) {
        self.timeWindow = timeWindow
        self.minConfidence = minConfidence
    }

    /// Returns the set of detected fused moments from the given post buffer.
    ///
    /// Buckets posts by author identity, then does a pairwise within-author
    /// signature compare. Runs in roughly O(n) when posts are spread across
    /// many authors; worst case O(n²) when all posts share one author. For
    /// v1.0 timeline buffers (<200 posts) this is acceptable. Safe to run
    /// after every timeline refresh.
    public func detect(in posts: [Post]) -> [FusedMoment] {
        let byAuthor = Dictionary(grouping: posts, by: \.authorIdentityKey)
        var moments: [FusedMoment] = []
        for (authorKey, authorPosts) in byAuthor {
            let mastoPosts = authorPosts.filter { $0.platform == .mastodon }
            let bskyPosts = authorPosts.filter { $0.platform == .bluesky }
            guard !mastoPosts.isEmpty, !bskyPosts.isEmpty else { continue }
            // Precompute fingerprints so we don't re-tokenize on every pair.
            let mastoSigs: [(Post, String)] = mastoPosts.compactMap { post in
                let sig = ContentSignature.fingerprint(for: post.content)
                return sig.isEmpty ? nil : (post, sig)
            }
            let bskySigs: [(Post, String)] = bskyPosts.compactMap { post in
                let sig = ContentSignature.fingerprint(for: post.content)
                return sig.isEmpty ? nil : (post, sig)
            }

            for (m, mSig) in mastoSigs {
                for (b, bSig) in bskySigs {
                    guard mSig == bSig else { continue }
                    guard abs(m.createdAt.timeIntervalSince(b.createdAt)) <= timeWindow else { continue }
                    let confidence = computeConfidence(mastoContent: m.content, bskyContent: b.content)
                    guard confidence >= minConfidence else { continue }
                    moments.append(FusedMoment(
                        mastodonPostID: m.id,
                        blueskyPostID: b.id,
                        authorIdentityKey: authorKey,
                        firstSeenAt: min(m.createdAt, b.createdAt),
                        confidence: confidence
                    ))
                }
            }
        }
        return moments
    }

    /// v1.0 confidence is binary-ish: a content-signature match plus same
    /// author plus in-window gets the baseline. Add small boosts for tight
    /// timing and exact length match; subtract for very short content
    /// (high false-positive risk).
    private func computeConfidence(mastoContent: String, bskyContent: String) -> Double {
        let mLen = mastoContent.trimmingCharacters(in: .whitespacesAndNewlines).count
        let bLen = bskyContent.trimmingCharacters(in: .whitespacesAndNewlines).count
        let shorter = min(mLen, bLen)
        var c = Self.baselineConfidence
        if shorter < Self.shortContentThreshold { c -= Self.shortContentPenalty }
        if shorter > Self.longContentThreshold { c += Self.longContentBonus }
        if mLen == bLen { c += Self.exactLengthMatchBonus }
        return min(max(c, 0), 1)
    }
}

private extension Post {
    /// In v1.0 we key on the post's author ID (already platform-specific). When
    /// the merged-identity feature lands in a sibling plan, swap this for the
    /// stable cross-network identity key. Wrap here so the swap is one line.
    var authorIdentityKey: String { authorId }
}

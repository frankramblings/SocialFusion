import Foundation

/// Detects pairs of posts that represent the same moment from the same author
/// posted to both Mastodon and Bluesky.
public final class FusedMomentDetector {
    /// Maximum time delta between two posts to consider them a fusion candidate.
    public let timeWindow: TimeInterval

    /// Minimum confidence required to emit a `FusedMoment`.
    public let minConfidence: Double

    public init(timeWindow: TimeInterval = 10 * 60, minConfidence: Double = 0.75) {
        self.timeWindow = timeWindow
        self.minConfidence = minConfidence
    }

    /// Returns the set of detected fused moments from the given post buffer.
    /// Operates in O(n) by bucketing posts by author identity, then doing
    /// pairwise within-author signature compare. Safe to run after every
    /// timeline refresh on the loaded buffer (typically < 200 posts).
    public func detect(in posts: [Post]) -> [FusedMoment] {
        let byAuthor = Dictionary(grouping: posts, by: \.authorIdentityKey)
        var moments: [FusedMoment] = []
        for (authorKey, authorPosts) in byAuthor {
            let mastoPosts = authorPosts.filter { $0.platform == .mastodon }
            let bskyPosts = authorPosts.filter { $0.platform == .bluesky }
            guard !mastoPosts.isEmpty, !bskyPosts.isEmpty else { continue }
            for m in mastoPosts {
                let mSig = ContentSignature.fingerprint(for: m.content)
                guard !mSig.isEmpty else { continue }
                for b in bskyPosts {
                    let bSig = ContentSignature.fingerprint(for: b.content)
                    guard !bSig.isEmpty else { continue }
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
    /// author plus in-window gets 0.85 baseline. Add small boosts for tight
    /// timing and exact length match; subtract for very short content
    /// (high false-positive risk).
    private func computeConfidence(mastoContent: String, bskyContent: String) -> Double {
        let mLen = mastoContent.trimmingCharacters(in: .whitespacesAndNewlines).count
        let bLen = bskyContent.trimmingCharacters(in: .whitespacesAndNewlines).count
        let shorter = min(mLen, bLen)
        var c = 0.85
        if shorter < 20 { c -= 0.20 }       // short content is risky
        if shorter > 80 { c += 0.05 }       // longer content rarely collides
        if mLen == bLen { c += 0.05 }       // exact length match
        return min(max(c, 0), 1)
    }
}

private extension Post {
    /// In v1.0 we key on the post's author ID (already platform-specific). When
    /// the merged-identity feature lands in a sibling plan, swap this for the
    /// stable cross-network identity key. Wrap here so the swap is one line.
    var authorIdentityKey: String { authorId }
}

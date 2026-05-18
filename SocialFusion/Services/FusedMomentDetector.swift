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

    /// Pre-resolved author-key lookup table: `"\(platform.rawValue):\(authorID)"` → merged-identity ID.
    ///
    /// Built on MainActor by the caller from a snapshot of `MergedIdentityStore`
    /// and passed in before each detection pass. Keeping this resolution out of
    /// the detector itself lets `detect(in:identityMap:)` stay off-MainActor and
    /// concurrency-clean — the store is `@MainActor`, but a plain
    /// `[String: String]` is freely sendable.
    public typealias IdentityKeyMap = [String: String]

    /// Returns the set of detected fused moments from the given post buffer.
    ///
    /// Buckets posts by author identity, then does a pairwise within-author
    /// signature compare. Runs in roughly O(n) when posts are spread across
    /// many authors; worst case O(n²) when all posts share one author. For
    /// v1.0 timeline buffers (<200 posts) this is acceptable. Safe to run
    /// after every timeline refresh.
    ///
    /// `identityMap` lets callers route Mastodon and Bluesky posts from the same
    /// human into the same author bucket even when their platform-native
    /// `authorId`s differ — this is the production wiring into the
    /// merged-identity layer. When the map is empty or the post's author isn't
    /// in it, the detector falls back to the post's native `authorId`, which
    /// is already platform-disjoint in practice (Bluesky DIDs and Mastodon
    /// URL-IDs never collide).
    public func detect(in posts: [Post], identityMap: IdentityKeyMap = [:]) -> [FusedMoment] {
        let byAuthor = Dictionary(grouping: posts, by: { Self.authorIdentityKey(for: $0, in: identityMap) })
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

extension FusedMomentDetector {
    /// The grouping key for an author. When `identityMap` contains an entry for
    /// the post's `(platform, authorId)`, returns the merged identity's stable
    /// `id` so Mastodon and Bluesky posts from the same human end up in the
    /// same bucket. Otherwise falls back to the post's native `authorId`,
    /// which is already platform-disjoint in practice and preserves
    /// pre-merged-identity test behavior.
    internal static func authorIdentityKey(for post: Post, in identityMap: IdentityKeyMap) -> String {
        let lookupKey = "\(post.platform.rawValue):\(post.authorId)"
        return identityMap[lookupKey] ?? post.authorId
    }
}

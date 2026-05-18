import Foundation

/// A moment from a single author that exists on both Bluesky and Mastodon.
///
/// Detected by `FusedMomentDetector` when matching content from the same
/// author lands on both networks within a small time window.
public struct FusedMoment: Identifiable, Hashable, Codable {
    /// Stable identifier derived from the pair of post IDs.
    public let id: String

    /// The post ID on Mastodon (platform-scoped).
    public let mastodonPostID: String

    /// The post ID on Bluesky (platform-scoped).
    public let blueskyPostID: String

    /// The author's stable identity (the merged-identity ID from Principle 2,
    /// or — in v1.0 — the platform-specific author ID prefixed with the platform
    /// of the side that was seen first).
    public let authorIdentityKey: String

    /// The earliest createdAt across the two posts.
    public let firstSeenAt: Date

    /// Confidence score in [0, 1]. Lower bound of confidence we'll show the
    /// Fused glyph at is 0.75 (configurable in detector).
    public let confidence: Double

    public init(
        mastodonPostID: String,
        blueskyPostID: String,
        authorIdentityKey: String,
        firstSeenAt: Date,
        confidence: Double
    ) {
        // Deterministic ID from the sorted pair so the same moment always
        // hashes to the same value regardless of which side arrived first.
        self.id = "fused:\(mastodonPostID)+\(blueskyPostID)"
        self.mastodonPostID = mastodonPostID
        self.blueskyPostID = blueskyPostID
        self.authorIdentityKey = authorIdentityKey
        self.firstSeenAt = firstSeenAt
        self.confidence = confidence
    }

    /// Returns the post ID for the opposite network from the given platform.
    public func twinPostID(for platform: SocialPlatform) -> String {
        switch platform {
        case .mastodon: return blueskyPostID
        case .bluesky: return mastodonPostID
        }
    }
}

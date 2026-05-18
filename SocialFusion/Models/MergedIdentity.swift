import Foundation

/// How an identity match was established. The priority is: user-confirmed
/// (strongest) → verified bio cross-link → handle-convention match (weakest).
public enum MergeProvenance: String, Codable, Hashable, Sendable {
    /// The user explicitly tapped "Merge" to bind the two accounts.
    case userConfirmed

    /// Both bios contained verifiable cross-links pointing at each other.
    case verifiedBioCrossLink

    /// Handles share a local-part on conventional domains
    /// (e.g. `gruber@mastodon.social` ↔ `gruber.bsky.social`).
    case handleConvention
}

/// Stable cross-network handle key for one side of a merge.
///
/// We key on `(platform, accountID)` rather than display username so that
/// re-renames on either side don't break the merge. `accountID` is the
/// platform's stable identifier (Mastodon numeric ID, Bluesky DID).
public struct MergedIdentityKey: Hashable, Codable, Sendable {
    public let platform: SocialPlatform
    public let accountID: String
    /// The handle at the time of merge — recorded for UI display only.
    public let handle: String

    public init(platform: SocialPlatform, accountID: String, handle: String) {
        self.platform = platform
        self.accountID = accountID
        self.handle = handle
    }

    /// Storage key used by the side-channel store and `UserDefaults`.
    public var storageKey: String {
        "\(platform.rawValue):\(accountID)"
    }
}

/// A merged identity: two `MergedIdentityKey`s, one per network, bound together
/// either by user confirmation, by verified bio cross-links, or by handle
/// convention. Confidence is in [0, 1]; user-confirmed merges are always 1.0.
public struct MergedIdentity: Identifiable, Hashable, Codable, Sendable {
    /// Stable ID derived from the deterministically-sorted pair of storage keys.
    public let id: String

    public let mastodon: MergedIdentityKey
    public let bluesky: MergedIdentityKey

    public let provenance: MergeProvenance
    public let confidence: Double
    public let createdAt: Date

    public init(
        mastodon: MergedIdentityKey,
        bluesky: MergedIdentityKey,
        provenance: MergeProvenance,
        confidence: Double,
        createdAt: Date = Date()
    ) {
        precondition(mastodon.platform == .mastodon, "Mastodon side must be .mastodon")
        precondition(bluesky.platform == .bluesky, "Bluesky side must be .bluesky")
        // Deterministic ID so the same pair always hashes the same way.
        self.id = "merged:\(mastodon.storageKey)+\(bluesky.storageKey)"
        self.mastodon = mastodon
        self.bluesky = bluesky
        self.provenance = provenance
        self.confidence = max(0, min(1, confidence))
        self.createdAt = createdAt
    }

    /// Returns the key for the opposite network from the given side.
    public func twin(of platform: SocialPlatform) -> MergedIdentityKey {
        switch platform {
        case .mastodon: return bluesky
        case .bluesky: return mastodon
        }
    }

    /// Returns the key for the matching network.
    public func key(for platform: SocialPlatform) -> MergedIdentityKey {
        switch platform {
        case .mastodon: return mastodon
        case .bluesky: return bluesky
        }
    }
}

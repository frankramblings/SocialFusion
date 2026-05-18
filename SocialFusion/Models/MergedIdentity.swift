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
    ///
    /// **Opaque.** The format embeds the raw `accountID`, which on Bluesky
    /// is a DID like `did:plc:abc123` (contains colons). Do NOT parse this
    /// key by splitting on `:` or `+`. Use the `platform`/`accountID`
    /// properties directly.
    public var storageKey: String {
        "\(platform.rawValue):\(accountID)"
    }
}

/// A merged identity: two `MergedIdentityKey`s, one per network, bound together
/// either by user confirmation, by verified bio cross-links, or by handle
/// convention. Confidence is in [0, 1]; user-confirmed merges are always 1.0.
public struct MergedIdentity: Identifiable, Hashable, Codable, Sendable {
    /// Stable ID derived from the pair of storage keys.
    ///
    /// **Opaque.** Format embeds both sides' storage keys, which themselves
    /// embed DIDs containing colons. Do NOT parse this id; use the
    /// `mastodon`/`bluesky` keys directly. Two `MergedIdentity` instances
    /// representing the same pair will always have equal `id`, regardless of
    /// `confidence`, `provenance`, or `createdAt`.
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

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, mastodon, bluesky, provenance, confidence, createdAt
    }

    /// Validates platform-side invariants after decode. The synthesized
    /// memberwise init does this via `precondition`, but `Codable`'s
    /// synthesized decode would otherwise bypass it.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        let mastodon = try c.decode(MergedIdentityKey.self, forKey: .mastodon)
        let bluesky = try c.decode(MergedIdentityKey.self, forKey: .bluesky)
        let provenance = try c.decode(MergeProvenance.self, forKey: .provenance)
        let confidence = try c.decode(Double.self, forKey: .confidence)
        let createdAt = try c.decode(Date.self, forKey: .createdAt)

        guard mastodon.platform == .mastodon else {
            throw DecodingError.dataCorruptedError(
                forKey: .mastodon, in: c,
                debugDescription: "Mastodon side must have platform == .mastodon, got \(mastodon.platform)"
            )
        }
        guard bluesky.platform == .bluesky else {
            throw DecodingError.dataCorruptedError(
                forKey: .bluesky, in: c,
                debugDescription: "Bluesky side must have platform == .bluesky, got \(bluesky.platform)"
            )
        }

        self.id = id
        self.mastodon = mastodon
        self.bluesky = bluesky
        self.provenance = provenance
        self.confidence = max(0, min(1, confidence))
        self.createdAt = createdAt
    }
}

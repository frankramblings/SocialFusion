import Foundation

/// Computes heuristic identity matches between Mastodon and Bluesky profiles.
///
/// Strictly priority-ordered. The matcher returns at most one candidate per
/// pair, with the *strongest* provenance that applies:
///
/// 1. **Verified bio cross-link** — both sides advertise the other and at
///    least one side carries an explicit verified marker. Confidence 0.92.
/// 2. **Handle convention** — the local-part matches across networks on
///    conventional domains. Confidence 0.78.
///
/// User-confirmed merges (provenance `.userConfirmed`, confidence 1.0) are
/// not produced here; they're inserted directly into `MergedIdentityStore`.
public struct IdentityMatcher: Sendable {
    public init() {}

    /// Bluesky domains we treat as conventional (no custom-domain signal).
    /// Only `bsky.social` — Bluesky's default PDS-hosted suffix — counts.
    /// `bsky.team` and similar are vanity/team domains and treated as custom,
    /// which means a match there requires the Mastodon side to use the same
    /// domain (or a stronger signal like a verified bio cross-link).
    private static let conventionalBlueskyDomains: Set<String> = [
        "bsky.social"
    ]

    /// Mastodon instance domains we treat as conventional. For these, the
    /// local-part alone is enough alongside a `*.bsky.social`
    /// Bluesky handle to call it a handle-convention match.
    private static let conventionalMastodonDomains: Set<String> = [
        "mastodon.social",
        "mastodon.online",
        "mas.to",
        "hachyderm.io",
        "fosstodon.org",
        "infosec.exchange",
        "indieweb.social",
        "social.lol",
        "mastodon.cloud"
    ]

    public func match(mastodon: UserProfile, bluesky: UserProfile) -> MergedIdentity? {
        precondition(mastodon.platform == .mastodon)
        precondition(bluesky.platform == .bluesky)

        if let verified = matchByVerifiedBioCrossLink(mastodon: mastodon, bluesky: bluesky) {
            return verified
        }
        if let conv = matchByHandleConvention(mastodon: mastodon, bluesky: bluesky) {
            return conv
        }
        return nil
    }

    // MARK: - Verified bio cross-link

    private func matchByVerifiedBioCrossLink(
        mastodon: UserProfile,
        bluesky: UserProfile
    ) -> MergedIdentity? {
        let mastodonClaimsBluesky = mastodonHasVerifiedLinkTo(bluesky: bluesky, in: mastodon)
        let blueskyClaimsMastodon = blueskyBioMentions(mastodon: mastodon, in: bluesky)
        guard mastodonClaimsBluesky && blueskyClaimsMastodon else { return nil }
        return makeMatch(
            mastodon: mastodon,
            bluesky: bluesky,
            provenance: .verifiedBioCrossLink,
            confidence: 0.92
        )
    }

    private func mastodonHasVerifiedLinkTo(
        bluesky: UserProfile,
        in mastodon: UserProfile
    ) -> Bool {
        let handle = bluesky.username.lowercased()
        let urlVariant = "bsky.app/profile/\(handle)"
        guard let fields = mastodon.fields else { return false }
        for field in fields where field.isVerified {
            let value = field.value.lowercased()
            if value.contains(handle) || value.contains(urlVariant) {
                return true
            }
        }
        return false
    }

    private func blueskyBioMentions(
        mastodon: UserProfile,
        in bluesky: UserProfile
    ) -> Bool {
        guard let bio = bluesky.bio?.lowercased() else { return false }
        let needle = mastodon.username.lowercased()
        return bio.contains("@\(needle)") || bio.contains(needle)
    }

    // MARK: - Handle convention

    private func matchByHandleConvention(
        mastodon: UserProfile,
        bluesky: UserProfile
    ) -> MergedIdentity? {
        let mastoParts = mastodon.username.split(separator: "@", maxSplits: 1).map(String.init)
        guard mastoParts.count == 2 else { return nil }
        let mastoLocal = mastoParts[0].lowercased()
        let mastoDomain = mastoParts[1].lowercased()

        let bskyHandle = bluesky.username.lowercased()
        guard let firstDot = bskyHandle.firstIndex(of: ".") else { return nil }
        let bskyLocal = String(bskyHandle[..<firstDot])
        let bskyDomain = String(bskyHandle[bskyHandle.index(after: firstDot)...])

        guard mastoLocal == bskyLocal else { return nil }

        let bothConventional =
            Self.conventionalMastodonDomains.contains(mastoDomain) &&
            Self.conventionalBlueskyDomains.contains(bskyDomain)
        let sharedCustomDomain = mastoDomain == bskyDomain && !mastoDomain.isEmpty

        guard bothConventional || sharedCustomDomain else { return nil }

        return makeMatch(
            mastodon: mastodon,
            bluesky: bluesky,
            provenance: .handleConvention,
            confidence: 0.78
        )
    }

    // MARK: - Helpers

    private func makeMatch(
        mastodon: UserProfile,
        bluesky: UserProfile,
        provenance: MergeProvenance,
        confidence: Double
    ) -> MergedIdentity {
        MergedIdentity(
            mastodon: MergedIdentityKey(
                platform: .mastodon,
                accountID: mastodon.id,
                handle: mastodon.username
            ),
            bluesky: MergedIdentityKey(
                platform: .bluesky,
                accountID: bluesky.id,
                handle: bluesky.username
            ),
            provenance: provenance,
            confidence: confidence
        )
    }
}

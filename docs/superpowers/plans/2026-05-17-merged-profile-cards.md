# Merged Profile Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When SocialFusion recognizes two profiles as the same human across Bluesky and Mastodon, present them as a single, unified profile card — both handles visible, bio swappable per network, combined follower/following counts with per-network breakdown, a "Merged identity" chip near the avatar, and a one-tap Unmerge action. Users can also manually merge two profiles they're viewing.

**Architecture:** Side-channel store pattern (mirrors `FusedMomentStore` from `2026-05-17-the-fuse-breakthrough.md` and `PostActionStore`). A new `IdentityMatcher` service runs three heuristics in priority order — (a) user-confirmed merges from `MergedIdentityStore`, (b) verified bio cross-links (Bluesky bio mentions Mastodon handle with a verified link entry, or a Mastodon verified field points to the Bluesky DID/handle), (c) handle-convention matches on conventional domains (e.g. `gruber@mastodon.social` ↔ `gruber.bsky.social`). A new `MergedIdentity` model holds the pair of `SocialActor`-style keys plus provenance. The `MergedIdentityStore` is `@MainActor`, `ObservableObject`, in-memory `[String: MergedIdentity]` keyed on each side's author identity key, and persists user-confirmed merges (and explicit unmerges) to `UserDefaults` so the choice survives launches. `ProfileViewModel` queries the store and, when a merge exists, fetches the twin profile from the opposite network in parallel and exposes a `MergedProfile` view-state with both `UserProfile`s. `ProfileHeaderView` is extended (not replaced) with a "Merged identity" chip + handle swap segmented control + combined-counts surface; Posts/Replies/Media tabs fetch from both networks and merge by timestamp with each item carrying its existing `PlatformLogoBadge`.

**Tech Stack:** Swift 5+, SwiftUI, Combine, XCTest. iOS 17+ floor. Reuses existing patterns: side-channel stores, `@MainActor` published state, `ObservableObject` view models, `PlatformLogoBadge` shape-coded indicators, the launch-animation color palette for the merged chip (`#8A63FF` purple, `#0096FF` blue, `#1EE7FF` cyan).

**Spec reference:** `docs/superpowers/specs/2026-05-17-socialfusion-v1-vision-design.md` — see Principle 2 ("Identity is whole, not partitioned") and the "New for v1.0" item "Merged profile cards."

**File map (creates/modifies):**

- Create: `SocialFusion/Models/MergedIdentity.swift`
- Create: `SocialFusion/Services/IdentityMatcher.swift`
- Create: `SocialFusion/Stores/MergedIdentityStore.swift`
- Create: `SocialFusion/Views/Components/MergedIdentityChip.swift`
- Create: `SocialFusion/Views/Components/MergedHandleSelector.swift`
- Create: `SocialFusion/Views/MergeConfirmationSheet.swift`
- Create: `SocialFusionTests/MergedIdentityStoreTests.swift`
- Create: `SocialFusionTests/IdentityMatcherTests.swift`
- Create: `SocialFusionTests/ProfileViewModelMergeTests.swift`
- Modify: `SocialFusion/ViewModels/ProfileViewModel.swift` (load + expose merged twin profile, drive handle selection, expose merge/unmerge actions)
- Modify: `SocialFusion/Views/ProfileView.swift` (consume merged view-state, route header bindings, surface confirmation sheet, render unified post timeline)
- Modify: `SocialFusion/Views/Components/ProfileHeaderView.swift` (merged-identity chip, dual-handle row, combined stats with per-network breakdown, unmerge menu entry)
- Modify: `SocialFusion/SocialFusionApp.swift` (instantiate `MergedIdentityStore` as `@StateObject`, inject as `@EnvironmentObject`)
- Modify: `SocialFusion/Views/SettingsView.swift` (add "Merged identities" management row)

**Implementer assumptions to verify before each task:**

1. `UserProfile` is `public struct UserProfile: Codable, Sendable` at `SocialFusion/Models/SocialModels.swift:238`, with fields including `id`, `username`, `platform`, `bio: String?`, `headerURL: String?`, `fields: [ProfileField]?`, `followersCount`, `followingCount`, `statusesCount`, `displayNameEmojiMap`.
2. `SearchUser` is `public struct SearchUser: Identifiable, Sendable` at `SocialFusion/Models/SocialModels.swift:305` with `id`, `username`, `displayName?`, `avatarURL?`, `platform`, `displayNameEmojiMap?`.
3. `ProfileViewModel` is `@MainActor public final class ProfileViewModel: ObservableObject` at `SocialFusion/ViewModels/ProfileViewModel.swift`. Initialized with `(user: SearchUser, isOwnProfile: Bool, serviceManager: SocialServiceManager)`.
4. `SocialServiceManager.fetchUserProfile(user:account:)` returns `UserProfile` (signature at `SocialFusion/Services/SocialServiceManager.swift:2250`).
5. `SocialServiceManager.fetchFilteredUserPosts(user:account:cursor:excludeReplies:onlyMedia:)` returns `([Post], String?)`.
6. `SocialPlatform` is `String`-backed enum with cases `.mastodon` and `.bluesky` (per CLAUDE.md memory).
7. `PlatformLogoBadge(platform:size:shadowEnabled:)` is at `SocialFusion/Views/Components/PlatformLogoBadge.swift:5`.
8. `ProfileField` is `public struct ProfileField: Codable, Sendable` with `name`, `value`, `isVerified` — used by `UserProfile.fields`.
9. The test target is `SocialFusionTests`. Tests subclass `XCTestCase`. `@testable import SocialFusion`.
10. App root state objects are injected in `SocialFusion/SocialFusionApp.swift` (verified: `serviceManager`, `oauthManager`, `notificationManager`, `draftStore`, `chatStreamService`, etc., all wired in three scene branches).

---

## Task 1: MergedIdentity data model

**Files:**
- Create: `SocialFusion/Models/MergedIdentity.swift`

The model that represents a confirmed (or heuristically-detected) cross-network identity. Holds the pair of identity keys (one per network), provenance, and a confidence score.

- [ ] **Step 1: Implement the model**

Create `SocialFusion/Models/MergedIdentity.swift`:

```swift
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
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add SocialFusion/Models/MergedIdentity.swift
git commit -m "feat(merge): add MergedIdentity model with provenance + identity keys"
```

---

## Task 2: IdentityMatcher heuristic

**Files:**
- Create: `SocialFusion/Services/IdentityMatcher.swift`
- Test: `SocialFusionTests/IdentityMatcherTests.swift`

The heuristic that produces a candidate `MergedIdentity` from a pair of `UserProfile`s (or returns `nil`). Runs only the automatic checks — bio cross-link and handle-convention. User-confirmed merges bypass the matcher; they're stored directly.

- [ ] **Step 1: Write the failing tests**

Create `SocialFusionTests/IdentityMatcherTests.swift`:

```swift
import XCTest
@testable import SocialFusion

final class IdentityMatcherTests: XCTestCase {
    // MARK: - Handle convention

    func testHandleConventionMatchesOnSharedLocalPart() {
        let matcher = IdentityMatcher()
        let masto = makeProfile(id: "m1", username: "gruber@mastodon.social", platform: .mastodon)
        let bsky = makeProfile(id: "b1", username: "gruber.bsky.social", platform: .bluesky)
        let result = matcher.match(mastodon: masto, bluesky: bsky)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.provenance, .handleConvention)
        XCTAssertEqual(result?.mastodon.handle, "gruber@mastodon.social")
        XCTAssertEqual(result?.bluesky.handle, "gruber.bsky.social")
    }

    func testHandleConventionRejectsMismatchedLocalParts() {
        let matcher = IdentityMatcher()
        let masto = makeProfile(id: "m1", username: "gruber@mastodon.social", platform: .mastodon)
        let bsky = makeProfile(id: "b1", username: "siracusa.bsky.social", platform: .bluesky)
        XCTAssertNil(matcher.match(mastodon: masto, bluesky: bsky))
    }

    func testHandleConventionRejectsUnconventionalDomains() {
        // Random Mastodon instance + bsky.social does not give us enough signal.
        let matcher = IdentityMatcher()
        let masto = makeProfile(id: "m1", username: "alice@some-tiny-instance.example", platform: .mastodon)
        let bsky = makeProfile(id: "b1", username: "alice.bsky.social", platform: .bluesky)
        XCTAssertNil(matcher.match(mastodon: masto, bluesky: bsky))
    }

    func testHandleConventionAcceptsCustomBlueskyDomain() {
        // A custom Bluesky domain (alice.example.com) and a Mastodon handle
        // on the same domain (alice@example.com) is a valid signal.
        let matcher = IdentityMatcher()
        let masto = makeProfile(id: "m1", username: "alice@example.com", platform: .mastodon)
        let bsky = makeProfile(id: "b1", username: "alice.example.com", platform: .bluesky)
        let result = matcher.match(mastodon: masto, bluesky: bsky)
        XCTAssertEqual(result?.provenance, .handleConvention)
    }

    // MARK: - Verified bio cross-link

    func testVerifiedBioCrossLinkBeatsHandleConvention() {
        let matcher = IdentityMatcher()
        let masto = makeProfile(
            id: "m1",
            username: "different@mastodon.social",
            platform: .mastodon,
            fields: [ProfileField(name: "Bluesky", value: "https://bsky.app/profile/zelda.bsky.social", isVerified: true)]
        )
        let bsky = makeProfile(
            id: "b1",
            username: "zelda.bsky.social",
            platform: .bluesky,
            bio: "I'm @different@mastodon.social on the fediverse."
        )
        let result = matcher.match(mastodon: masto, bluesky: bsky)
        XCTAssertEqual(result?.provenance, .verifiedBioCrossLink)
    }

    func testUnverifiedBioFieldDoesNotMatch() {
        // A field can claim cross-link, but if it's not isVerified it's not enough.
        let matcher = IdentityMatcher()
        let masto = makeProfile(
            id: "m1",
            username: "alice@mastodon.social",
            platform: .mastodon,
            fields: [ProfileField(name: "Bluesky", value: "https://bsky.app/profile/bob.bsky.social", isVerified: false)]
        )
        let bsky = makeProfile(id: "b1", username: "bob.bsky.social", platform: .bluesky)
        XCTAssertNil(matcher.match(mastodon: masto, bluesky: bsky))
    }

    func testBlueskyBioWithoutMastodonCounterClaimDoesNotMatch() {
        // Bluesky bio mentions a Mastodon handle but Mastodon side has no link back.
        let matcher = IdentityMatcher()
        let masto = makeProfile(id: "m1", username: "alice@mastodon.social", platform: .mastodon)
        let bsky = makeProfile(
            id: "b1",
            username: "alice.bsky.team",
            platform: .bluesky,
            bio: "Also @alice@mastodon.social"
        )
        XCTAssertNil(matcher.match(mastodon: masto, bluesky: bsky))
    }

    // MARK: - Confidence ordering

    func testConfidenceOrdering() {
        let matcher = IdentityMatcher()

        let verifiedMasto = makeProfile(
            id: "m", username: "x@mastodon.social", platform: .mastodon,
            fields: [ProfileField(name: "BSky", value: "https://bsky.app/profile/x.bsky.social", isVerified: true)]
        )
        let verifiedBsky = makeProfile(
            id: "b", username: "x.bsky.social", platform: .bluesky,
            bio: "I'm @x@mastodon.social"
        )
        let verified = matcher.match(mastodon: verifiedMasto, bluesky: verifiedBsky)

        let convMasto = makeProfile(id: "m", username: "y@mastodon.social", platform: .mastodon)
        let convBsky = makeProfile(id: "b", username: "y.bsky.social", platform: .bluesky)
        let conv = matcher.match(mastodon: convMasto, bluesky: convBsky)

        XCTAssertNotNil(verified)
        XCTAssertNotNil(conv)
        XCTAssertGreaterThan(verified!.confidence, conv!.confidence)
    }

    // MARK: - Helpers

    private func makeProfile(
        id: String,
        username: String,
        platform: SocialPlatform,
        bio: String? = nil,
        fields: [ProfileField]? = nil
    ) -> UserProfile {
        UserProfile(
            id: id,
            username: username,
            displayName: nil,
            avatarURL: nil,
            headerURL: nil,
            bio: bio,
            followersCount: 0,
            followingCount: 0,
            statusesCount: 0,
            platform: platform,
            fields: fields
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/IdentityMatcherTests`
Expected: FAIL — `IdentityMatcher` not defined.

- [ ] **Step 3: Implement the matcher**

Create `SocialFusion/Services/IdentityMatcher.swift`:

```swift
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
public struct IdentityMatcher {
    public init() {}

    /// The set of Bluesky domains we treat as conventional (no custom-domain
    /// signal). For these, the local-part must match alone — we don't accept
    /// it as evidence of identity unless the Mastodon side is *also* on a
    /// conventional / well-known instance domain.
    private static let conventionalBlueskyDomains: Set<String> = [
        "bsky.social",
        "bsky.team"
    ]

    /// The set of Mastodon instance domains we treat as conventional. For
    /// these, the local-part alone is enough alongside a `*.bsky.social` /
    /// `*.bsky.team` Bluesky handle to call it a handle-convention match.
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

    /// Returns true if any verified field on the Mastodon profile contains
    /// the Bluesky handle (or a `bsky.app/profile/{handle}` URL).
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

    /// Returns true if the Bluesky bio mentions the Mastodon handle.
    /// Format accepted: `@user@instance.example` or the bare `user@instance.example`.
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

        // Accept if (a) both sides are on conventional / well-known domains, or
        // (b) the Mastodon domain equals the Bluesky domain (custom-domain case).
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/IdentityMatcherTests`
Expected: PASS, all 8 tests green.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Services/IdentityMatcher.swift SocialFusionTests/IdentityMatcherTests.swift
git commit -m "feat(merge): add IdentityMatcher heuristic (bio cross-link + handle convention)"
```

---

## Task 3: MergedIdentityStore (side-channel persistence)

**Files:**
- Create: `SocialFusion/Stores/MergedIdentityStore.swift`
- Test: `SocialFusionTests/MergedIdentityStoreTests.swift`

Side-channel store, MainActor-isolated. In-memory `[String: MergedIdentity]` keyed on each side's storage key. User-confirmed merges and explicit unmerges (a "tombstone" set) persist to `UserDefaults` so the choice survives launches. Heuristic merges are recomputed on each session.

- [ ] **Step 1: Write the failing tests**

Create `SocialFusionTests/MergedIdentityStoreTests.swift`:

```swift
import XCTest
@testable import SocialFusion

@MainActor
final class MergedIdentityStoreTests: XCTestCase {
    func testInsertAndLookupBySide() {
        let store = MergedIdentityStore(userDefaults: makeEphemeralDefaults(), defaultsKey: "k")
        let m = makeMerge()
        store.insert([m])
        XCTAssertEqual(store.merge(forPlatform: .mastodon, accountID: m.mastodon.accountID)?.id, m.id)
        XCTAssertEqual(store.merge(forPlatform: .bluesky, accountID: m.bluesky.accountID)?.id, m.id)
        XCTAssertNil(store.merge(forPlatform: .mastodon, accountID: "nonexistent"))
    }

    func testInsertingSameMergeTwiceIsIdempotent() {
        let store = MergedIdentityStore(userDefaults: makeEphemeralDefaults(), defaultsKey: "k")
        let m = makeMerge()
        store.insert([m, m])
        XCTAssertEqual(store.allMerges().count, 1)
    }

    func testTwinKeyLookup() {
        let store = MergedIdentityStore(userDefaults: makeEphemeralDefaults(), defaultsKey: "k")
        let m = makeMerge()
        store.insert([m])
        let twin = store.twin(forPlatform: .mastodon, accountID: m.mastodon.accountID)
        XCTAssertEqual(twin?.platform, .bluesky)
        XCTAssertEqual(twin?.accountID, m.bluesky.accountID)
    }

    func testUserConfirmIsHigherPrecedenceThanHeuristic() {
        let store = MergedIdentityStore(userDefaults: makeEphemeralDefaults(), defaultsKey: "k")
        let masto = MergedIdentityKey(platform: .mastodon, accountID: "m", handle: "x@mastodon.social")
        let bsky = MergedIdentityKey(platform: .bluesky, accountID: "b", handle: "x.bsky.social")
        let heuristic = MergedIdentity(mastodon: masto, bluesky: bsky,
                                       provenance: .handleConvention, confidence: 0.78)
        store.insert([heuristic])
        store.confirmMerge(mastodon: masto, bluesky: bsky)
        XCTAssertEqual(store.merge(forPlatform: .mastodon, accountID: "m")?.provenance, .userConfirmed)
        XCTAssertEqual(store.merge(forPlatform: .mastodon, accountID: "m")?.confidence, 1.0)
    }

    func testUnmergeRemovesAndTombstones() {
        let store = MergedIdentityStore(userDefaults: makeEphemeralDefaults(), defaultsKey: "k")
        let m = makeMerge()
        store.insert([m])
        store.unmerge(id: m.id)
        XCTAssertNil(store.merge(forPlatform: .mastodon, accountID: m.mastodon.accountID))
        // Re-inserting the same heuristic merge should be blocked by the tombstone.
        store.insert([m])
        XCTAssertNil(store.merge(forPlatform: .mastodon, accountID: m.mastodon.accountID))
    }

    func testUserConfirmedMergePersistsAcrossInstances() {
        let defaults = makeEphemeralDefaults()
        let key = "persist-test-key"
        let masto = MergedIdentityKey(platform: .mastodon, accountID: "m", handle: "x@mastodon.social")
        let bsky = MergedIdentityKey(platform: .bluesky, accountID: "b", handle: "x.bsky.social")

        let s1 = MergedIdentityStore(userDefaults: defaults, defaultsKey: key)
        s1.confirmMerge(mastodon: masto, bluesky: bsky)

        let s2 = MergedIdentityStore(userDefaults: defaults, defaultsKey: key)
        XCTAssertEqual(s2.merge(forPlatform: .mastodon, accountID: "m")?.provenance, .userConfirmed)
    }

    func testUnmergePersistsAcrossInstances() {
        let defaults = makeEphemeralDefaults()
        let key = "tombstone-test-key"
        let m = makeMerge()

        let s1 = MergedIdentityStore(userDefaults: defaults, defaultsKey: key)
        s1.insert([m])
        s1.unmerge(id: m.id)

        let s2 = MergedIdentityStore(userDefaults: defaults, defaultsKey: key)
        s2.insert([m])
        XCTAssertNil(s2.merge(forPlatform: .mastodon, accountID: m.mastodon.accountID))
    }

    // MARK: - Helpers

    private func makeMerge() -> MergedIdentity {
        MergedIdentity(
            mastodon: MergedIdentityKey(platform: .mastodon, accountID: "m1", handle: "x@mastodon.social"),
            bluesky: MergedIdentityKey(platform: .bluesky, accountID: "b1", handle: "x.bsky.social"),
            provenance: .handleConvention,
            confidence: 0.78
        )
    }

    private func makeEphemeralDefaults() -> UserDefaults {
        let suite = "MergedIdentityStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/MergedIdentityStoreTests`
Expected: FAIL — `MergedIdentityStore` not defined.

- [ ] **Step 3: Implement the store**

Create `SocialFusion/Stores/MergedIdentityStore.swift`:

```swift
import Combine
import Foundation
import SwiftUI

/// Side-channel store of detected and user-confirmed merged identities.
///
/// Keyed on each side's `(platform, accountID)` storage key so any UI surface
/// that holds a `UserProfile` can ask the store whether the profile is bound
/// to a twin on the other network. Follows the established pattern from
/// `PostActionStore` / `FusedMomentStore`.
///
/// Persistence: user-confirmed merges and explicit unmerges (tombstones)
/// persist to `UserDefaults`. Heuristic merges are recomputed each session
/// via `IdentityMatcher` and inserted with `insert(_:)`. Tombstones block
/// re-detection of a pair the user explicitly unmerged.
@MainActor
public final class MergedIdentityStore: ObservableObject {
    /// All known merges by their stable ID.
    @Published public private(set) var merges: [String: MergedIdentity] = [:]

    /// Index from per-side storage key → merge ID (both sides).
    private var sideToMerge: [String: String] = [:]

    /// IDs of merges the user explicitly unmerged. These block re-insertion
    /// from heuristic detection so the user's choice is respected.
    @Published public private(set) var tombstones: Set<String> = []

    private let userDefaults: UserDefaults
    private let defaultsKey: String

    private struct Persisted: Codable {
        var userConfirmed: [MergedIdentity]
        var tombstones: [String]
    }

    public init(
        userDefaults: UserDefaults = .standard,
        defaultsKey: String = "MergedIdentityStore.v1"
    ) {
        self.userDefaults = userDefaults
        self.defaultsKey = defaultsKey
        load()
    }

    // MARK: - Mutations

    /// Inserts a batch of merges (typically from the heuristic matcher).
    /// Idempotent. Merges whose `id` appears in `tombstones` are skipped.
    /// A pre-existing user-confirmed merge for the same side is never
    /// replaced by a heuristic merge.
    public func insert(_ batch: [MergedIdentity]) {
        for incoming in batch {
            if tombstones.contains(incoming.id) { continue }
            if let existingID = sideToMerge[incoming.mastodon.storageKey] ?? sideToMerge[incoming.bluesky.storageKey],
               let existing = merges[existingID],
               existing.provenance == .userConfirmed {
                continue
            }
            indexMerge(incoming)
        }
        objectWillChange.send()
    }

    /// Records a user-confirmed merge. Always wins over any heuristic merge
    /// previously stored for either side. Clears the tombstone for this pair
    /// if it existed.
    public func confirmMerge(mastodon: MergedIdentityKey, bluesky: MergedIdentityKey) {
        let merge = MergedIdentity(
            mastodon: mastodon,
            bluesky: bluesky,
            provenance: .userConfirmed,
            confidence: 1.0
        )
        // Evict any prior merge attached to either side.
        if let prior = sideToMerge[mastodon.storageKey], let priorMerge = merges[prior] {
            evictMerge(priorMerge)
        }
        if let prior = sideToMerge[bluesky.storageKey], let priorMerge = merges[prior] {
            evictMerge(priorMerge)
        }
        tombstones.remove(merge.id)
        indexMerge(merge)
        save()
        objectWillChange.send()
    }

    /// Removes a merge by ID and records a tombstone so heuristics can't
    /// re-add the same pair.
    public func unmerge(id: String) {
        guard let merge = merges[id] else { return }
        evictMerge(merge)
        tombstones.insert(id)
        save()
        objectWillChange.send()
    }

    // MARK: - Lookups

    public func merge(forPlatform platform: SocialPlatform, accountID: String) -> MergedIdentity? {
        let key = MergedIdentityKey(platform: platform, accountID: accountID, handle: "").storageKey
        guard let mergeID = sideToMerge[key] else { return nil }
        return merges[mergeID]
    }

    /// Returns the twin key on the opposite network, or `nil` if no merge exists.
    public func twin(forPlatform platform: SocialPlatform, accountID: String) -> MergedIdentityKey? {
        guard let merge = merge(forPlatform: platform, accountID: accountID) else { return nil }
        return merge.twin(of: platform)
    }

    public func allMerges() -> [MergedIdentity] {
        Array(merges.values)
    }

    /// All user-confirmed merges, used for the Settings management UI.
    public func userConfirmedMerges() -> [MergedIdentity] {
        merges.values.filter { $0.provenance == .userConfirmed }
    }

    // MARK: - Private

    private func indexMerge(_ merge: MergedIdentity) {
        merges[merge.id] = merge
        sideToMerge[merge.mastodon.storageKey] = merge.id
        sideToMerge[merge.bluesky.storageKey] = merge.id
    }

    private func evictMerge(_ merge: MergedIdentity) {
        merges.removeValue(forKey: merge.id)
        sideToMerge.removeValue(forKey: merge.mastodon.storageKey)
        sideToMerge.removeValue(forKey: merge.bluesky.storageKey)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = userDefaults.data(forKey: defaultsKey),
              let persisted = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        for merge in persisted.userConfirmed {
            indexMerge(merge)
        }
        tombstones = Set(persisted.tombstones)
    }

    private func save() {
        let userConfirmed = merges.values.filter { $0.provenance == .userConfirmed }
        let persisted = Persisted(
            userConfirmed: Array(userConfirmed),
            tombstones: Array(tombstones)
        )
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        userDefaults.set(data, forKey: defaultsKey)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/MergedIdentityStoreTests`
Expected: PASS, all 7 tests green.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Stores/MergedIdentityStore.swift SocialFusionTests/MergedIdentityStoreTests.swift
git commit -m "feat(merge): add MergedIdentityStore with UserDefaults persistence + tombstones"
```

---

## Task 4: Wire MergedIdentityStore into the app root

**Files:**
- Modify: `SocialFusion/SocialFusionApp.swift`

Inject the store at app root so any view in any of the three scene branches (launch animation, onboarding, content) can access it.

- [ ] **Step 1: Add the StateObject and environment injections**

Open `SocialFusion/SocialFusionApp.swift`. Below the existing `@StateObject` declarations (currently ending with `crashReporting` at line 35), add:

```swift
// Merged identity store for cross-network profile unification
@StateObject private var mergedIdentityStore = MergedIdentityStore()
```

Then, in each of the three scene branches inside `body`, add `.environmentObject(mergedIdentityStore)` alongside the other store injections. Specifically:

In the `LaunchAnimationView` branch (currently at lines 53-69), after `.environmentObject(chatStreamService)`:

```swift
.environmentObject(chatStreamService)
.environmentObject(mergedIdentityStore)
```

In the `OnboardingView` branch (currently at lines 71-79), after `.environmentObject(chatStreamService)`:

```swift
.environmentObject(chatStreamService)
.environmentObject(mergedIdentityStore)
```

In the `ContentView` branch (currently at lines 81-107), after `.environmentObject(chatStreamService)`:

```swift
.environmentObject(chatStreamService)
.environmentObject(mergedIdentityStore)
```

- [ ] **Step 2: Verify the build succeeds**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add SocialFusion/SocialFusionApp.swift
git commit -m "feat(merge): inject MergedIdentityStore at app root"
```

---

## Task 5: MergedIdentityChip component

**Files:**
- Create: `SocialFusion/Views/Components/MergedIdentityChip.swift`

Small badge that appears near the profile avatar when a profile is part of a merged identity. Uses the launch-animation purple/blue/cyan palette so it visually rhymes with the Fuse glyph. Includes a glass material background to match `PlatformLogoBadge`.

- [ ] **Step 1: Implement the component**

Create `SocialFusion/Views/Components/MergedIdentityChip.swift`:

```swift
import SwiftUI

/// A pill-shaped chip indicating a profile is part of a merged identity.
///
/// Visually rhymes with the Fuse glyph: same purple/blue/cyan brand palette
/// from `LaunchAnimationView`. Tap target surfaces the unmerge / inspect
/// options; the chip itself is just visual indication.
///
/// Tappable: the parent supplies an `onTap` closure to present the unmerge
/// menu or details sheet.
public struct MergedIdentityChip: View {
    public let provenance: MergeProvenance
    public var onTap: (() -> Void)?

    private let purple = Color(red: 0.54, green: 0.39, blue: 1.00)
    private let blue = Color(red: 0.00, green: 0.59, blue: 1.00)
    private let cyan = Color(red: 0.11, green: 0.91, blue: 1.00)

    public init(provenance: MergeProvenance, onTap: (() -> Void)? = nil) {
        self.provenance = provenance
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 4) {
                miniGlyph
                Text("Merged identity")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule().fill(
                            LinearGradient(
                                colors: [purple.opacity(0.85), blue.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    )
            )
            .overlay(
                Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(onTap == nil ? "" : "Double-tap to manage this merge.")
    }

    private var miniGlyph: some View {
        ZStack {
            Circle().fill(purple).frame(width: 8, height: 8).offset(x: -2)
            Circle().fill(blue).frame(width: 8, height: 8).offset(x: 2)
            Ellipse().fill(cyan).frame(width: 2.6, height: 6.5)
        }
        .frame(width: 14, height: 10)
    }

    private var accessibilityLabel: String {
        switch provenance {
        case .userConfirmed:
            return "Merged identity, confirmed by you"
        case .verifiedBioCrossLink:
            return "Merged identity, verified via cross-network bio links"
        case .handleConvention:
            return "Merged identity, suggested from matching handles"
        }
    }
}

#if DEBUG
struct MergedIdentityChip_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            MergedIdentityChip(provenance: .userConfirmed)
            MergedIdentityChip(provenance: .verifiedBioCrossLink)
            MergedIdentityChip(provenance: .handleConvention)
        }
        .padding()
        .background(Color.gray.opacity(0.2))
    }
}
#endif
```

- [ ] **Step 2: Verify the preview renders**

In Xcode, open `MergedIdentityChip.swift`, resume the Canvas preview, and verify all three provenance variants render with the gradient capsule + mini glyph.

- [ ] **Step 3: Build to verify no compile errors**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add SocialFusion/Views/Components/MergedIdentityChip.swift
git commit -m "feat(merge): add MergedIdentityChip badge component"
```

---

## Task 6: MergedHandleSelector component

**Files:**
- Create: `SocialFusion/Views/Components/MergedHandleSelector.swift`

A two-segment selector showing both handles side by side with their `PlatformLogoBadge`s. Tapping a segment swaps which side's bio/fields/banner the profile header shows. The non-selected segment is dimmed but always visible — both handles are always on screen.

- [ ] **Step 1: Implement the component**

Create `SocialFusion/Views/Components/MergedHandleSelector.swift`:

```swift
import SwiftUI

/// A horizontal two-segment selector for a merged profile's handles.
///
/// Both handles are always visible — the merge is the point — but tapping a
/// segment swaps which side drives the bio, fields, and banner display in
/// the surrounding `ProfileHeaderView`.
public struct MergedHandleSelector: View {
    public let mastodonHandle: String
    public let blueskyHandle: String
    @Binding public var selected: SocialPlatform

    public init(
        mastodonHandle: String,
        blueskyHandle: String,
        selected: Binding<SocialPlatform>
    ) {
        self.mastodonHandle = mastodonHandle
        self.blueskyHandle = blueskyHandle
        self._selected = selected
    }

    public var body: some View {
        HStack(spacing: 8) {
            handleSegment(
                platform: .mastodon,
                handle: mastodonHandle,
                isSelected: selected == .mastodon
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selected = .mastodon
                }
            }

            handleSegment(
                platform: .bluesky,
                handle: blueskyHandle,
                isSelected: selected == .bluesky
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selected = .bluesky
                }
            }
        }
    }

    private func handleSegment(
        platform: SocialPlatform,
        handle: String,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 6) {
            PlatformLogoBadge(platform: platform, size: 18, shadowEnabled: false)
            Text("@\(handle)")
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color(.secondarySystemBackground) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isSelected ? Color.primary.opacity(0.15) : Color.clear,
                    lineWidth: 0.5
                )
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(platform.rawValue.capitalized) handle, at \(handle)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

#if DEBUG
struct MergedHandleSelector_Previews: PreviewProvider {
    struct Wrapper: View {
        @State var selected: SocialPlatform = .mastodon
        var body: some View {
            MergedHandleSelector(
                mastodonHandle: "gruber@mastodon.social",
                blueskyHandle: "gruber.bsky.social",
                selected: $selected
            )
            .padding()
        }
    }
    static var previews: some View {
        Wrapper()
    }
}
#endif
```

- [ ] **Step 2: Build to verify no compile errors**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add SocialFusion/Views/Components/MergedHandleSelector.swift
git commit -m "feat(merge): add MergedHandleSelector dual-handle component"
```

---

## Task 7: Extend ProfileViewModel — merged twin loading + handle selection

**Files:**
- Modify: `SocialFusion/ViewModels/ProfileViewModel.swift`
- Test: `SocialFusionTests/ProfileViewModelMergeTests.swift`

Teach `ProfileViewModel` how to discover a twin profile via the store and the matcher, load it from the opposite-network account, expose a `selectedSide` binding so the UI can swap which bio is shown, and surface confirm/unmerge intents.

- [ ] **Step 1: Write the failing tests**

Create `SocialFusionTests/ProfileViewModelMergeTests.swift`:

```swift
import XCTest
@testable import SocialFusion

@MainActor
final class ProfileViewModelMergeTests: XCTestCase {
    func testSelectedSideDefaultsToProfilePlatform() {
        let user = SearchUser(id: "m1", username: "x@mastodon.social", platform: .mastodon)
        let vm = ProfileViewModel(
            user: user, isOwnProfile: false,
            serviceManager: SocialServiceManager()
        )
        XCTAssertEqual(vm.selectedSide, .mastodon)
    }

    func testMergedProfileBindingReadsMastodonProfileWhenMastodonSelected() {
        let user = SearchUser(id: "m1", username: "x@mastodon.social", platform: .mastodon)
        let vm = ProfileViewModel(
            user: user, isOwnProfile: false,
            serviceManager: SocialServiceManager()
        )
        let mastoProfile = makeProfile(id: "m1", username: "x@mastodon.social", platform: .mastodon)
        let bskyProfile = makeProfile(id: "b1", username: "x.bsky.social", platform: .bluesky)
        vm.profile = mastoProfile
        vm.mergedTwinProfile = bskyProfile
        vm.selectedSide = .mastodon
        XCTAssertEqual(vm.activeProfile?.id, "m1")
        vm.selectedSide = .bluesky
        XCTAssertEqual(vm.activeProfile?.id, "b1")
    }

    func testCombinedFollowerAndFollowingCountsSumWhenMerged() {
        let user = SearchUser(id: "m1", username: "x@mastodon.social", platform: .mastodon)
        let vm = ProfileViewModel(
            user: user, isOwnProfile: false,
            serviceManager: SocialServiceManager()
        )
        vm.profile = makeProfile(
            id: "m1", username: "x@mastodon.social", platform: .mastodon,
            followersCount: 100, followingCount: 50, statusesCount: 200
        )
        vm.mergedTwinProfile = makeProfile(
            id: "b1", username: "x.bsky.social", platform: .bluesky,
            followersCount: 70, followingCount: 30, statusesCount: 150
        )
        XCTAssertEqual(vm.combinedFollowersCount, 170)
        XCTAssertEqual(vm.combinedFollowingCount, 80)
        XCTAssertEqual(vm.combinedStatusesCount, 350)
    }

    func testCombinedCountsFallBackToActiveProfileWhenUnmerged() {
        let user = SearchUser(id: "m1", username: "x@mastodon.social", platform: .mastodon)
        let vm = ProfileViewModel(
            user: user, isOwnProfile: false,
            serviceManager: SocialServiceManager()
        )
        vm.profile = makeProfile(
            id: "m1", username: "x@mastodon.social", platform: .mastodon,
            followersCount: 100, followingCount: 50, statusesCount: 200
        )
        vm.mergedTwinProfile = nil
        XCTAssertEqual(vm.combinedFollowersCount, 100)
        XCTAssertEqual(vm.combinedFollowingCount, 50)
        XCTAssertEqual(vm.combinedStatusesCount, 200)
    }

    private func makeProfile(
        id: String, username: String, platform: SocialPlatform,
        followersCount: Int = 0, followingCount: Int = 0, statusesCount: Int = 0
    ) -> UserProfile {
        UserProfile(
            id: id, username: username, displayName: nil,
            avatarURL: nil, headerURL: nil, bio: nil,
            followersCount: followersCount,
            followingCount: followingCount,
            statusesCount: statusesCount,
            platform: platform
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/ProfileViewModelMergeTests`
Expected: FAIL — `selectedSide`, `mergedTwinProfile`, `combinedFollowersCount`, `combinedFollowingCount`, `combinedStatusesCount`, and `activeProfile` are not yet defined.

- [ ] **Step 3: Extend ProfileViewModel**

Open `SocialFusion/ViewModels/ProfileViewModel.swift`. Below the existing `// MARK: - Profile State` block (around line 22, after `@Published var profileError: Error?`), add:

```swift
// MARK: - Merged Identity State

/// The twin profile fetched from the opposite network when this profile
/// participates in a merged identity. Nil when no merge is active.
@Published var mergedTwinProfile: UserProfile?

/// The merged-identity record this profile is bound to, if any.
@Published var mergedIdentity: MergedIdentity?

/// Which side's bio/fields/banner is currently rendered in the header.
/// Defaults to the side the user navigated in on.
@Published var selectedSide: SocialPlatform

/// Whether a merge-confirmation sheet should be presented.
@Published var showMergeConfirmation: Bool = false

/// Candidate proposed by the matcher but not yet confirmed/dismissed.
/// Drives the in-line "Looks like this is also @x.bsky.social?" prompt.
@Published var pendingMatchCandidate: MergedIdentity?
```

Then update the existing designated initializer (currently at line 81) to seed `selectedSide`:

Replace this block:

```swift
init(user: SearchUser, isOwnProfile: Bool = false, serviceManager: SocialServiceManager) {
    self.user = user
    self.isOwnProfile = isOwnProfile
    self.serviceManager = serviceManager
}
```

With:

```swift
init(user: SearchUser, isOwnProfile: Bool = false, serviceManager: SocialServiceManager) {
    self.user = user
    self.isOwnProfile = isOwnProfile
    self.serviceManager = serviceManager
    self.selectedSide = user.platform
}
```

Below the `// MARK: - Computed Properties` block (around line 53), add:

```swift
// MARK: - Merge-Derived Computed Properties

/// The profile currently driving the header bio/fields/banner — either
/// `profile` or `mergedTwinProfile` depending on `selectedSide`.
var activeProfile: UserProfile? {
    guard let base = profile else { return nil }
    if let twin = mergedTwinProfile, selectedSide != base.platform {
        return twin
    }
    return base
}

/// Returns true when this profile participates in a merge and both sides
/// have been loaded.
var isMerged: Bool {
    mergedIdentity != nil && mergedTwinProfile != nil
}

var combinedFollowersCount: Int {
    (profile?.followersCount ?? 0) + (mergedTwinProfile?.followersCount ?? 0)
}

var combinedFollowingCount: Int {
    (profile?.followingCount ?? 0) + (mergedTwinProfile?.followingCount ?? 0)
}

var combinedStatusesCount: Int {
    (profile?.statusesCount ?? 0) + (mergedTwinProfile?.statusesCount ?? 0)
}
```

Below the existing `// MARK: - Profile Loading` block (around line 100), replace the existing `loadProfile()` method body and add new merge-aware loading methods. The new `loadProfile()`:

```swift
/// Load the full UserProfile from the API, then attempt to resolve a
/// merged twin profile from the opposite network.
func loadProfile() async {
    guard profile == nil, !isLoadingProfile else { return }

    guard let account = serviceManager.accounts.first(where: { $0.platform == user.platform })
    else {
        profileError = ProfileViewModelError.noAccountForPlatform(user.platform)
        return
    }

    isLoadingProfile = true
    profileError = nil

    do {
        let result = try await serviceManager.fetchUserProfile(user: user, account: account)
        profile = result
        await resolveMergedTwin(for: result)
    } catch {
        profileError = error
    }

    isLoadingProfile = false
}

/// Resolve and (if present) load the twin profile from the opposite network.
/// Side-effect: sets `mergedIdentity`, `mergedTwinProfile`, and/or
/// `pendingMatchCandidate` on the view model.
///
/// Resolution order, matching the spec's Principle 2 priority:
/// 1. User-confirmed merge from `MergedIdentityStore` → load twin, set merge.
/// 2. Heuristic match from `IdentityMatcher` against a probable twin → set
///    `pendingMatchCandidate` so the UI can prompt the user.
private func resolveMergedTwin(for profile: UserProfile) async {
    let oppositePlatform: SocialPlatform = profile.platform == .mastodon ? .bluesky : .mastodon
    guard let store = mergedIdentityStore else { return }
    guard let account = serviceManager.accounts.first(where: { $0.platform == oppositePlatform })
    else { return }

    // 1. User-confirmed merge wins.
    if let confirmed = store.merge(forPlatform: profile.platform, accountID: profile.id) {
        let twinKey = confirmed.twin(of: profile.platform)
        await loadTwinProfile(
            twinAccountID: twinKey.accountID,
            twinHandle: twinKey.handle,
            twinPlatform: twinKey.platform,
            account: account,
            displayNameEmojiMap: nil
        )
        mergedIdentity = confirmed
        return
    }

    // 2. Heuristic match against a probable twin candidate.
    if let candidateUser = await findHeuristicTwinCandidate(for: profile, account: account) {
        let candidateProfile = try? await serviceManager.fetchUserProfile(
            user: candidateUser, account: account
        )
        guard let candidateProfile else { return }
        let matcher = IdentityMatcher()
        let (mastodon, bluesky) = orderProfiles(profile, candidateProfile)
        if let match = matcher.match(mastodon: mastodon, bluesky: bluesky) {
            // Verified-bio matches we auto-apply; handle-convention is offered as a prompt.
            switch match.provenance {
            case .verifiedBioCrossLink:
                store.insert([match])
                mergedIdentity = match
                mergedTwinProfile = candidateProfile
            case .handleConvention:
                pendingMatchCandidate = match
            case .userConfirmed:
                break // not produced by the matcher
            }
        }
    }
}

/// Searches the opposite network for a profile whose handle matches the
/// shared local-part — the cheapest signal for finding a candidate.
private func findHeuristicTwinCandidate(
    for profile: UserProfile,
    account: SocialAccount
) async -> SearchUser? {
    let localPart: String
    switch profile.platform {
    case .mastodon:
        // user@instance → "user"
        localPart = String(profile.username.split(separator: "@", maxSplits: 1).first ?? "")
    case .bluesky:
        // user.example.com → "user"
        localPart = String(profile.username.split(separator: ".", maxSplits: 1).first ?? "")
    }
    guard !localPart.isEmpty else { return nil }
    do {
        let result = try await serviceManager.searchUsers(query: localPart, account: account, limit: 5)
        return result.first(where: { user in
            switch user.platform {
            case .mastodon:
                let parts = user.username.split(separator: "@", maxSplits: 1)
                return parts.first.map(String.init)?.lowercased() == localPart.lowercased()
            case .bluesky:
                let parts = user.username.split(separator: ".", maxSplits: 1)
                return parts.first.map(String.init)?.lowercased() == localPart.lowercased()
            }
        })
    } catch {
        return nil
    }
}

private func loadTwinProfile(
    twinAccountID: String,
    twinHandle: String,
    twinPlatform: SocialPlatform,
    account: SocialAccount,
    displayNameEmojiMap: [String: String]?
) async {
    let twinUser = SearchUser(
        id: twinAccountID,
        username: twinHandle,
        displayName: nil,
        avatarURL: nil,
        platform: twinPlatform,
        displayNameEmojiMap: displayNameEmojiMap
    )
    do {
        mergedTwinProfile = try await serviceManager.fetchUserProfile(user: twinUser, account: account)
    } catch {
        // Non-fatal: surface header without twin; UI still shows the chip and
        // a degraded "twin unavailable" hint when needed.
        mergedTwinProfile = nil
    }
}

private func orderProfiles(_ a: UserProfile, _ b: UserProfile) -> (mastodon: UserProfile, bluesky: UserProfile) {
    if a.platform == .mastodon { return (a, b) } else { return (b, a) }
}

// MARK: - Merge Actions

/// Confirm a pending heuristic match and persist it.
func confirmPendingMatch() {
    guard let candidate = pendingMatchCandidate, let store = mergedIdentityStore else { return }
    store.confirmMerge(mastodon: candidate.mastodon, bluesky: candidate.bluesky)
    mergedIdentity = store.merge(forPlatform: candidate.mastodon.platform, accountID: candidate.mastodon.accountID)
    pendingMatchCandidate = nil
    // The twin profile was already fetched during resolution; if not, fetch now.
    if mergedTwinProfile == nil, let profile = profile {
        let twinKey = candidate.twin(of: profile.platform)
        if let account = serviceManager.accounts.first(where: { $0.platform == twinKey.platform }) {
            Task {
                await loadTwinProfile(
                    twinAccountID: twinKey.accountID,
                    twinHandle: twinKey.handle,
                    twinPlatform: twinKey.platform,
                    account: account,
                    displayNameEmojiMap: nil
                )
            }
        }
    }
}

/// Dismiss a pending heuristic match without persisting anything.
func dismissPendingMatch() {
    pendingMatchCandidate = nil
}

/// Unmerge this profile from its twin and clear local state.
func unmerge() {
    guard let merge = mergedIdentity, let store = mergedIdentityStore else { return }
    store.unmerge(id: merge.id)
    mergedIdentity = nil
    mergedTwinProfile = nil
    selectedSide = profile?.platform ?? user.platform
}
```

Finally, add the store reference at the top of the class. Below the line `let user: SearchUser` (around line 49), add:

```swift
/// Side-channel store injected by the view via `attach(mergedIdentityStore:)`.
private(set) weak var mergedIdentityStore: MergedIdentityStore?

/// Called by the surrounding View on first appearance to bind the store.
func attach(mergedIdentityStore: MergedIdentityStore) {
    self.mergedIdentityStore = mergedIdentityStore
}
```

The store is intentionally injected lazily via `attach(_:)` rather than the initializer to avoid cascading constructor changes on every existing call site. The view passes it in via `.task`.

- [ ] **Step 4: Verify SocialServiceManager exposes a searchUsers method**

The `findHeuristicTwinCandidate(...)` method calls `serviceManager.searchUsers(query:account:limit:)`. Confirm this method exists on `SocialServiceManager`. If it does not exist exactly under that signature but search functionality lives in `SearchStore` / `UnifiedSearchProvider`, add a thin wrapper to `SocialServiceManager`:

```swift
/// Search for users on the same network as the supplied account, returning
/// up to `limit` candidates. Used by ProfileViewModel for merged-identity
/// candidate discovery.
public func searchUsers(query: String, account: SocialAccount, limit: Int) async throws -> [SearchUser] {
    switch account.platform {
    case .mastodon:
        return try await mastodonService.searchUsers(query: query, account: account, limit: limit)
    case .bluesky:
        return try await blueskyService.searchUsers(query: query, account: account, limit: limit)
    }
}
```

If either platform-specific service lacks `searchUsers(query:account:limit:)`, reuse the existing search code path used by `SearchView` — search is already a built-in feature per `CLAUDE.md` "What Works." The minimal contract here is: return `[SearchUser]` matching the query on a single network.

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/ProfileViewModelMergeTests`
Expected: PASS, all 4 tests green.

- [ ] **Step 6: Commit**

```bash
git add SocialFusion/ViewModels/ProfileViewModel.swift SocialFusion/Services/SocialServiceManager.swift SocialFusionTests/ProfileViewModelMergeTests.swift
git commit -m "feat(merge): extend ProfileViewModel with twin loading and merge actions"
```

---

## Task 8: MergeConfirmationSheet (handle-convention prompt)

**Files:**
- Create: `SocialFusion/Views/MergeConfirmationSheet.swift`

A sheet shown when the matcher's handle-convention heuristic finds a likely twin but the user hasn't confirmed yet. Shows both profiles' avatars + handles, the reason ("Same handle on `mastodon.social` and `bsky.social`"), and three actions: Confirm merge, Not the same person, Decide later.

- [ ] **Step 1: Implement the sheet**

Create `SocialFusion/Views/MergeConfirmationSheet.swift`:

```swift
import SwiftUI

/// Sheet that asks the user to confirm a heuristic merge candidate.
///
/// Used only for `.handleConvention` provenance — verified bio cross-links
/// auto-apply without asking. User-confirmed merges persist; "Not the same
/// person" inserts a tombstone via `unmerge(id:)` semantics.
public struct MergeConfirmationSheet: View {
    public let candidate: MergedIdentity
    public let mastodonAvatarURL: String?
    public let blueskyAvatarURL: String?
    public let onConfirm: () -> Void
    public let onReject: () -> Void
    public let onDismiss: () -> Void

    public init(
        candidate: MergedIdentity,
        mastodonAvatarURL: String?,
        blueskyAvatarURL: String?,
        onConfirm: @escaping () -> Void,
        onReject: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.candidate = candidate
        self.mastodonAvatarURL = mastodonAvatarURL
        self.blueskyAvatarURL = blueskyAvatarURL
        self.onConfirm = onConfirm
        self.onReject = onReject
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 20) {
            header
            pairSummary
            reasonLine
            Spacer(minLength: 0)
            actions
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(spacing: 6) {
            MergedIdentityChip(provenance: candidate.provenance)
            Text("Looks like the same person")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Confirm to view both profiles as one.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private var pairSummary: some View {
        HStack(spacing: 12) {
            sideCard(
                platform: .mastodon,
                handle: candidate.mastodon.handle,
                avatarURL: mastodonAvatarURL
            )
            Image(systemName: "arrow.left.and.right")
                .font(.headline)
                .foregroundStyle(.secondary)
            sideCard(
                platform: .bluesky,
                handle: candidate.bluesky.handle,
                avatarURL: blueskyAvatarURL
            )
        }
    }

    private func sideCard(platform: SocialPlatform, handle: String, avatarURL: String?) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                avatarView(urlString: avatarURL)
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                PlatformLogoBadge(platform: platform, size: 22)
                    .offset(x: 2, y: 2)
            }
            Text("@\(handle)")
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func avatarView(urlString: String?) -> some View {
        if let urlString = urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle().fill(Color(.secondarySystemBackground))
            }
        } else {
            Circle().fill(Color(.secondarySystemBackground))
                .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
        }
    }

    private var reasonLine: some View {
        let reason: String = {
            switch candidate.provenance {
            case .handleConvention:
                return "Both handles share \"@\(localPart(candidate.mastodon.handle))\" on conventional domains."
            case .verifiedBioCrossLink:
                return "Each profile's bio verifiably links to the other."
            case .userConfirmed:
                return "You confirmed this merge."
            }
        }()
        return Text(reason)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    private func localPart(_ handle: String) -> String {
        if let at = handle.firstIndex(of: "@") {
            return String(handle[..<at])
        }
        if let dot = handle.firstIndex(of: ".") {
            return String(handle[..<dot])
        }
        return handle
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: onConfirm) {
                Text("Confirm merge")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            Button(action: onReject) {
                Text("Not the same person")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            Button("Decide later", action: onDismiss)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
struct MergeConfirmationSheet_Previews: PreviewProvider {
    static var previews: some View {
        MergeConfirmationSheet(
            candidate: MergedIdentity(
                mastodon: MergedIdentityKey(platform: .mastodon, accountID: "m1", handle: "gruber@mastodon.social"),
                bluesky: MergedIdentityKey(platform: .bluesky, accountID: "b1", handle: "gruber.bsky.social"),
                provenance: .handleConvention,
                confidence: 0.78
            ),
            mastodonAvatarURL: nil,
            blueskyAvatarURL: nil,
            onConfirm: {}, onReject: {}, onDismiss: {}
        )
    }
}
#endif
```

- [ ] **Step 2: Build to verify no compile errors**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add SocialFusion/Views/MergeConfirmationSheet.swift
git commit -m "feat(merge): add MergeConfirmationSheet for heuristic candidate prompts"
```

---

## Task 9: Integrate merged-identity rendering into ProfileHeaderView

**Files:**
- Modify: `SocialFusion/Views/Components/ProfileHeaderView.swift`

Surface the chip, dual-handle selector, combined-counts row, and unmerge menu entry inside the existing header. The header remains a single source of truth for the avatar/banner/bio surface — it just consumes additional optional inputs that activate the merged surface when present.

- [ ] **Step 1: Extend the ProfileHeaderView API**

Open `SocialFusion/Views/Components/ProfileHeaderView.swift`. Modify the struct declaration block (currently at lines 87-100) to add merge inputs. Replace this block:

```swift
struct ProfileHeaderView: View {
  let profile: UserProfile
  let isOwnProfile: Bool
  var onEditProfile: (() -> Void)?
  var relationshipState: (isFollowing: Bool, isFollowedBy: Bool, isMuting: Bool, isBlocking: Bool)?
  var onFollow: (() -> Void)?
  var onUnfollow: (() -> Void)?
  var onMute: (() -> Void)?
  var onUnmute: (() -> Void)?
  var onBlock: (() -> Void)?
  var onUnblock: (() -> Void)?
  /// Binding that the header sets to true when the avatar has scrolled past the nav bar
  @Binding var isAvatarDocked: Bool
  var scrollOffset: CGFloat = 0
```

With:

```swift
struct ProfileHeaderView: View {
  let profile: UserProfile
  let isOwnProfile: Bool
  var onEditProfile: (() -> Void)?
  var relationshipState: (isFollowing: Bool, isFollowedBy: Bool, isMuting: Bool, isBlocking: Bool)?
  var onFollow: (() -> Void)?
  var onUnfollow: (() -> Void)?
  var onMute: (() -> Void)?
  var onUnmute: (() -> Void)?
  var onBlock: (() -> Void)?
  var onUnblock: (() -> Void)?
  /// Binding that the header sets to true when the avatar has scrolled past the nav bar
  @Binding var isAvatarDocked: Bool
  var scrollOffset: CGFloat = 0

  // MARK: - Merged Identity Inputs (all optional; absent means no merge active)
  var mergedIdentity: MergedIdentity? = nil
  var mergedTwinProfile: UserProfile? = nil
  @Binding var selectedSide: SocialPlatform
  var combinedFollowersCount: Int? = nil
  var combinedFollowingCount: Int? = nil
  var combinedStatusesCount: Int? = nil
  var onUnmerge: (() -> Void)? = nil
  var onTapMergeChip: (() -> Void)? = nil
```

Because the existing call sites do not pass `selectedSide`, we need an internal default. Add a private state-driven default at the top of the body, but in practice we cannot have `@Binding` with a default-property in a `View` struct without a wrapper. Solution: provide a convenience init that supplies a constant binding when the caller has no merge. Add immediately below the `var onTapMergeChip` line:

```swift
}

extension ProfileHeaderView {
  /// Convenience init for non-merged headers — supplies a constant binding
  /// for `selectedSide` so existing call sites keep working unchanged.
  init(
    profile: UserProfile,
    isOwnProfile: Bool,
    onEditProfile: (() -> Void)? = nil,
    relationshipState: (isFollowing: Bool, isFollowedBy: Bool, isMuting: Bool, isBlocking: Bool)? = nil,
    onFollow: (() -> Void)? = nil,
    onUnfollow: (() -> Void)? = nil,
    onMute: (() -> Void)? = nil,
    onUnmute: (() -> Void)? = nil,
    onBlock: (() -> Void)? = nil,
    onUnblock: (() -> Void)? = nil,
    isAvatarDocked: Binding<Bool>,
    scrollOffset: CGFloat = 0
  ) {
    self.profile = profile
    self.isOwnProfile = isOwnProfile
    self.onEditProfile = onEditProfile
    self.relationshipState = relationshipState
    self.onFollow = onFollow
    self.onUnfollow = onUnfollow
    self.onMute = onMute
    self.onUnmute = onUnmute
    self.onBlock = onBlock
    self.onUnblock = onUnblock
    self._isAvatarDocked = isAvatarDocked
    self.scrollOffset = scrollOffset
    self.mergedIdentity = nil
    self.mergedTwinProfile = nil
    self._selectedSide = .constant(profile.platform)
    self.combinedFollowersCount = nil
    self.combinedFollowingCount = nil
    self.combinedStatusesCount = nil
    self.onUnmerge = nil
    self.onTapMergeChip = nil
  }
```

(That extension brace closes the convenience init scope. The closing `}` of the struct body lower in the file remains in place — you are only inserting the convenience init at the same nesting level as the existing properties.)

> **Note for the implementing engineer:** in Swift, a SwiftUI `View` struct cannot define an extension with a stored-property-touching init in the same file in the literal arrangement shown above — instead, define the convenience init as a *second* designated init *inside* the `struct ProfileHeaderView` body, immediately below the property list and above the `// MARK: - Constants` line. The bodies and parameter list are exactly as written above; only the wrapping `extension` block is conceptual. Use:

```swift
  // Convenience init for non-merged headers
  init(
    profile: UserProfile,
    isOwnProfile: Bool,
    onEditProfile: (() -> Void)? = nil,
    relationshipState: (isFollowing: Bool, isFollowedBy: Bool, isMuting: Bool, isBlocking: Bool)? = nil,
    onFollow: (() -> Void)? = nil,
    onUnfollow: (() -> Void)? = nil,
    onMute: (() -> Void)? = nil,
    onUnmute: (() -> Void)? = nil,
    onBlock: (() -> Void)? = nil,
    onUnblock: (() -> Void)? = nil,
    isAvatarDocked: Binding<Bool>,
    scrollOffset: CGFloat = 0
  ) {
    self.profile = profile
    self.isOwnProfile = isOwnProfile
    self.onEditProfile = onEditProfile
    self.relationshipState = relationshipState
    self.onFollow = onFollow
    self.onUnfollow = onUnfollow
    self.onMute = onMute
    self.onUnmute = onUnmute
    self.onBlock = onBlock
    self.onUnblock = onUnblock
    self._isAvatarDocked = isAvatarDocked
    self.scrollOffset = scrollOffset
    self.mergedIdentity = nil
    self.mergedTwinProfile = nil
    self._selectedSide = .constant(profile.platform)
    self.combinedFollowersCount = nil
    self.combinedFollowingCount = nil
    self.combinedStatusesCount = nil
    self.onUnmerge = nil
    self.onTapMergeChip = nil
  }
```

- [ ] **Step 2: Render the merge chip, handle selector, and unmerge menu entry**

Inside `var body: some View` (currently around line 120), modify the `identitySection` block so it renders the chip when a merge is present, and renders the `MergedHandleSelector` instead of the single-handle `Text("@\(profile.username)")` when merged.

Replace the existing `identitySection`:

```swift
  // MARK: - Identity

  private var identitySection: some View {
    VStack(alignment: .leading, spacing: 2) {
      EmojiDisplayNameText(
        profile.displayName ?? profile.username,
        emojiMap: profile.displayNameEmojiMap,
        font: .title2,
        fontWeight: .bold,
        foregroundColor: .primary,
        lineLimit: 2
      )

      Text("@\(profile.username)")
        .font(.subheadline)
        .foregroundColor(.secondary)
        .lineLimit(1)
    }
    .padding(.horizontal, Layout.horizontalPadding)
    .padding(.top, 8)
  }
```

With:

```swift
  // MARK: - Identity

  private var identitySection: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let merge = mergedIdentity {
        MergedIdentityChip(provenance: merge.provenance, onTap: onTapMergeChip)
          .padding(.bottom, 2)
      }

      EmojiDisplayNameText(
        profile.displayName ?? profile.username,
        emojiMap: profile.displayNameEmojiMap,
        font: .title2,
        fontWeight: .bold,
        foregroundColor: .primary,
        lineLimit: 2
      )

      if mergedIdentity != nil, let twin = mergedTwinProfile {
        MergedHandleSelector(
          mastodonHandle: profile.platform == .mastodon ? profile.username : twin.username,
          blueskyHandle: profile.platform == .bluesky ? profile.username : twin.username,
          selected: $selectedSide
        )
      } else {
        Text("@\(profile.username)")
          .font(.subheadline)
          .foregroundColor(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, Layout.horizontalPadding)
    .padding(.top, 8)
  }
```

- [ ] **Step 3: Surface unmerge in the existing following-action menu**

Inside `private func followingButton(isMuting: Bool) -> some View` (currently around line 304), add an additional menu entry inside the `Menu { ... }` block, just above the `Divider()`:

```swift
    Menu {
      Button(role: .destructive, action: { onUnfollow?() }) {
        Label("Unfollow", systemImage: "person.badge.minus")
      }
      if let onUnmerge = onUnmerge {
        Button(role: .destructive, action: onUnmerge) {
          Label("Unmerge identities", systemImage: "person.crop.circle.badge.minus")
        }
      }
      Divider()
      // … existing mute / block entries stay unchanged …
```

For non-following users (own profile, or when no following relationship exists yet), expose unmerge via the chip's `onTap` action — the parent View routes the chip tap to a context menu or sheet that includes "Unmerge."

- [ ] **Step 4: Show combined stats with per-network breakdown when merged**

Replace the existing `private var statsRow: some View` (currently around line 502):

```swift
  // MARK: - Stats

  private var statsRow: some View {
    HStack(spacing: 16) {
      statItem(count: profile.statusesCount, label: "Posts")
      statItem(count: profile.followingCount, label: "Following")
      statItem(count: profile.followersCount, label: "Followers")
      Spacer()
    }
    .padding(.horizontal, Layout.horizontalPadding)
    .padding(.top, 12)
    .padding(.bottom, 8)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(profile.statusesCount) posts, \(profile.followingCount) following, \(profile.followersCount) followers")
  }
```

With:

```swift
  // MARK: - Stats

  private var statsRow: some View {
    let posts = combinedStatusesCount ?? profile.statusesCount
    let following = combinedFollowingCount ?? profile.followingCount
    let followers = combinedFollowersCount ?? profile.followersCount

    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 16) {
        statItem(count: posts, label: "Posts")
        statItem(count: following, label: "Following")
        statItem(count: followers, label: "Followers")
        Spacer()
      }

      if mergedIdentity != nil, let twin = mergedTwinProfile {
        breakdownRow(twin: twin)
      }
    }
    .padding(.horizontal, Layout.horizontalPadding)
    .padding(.top, 12)
    .padding(.bottom, 8)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(statsAccessibilityLabel(posts: posts, following: following, followers: followers))
  }

  private func breakdownRow(twin: UserProfile) -> some View {
    HStack(spacing: 12) {
      HStack(spacing: 4) {
        PlatformLogoBadge(platform: .mastodon, size: 12, shadowEnabled: false)
        let mastoCount = profile.platform == .mastodon ? profile.followersCount : twin.followersCount
        Text("\(Self.formatCount(mastoCount))")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      HStack(spacing: 4) {
        PlatformLogoBadge(platform: .bluesky, size: 12, shadowEnabled: false)
        let bskyCount = profile.platform == .bluesky ? profile.followersCount : twin.followersCount
        Text("\(Self.formatCount(bskyCount))")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(breakdownAccessibilityLabel(twin: twin))
  }

  private func statsAccessibilityLabel(posts: Int, following: Int, followers: Int) -> String {
    if mergedIdentity != nil {
      return "Combined: \(posts) posts, \(following) following, \(followers) followers"
    } else {
      return "\(posts) posts, \(following) following, \(followers) followers"
    }
  }

  private func breakdownAccessibilityLabel(twin: UserProfile) -> String {
    let mastoCount = profile.platform == .mastodon ? profile.followersCount : twin.followersCount
    let bskyCount = profile.platform == .bluesky ? profile.followersCount : twin.followersCount
    return "Per network: \(mastoCount) Mastodon followers, \(bskyCount) Bluesky followers"
  }
```

- [ ] **Step 5: Build**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED. Existing previews and call sites continue compiling because the new convenience init preserves the old call signature.

- [ ] **Step 6: Commit**

```bash
git add SocialFusion/Views/Components/ProfileHeaderView.swift
git commit -m "feat(merge): render merge chip, handle selector, and combined stats in profile header"
```

---

## Task 10: Wire the merged header into ProfileView

**Files:**
- Modify: `SocialFusion/Views/ProfileView.swift`

`ProfileView` is the surrounding container. Inject the `MergedIdentityStore`, attach it to the view model on first appearance, and route the new merge bindings/actions/sheet into `ProfileHeaderView`.

- [ ] **Step 1: Inject the store and wire it into the view model**

Open `SocialFusion/Views/ProfileView.swift`. At the top, alongside the existing `@EnvironmentObject var serviceManager: SocialServiceManager` (line 8), add:

```swift
  @EnvironmentObject var mergedIdentityStore: MergedIdentityStore
```

In the `.task { … }` block (currently at lines 114-118), insert the attach call as the very first statement:

Replace:

```swift
    .task {
      await viewModel.loadProfile()
      await viewModel.loadPostsForCurrentTab()
      setupRelationshipViewModel()
    }
```

With:

```swift
    .task {
      viewModel.attach(mergedIdentityStore: mergedIdentityStore)
      await viewModel.loadProfile()
      await viewModel.loadPostsForCurrentTab()
      setupRelationshipViewModel()
    }
```

- [ ] **Step 2: Route the merge inputs into ProfileHeaderView**

In the body (lines 47-83), modify the existing `ProfileHeaderView(...)` instantiation. Replace this block:

```swift
            ProfileHeaderView(
              profile: profile,
              isOwnProfile: viewModel.isOwnProfile,
              onEditProfile: { showEditProfile = true },
              relationshipState: relationshipState,
              onFollow: { Task { await relationshipViewModel?.follow() } },
              onUnfollow: { Task { await relationshipViewModel?.unfollow() } },
              onMute: { Task { await relationshipViewModel?.mute() } },
              onUnmute: { Task { await relationshipViewModel?.unmute() } },
              onBlock: { Task { await relationshipViewModel?.block() } },
              onUnblock: { Task { await relationshipViewModel?.unblock() } },
              isAvatarDocked: $isAvatarDocked,
              scrollOffset: scrollOffset
            )
```

With:

```swift
            ProfileHeaderView(
              profile: viewModel.activeProfile ?? profile,
              isOwnProfile: viewModel.isOwnProfile,
              onEditProfile: { showEditProfile = true },
              relationshipState: relationshipState,
              onFollow: { Task { await relationshipViewModel?.follow() } },
              onUnfollow: { Task { await relationshipViewModel?.unfollow() } },
              onMute: { Task { await relationshipViewModel?.mute() } },
              onUnmute: { Task { await relationshipViewModel?.unmute() } },
              onBlock: { Task { await relationshipViewModel?.block() } },
              onUnblock: { Task { await relationshipViewModel?.unblock() } },
              isAvatarDocked: $isAvatarDocked,
              scrollOffset: scrollOffset,
              mergedIdentity: viewModel.mergedIdentity,
              mergedTwinProfile: viewModel.mergedTwinProfile,
              selectedSide: $viewModel.selectedSide,
              combinedFollowersCount: viewModel.isMerged ? viewModel.combinedFollowersCount : nil,
              combinedFollowingCount: viewModel.isMerged ? viewModel.combinedFollowingCount : nil,
              combinedStatusesCount: viewModel.isMerged ? viewModel.combinedStatusesCount : nil,
              onUnmerge: { viewModel.unmerge() },
              onTapMergeChip: { showMergeChipMenu = true }
            )
```

This instantiation is now the *full* designated init (not the convenience init from Task 9). The header has both forms; this call site uses the merged one.

- [ ] **Step 3: Add state for the chip menu and the candidate sheet**

In the `@State` declarations near the top of `ProfileView` (currently around lines 11-15), add:

```swift
  @State private var showMergeChipMenu = false
```

The pending-candidate sheet is driven by `viewModel.pendingMatchCandidate`. At the end of the body, just before the closing `}` of the outermost `var body`, attach the modifiers:

Find the line:

```swift
    .onChange(of: viewModel.selectedTab) { _, _ in
      Task { await viewModel.loadPostsForCurrentTab() }
```

and *above* it (preserving the rest of the body intact), add:

```swift
    .sheet(item: $viewModel.pendingMatchCandidate) { candidate in
      MergeConfirmationSheet(
        candidate: candidate,
        mastodonAvatarURL: candidate.mastodon.platform == .mastodon
          ? viewModel.profile?.avatarURL
          : viewModel.mergedTwinProfile?.avatarURL,
        blueskyAvatarURL: candidate.bluesky.platform == .bluesky
          ? viewModel.profile?.avatarURL
          : viewModel.mergedTwinProfile?.avatarURL,
        onConfirm: {
          viewModel.confirmPendingMatch()
        },
        onReject: {
          // Treat reject as a tombstone-equivalent: dismiss the candidate
          // and don't re-prompt for the same pair in this session.
          viewModel.dismissPendingMatch()
        },
        onDismiss: {
          viewModel.dismissPendingMatch()
        }
      )
    }
    .confirmationDialog(
      "Merged identity",
      isPresented: $showMergeChipMenu,
      titleVisibility: .visible
    ) {
      if let merge = viewModel.mergedIdentity {
        Button(mergeProvenanceLabel(merge.provenance)) {
          // Information-only row; selecting it just dismisses.
        }
        Button("Unmerge identities", role: .destructive) {
          viewModel.unmerge()
        }
        Button("Cancel", role: .cancel) {}
      }
    } message: {
      if let merge = viewModel.mergedIdentity {
        Text("@\(merge.mastodon.handle) and @\(merge.bluesky.handle) are shown as the same person.")
      }
    }
```

Add the helper at the end of the struct (below `var body`):

```swift
  private func mergeProvenanceLabel(_ provenance: MergeProvenance) -> String {
    switch provenance {
    case .userConfirmed: return "Confirmed by you"
    case .verifiedBioCrossLink: return "Verified via bio cross-link"
    case .handleConvention: return "Suggested from matching handles"
    }
  }
```

For `MergedIdentity` to work with `.sheet(item:)`, it must already conform to `Identifiable`. Confirm Task 1's `MergedIdentity` struct conforms to `Identifiable` — it does (`public struct MergedIdentity: Identifiable, Hashable, Codable, Sendable` with `public let id: String`).

- [ ] **Step 4: Verify the build**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Smoke-test on the simulator**

Build and run on the iPhone 17 Pro simulator. Sign in with two accounts (Mastodon + Bluesky) that you know map to the same human via handle convention (the easiest case to test: any account where `local@mastodon.social` aligns with `local.bsky.social`).

- Navigate to one of the matched profiles via search or a post avatar tap.
- Verify the `MergeConfirmationSheet` appears (handle-convention case).
- Tap "Confirm merge."
- Verify the chip appears, the dual-handle selector renders, combined stats appear, and tapping the other handle swaps the bio displayed.
- Tap the chip → choose "Unmerge identities."
- Verify both handles disappear, the header reverts to single-handle layout, and re-navigating to the same profile does *not* re-prompt (the tombstone is honored).

- [ ] **Step 6: Commit**

```bash
git add SocialFusion/Views/ProfileView.swift
git commit -m "feat(merge): route merge state, candidate sheet, and unmerge menu into ProfileView"
```

---

## Task 11: Merge unified posts feed (both networks' posts in one timeline)

**Files:**
- Modify: `SocialFusion/ViewModels/ProfileViewModel.swift`

When a profile is merged, the Posts/Replies/Media tabs should show posts from both networks, interleaved by `createdAt`, each carrying its existing `PlatformLogoBadge` so the network is always visible. Per-network breakdowns remain accessible via the handle selector (swapping selectedSide reverts to single-network filtering).

- [ ] **Step 1: Add a merged-or-single fetch path**

Open `SocialFusion/ViewModels/ProfileViewModel.swift`. Locate the existing `private func fetchPosts(for tab: ProfileTab, account: SocialAccount, cursor: String? = nil) async throws -> ([Post], String?)` method (currently around line 240).

Replace it with:

```swift
  /// Fetch posts for a given tab with the appropriate filters.
  /// When the profile is merged AND the user is viewing the unified surface
  /// (selectedSide matches `profile.platform` — the default), both sides
  /// are fetched in parallel and merged by `createdAt`. When the user has
  /// swapped to the twin side via the handle selector, only that side fetches.
  private func fetchPosts(
    for tab: ProfileTab, account: SocialAccount, cursor: String? = nil
  ) async throws -> ([Post], String?) {
    let (excludeReplies, onlyMedia) = filters(for: tab)

    let primary = try await serviceManager.fetchFilteredUserPosts(
      user: user, account: account, cursor: cursor,
      excludeReplies: excludeReplies, onlyMedia: onlyMedia
    )

    // Only merge on the *first* page (cursor == nil) to keep pagination
    // simple. Subsequent pages continue paginating the primary side.
    guard cursor == nil,
          isMerged,
          selectedSide == profile?.platform,
          let twinProfile = mergedTwinProfile,
          let twinAccount = serviceManager.accounts.first(where: { $0.platform == twinProfile.platform })
    else {
      return primary
    }

    let twinUser = SearchUser(
      id: twinProfile.id,
      username: twinProfile.username,
      displayName: twinProfile.displayName,
      avatarURL: twinProfile.avatarURL,
      platform: twinProfile.platform,
      displayNameEmojiMap: twinProfile.displayNameEmojiMap
    )

    let twin: ([Post], String?)
    do {
      twin = try await serviceManager.fetchFilteredUserPosts(
        user: twinUser, account: twinAccount, cursor: nil,
        excludeReplies: excludeReplies, onlyMedia: onlyMedia
      )
    } catch {
      // Degrade gracefully — if the twin side errors, just return primary.
      return primary
    }

    let merged = (primary.0 + twin.0).sorted { $0.createdAt > $1.createdAt }
    // Pagination cursor reflects the primary side only; the twin's
    // remaining pages are surfaced when the user swaps sides.
    return (merged, primary.1)
  }

  private func filters(for tab: ProfileTab) -> (excludeReplies: Bool, onlyMedia: Bool) {
    switch tab {
    case .posts: return (excludeReplies: true, onlyMedia: false)
    case .postsAndReplies: return (excludeReplies: false, onlyMedia: false)
    case .media: return (excludeReplies: false, onlyMedia: true)
    }
  }
```

- [ ] **Step 2: Refetch the active tab when selectedSide changes**

Inside the View Model, observe `selectedSide` and reload the current tab when it changes. Add an `objectWillChange` hook by exposing a method the view can call. At the end of the class (above `// MARK: - Errors` declaration in `ProfileViewModelError`), add:

```swift
  /// Reset the currently-loaded tab so a side swap re-fetches under the new
  /// filter (single-network view of the now-selected side).
  func reloadCurrentTabForSideChange() async {
    switch selectedTab {
    case .posts:
      postsLoaded = false
      posts = []
      postsCursor = nil
      canLoadMorePosts = true
    case .postsAndReplies:
      postsAndRepliesLoaded = false
      postsAndReplies = []
      postsAndRepliesCursor = nil
      canLoadMorePostsAndReplies = true
    case .media:
      mediaPostsLoaded = false
      mediaPosts = []
      mediaPostsCursor = nil
      canLoadMoreMedia = true
    }
    await loadPostsForCurrentTab()
  }
```

But the actual fetch needs to know *which* user to fetch. When the user swaps sides, the `loadPostsForCurrentTab()` method (line 128) currently always uses `user` for the search. Modify it so that when `selectedSide != user.platform` and a merged twin is available, the twin is used. Locate inside `loadPostsForCurrentTab`:

```swift
    guard let account = serviceManager.accounts.first(where: { $0.platform == user.platform })
    else { return }
```

Replace with:

```swift
    let activePlatform = selectedSide
    guard let account = serviceManager.accounts.first(where: { $0.platform == activePlatform })
    else { return }
```

Then locate the call to `fetchPosts(for:account:)` inside that method:

```swift
      let (fetchedPosts, cursor) = try await fetchPosts(for: selectedTab, account: account)
```

Leave it as-is. The semantics work because:
- When `selectedSide == profile.platform`: fetchPosts merges both sides (Step 1 path).
- When `selectedSide != profile.platform`: `isMerged && selectedSide == profile?.platform` is false, so fetchPosts returns the primary side, where "primary" is now driven by `account` which is the twin's account.

But `fetchPosts` itself uses `user` (the original) for the primary fetch. We need it to use the active user. Update the primary fetch in `fetchPosts` to:

```swift
    let activeUser: SearchUser = {
      if selectedSide == user.platform {
        return user
      }
      if let twin = mergedTwinProfile {
        return SearchUser(
          id: twin.id, username: twin.username,
          displayName: twin.displayName, avatarURL: twin.avatarURL,
          platform: twin.platform, displayNameEmojiMap: twin.displayNameEmojiMap
        )
      }
      return user
    }()

    let primary = try await serviceManager.fetchFilteredUserPosts(
      user: activeUser, account: account, cursor: cursor,
      excludeReplies: excludeReplies, onlyMedia: onlyMedia
    )
```

(i.e. replace the `let primary = …` block at the top of `fetchPosts` with the snippet above.)

- [ ] **Step 3: Call reloadCurrentTabForSideChange when selectedSide changes**

In `ProfileView.swift`, find the existing `.onChange(of: viewModel.selectedTab)` modifier (around line 119) and add a sibling for `selectedSide` immediately below it:

```swift
    .onChange(of: viewModel.selectedSide) { _, _ in
      Task { await viewModel.reloadCurrentTabForSideChange() }
    }
```

- [ ] **Step 4: Verify the build succeeds**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Manual smoke test on the simulator**

With a merged profile (from Task 10's smoke test):
- Verify the Posts tab shows interleaved Mastodon + Bluesky posts ordered by recency.
- Verify each post in the list shows the existing `PlatformLogoBadge` (this is already true in `PostCardView`).
- Swap the handle selector to the twin side. Verify the post list reloads and now shows only that network's posts.
- Swap back. Verify both networks reappear interleaved.

- [ ] **Step 6: Commit**

```bash
git add SocialFusion/ViewModels/ProfileViewModel.swift SocialFusion/Views/ProfileView.swift
git commit -m "feat(merge): unify posts feed across both networks when merged"
```

---

## Task 12: Settings — Merged identities management row

**Files:**
- Modify: `SocialFusion/Views/SettingsView.swift`

Add a Settings row that lists all user-confirmed merges and lets the user unmerge any of them. This is the canonical "I made a mistake" affordance per the spec.

- [ ] **Step 1: Add the row to the existing Settings hierarchy**

Open `SocialFusion/Views/SettingsView.swift`. Locate the `Section(header: Text("About"))` block (currently around line 174). Above it, insert a new section:

```swift
                Section(header: Text("Identity")) {
                    NavigationLink(destination: MergedIdentitiesManagementView()) {
                        Label("Merged identities", systemImage: "person.2.circle")
                    }
                }
```

- [ ] **Step 2: Implement the management view inline**

At the bottom of `SocialFusion/Views/SettingsView.swift`, below the existing `SettingsView` declaration, add:

```swift
/// Lists all user-confirmed cross-network identity merges and lets the user
/// remove any of them. Heuristic / unconfirmed merges live only in-memory
/// for the session and are not surfaced here.
private struct MergedIdentitiesManagementView: View {
    @EnvironmentObject private var mergedIdentityStore: MergedIdentityStore

    var body: some View {
        List {
            let merges = mergedIdentityStore.userConfirmedMerges()
            if merges.isEmpty {
                Section {
                    Text("You haven't merged any cross-network identities yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(merges) { merge in
                        mergeRow(merge)
                    }
                } footer: {
                    Text("Merged identities show profiles from both networks as a single card with both handles visible.")
                }
            }
        }
        .navigationTitle("Merged identities")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func mergeRow(_ merge: MergedIdentity) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    PlatformLogoBadge(platform: .mastodon, size: 14, shadowEnabled: false)
                    Text("@\(merge.mastodon.handle)")
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 6) {
                    PlatformLogoBadge(platform: .bluesky, size: 14, shadowEnabled: false)
                    Text("@\(merge.bluesky.handle)")
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Button(role: .destructive) {
                mergedIdentityStore.unmerge(id: merge.id)
            } label: {
                Text("Unmerge")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Merged: at \(merge.mastodon.handle) and at \(merge.bluesky.handle). Double-tap Unmerge to separate.")
    }
}
```

- [ ] **Step 3: Verify the build**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Smoke test**

In the simulator, with at least one user-confirmed merge in place:
- Open Settings → Identity → Merged identities.
- Verify the merge appears with both handles + their platform badges.
- Tap Unmerge.
- Verify the row disappears and the next visit to the merged profile no longer shows the chip.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Views/SettingsView.swift
git commit -m "feat(merge): add Settings row to manage merged identities"
```

---

## Task 13: Accessibility audit pass for the merged surface

**Files:** (no code changes — verification only)
- Verify: `SocialFusion/Views/Components/MergedIdentityChip.swift`
- Verify: `SocialFusion/Views/Components/MergedHandleSelector.swift`
- Verify: `SocialFusion/Views/MergeConfirmationSheet.swift`
- Verify: `SocialFusion/Views/Components/ProfileHeaderView.swift` (merged stats section)

The spec's Principle 5 ("Accessibility is first-class") and the v1.0 acceptance criterion ("Every network-signaling UI surface passes a colorblind-simulator screenshot review") require that every new surface introduced here is dual-coded (shape + label, never color alone), respects Dynamic Type, and is reachable by VoiceOver and keyboard.

- [ ] **Step 1: VoiceOver pass**

Enable VoiceOver (Settings → Accessibility → VoiceOver, or Cmd+F5 in Simulator). Navigate to a merged profile.

Verify each spoken label:
- "Merged identity, confirmed by you" (or "verified via cross-network bio links" / "suggested from matching handles") — the chip.
- "Mastodon handle, at gruber@mastodon.social, selected, button" — selected handle segment.
- "Bluesky handle, at gruber.bsky.social, button" — unselected segment.
- "Combined: 1,234 posts, 567 following, 8,910 followers" — stats row when merged.
- "Per network: 600 Mastodon followers, 8,310 Bluesky followers" — breakdown row.

Walk the MergeConfirmationSheet:
- The sheet headline reads.
- Each avatar reads as "Mastodon profile picture for X" via `PlatformLogoBadge`'s overlay (existing behavior).
- "Confirm merge, button", "Not the same person, button", "Decide later, button."

Walk the Settings → Merged identities view:
- Each row reads its combined label ("Merged: at @gruber@mastodon.social and at @gruber.bsky.social. Double-tap Unmerge to separate.").

If any label is missing or unclear, add `.accessibilityLabel(_:)` / `.accessibilityHint(_:)` modifiers to fix.

- [ ] **Step 2: Dynamic Type pass at AX5**

In Simulator: Settings → Accessibility → Display & Text Size → Larger Text → drag to the rightmost (AX5) position.

Verify:
- The chip wraps gracefully or truncates without overflowing the avatar.
- The dual-handle selector wraps to two lines if needed (handle text is `.lineLimit(1)` with `.middle` truncation — confirm both handles remain legible).
- The merge confirmation sheet content scrolls if it exceeds available height (Spacer + ScrollView fallback should be added if it doesn't already; the current layout uses `Spacer(minLength: 0)` which collapses — *if it overflows, wrap the inner VStack in a ScrollView*).
- The Settings management rows do not clip.

If any layout breaks, fix with `ViewThatFits` or by allowing wraps.

- [ ] **Step 3: Reduce-Motion pass**

In Simulator: Settings → Accessibility → Motion → Reduce Motion → On.

Verify:
- The chip's gradient still renders (it has no motion to suppress — passes by inspection).
- The handle selector's `withAnimation(.easeInOut(duration: 0.18))` runs at near-zero duration when reduce-motion is on. (SwiftUI's `withAnimation` honors `accessibilityReduceMotion` automatically; if not, wrap the call: `if !UIAccessibility.isReduceMotionEnabled { withAnimation(...) { selected = ... } } else { selected = ... }`.)

- [ ] **Step 4: Colorblind-simulator screenshot**

Take screenshots of:
- A merged profile header (chip + handle selector + combined stats + breakdown).
- The MergeConfirmationSheet.
- The Settings → Merged identities list.

Apply deuteranopia, protanopia, and tritanopia simulation (Xcode's Accessibility Inspector → Color Vision Deficiency, or the macOS `xcrun simctl accessibility set` command, or Sim Daltonism). Confirm:
- The chip's purple→blue gradient remains visually distinct from accent capsules — its content "Merged identity" is the actual signal, color is decoration.
- Both `PlatformLogoBadge` overlays inside the chip's mini-glyph remain shape-coded (two overlapping circles + lens are the brand glyph; they do not rely on color to be parsed).
- The dual-handle selector uses `PlatformLogoBadge` for the network indicator and a typography weight change for selection — color is never the sole differentiator.

- [ ] **Step 5: Commit findings**

If any of the above passes required modifier additions, commit them under a single fix-up commit:

```bash
git add SocialFusion/Views/Components/MergedIdentityChip.swift SocialFusion/Views/Components/MergedHandleSelector.swift SocialFusion/Views/MergeConfirmationSheet.swift SocialFusion/Views/Components/ProfileHeaderView.swift SocialFusion/Views/SettingsView.swift
git commit -m "fix(merge): accessibility fixes from a11y audit (VoiceOver labels, Dynamic Type, reduce-motion)"
```

If no changes were required, skip the commit and proceed to Task 14.

---

## Task 14: End-to-end integration test

**Files:**
- Create: `SocialFusionTests/MergedIdentityEndToEndTests.swift`

Confirm the full pipeline — heuristic detection → user confirmation → twin loading → unmerge → tombstone — survives across simulated app sessions.

- [ ] **Step 1: Write the test**

Create `SocialFusionTests/MergedIdentityEndToEndTests.swift`:

```swift
import XCTest
@testable import SocialFusion

@MainActor
final class MergedIdentityEndToEndTests: XCTestCase {
    /// Acceptance: a heuristic match flows from the matcher into the store
    /// and back out as a query result.
    func testHeuristicDetectionAndStoreInsertion() {
        let store = MergedIdentityStore(userDefaults: makeEphemeralDefaults(), defaultsKey: "k")
        let matcher = IdentityMatcher()
        let masto = makeProfile(id: "m", username: "gruber@mastodon.social", platform: .mastodon)
        let bsky = makeProfile(id: "b", username: "gruber.bsky.social", platform: .bluesky)
        guard let match = matcher.match(mastodon: masto, bluesky: bsky) else {
            XCTFail("Expected handle-convention match")
            return
        }
        store.insert([match])
        let lookup = store.merge(forPlatform: .mastodon, accountID: "m")
        XCTAssertEqual(lookup?.id, match.id)
        XCTAssertEqual(lookup?.provenance, .handleConvention)
    }

    /// Acceptance: user-confirmed merges persist across store instances and
    /// take precedence over fresh heuristic re-detection.
    func testUserConfirmationPersistsAndTrumpsHeuristic() {
        let defaults = makeEphemeralDefaults()
        let key = "e2e-confirm"
        let masto = MergedIdentityKey(platform: .mastodon, accountID: "m", handle: "gruber@mastodon.social")
        let bsky = MergedIdentityKey(platform: .bluesky, accountID: "b", handle: "gruber.bsky.social")

        let s1 = MergedIdentityStore(userDefaults: defaults, defaultsKey: key)
        s1.confirmMerge(mastodon: masto, bluesky: bsky)
        XCTAssertEqual(s1.merge(forPlatform: .mastodon, accountID: "m")?.provenance, .userConfirmed)

        // New session — heuristic match is re-detected, but user-confirmed wins.
        let s2 = MergedIdentityStore(userDefaults: defaults, defaultsKey: key)
        let heuristic = MergedIdentity(
            mastodon: masto, bluesky: bsky,
            provenance: .handleConvention, confidence: 0.78
        )
        s2.insert([heuristic])
        XCTAssertEqual(s2.merge(forPlatform: .mastodon, accountID: "m")?.provenance, .userConfirmed)
    }

    /// Acceptance: unmerge produces a tombstone that survives across sessions
    /// and blocks heuristic re-detection.
    func testUnmergeTombstonePersistsAcrossSessions() {
        let defaults = makeEphemeralDefaults()
        let key = "e2e-tombstone"
        let merge = MergedIdentity(
            mastodon: MergedIdentityKey(platform: .mastodon, accountID: "m", handle: "x@mastodon.social"),
            bluesky: MergedIdentityKey(platform: .bluesky, accountID: "b", handle: "x.bsky.social"),
            provenance: .handleConvention, confidence: 0.78
        )

        let s1 = MergedIdentityStore(userDefaults: defaults, defaultsKey: key)
        s1.insert([merge])
        s1.unmerge(id: merge.id)
        XCTAssertNil(s1.merge(forPlatform: .mastodon, accountID: "m"))

        let s2 = MergedIdentityStore(userDefaults: defaults, defaultsKey: key)
        s2.insert([merge])
        XCTAssertNil(s2.merge(forPlatform: .mastodon, accountID: "m"))
    }

    /// Acceptance: the verified-bio-cross-link path is *not* blocked when
    /// it's a stronger signal — but tombstoned IDs match exactly on pair,
    /// so a tombstone for the heuristic version still blocks the same pair
    /// if re-detected via the same pair of IDs. (Confirmed: the tombstone
    /// is keyed on the deterministic pair ID, which is identical regardless
    /// of provenance.)
    func testTombstoneAppliesAcrossProvenances() {
        let store = MergedIdentityStore(userDefaults: makeEphemeralDefaults(), defaultsKey: "k")
        let merge = MergedIdentity(
            mastodon: MergedIdentityKey(platform: .mastodon, accountID: "m", handle: "x@mastodon.social"),
            bluesky: MergedIdentityKey(platform: .bluesky, accountID: "b", handle: "x.bsky.social"),
            provenance: .handleConvention, confidence: 0.78
        )
        store.insert([merge])
        store.unmerge(id: merge.id)

        // A subsequent verified-bio-cross-link detection on the same pair is
        // *also* blocked. This is the correct behavior: the user said "no."
        let verified = MergedIdentity(
            mastodon: MergedIdentityKey(platform: .mastodon, accountID: "m", handle: "x@mastodon.social"),
            bluesky: MergedIdentityKey(platform: .bluesky, accountID: "b", handle: "x.bsky.social"),
            provenance: .verifiedBioCrossLink, confidence: 0.92
        )
        store.insert([verified])
        XCTAssertNil(store.merge(forPlatform: .mastodon, accountID: "m"))

        // But explicit user confirmation overrides the tombstone.
        store.confirmMerge(mastodon: verified.mastodon, bluesky: verified.bluesky)
        XCTAssertEqual(store.merge(forPlatform: .mastodon, accountID: "m")?.provenance, .userConfirmed)
    }

    // MARK: - Helpers

    private func makeProfile(id: String, username: String, platform: SocialPlatform) -> UserProfile {
        UserProfile(
            id: id, username: username, displayName: nil,
            avatarURL: nil, headerURL: nil, bio: nil,
            followersCount: 0, followingCount: 0, statusesCount: 0,
            platform: platform
        )
    }

    private func makeEphemeralDefaults() -> UserDefaults {
        let suite = "MergedIdentityEndToEndTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
```

- [ ] **Step 2: Run the test suite**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/MergedIdentityEndToEndTests`
Expected: PASS, all 4 tests green.

- [ ] **Step 3: Run the full suite to confirm no regressions**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: PASS, all tests green.

- [ ] **Step 4: Commit**

```bash
git add SocialFusionTests/MergedIdentityEndToEndTests.swift
git commit -m "test(merge): end-to-end persistence + tombstone + override coverage"
```

---

## Acceptance gate before promoting to TestFlight

After all 14 tasks are complete:

1. **Full unit test suite passes:** `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet` returns 0. In particular: `IdentityMatcherTests`, `MergedIdentityStoreTests`, `ProfileViewModelMergeTests`, `MergedIdentityEndToEndTests` are all green.

2. **Manual smoke test against Frank's iPhone 17 Pro and iPad Pro** (UDIDs in `MEMORY.md`):
   - Find a real cross-network identity in your feeds — at minimum, your own Mastodon + Bluesky accounts.
   - Navigate to the profile via search.
   - Verify the `MergeConfirmationSheet` appears for handle-convention candidates.
   - Confirm the merge. Verify the chip, dual-handle selector, combined stats with per-network breakdown, and merged Posts feed all render correctly.
   - Swap handles via the selector. Verify bio/banner swap and the post feed reloads to that single network.
   - Tap the chip → Unmerge. Verify the profile reverts.
   - Quit and relaunch the app. Verify the unmerge tombstone holds (no re-prompt).
   - Re-confirm. Quit and relaunch. Verify the merge restored from persistence.

3. **Accessibility verified** per Task 13 — VoiceOver walk-through, Dynamic Type AX5, reduce-motion, and colorblind-simulator screenshots all pass.

4. **No new `AttributeGraph` warnings** in the Xcode console during the manual smoke test.

5. **Verified-bio-cross-link path tested with real accounts** — pick one example where the cross-link holds on both sides (a Mastodon verified field pointing to `bsky.app/profile/{handle}` and a Bluesky bio mentioning the Mastodon handle) and verify the merge applies silently (no confirmation sheet for verified provenance).

6. **Settings management visible and functional** — the Identity section appears, lists user-confirmed merges, and the Unmerge button per row works.

---

## What's intentionally out of scope for this plan

The following live in sibling plans (see spec, "What's not in this spec") or are explicitly deferred per Principle 2 of the v1.0 vision:

- **iCloud KVS sync of merged identities** — depends on the cross-device timeline-position sync plan landing first; if budget remains, piggybacked in v1.0; otherwise v1.1.
- **Cross-account merge for accounts the user owns themselves** — when the user has both their own Mastodon and Bluesky accounts signed in. This is handled by the existing multi-account system (Principle 2: "Your accounts… are all active at once"), not by the heuristic merge surface. The two are conceptually adjacent but architecturally distinct.
- **Federated network beyond Mastodon + Bluesky** — Threads, Nostr, etc. The current `IdentityMatcher` is binary; generalizing to N networks is v1.x.
- **Cross-network DM unification on merged identities** — if Alice has DMs with you on both networks, should the merged profile inbox surface unified? Deferred to v1.x; v1.0 DMs stay per-network.
- **Echo-aware posts on merged-profile feeds** — when both networks have a post that's part of a Fused moment, deduplicate it in the merged profile timeline. Out of scope here; handled by the Fuse plan's deduplication if/when extended to the profile timeline.
- **Fused glyph (A→D bloom) on merged-identity confirmation** — the spec defines the bloom for *post* fusion, not identity merge. A merged-identity confirmation does not bloom in v1.0.
- **Test corpus expansion** — `IdentityMatcherTests` covers the heuristic logic but not a 100+ real-pair corpus akin to the Fuse plan's. Real-world pair corpus is a follow-up if false-positive complaints surface.
- **Merge invitations across users** — "this looks like your friend on the other network — want to merge them in your view?" deferred to v1.x.
- **Pinnable merged-identity timelines** — see Pinnable Timelines plan for "all posts from this merged person" as a pinned surface.

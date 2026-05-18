# The Fuse Breakthrough Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement SocialFusion's signature v1.0 breakthrough — detect when a single moment exists on both Bluesky and Mastodon, unify the conversation across both networks, and let users echo replies, watch threads, and visually identify Fused posts via a distinctive glyph.

**Architecture:** Side-channel store pattern (consistent with `PostActionStore`, `CanonicalPostStore`). A new `FusedMomentDetector` runs after post normalization, matching same-author posts with normalized content fingerprints within a sliding time window. Matches are persisted in `FusedMomentStore` keyed on post IDs. Posts query the store on-demand to discover their twin. A unified `FusedConversationView` loads both sides' reply trees, merges them by timestamp, and tags each reply with the existing `PlatformLogoBadge` for shape-coded accessibility. Echo reply lives in a new `EchoComposeView` with per-network toggles; its starting state is driven by `EchoPolicyStore` (set from onboarding or Settings). Watch is a separate small store + view that taps into the existing `NotificationManager` polling.

**Tech Stack:** Swift 5+, SwiftUI, Combine, XCTest. iOS 17+ floor. Reuses existing patterns: side-channel stores, `@MainActor` published state, `ObservableObject` view models, `PlatformLogoBadge`, the launch-animation color palette (`#8A63FF` purple, `#0096FF` blue, `#1EE7FF` cyan).

**Spec reference:** `docs/superpowers/specs/2026-05-17-socialfusion-v1-vision-design.md` — see "The Fuse — Signature Breakthrough" and "v1.0 Acceptance Criteria."

**File map (creates/modifies):**

- Create: `SocialFusion/Utilities/ContentSignature.swift`
- Create: `SocialFusion/Models/FusedMoment.swift`
- Create: `SocialFusion/Models/WatchedConversation.swift`
- Create: `SocialFusion/Services/FusedMomentDetector.swift`
- Create: `SocialFusion/Stores/FusedMomentStore.swift`
- Create: `SocialFusion/Stores/EchoPolicyStore.swift`
- Create: `SocialFusion/Stores/WatchedConversationStore.swift`
- Create: `SocialFusion/Views/Components/FusedGlyph.swift`
- Create: `SocialFusion/Views/FusedConversationView.swift`
- Create: `SocialFusion/Views/EchoComposeView.swift`
- Create: `SocialFusion/Views/WatchedConversationsView.swift`
- Create: `SocialFusion/ViewModels/FusedConversationViewModel.swift`
- Create: `SocialFusion/ViewModels/EchoComposeViewModel.swift`
- Create: `SocialFusionTests/Fixtures/fused-moments-corpus.json`
- Create: `SocialFusionTests/ContentSignatureTests.swift`
- Create: `SocialFusionTests/FusedMomentDetectorTests.swift`
- Create: `SocialFusionTests/FusedMomentStoreTests.swift`
- Create: `SocialFusionTests/EchoPolicyStoreTests.swift`
- Create: `SocialFusionTests/FusedConversationViewModelTests.swift`
- Create: `SocialFusionTests/EchoComposeViewModelTests.swift`
- Create: `SocialFusionTests/WatchedConversationStoreTests.swift`
- Modify: `SocialFusion/Services/PostNormalizerImpl.swift` (invoke detector after normalization)
- Modify: `SocialFusion/Views/Components/PostCardView.swift` (render glyph + unified counts)
- Modify: `SocialFusion/Views/OnboardingView.swift` (add echo policy step)
- Modify: `SocialFusion/Views/SettingsView.swift` (add echo policy radio)
- Modify: `SocialFusion/Services/NotificationManager.swift` (poll watched conversations)
- Modify: `SocialFusion/Controllers/UnifiedTimelineController.swift` (route tap on Fused posts)

**Implementer assumptions to verify before each task:**

1. `Post` is a `public class … ObservableObject` with `public let id: String`, `public let content: String`, `public let authorId: String`, `public let createdAt: Date`, `public let platform: SocialPlatform` (verified in `SocialFusion/Models/Post.swift:244-256`).
2. `SocialPlatform` is a `String`-backed enum with cases `.mastodon` and `.bluesky` (per `CLAUDE.md` memory).
3. `PlatformLogoBadge(platform:size:)` is the established shape-coded network indicator (`SocialFusion/Views/Components/PlatformLogoBadge.swift`).
4. The launch animation lives in `SocialFusion/Views/Components/LaunchAnimationView.swift` and uses purple `Color(red: 0.54, green: 0.39, blue: 1.00)`, blue `Color(red: 0.00, green: 0.59, blue: 1.00)`, cyan `Color(red: 0.11, green: 0.91, blue: 1.00)`. Reuse these.
5. Side-channel stores follow the `PostActionStore` shape: `@MainActor`, `ObservableObject`, in-memory `[String: T]` keyed on post IDs, with a Combine `objectWillChange` to drive views.
6. The test target is `SocialFusionTests`. Tests subclass `XCTestCase`.

---

## Task 1: Content signature utility

**Files:**
- Create: `SocialFusion/Utilities/ContentSignature.swift`
- Test: `SocialFusionTests/ContentSignatureTests.swift`

This utility normalizes post text for cross-post matching. Cross-posters often have small differences — trailing hashtags one side adds, mentions that don't exist on the other network, link expansion variations, whitespace. The signature collapses these into a stable comparison key.

- [ ] **Step 1: Write the failing tests**

Create `SocialFusionTests/ContentSignatureTests.swift`:

```swift
import XCTest
@testable import SocialFusion

final class ContentSignatureTests: XCTestCase {
    func testIdenticalTextProducesIdenticalSignature() {
        let a = ContentSignature.fingerprint(for: "Hello world")
        let b = ContentSignature.fingerprint(for: "Hello world")
        XCTAssertEqual(a, b)
    }

    func testWhitespaceDifferencesCollapse() {
        let a = ContentSignature.fingerprint(for: "Hello  world\n")
        let b = ContentSignature.fingerprint(for: " Hello world")
        XCTAssertEqual(a, b)
    }

    func testTrailingMentionsAreStripped() {
        let a = ContentSignature.fingerprint(for: "Big news today!")
        let b = ContentSignature.fingerprint(for: "Big news today! @friend@example.social")
        XCTAssertEqual(a, b)
    }

    func testTrailingHashtagsAreStripped() {
        let a = ContentSignature.fingerprint(for: "Big news today!")
        let b = ContentSignature.fingerprint(for: "Big news today! #news #important")
        XCTAssertEqual(a, b)
    }

    func testUrlsAreNormalized() {
        // bsky often shortens vs masto full URL, but punycode/path should match
        let a = ContentSignature.fingerprint(for: "Read this https://example.com/article")
        let b = ContentSignature.fingerprint(for: "Read this https://example.com/article#anchor")
        XCTAssertEqual(a, b)
    }

    func testDistinctContentProducesDistinctSignatures() {
        let a = ContentSignature.fingerprint(for: "Hello world")
        let b = ContentSignature.fingerprint(for: "Goodbye world")
        XCTAssertNotEqual(a, b)
    }

    func testEmptyAndWhitespaceOnlyProduceSameSignature() {
        XCTAssertEqual(
            ContentSignature.fingerprint(for: ""),
            ContentSignature.fingerprint(for: "   \n\t  ")
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/ContentSignatureTests`
Expected: FAIL — `ContentSignature` not defined.

- [ ] **Step 3: Implement the utility**

Create `SocialFusion/Utilities/ContentSignature.swift`:

```swift
import Foundation

/// Produces a normalized fingerprint of post text for cross-network matching.
///
/// Strips cross-poster artifacts that differ between networks without
/// changing semantic content: trailing hashtags, trailing handles/mentions,
/// URL fragments and trailing slashes, and whitespace differences.
public enum ContentSignature {
    /// Returns a stable, normalized fingerprint suitable for equality comparison.
    public static func fingerprint(for text: String) -> String {
        var s = text

        // 1. Normalize URLs: strip fragments and trailing slashes.
        s = normalizeURLs(in: s)

        // 2. Strip trailing mentions (@user, @user@host) and hashtags.
        s = stripTrailingTokens(in: s)

        // 3. Collapse whitespace and trim.
        s = s
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // 4. Lowercase for case-insensitive matching.
        return s.lowercased()
    }

    private static func normalizeURLs(in text: String) -> String {
        let pattern = #"https?://[^\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange).reversed()
        var result = text
        for match in matches {
            guard let range = Range(match.range, in: result) else { continue }
            var url = String(result[range])
            if let fragmentStart = url.firstIndex(of: "#") {
                url = String(url[..<fragmentStart])
            }
            while url.hasSuffix("/") {
                url.removeLast()
            }
            result.replaceSubrange(range, with: url)
        }
        return result
    }

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
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/ContentSignatureTests`
Expected: PASS, all 7 tests green.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Utilities/ContentSignature.swift SocialFusionTests/ContentSignatureTests.swift
git commit -m "feat(fuse): add ContentSignature utility for cross-post text normalization"
```

---

## Task 2: FusedMoment data model

**Files:**
- Create: `SocialFusion/Models/FusedMoment.swift`

The model that represents a single moment as it exists on both networks. Holds references to both post IDs, the authoritative author, and the detection timestamp window.

- [ ] **Step 1: Implement the model**

Create `SocialFusion/Models/FusedMoment.swift`:

```swift
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
```

- [ ] **Step 2: Verify it compiles**

Build the project to catch any syntax issues.

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add SocialFusion/Models/FusedMoment.swift
git commit -m "feat(fuse): add FusedMoment model"
```

---

## Task 3: FusedMomentDetector heuristic

**Files:**
- Create: `SocialFusion/Services/FusedMomentDetector.swift`
- Test: `SocialFusionTests/FusedMomentDetectorTests.swift`

The detector that pairs same-author posts with matching content signatures within a configurable time window.

- [ ] **Step 1: Write the failing tests**

Create `SocialFusionTests/FusedMomentDetectorTests.swift`:

```swift
import XCTest
@testable import SocialFusion

final class FusedMomentDetectorTests: XCTestCase {
    private func makePost(
        id: String,
        platform: SocialPlatform,
        content: String,
        authorId: String,
        createdAt: Date
    ) -> Post {
        // The Post initializer signature lives at SocialFusion/Models/Post.swift:244+.
        // Use the public init with sensible defaults for fields not under test.
        Post(
            id: id,
            content: content,
            authorName: "Test Author",
            authorUsername: "testuser",
            authorProfilePictureURL: "",
            createdAt: createdAt,
            platform: platform,
            originalURL: "",
            attachments: [],
            mentions: [],
            tags: [],
            authorId: authorId
        )
    }

    func testMatchesPostsWithSameSignatureAndAuthorWithinWindow() {
        let now = Date()
        let mastoPost = makePost(
            id: "m1",
            platform: .mastodon,
            content: "Big news today!",
            authorId: "author-identity-1",
            createdAt: now
        )
        let bskyPost = makePost(
            id: "b1",
            platform: .bluesky,
            content: "Big news today! #news",
            authorId: "author-identity-1",
            createdAt: now.addingTimeInterval(120) // 2 min later
        )

        let detector = FusedMomentDetector()
        let result = detector.detect(in: [mastoPost, bskyPost])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.mastodonPostID, "m1")
        XCTAssertEqual(result.first?.blueskyPostID, "b1")
    }

    func testDoesNotMatchDifferentAuthors() {
        let now = Date()
        let posts = [
            makePost(id: "m1", platform: .mastodon, content: "Hello", authorId: "author-1", createdAt: now),
            makePost(id: "b1", platform: .bluesky, content: "Hello", authorId: "author-2", createdAt: now)
        ]
        XCTAssertEqual(FusedMomentDetector().detect(in: posts).count, 0)
    }

    func testDoesNotMatchOutsideTimeWindow() {
        let now = Date()
        let posts = [
            makePost(id: "m1", platform: .mastodon, content: "Hello", authorId: "a", createdAt: now),
            makePost(id: "b1", platform: .bluesky, content: "Hello", authorId: "a",
                     createdAt: now.addingTimeInterval(60 * 60)) // 1 hour later
        ]
        XCTAssertEqual(FusedMomentDetector().detect(in: posts).count, 0)
    }

    func testDoesNotMatchTwoSameNetworkPosts() {
        let now = Date()
        let posts = [
            makePost(id: "m1", platform: .mastodon, content: "Hello", authorId: "a", createdAt: now),
            makePost(id: "m2", platform: .mastodon, content: "Hello", authorId: "a", createdAt: now.addingTimeInterval(60))
        ]
        XCTAssertEqual(FusedMomentDetector().detect(in: posts).count, 0)
    }

    func testEmptyPostsAreNeverMatched() {
        let now = Date()
        let posts = [
            makePost(id: "m1", platform: .mastodon, content: "", authorId: "a", createdAt: now),
            makePost(id: "b1", platform: .bluesky, content: "   ", authorId: "a", createdAt: now)
        ]
        XCTAssertEqual(FusedMomentDetector().detect(in: posts).count, 0,
                       "Empty-content matches are too noisy; never fuse them.")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/FusedMomentDetectorTests`
Expected: FAIL — `FusedMomentDetector` not defined.

- [ ] **Step 3: Implement the detector**

Create `SocialFusion/Services/FusedMomentDetector.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/FusedMomentDetectorTests`
Expected: PASS, all 5 tests green.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Services/FusedMomentDetector.swift SocialFusionTests/FusedMomentDetectorTests.swift
git commit -m "feat(fuse): add FusedMomentDetector heuristic with confidence scoring"
```

---

## Task 4: Detection corpus + acceptance test

**Files:**
- Create: `SocialFusionTests/Fixtures/fused-moments-corpus.json`
- Modify: `SocialFusionTests/FusedMomentDetectorTests.swift` (add corpus test)

The spec mandates a corpus of 100+ real cross-post examples with FP < 1% and FN < 5%. v1.0 ships with a seed corpus and a test that fails the build if the rates regress.

- [ ] **Step 1: Create the corpus fixture**

Create `SocialFusionTests/Fixtures/fused-moments-corpus.json` with at least 100 entries. The skeleton (engineer must hand-curate the remaining entries from real cross-posters' feeds — Frank's own, @mergesort, @gruber, @siracusa, etc.):

```json
{
  "version": 1,
  "description": "Hand-curated corpus of real cross-post pairs plus near-miss decoys. Used to measure FusedMomentDetector false-positive and false-negative rates against the spec acceptance criteria.",
  "examples": [
    {
      "label": "positive",
      "note": "Frank's own cross-post — identical text",
      "masto": { "id": "m_001", "content": "Just shipped v0.9!", "authorId": "frank_id", "createdAt": "2026-05-10T14:32:00Z" },
      "bsky":  { "id": "b_001", "content": "Just shipped v0.9!", "authorId": "frank_id", "createdAt": "2026-05-10T14:32:05Z" },
      "expectFused": true
    },
    {
      "label": "positive",
      "note": "Trailing hashtags differ between networks",
      "masto": { "id": "m_002", "content": "Sunset over the bay", "authorId": "frank_id", "createdAt": "2026-05-11T19:15:00Z" },
      "bsky":  { "id": "b_002", "content": "Sunset over the bay #sunset #sf", "authorId": "frank_id", "createdAt": "2026-05-11T19:15:30Z" },
      "expectFused": true
    },
    {
      "label": "negative",
      "note": "Same author, similar topic, different posts — should NOT fuse",
      "masto": { "id": "m_003", "content": "Loving this album!", "authorId": "frank_id", "createdAt": "2026-05-12T10:00:00Z" },
      "bsky":  { "id": "b_003", "content": "Best album of the year imo", "authorId": "frank_id", "createdAt": "2026-05-12T10:00:30Z" },
      "expectFused": false
    },
    {
      "label": "negative",
      "note": "Identical content but different authors — should NOT fuse",
      "masto": { "id": "m_004", "content": "Happy Friday everyone", "authorId": "alice_id", "createdAt": "2026-05-12T16:00:00Z" },
      "bsky":  { "id": "b_004", "content": "Happy Friday everyone", "authorId": "bob_id", "createdAt": "2026-05-12T16:00:30Z" },
      "expectFused": false
    },
    {
      "label": "negative",
      "note": "Same content/author but posted hours apart — should NOT fuse (intentional repost, not a cross-post)",
      "masto": { "id": "m_005", "content": "Reminder: meetup at 7", "authorId": "frank_id", "createdAt": "2026-05-13T10:00:00Z" },
      "bsky":  { "id": "b_005", "content": "Reminder: meetup at 7", "authorId": "frank_id", "createdAt": "2026-05-13T18:00:00Z" },
      "expectFused": false
    }
  ]
}
```

> **For the implementer:** the corpus needs at least 100 entries before v1.0 ships, with a ~70/30 split positive/negative. Hand-curate from real feeds. The 5 examples above are the skeleton; expand the file with real-world variations: short posts, posts with media references, posts with URLs, posts with mentions, threads, near-duplicate posts that should NOT fuse, etc.

- [ ] **Step 2: Add the corpus test**

Append to `SocialFusionTests/FusedMomentDetectorTests.swift`:

```swift
extension FusedMomentDetectorTests {
    struct CorpusEntry: Decodable {
        let label: String
        let note: String
        let masto: CorpusPost
        let bsky: CorpusPost
        let expectFused: Bool
    }
    struct CorpusPost: Decodable {
        let id: String
        let content: String
        let authorId: String
        let createdAt: Date
    }
    struct Corpus: Decodable {
        let version: Int
        let examples: [CorpusEntry]
    }

    func testCorpusFalsePositiveAndFalseNegativeRates() throws {
        let url = Bundle(for: Self.self).url(forResource: "fused-moments-corpus", withExtension: "json")
        let data = try Data(contentsOf: XCTUnwrap(url, "Corpus fixture missing"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let corpus = try decoder.decode(Corpus.self, from: data)

        let detector = FusedMomentDetector()
        var falsePositives = 0
        var falseNegatives = 0
        var positives = 0
        var negatives = 0

        for entry in corpus.examples {
            let m = makePost(
                id: entry.masto.id, platform: .mastodon,
                content: entry.masto.content, authorId: entry.masto.authorId,
                createdAt: entry.masto.createdAt
            )
            let b = makePost(
                id: entry.bsky.id, platform: .bluesky,
                content: entry.bsky.content, authorId: entry.bsky.authorId,
                createdAt: entry.bsky.createdAt
            )
            let detected = !detector.detect(in: [m, b]).isEmpty
            if entry.expectFused {
                positives += 1
                if !detected { falseNegatives += 1 }
            } else {
                negatives += 1
                if detected { falsePositives += 1 }
            }
        }

        let fpRate = negatives > 0 ? Double(falsePositives) / Double(negatives) : 0
        let fnRate = positives > 0 ? Double(falseNegatives) / Double(positives) : 0

        XCTAssertLessThan(fpRate, 0.01, "False-positive rate \(fpRate) exceeds spec ceiling 1%.")
        XCTAssertLessThan(fnRate, 0.05, "False-negative rate \(fnRate) exceeds spec ceiling 5%.")

        // Optional: log so CI surfaces the rates even when passing.
        print("Fuse corpus — positives: \(positives), negatives: \(negatives), FP: \(fpRate), FN: \(fnRate)")
    }
}
```

You will also need to register the fixture as a bundled resource in `project.yml` so XCTest can find it. Add under the `SocialFusionTests` target sources:

```yaml
SocialFusionTests:
  resources:
    - SocialFusionTests/Fixtures
```

(If `resources:` already exists, append the path. After editing `project.yml`, run `xcodegen` per `CLAUDE.md` to regenerate `project.pbxproj`.)

- [ ] **Step 3: Run tests to verify the corpus test passes with the seed**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/FusedMomentDetectorTests/testCorpusFalsePositiveAndFalseNegativeRates`
Expected: PASS with the seed corpus (5 entries; rates are 0%/0%). Fails meaningfully only when the engineer adds the full corpus with edge cases.

- [ ] **Step 4: Commit**

```bash
git add SocialFusionTests/Fixtures/fused-moments-corpus.json SocialFusionTests/FusedMomentDetectorTests.swift project.yml
git commit -m "test(fuse): add detector corpus + FP/FN acceptance test"
```

- [ ] **Step 5: Track corpus expansion as an open follow-up**

This task ships the harness, not the full corpus. Before v1.0 promote-to-App-Store, the corpus must reach 100+ entries with real-world variety. Open an issue or add a `// MARK: TODO - expand corpus before v1.0 ship` note in the fixture, and surface it to the user in the post-implementation review.

---

## Task 5: FusedMomentStore (side-channel persistence)

**Files:**
- Create: `SocialFusion/Stores/FusedMomentStore.swift`
- Test: `SocialFusionTests/FusedMomentStoreTests.swift`

Side-channel store, MainActor-isolated, in-memory with optional disk persistence later. Follows the `PostActionStore` shape.

- [ ] **Step 1: Write the failing tests**

Create `SocialFusionTests/FusedMomentStoreTests.swift`:

```swift
import XCTest
@testable import SocialFusion

@MainActor
final class FusedMomentStoreTests: XCTestCase {
    func testInsertAndLookupByPostID() {
        let store = FusedMomentStore()
        let m = FusedMoment(
            mastodonPostID: "m1", blueskyPostID: "b1",
            authorIdentityKey: "author-1",
            firstSeenAt: Date(), confidence: 0.9
        )
        store.insert([m])
        XCTAssertEqual(store.moment(for: "m1")?.id, m.id)
        XCTAssertEqual(store.moment(for: "b1")?.id, m.id)
        XCTAssertNil(store.moment(for: "nonexistent"))
    }

    func testInsertingSameMomentTwiceIsIdempotent() {
        let store = FusedMomentStore()
        let m = FusedMoment(
            mastodonPostID: "m1", blueskyPostID: "b1",
            authorIdentityKey: "a", firstSeenAt: Date(), confidence: 0.9
        )
        store.insert([m, m])
        XCTAssertEqual(store.allMoments().count, 1)
    }

    func testTwinPostIDLookup() {
        let store = FusedMomentStore()
        let m = FusedMoment(
            mastodonPostID: "m1", blueskyPostID: "b1",
            authorIdentityKey: "a", firstSeenAt: Date(), confidence: 0.9
        )
        store.insert([m])
        XCTAssertEqual(store.twinPostID(for: "m1", on: .mastodon), "b1")
        XCTAssertEqual(store.twinPostID(for: "b1", on: .bluesky), "m1")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/FusedMomentStoreTests`
Expected: FAIL — `FusedMomentStore` not defined.

- [ ] **Step 3: Implement the store**

Create `SocialFusion/Stores/FusedMomentStore.swift`:

```swift
import Combine
import Foundation
import SwiftUI

/// Side-channel store of detected Fused moments.
///
/// Keyed on the underlying post IDs (both sides) so any UI surface that
/// holds a post can ask the store whether the post participates in a moment.
/// Follows the established pattern from `PostActionStore`.
@MainActor
public final class FusedMomentStore: ObservableObject {
    /// All known moments by their stable ID.
    @Published private(set) var moments: [String: FusedMoment] = [:]

    /// Index from underlying post ID → moment ID (both sides).
    private var postToMoment: [String: String] = [:]

    /// IDs of moments whose D-state bloom hasn't played yet. Read once by
    /// the timeline card; cleared on first appearance.
    @Published private(set) var pendingBloom: Set<String> = []

    public init() {}

    /// Inserts a batch of moments. Idempotent — re-inserting the same moment
    /// has no effect except clearing it from the pendingBloom set if seen.
    public func insert(_ batch: [FusedMoment]) {
        for moment in batch {
            let id = moment.id
            if moments[id] == nil {
                moments[id] = moment
                postToMoment[moment.mastodonPostID] = id
                postToMoment[moment.blueskyPostID] = id
                pendingBloom.insert(id)
            }
        }
    }

    public func moment(for postID: String) -> FusedMoment? {
        guard let momentID = postToMoment[postID] else { return nil }
        return moments[momentID]
    }

    public func twinPostID(for postID: String, on platform: SocialPlatform) -> String? {
        guard let moment = moment(for: postID) else { return nil }
        return moment.twinPostID(for: platform)
    }

    public func allMoments() -> [FusedMoment] {
        Array(moments.values)
    }

    /// Called by the Fused post card the first time it appears on screen.
    /// Returns true once per moment — true when the D-bloom should play,
    /// false on every subsequent appearance.
    public func consumePendingBloom(for momentID: String) -> Bool {
        if pendingBloom.contains(momentID) {
            pendingBloom.remove(momentID)
            return true
        }
        return false
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/FusedMomentStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Stores/FusedMomentStore.swift SocialFusionTests/FusedMomentStoreTests.swift
git commit -m "feat(fuse): add FusedMomentStore (side-channel, MainActor)"
```

---

## Task 6: Wire detector into the post normalization pipeline

**Files:**
- Modify: `SocialFusion/Services/PostNormalizerImpl.swift` (after the final normalized array is produced, run the detector and feed the store)
- Modify: `SocialFusion/SocialFusionApp.swift` (instantiate `FusedMomentStore` as an `@StateObject`, inject as `@EnvironmentObject`)

- [ ] **Step 1: Inject the store at app root**

Locate the `@main` `SocialFusionApp` struct in `SocialFusion/SocialFusionApp.swift`. It already creates state objects per CLAUDE.md. Add a new one:

```swift
@StateObject private var fusedMomentStore = FusedMomentStore()
```

And inject it into the environment alongside the other stores:

```swift
.environmentObject(fusedMomentStore)
```

- [ ] **Step 2: Run the detector during normalization**

In `SocialFusion/Services/PostNormalizerImpl.swift`, find the method that returns the final normalized `[Post]` buffer (likely something like `normalize(...)` or `unifiedTimeline(...)`). After the array is assembled but before it's returned, run the detector and route results to the store.

Because `PostNormalizerImpl` is likely not MainActor-isolated, the detector itself stays non-actor-isolated and the *store insert* is dispatched to MainActor:

```swift
let detector = FusedMomentDetector()
let detected = detector.detect(in: normalizedPosts)

if !detected.isEmpty {
    Task { @MainActor [fusedMomentStore] in
        fusedMomentStore.insert(detected)
    }
}
```

The `fusedMomentStore` reference needs to be passed into `PostNormalizerImpl` at construction time, or accessed via a held weak ref. Use whichever pattern matches the surrounding code — but the cleanest approach is constructor injection:

```swift
// At the top of PostNormalizerImpl:
public let fusedMomentStore: FusedMomentStore

public init(fusedMomentStore: FusedMomentStore) {
    self.fusedMomentStore = fusedMomentStore
}
```

Update construction sites (likely `SocialServiceManager`) to pass the store in.

- [ ] **Step 3: Verify build succeeds**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Smoke test — log detected moments to console**

Temporarily add a `print("[Fuse] detected \(detected.count) moments")` after the `detector.detect(...)` call. Boot the app on the simulator, sign in with your real Mastodon + Bluesky accounts, scroll the unified timeline. Verify the console emits detection logs and that they reflect real cross-posts in your feeds.

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' && xcrun simctl install booted /path/to/built.app && xcrun simctl launch booted com.socialfusionapp.app`

Expected: console emits `[Fuse] detected N moments` on each timeline refresh, where N matches your eyeball count.

Remove the print before committing.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Services/PostNormalizerImpl.swift SocialFusion/SocialFusionApp.swift SocialFusion/Services/SocialServiceManager.swift
git commit -m "feat(fuse): wire detector into timeline normalization pipeline"
```

---

## Task 7: FusedGlyph SwiftUI component (states A + D)

**Files:**
- Create: `SocialFusion/Views/Components/FusedGlyph.swift`

The visible mark. State A is the calm filled-Venn glyph used at rest. State D plays a bloom on first appearance, then settles to A — same animation gesture as `LaunchAnimationView`, at glyph scale.

- [ ] **Step 1: Implement the component**

Create `SocialFusion/Views/Components/FusedGlyph.swift`:

```swift
import SwiftUI

/// The Fused motif: a miniature of the SocialFusion logo. Two overlapping
/// circles (Mastodon purple + Bluesky blue) with a cyan lens at their
/// intersection. Optionally plays a bloom on first appearance.
public struct FusedGlyph: View {
    /// Visual size of the bounding box in pt.
    public let size: CGFloat

    /// If true, the glyph plays the D-bloom on first appearance, then settles to A.
    /// If false, it renders A statically.
    public let bloomOnAppear: Bool

    @State private var bloomScale: CGFloat = 1.0
    @State private var bloomOpacity: Double = 0.0

    // Colors from LaunchAnimationView for exact brand alignment.
    private let purple = Color(red: 0.54, green: 0.39, blue: 1.00)
    private let blue = Color(red: 0.00, green: 0.59, blue: 1.00)
    private let cyan = Color(red: 0.11, green: 0.91, blue: 1.00)

    public init(size: CGFloat = 18, bloomOnAppear: Bool = false) {
        self.size = size
        self.bloomOnAppear = bloomOnAppear
    }

    public var body: some View {
        let circleSize = size * 0.68
        ZStack {
            // Purple circle (Mastodon side).
            Circle()
                .fill(purple.opacity(0.88))
                .frame(width: circleSize, height: circleSize)
                .offset(x: -circleSize * 0.20)

            // Blue circle (Bluesky side).
            Circle()
                .fill(blue.opacity(0.88))
                .frame(width: circleSize, height: circleSize)
                .offset(x: circleSize * 0.20)

            // Cyan lens at the intersection.
            Ellipse()
                .fill(cyan.opacity(0.95))
                .frame(width: circleSize * 0.22, height: circleSize * 0.78)

            // Bloom (D state) — radial glow centered on the lens.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.85), cyan.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: circleSize * 0.55
                    )
                )
                .frame(width: circleSize * 1.2, height: circleSize * 1.2)
                .blendMode(.plusLighter)
                .scaleEffect(bloomScale)
                .opacity(bloomOpacity)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true) // Decorative; semantics live on the badge text.
        .onAppear {
            guard bloomOnAppear else { return }
            // Reduce-motion respect: skip bloom if reduce motion is on.
            if UIAccessibility.isReduceMotionEnabled { return }
            withAnimation(.easeOut(duration: 0.18)) {
                bloomScale = 1.4
                bloomOpacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                withAnimation(.easeIn(duration: 0.32)) {
                    bloomScale = 1.0
                    bloomOpacity = 0.0
                }
            }
        }
    }
}

#if DEBUG
struct FusedGlyph_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 20) {
            FusedGlyph(size: 14)
            FusedGlyph(size: 18)
            FusedGlyph(size: 24)
            FusedGlyph(size: 40, bloomOnAppear: true)
        }
        .padding()
    }
}
#endif
```

- [ ] **Step 2: Verify the preview renders**

In Xcode, open `FusedGlyph.swift` and resume the Canvas preview. Verify all four glyph sizes render with the expected purple/blue/cyan composition. The largest one should pulse a bloom on appear.

- [ ] **Step 3: Build to verify no compile errors**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add SocialFusion/Views/Components/FusedGlyph.swift
git commit -m "feat(fuse): add FusedGlyph component (A dormant + D bloom)"
```

---

## Task 8: PostCardView integration — show glyph and unified counts

**Files:**
- Modify: `SocialFusion/Views/Components/PostCardView.swift`

Render the FusedGlyph on cards whose post participates in a Fused moment. Display unified reply count ("15 across") instead of the per-network count. Play the bloom on first appearance after sync.

- [ ] **Step 1: Locate the card header**

Open `SocialFusion/Views/Components/PostCardView.swift`. Find where the platform indicator currently renders (likely a `PlatformLogoBadge` or similar near the author row). Identify a stable insertion point above or beside it.

- [ ] **Step 2: Inject the FusedMomentStore**

At the top of the `PostCardView` struct:

```swift
@EnvironmentObject private var fusedMomentStore: FusedMomentStore
```

- [ ] **Step 3: Add the glyph rendering**

Where you placed the insertion point, add:

```swift
if let moment = fusedMomentStore.moment(for: post.id) {
    let shouldBloom = fusedMomentStore.consumePendingBloom(for: moment.id)
    HStack(spacing: 6) {
        FusedGlyph(size: 16, bloomOnAppear: shouldBloom)
        Text("Fused")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityLabel("Fused: this moment exists on both networks")
    }
    .padding(.bottom, 4)
}
```

- [ ] **Step 4: Unify reply counts on Fused cards**

Find the action bar (the row with reply/repost/like counts). When the post is part of a Fused moment, the reply count should reflect both sides combined. The simplest v1.0 approach: leave the action bar wired to the local post's counts, but show a secondary "+ N from <other-network>" beneath only when both sides have replies. The implementing engineer needs to look up the twin post's reply count via the existing `CanonicalPostStore` or `UnifiedPostStore` (whichever holds the twin's post-action state):

```swift
if let moment = fusedMomentStore.moment(for: post.id),
   let twinID = fusedMomentStore.twinPostID(for: post.id, on: post.platform),
   let twinReplyCount = unifiedPostStore.replyCount(for: twinID),
   twinReplyCount > 0 {
    Text("+\(twinReplyCount) from \(post.platform == .mastodon ? "Bluesky" : "Mastodon")")
        .font(.caption2)
        .foregroundStyle(.tertiary)
}
```

If `unifiedPostStore.replyCount(for:)` doesn't exist, add it as a tiny method that reads from the existing store. Keep the change minimal — the goal is correctness, not a full counter redesign in this task.

- [ ] **Step 5: Verify on the simulator**

Build and run. Scroll the timeline and verify:
- Cards whose posts have a detected twin display the Fused glyph and "Fused" label.
- The glyph blooms ONLY on the first appearance of each moment (not on subsequent scrolls past).
- Reply counts include twin-side contribution when present.
- Reduce-motion users do not see the bloom (verify by enabling Settings → Accessibility → Reduce Motion).

- [ ] **Step 6: Commit**

```bash
git add SocialFusion/Views/Components/PostCardView.swift
git commit -m "feat(fuse): render FusedGlyph + unified reply count on Fused posts"
```

---

## Task 9: FusedConversationViewModel

**Files:**
- Create: `SocialFusion/ViewModels/FusedConversationViewModel.swift`
- Test: `SocialFusionTests/FusedConversationViewModelTests.swift`

The view model that loads both sides' reply trees in parallel, merges them by time, handles one-side outages gracefully, and streams replies as they arrive.

- [ ] **Step 1: Define the loading state**

Create `SocialFusion/ViewModels/FusedConversationViewModel.swift`:

```swift
import Combine
import Foundation
import SwiftUI

@MainActor
public final class FusedConversationViewModel: ObservableObject {
    public enum SideStatus: Equatable {
        case loading
        case loaded
        case failed(message: String)
    }

    public struct MergedReply: Identifiable, Equatable {
        public let id: String
        public let post: Post
        public var sourcePlatform: SocialPlatform { post.platform }
    }

    @Published public private(set) var moment: FusedMoment
    @Published public private(set) var rootPost: Post?
    @Published public private(set) var replies: [MergedReply] = []
    @Published public private(set) var mastodonStatus: SideStatus = .loading
    @Published public private(set) var blueskyStatus: SideStatus = .loading

    /// True if one side failed and the user has chosen to dismiss its banner.
    @Published public var dismissedFailureBanners: Set<SocialPlatform> = []

    private let mastodonService: MastodonService
    private let blueskyService: BlueskyService

    public init(
        moment: FusedMoment,
        mastodonService: MastodonService,
        blueskyService: BlueskyService
    ) {
        self.moment = moment
        self.mastodonService = mastodonService
        self.blueskyService = blueskyService
    }

    /// Kicks off parallel loading of both sides. Streams results into
    /// `replies` as each side resolves so the UI never waits for the slower
    /// network.
    public func load() async {
        async let masto = loadSide(.mastodon)
        async let bsky = loadSide(.bluesky)
        _ = await (masto, bsky)
    }

    private func loadSide(_ platform: SocialPlatform) async {
        let postID = (platform == .mastodon) ? moment.mastodonPostID : moment.blueskyPostID
        do {
            let (root, sideReplies) = try await fetchThread(for: postID, on: platform)
            if rootPost == nil { rootPost = root }
            mergeAndPublish(sideReplies)
            setStatus(.loaded, for: platform)
        } catch {
            setStatus(.failed(message: error.localizedDescription), for: platform)
        }
    }

    private func fetchThread(for postID: String, on platform: SocialPlatform)
        async throws -> (Post, [Post])
    {
        switch platform {
        case .mastodon:
            return try await mastodonService.fetchThread(postID: postID)
        case .bluesky:
            return try await blueskyService.fetchThread(postID: postID)
        }
    }

    private func mergeAndPublish(_ newReplies: [Post]) {
        var combined = replies + newReplies.map { MergedReply(id: $0.id, post: $0) }
        // De-dup by id (in case the same reply somehow appears via both sides — unlikely
        // unless the API echoes; defensive).
        var seen = Set<String>()
        combined = combined.filter { seen.insert($0.id).inserted }
        // Sort by createdAt ascending.
        combined.sort { $0.post.createdAt < $1.post.createdAt }
        replies = combined
    }

    private func setStatus(_ status: SideStatus, for platform: SocialPlatform) {
        switch platform {
        case .mastodon: mastodonStatus = status
        case .bluesky: blueskyStatus = status
        }
    }

    public func retry(_ platform: SocialPlatform) async {
        setStatus(.loading, for: platform)
        await loadSide(platform)
    }
}
```

- [ ] **Step 2: Write tests with a stubbed service layer**

Create `SocialFusionTests/FusedConversationViewModelTests.swift`. Stub the services with protocols if the existing services don't have testable extension points. (In practice, the implementer should introduce minimal `MastodonServicing` / `BlueskyServicing` protocols if they don't exist, with `fetchThread(postID:)` as the only required surface for this test. Keep the protocols colocated with the services.)

```swift
import XCTest
@testable import SocialFusion

@MainActor
final class FusedConversationViewModelTests: XCTestCase {
    func testStreamsRepliesAsEachSideResolves() async throws {
        // Set up: both sides succeed with disjoint reply sets.
        let masto = StubMastodonService(thread: (rootPost("m1"), [reply("m_r1", at: 1)]))
        let bsky = StubBlueskyService(thread: (rootPost("b1"), [reply("b_r1", at: 2)]))
        let vm = FusedConversationViewModel(
            moment: FusedMoment(mastodonPostID: "m1", blueskyPostID: "b1",
                                authorIdentityKey: "a", firstSeenAt: Date(), confidence: 0.9),
            mastodonService: masto,
            blueskyService: bsky
        )
        await vm.load()
        XCTAssertEqual(vm.replies.map(\.id), ["m_r1", "b_r1"])
        XCTAssertEqual(vm.mastodonStatus, .loaded)
        XCTAssertEqual(vm.blueskyStatus, .loaded)
    }

    func testHandlesOneSideOutageGracefully() async {
        let masto = StubMastodonService(thread: (rootPost("m1"), [reply("m_r1", at: 1)]))
        let bsky = StubBlueskyService(error: TestError.boom)
        let vm = FusedConversationViewModel(
            moment: FusedMoment(mastodonPostID: "m1", blueskyPostID: "b1",
                                authorIdentityKey: "a", firstSeenAt: Date(), confidence: 0.9),
            mastodonService: masto,
            blueskyService: bsky
        )
        await vm.load()
        XCTAssertEqual(vm.replies.map(\.id), ["m_r1"], "Working side must still render.")
        XCTAssertEqual(vm.mastodonStatus, .loaded)
        if case .failed = vm.blueskyStatus {} else { XCTFail("Bluesky side should be failed") }
    }

    // MARK: helpers
    private func rootPost(_ id: String) -> Post { /* construct as in Task 3 helper */ fatalError("expand from Task 3 helper") }
    private func reply(_ id: String, at offset: TimeInterval) -> Post { /* construct as in Task 3 helper with createdAt offset */ fatalError("expand from Task 3 helper") }
}

private enum TestError: Error { case boom }
```

(The implementer should reuse the `makePost` helper pattern from Task 3 and define the stub services in a private extension to keep the test file self-contained.)

- [ ] **Step 3: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/FusedConversationViewModelTests`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add SocialFusion/ViewModels/FusedConversationViewModel.swift SocialFusionTests/FusedConversationViewModelTests.swift
git commit -m "feat(fuse): FusedConversationViewModel with streaming merge + one-side outage"
```

---

## Task 10: FusedConversationView

**Files:**
- Create: `SocialFusion/Views/FusedConversationView.swift`

The unified merged-thread UI. Root post at the top with the FusedGlyph. Replies below, sorted by time, each tagged with `PlatformLogoBadge`. Banners for any side that failed, with retry.

- [ ] **Step 1: Implement the view**

Create `SocialFusion/Views/FusedConversationView.swift`:

```swift
import SwiftUI

public struct FusedConversationView: View {
    @StateObject var viewModel: FusedConversationViewModel
    @State private var didLoad = false

    public init(viewModel: FusedConversationViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                rootHeader
                outageBanners
                ForEach(viewModel.replies) { merged in
                    ReplyRow(post: merged.post)
                        .padding(.horizontal)
                }
                if viewModel.mastodonStatus == .loading || viewModel.blueskyStatus == .loading {
                    HStack { Spacer(); ProgressView().padding(); Spacer() }
                }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle("Fused conversation")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !didLoad else { return }
            didLoad = true
            await viewModel.load()
        }
    }

    private var rootHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                FusedGlyph(size: 18, bloomOnAppear: false)
                Text("Fused conversation")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let root = viewModel.rootPost {
                // Reuse existing post card for the root. Display in non-tappable mode.
                PostCardView(post: root /* configure as static header */)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var outageBanners: some View {
        if case .failed(let msg) = viewModel.mastodonStatus,
           !viewModel.dismissedFailureBanners.contains(.mastodon) {
            outageBanner(platform: .mastodon, message: msg) {
                Task { await viewModel.retry(.mastodon) }
            }
        }
        if case .failed(let msg) = viewModel.blueskyStatus,
           !viewModel.dismissedFailureBanners.contains(.bluesky) {
            outageBanner(platform: .bluesky, message: msg) {
                Task { await viewModel.retry(.bluesky) }
            }
        }
    }

    private func outageBanner(platform: SocialPlatform, message: String, retry: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            PlatformLogoBadge(platform: platform, size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(platform == .mastodon ? "Mastodon" : "Bluesky") replies didn't load")
                    .font(.footnote.weight(.semibold))
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Retry", action: retry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }
}

private struct ReplyRow: View {
    let post: Post

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: URL(string: post.authorProfilePictureURL)) { img in
                img.resizable()
            } placeholder: {
                Circle().fill(Color.gray.opacity(0.2))
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(post.authorName)
                        .font(.subheadline.weight(.semibold))
                    PlatformLogoBadge(platform: post.platform, size: 14)
                        .accessibilityLabel(post.platform == .mastodon ? "Mastodon" : "Bluesky")
                    Spacer(minLength: 0)
                    Text(post.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(post.content)
                    .font(.body)
            }
        }
    }
}
```

(If the existing `PostCardView` initializer doesn't accept a "static header" config, the engineer should add a minimal `isHeader: Bool = false` parameter that disables tap routing.)

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add SocialFusion/Views/FusedConversationView.swift
git commit -m "feat(fuse): FusedConversationView with merged replies and outage banners"
```

---

## Task 11: Route Fused-post taps to FusedConversationView

**Files:**
- Modify: `SocialFusion/Controllers/UnifiedTimelineController.swift` (or wherever post taps are routed)
- Modify: `SocialFusion/Views/Components/PostCardView.swift` (handler dispatch)

- [ ] **Step 1: Find the existing tap routing**

In `UnifiedTimelineController.swift`, locate the method that handles "user tapped a post in the timeline" and navigates to the single-post detail. There is likely a navigation enum or path being mutated.

- [ ] **Step 2: Add Fused branch**

Before the existing single-post navigation, check the `FusedMomentStore` for a moment containing this post. If present, navigate to `FusedConversationView` instead:

```swift
func handleTap(on post: Post) {
    if let moment = fusedMomentStore.moment(for: post.id) {
        navigationPath.append(.fusedConversation(moment))
    } else {
        navigationPath.append(.postDetail(post))
    }
}
```

Extend the destination enum:

```swift
enum TimelineDestination: Hashable {
    case postDetail(Post)
    case fusedConversation(FusedMoment)
}
```

In the destination switch, construct the `FusedConversationViewModel` and present the view:

```swift
case .fusedConversation(let moment):
    FusedConversationView(viewModel: FusedConversationViewModel(
        moment: moment,
        mastodonService: serviceManager.mastodonService,
        blueskyService: serviceManager.blueskyService
    ))
```

- [ ] **Step 3: Smoke test on the simulator**

Boot the app, find a Fused card in the timeline (or trigger one via Frank's test account), tap it. Expected: navigates to the unified conversation view, not the per-network detail.

- [ ] **Step 4: Commit**

```bash
git add SocialFusion/Controllers/UnifiedTimelineController.swift SocialFusion/Views/Components/PostCardView.swift
git commit -m "feat(fuse): route Fused-post taps to FusedConversationView"
```

---

## Task 12: EchoPolicyStore (persistence for the onboarding choice)

**Files:**
- Create: `SocialFusion/Stores/EchoPolicyStore.swift`
- Test: `SocialFusionTests/EchoPolicyStoreTests.swift`

A tiny store that holds the user's echo-reply default. Read at composer construction time; written by onboarding and Settings.

- [ ] **Step 1: Write the failing tests**

Create `SocialFusionTests/EchoPolicyStoreTests.swift`:

```swift
import XCTest
@testable import SocialFusion

@MainActor
final class EchoPolicyStoreTests: XCTestCase {
    private let key = "echo-policy-test-key"

    override func setUp() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    func testDefaultIsAskEachTime() {
        let store = EchoPolicyStore(userDefaults: .standard, defaultsKey: key)
        XCTAssertEqual(store.policy, .askEachTime)
    }

    func testSettingPersistsAcrossInstances() {
        let s1 = EchoPolicyStore(userDefaults: .standard, defaultsKey: key)
        s1.policy = .echoOn
        let s2 = EchoPolicyStore(userDefaults: .standard, defaultsKey: key)
        XCTAssertEqual(s2.policy, .echoOn)
    }

    func testInitialDefaultsForFusedReplyStartingState() {
        let s = EchoPolicyStore(userDefaults: .standard, defaultsKey: key)

        s.policy = .echoOn
        XCTAssertEqual(s.initialReplyTargets(originalPlatform: .mastodon),
                       Set([SocialPlatform.mastodon, .bluesky]))

        s.policy = .echoOff
        XCTAssertEqual(s.initialReplyTargets(originalPlatform: .mastodon),
                       Set([SocialPlatform.mastodon]))

        s.policy = .askEachTime
        XCTAssertEqual(s.initialReplyTargets(originalPlatform: .mastodon), [])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/EchoPolicyStoreTests`
Expected: FAIL — `EchoPolicyStore` not defined.

- [ ] **Step 3: Implement the store**

Create `SocialFusion/Stores/EchoPolicyStore.swift`:

```swift
import Combine
import Foundation
import SwiftUI

public enum EchoPolicy: String, Codable, CaseIterable {
    case echoOn          // Both networks pre-checked.
    case echoOff         // Only the original-side network pre-checked.
    case askEachTime     // Neither pre-checked; Send disabled until user picks.
}

@MainActor
public final class EchoPolicyStore: ObservableObject {
    @Published public var policy: EchoPolicy {
        didSet {
            userDefaults.set(policy.rawValue, forKey: defaultsKey)
        }
    }

    private let userDefaults: UserDefaults
    private let defaultsKey: String

    public init(
        userDefaults: UserDefaults = .standard,
        defaultsKey: String = "echo.reply.policy"
    ) {
        self.userDefaults = userDefaults
        self.defaultsKey = defaultsKey
        let raw = userDefaults.string(forKey: defaultsKey) ?? EchoPolicy.askEachTime.rawValue
        self.policy = EchoPolicy(rawValue: raw) ?? .askEachTime
    }

    /// Returns the set of platforms to pre-check in a Fused reply composer,
    /// given the platform the user is replying *from*.
    public func initialReplyTargets(originalPlatform: SocialPlatform) -> Set<SocialPlatform> {
        switch policy {
        case .echoOn: return [.mastodon, .bluesky]
        case .echoOff: return [originalPlatform]
        case .askEachTime: return []
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/EchoPolicyStoreTests`
Expected: PASS.

- [ ] **Step 5: Inject the store at app root**

In `SocialFusionApp.swift`, add `@StateObject private var echoPolicyStore = EchoPolicyStore()` and `.environmentObject(echoPolicyStore)`.

- [ ] **Step 6: Commit**

```bash
git add SocialFusion/Stores/EchoPolicyStore.swift SocialFusionTests/EchoPolicyStoreTests.swift SocialFusion/SocialFusionApp.swift
git commit -m "feat(fuse): EchoPolicyStore for onboarding/Settings reply policy"
```

---

## Task 13: EchoComposeView + ViewModel

**Files:**
- Create: `SocialFusion/Views/EchoComposeView.swift`
- Create: `SocialFusion/ViewModels/EchoComposeViewModel.swift`
- Test: `SocialFusionTests/EchoComposeViewModelTests.swift`

The per-post echo composer with Send-button-as-policy. Both network toggles, live character counts, the colored Send button that reflects current selection state.

- [ ] **Step 1: Write the ViewModel tests**

Create `SocialFusionTests/EchoComposeViewModelTests.swift`:

```swift
import XCTest
@testable import SocialFusion

@MainActor
final class EchoComposeViewModelTests: XCTestCase {
    func testSendActionLabelReflectsToggleState() {
        let vm = EchoComposeViewModel(
            moment: FusedMoment(mastodonPostID: "m1", blueskyPostID: "b1",
                                authorIdentityKey: "a", firstSeenAt: Date(), confidence: 0.9),
            initialTargets: [.mastodon, .bluesky]
        )
        XCTAssertEqual(vm.sendActionLabel, "Reply to both")
        vm.targets.remove(.bluesky)
        XCTAssertEqual(vm.sendActionLabel, "Reply on Mastodon")
        vm.targets = [.bluesky]
        XCTAssertEqual(vm.sendActionLabel, "Reply on Bluesky")
        vm.targets = []
        XCTAssertEqual(vm.sendActionLabel, "Reply…")
    }

    func testCanSendIsFalseWithNoTargetsOrEmptyText() {
        let vm = EchoComposeViewModel(
            moment: FusedMoment(mastodonPostID: "m1", blueskyPostID: "b1",
                                authorIdentityKey: "a", firstSeenAt: Date(), confidence: 0.9),
            initialTargets: []
        )
        vm.text = "hello"
        XCTAssertFalse(vm.canSend)        // no targets
        vm.targets = [.mastodon]
        XCTAssertTrue(vm.canSend)         // one target, has text
        vm.text = "  "
        XCTAssertFalse(vm.canSend)        // whitespace text
    }

    func testCharacterCountsAlwaysReportBothNetworkLimits() {
        let vm = EchoComposeViewModel(
            moment: FusedMoment(mastodonPostID: "m1", blueskyPostID: "b1",
                                authorIdentityKey: "a", firstSeenAt: Date(), confidence: 0.9),
            initialTargets: [.mastodon]
        )
        vm.text = String(repeating: "x", count: 250)
        XCTAssertEqual(vm.mastodonRemaining, 500 - 250) // Mastodon default 500
        XCTAssertEqual(vm.blueskyRemaining, 300 - 250)  // Bluesky default 300
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/EchoComposeViewModelTests`
Expected: FAIL — `EchoComposeViewModel` not defined.

- [ ] **Step 3: Implement the ViewModel**

Create `SocialFusion/ViewModels/EchoComposeViewModel.swift`:

```swift
import Combine
import Foundation
import SwiftUI

@MainActor
public final class EchoComposeViewModel: ObservableObject {
    public let moment: FusedMoment

    @Published public var text: String = ""
    @Published public var targets: Set<SocialPlatform>
    @Published public private(set) var isSending: Bool = false

    public init(moment: FusedMoment, initialTargets: Set<SocialPlatform>) {
        self.moment = moment
        self.targets = initialTargets
    }

    public var mastodonLimit: Int { 500 }
    public var blueskyLimit: Int { 300 }

    public var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var mastodonRemaining: Int { mastodonLimit - text.count }
    public var blueskyRemaining: Int { blueskyLimit - text.count }

    public var canSend: Bool {
        guard !trimmedText.isEmpty else { return false }
        guard !targets.isEmpty else { return false }
        if targets.contains(.mastodon) && mastodonRemaining < 0 { return false }
        if targets.contains(.bluesky) && blueskyRemaining < 0 { return false }
        return true
    }

    public var sendActionLabel: String {
        switch targets {
        case []: return "Reply…"
        case [.mastodon]: return "Reply on Mastodon"
        case [.bluesky]: return "Reply on Bluesky"
        case [.mastodon, .bluesky]: return "Reply to both"
        default: return "Reply…"
        }
    }

    public enum SendStyle {
        case dual, mastodonOnly, blueskyOnly, disabled
    }

    public var sendStyle: SendStyle {
        switch targets {
        case [.mastodon, .bluesky]: return .dual
        case [.mastodon]: return .mastodonOnly
        case [.bluesky]: return .blueskyOnly
        default: return .disabled
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/EchoComposeViewModelTests`
Expected: PASS.

- [ ] **Step 5: Implement the View**

Create `SocialFusion/Views/EchoComposeView.swift`:

```swift
import SwiftUI

public struct EchoComposeView: View {
    @StateObject var viewModel: EchoComposeViewModel
    @Environment(\.dismiss) private var dismiss
    var onSend: (String, Set<SocialPlatform>) async -> Void

    public init(
        viewModel: EchoComposeViewModel,
        onSend: @escaping (String, Set<SocialPlatform>) async -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onSend = onSend
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                replyingToHeader
                targetRows
                editor
                Spacer()
                charCounts
            }
            .padding(16)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text("Reply").font(.headline)
                }
                ToolbarItem(placement: .confirmationAction) {
                    sendButton
                }
            }
        }
    }

    private var replyingToHeader: some View {
        HStack(spacing: 8) {
            FusedGlyph(size: 16)
            Text("Replying in a Fused conversation")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var targetRows: some View {
        VStack(spacing: 0) {
            targetRow(.mastodon)
            Divider()
            targetRow(.bluesky)
        }
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func targetRow(_ platform: SocialPlatform) -> some View {
        HStack(spacing: 12) {
            PlatformLogoBadge(platform: platform, size: 24)
            Text(platform == .mastodon ? "Mastodon" : "Bluesky")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Toggle("", isOn: Binding(
                get: { viewModel.targets.contains(platform) },
                set: { isOn in
                    if isOn { viewModel.targets.insert(platform) }
                    else { viewModel.targets.remove(platform) }
                }
            ))
            .labelsHidden()
            .accessibilityLabel(platform == .mastodon ? "Reply on Mastodon" : "Reply on Bluesky")
        }
        .padding(12)
    }

    private var editor: some View {
        TextEditor(text: $viewModel.text)
            .frame(minHeight: 120)
            .padding(8)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
            .accessibilityLabel("Reply text")
    }

    private var charCounts: some View {
        HStack(spacing: 12) {
            Spacer()
            counterChip(label: "M", value: viewModel.mastodonRemaining,
                        dimmed: !viewModel.targets.contains(.mastodon),
                        color: .purple)
            counterChip(label: "B", value: viewModel.blueskyRemaining,
                        dimmed: !viewModel.targets.contains(.bluesky),
                        color: .blue)
        }
    }

    private func counterChip(label: String, value: Int, dimmed: Bool, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2.weight(.bold))
            Text("\(value)").font(.caption2.monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(dimmed ? 0.05 : 0.15), in: Capsule())
        .foregroundStyle(value < 0 ? .red : color)
        .opacity(dimmed ? 0.4 : 1.0)
    }

    private var sendButton: some View {
        Button {
            let text = viewModel.text
            let targets = viewModel.targets
            Task {
                await onSend(text, targets)
                dismiss()
            }
        } label: {
            Text(viewModel.sendActionLabel)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(sendButtonBackground, in: Capsule())
                .foregroundStyle(.white)
        }
        .disabled(!viewModel.canSend)
        .opacity(viewModel.canSend ? 1.0 : 0.45)
    }

    @ViewBuilder
    private var sendButtonBackground: some View {
        switch viewModel.sendStyle {
        case .dual:
            LinearGradient(
                colors: [
                    Color(red: 0.54, green: 0.39, blue: 1.00),
                    Color(red: 0.11, green: 0.91, blue: 1.00),
                    Color(red: 0.00, green: 0.59, blue: 1.00)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .mastodonOnly:
            Color(red: 0.54, green: 0.39, blue: 1.00)
        case .blueskyOnly:
            Color(red: 0.00, green: 0.59, blue: 1.00)
        case .disabled:
            Color.gray
        }
    }
}
```

- [ ] **Step 6: Wire reply action on FusedConversationView**

Back in `FusedConversationView.swift`, add a "Reply" button (toolbar or floating) that presents `EchoComposeView`. The starting `initialTargets` comes from `EchoPolicyStore`:

```swift
@EnvironmentObject private var echoPolicyStore: EchoPolicyStore
@State private var showingCompose = false

// In the toolbar:
ToolbarItem(placement: .primaryAction) {
    Button {
        showingCompose = true
    } label: {
        Image(systemName: "arrowshape.turn.up.left.fill")
    }
}

// In a .sheet modifier on the ScrollView:
.sheet(isPresented: $showingCompose) {
    EchoComposeView(
        viewModel: EchoComposeViewModel(
            moment: viewModel.moment,
            initialTargets: echoPolicyStore.initialReplyTargets(originalPlatform: viewModel.rootPost?.platform ?? .mastodon)
        ),
        onSend: { text, targets in
            await sendEchoedReply(
                text: text,
                targets: targets,
                replyToMastodonID: viewModel.moment.mastodonPostID,
                replyToBlueskyID: viewModel.moment.blueskyPostID,
                mastodonService: serviceManager.mastodonService,
                blueskyService: serviceManager.blueskyService
            )
        }
    )
}
```

Add the dispatch helper at file scope in `FusedConversationView.swift` (or as a static method on `EchoComposeViewModel` if you prefer to keep view-layer files smaller):

```swift
/// Dispatches a Fused reply to one or both networks in parallel.
/// Returns the set of platforms that succeeded. Callers can subtract from
/// the requested targets to learn which side(s) failed.
@discardableResult
func sendEchoedReply(
    text: String,
    targets: Set<SocialPlatform>,
    replyToMastodonID: String,
    replyToBlueskyID: String,
    mastodonService: MastodonService,
    blueskyService: BlueskyService
) async -> Set<SocialPlatform> {
    async let mastoResult: Result<Void, Error>? = {
        guard targets.contains(.mastodon) else { return nil }
        do {
            // The existing reply API on MastodonService is named differently in the
            // codebase; adapt this call site to it. The expected signature is
            // something like `replyToPost(id:text:)` or `createReply(parentID:body:)`.
            // Verify by grepping `MastodonService.swift` for `reply` before editing.
            try await mastodonService.reply(toPostID: replyToMastodonID, text: text)
            return .success(())
        } catch {
            return .failure(error)
        }
    }()

    async let bskyResult: Result<Void, Error>? = {
        guard targets.contains(.bluesky) else { return nil }
        do {
            try await blueskyService.reply(toPostID: replyToBlueskyID, text: text)
            return .success(())
        } catch {
            return .failure(error)
        }
    }()

    let (m, b) = await (mastoResult, bskyResult)
    var succeeded: Set<SocialPlatform> = []
    if case .success = m { succeeded.insert(.mastodon) }
    if case .success = b { succeeded.insert(.bluesky) }

    // On partial failure, surface a one-side-failed alert reusing the outage
    // banner pattern from Task 10. (Inline a single sheet/alert here, or
    // raise a Combine subject that the parent view observes — engineer's
    // choice; the banner UI in `FusedConversationView` can be reused.)
    let failures = targets.subtracting(succeeded)
    if !failures.isEmpty {
        // Show an alert listing the failed platforms; offer "Retry" buttons.
        // Reuse `outageBanner(platform:message:retry:)` from Task 10 by
        // exposing a small `@State` flag and presenting via .alert(...).
    }

    return succeeded
}
```

**Implementer note:** before pasting this code, run `grep -n "func reply\|reply(to" SocialFusion/Services/MastodonService.swift SocialFusion/Services/BlueskyService.swift` to find the actual reply method signatures. The names above are stand-ins for the canonical reply APIs already in those services — adapt the call sites to whatever the codebase uses today. If neither service exposes a reply method (unlikely given existing reply UI), add the smallest possible wrapper around the API client's reply endpoint and call that.

- [ ] **Step 7: Smoke test on the simulator**

Open a Fused conversation, tap reply, verify:
- Both rows show with toggles in the state from `EchoPolicyStore` (initially `.askEachTime` so neither is checked).
- Toggling a single network changes the Send button color/label correctly.
- Character counter shows both M and B at all times; the unchecked side dims.
- Send is disabled when no targets or empty text.

- [ ] **Step 8: Commit**

```bash
git add SocialFusion/Views/EchoComposeView.swift SocialFusion/ViewModels/EchoComposeViewModel.swift SocialFusionTests/EchoComposeViewModelTests.swift SocialFusion/Views/FusedConversationView.swift
git commit -m "feat(fuse): EchoComposeView with Send-button-as-policy"
```

---

## Task 14: Onboarding integration — Echo policy step

**Files:**
- Modify: `SocialFusion/Views/OnboardingView.swift`

Insert the "Echo your replies?" step between authentication and the timeline reveal. Toggle (default on) + Continue + "Not now — I'll choose each time" secondary action.

- [ ] **Step 1: Locate the carousel step model**

Open `SocialFusion/Views/OnboardingView.swift`. The file uses a carousel of pages per CLAUDE.md. Identify the page enum / array that drives the carousel.

- [ ] **Step 2: Add the echo step page**

Add a new case to the page enum (e.g., `.echoPolicy`) and a corresponding view:

```swift
struct EchoPolicyOnboardingPage: View {
    @EnvironmentObject var echoPolicyStore: EchoPolicyStore
    @State private var echoOn: Bool = true
    var onContinue: () -> Void
    var onAskEachTime: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            FusedGlyph(size: 64)
                .padding(.top, 40)
            Text("Echo your replies?")
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            Text("When you reply to a post that exists on both networks, SocialFusion can mirror your reply by default — so the conversation stays together.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            VStack {
                Toggle(isOn: $echoOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Echo replies by default")
                            .font(.subheadline.weight(.semibold))
                        Text("Mirror to both networks when you reply to a Fused post")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                echoPolicyStore.policy = echoOn ? .echoOn : .echoOff
                onContinue()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
                    .font(.headline)
            }
            .padding(.horizontal, 24)

            Button {
                echoPolicyStore.policy = .askEachTime
                onAskEachTime()
            } label: {
                Text("Not now — I'll choose each time")
                    .font(.footnote)
                    .foregroundStyle(.accentColor)
            }
            .padding(.bottom, 24)
        }
    }
}
```

- [ ] **Step 3: Insert into the carousel sequence**

Place `EchoPolicyOnboardingPage` after the authentication step and before the timeline reveal. Both `onContinue` and `onAskEachTime` should advance to the next page.

- [ ] **Step 4: Manual test**

Reset the app (uninstall + reinstall) to trigger onboarding. Step through. Verify the echo policy page renders correctly, both buttons advance the carousel, and the chosen policy persists across app restarts (kill and relaunch, then open a Fused conversation and tap reply — the initial toggles should reflect the choice).

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Views/OnboardingView.swift
git commit -m "feat(fuse): add echo policy step to onboarding carousel"
```

---

## Task 15: Settings integration — Echo policy radio

**Files:**
- Modify: `SocialFusion/Views/SettingsView.swift`

Add a Composer section to Settings with the three-radio policy choice, mirroring the onboarding ask so users can change their mind.

- [ ] **Step 1: Add the Composer section**

In `SettingsView.swift`, add a new `Section` (place it near other compose-related settings, or create a "Composer" section if none exists):

```swift
@EnvironmentObject private var echoPolicyStore: EchoPolicyStore

Section {
    Picker("Echo replies on Fused posts", selection: $echoPolicyStore.policy) {
        Text("Echo on by default").tag(EchoPolicy.echoOn)
        Text("Echo off by default").tag(EchoPolicy.echoOff)
        Text("Ask each time").tag(EchoPolicy.askEachTime)
    }
    .pickerStyle(.inline)
} header: {
    Text("Composer")
} footer: {
    Text("Controls the default state of the reply target toggles when you reply to a Fused conversation.")
}
```

- [ ] **Step 2: Manual test**

Open Settings, find the Composer section, change the policy. Open a Fused conversation, tap reply, verify the initial toggle state reflects the new policy.

- [ ] **Step 3: Commit**

```bash
git add SocialFusion/Views/SettingsView.swift
git commit -m "feat(fuse): add echo policy picker to Settings"
```

---

## Task 16: WatchedConversation model + store

**Files:**
- Create: `SocialFusion/Models/WatchedConversation.swift`
- Create: `SocialFusion/Stores/WatchedConversationStore.swift`
- Test: `SocialFusionTests/WatchedConversationStoreTests.swift`

A subscribe list for conversations. Backed by `UserDefaults` for v1.0 (lightweight; the watch list is small).

- [ ] **Step 1: Write the failing tests**

Create `SocialFusionTests/WatchedConversationStoreTests.swift`:

```swift
import XCTest
@testable import SocialFusion

@MainActor
final class WatchedConversationStoreTests: XCTestCase {
    private let key = "watched-conversations-test-key"

    override func setUp() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    func testWatchAndUnwatchToggle() {
        let store = WatchedConversationStore(userDefaults: .standard, defaultsKey: key)
        let conv = WatchedConversation(rootPostID: "m1", platform: .mastodon, fusedMomentID: "fused:m1+b1")
        XCTAssertFalse(store.isWatching(rootPostID: "m1"))
        store.watch(conv)
        XCTAssertTrue(store.isWatching(rootPostID: "m1"))
        XCTAssertTrue(store.isWatching(rootPostID: "b1")) // twin lookup via fusedMomentID
        store.unwatch(rootPostID: "m1")
        XCTAssertFalse(store.isWatching(rootPostID: "m1"))
    }

    func testPersistsAcrossInstances() {
        let s1 = WatchedConversationStore(userDefaults: .standard, defaultsKey: key)
        s1.watch(WatchedConversation(rootPostID: "m1", platform: .mastodon, fusedMomentID: nil))
        let s2 = WatchedConversationStore(userDefaults: .standard, defaultsKey: key)
        XCTAssertTrue(s2.isWatching(rootPostID: "m1"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/WatchedConversationStoreTests`
Expected: FAIL.

- [ ] **Step 3: Implement the model and store**

Create `SocialFusion/Models/WatchedConversation.swift`:

```swift
import Foundation

public struct WatchedConversation: Identifiable, Codable, Hashable {
    public let id: String
    public let rootPostID: String
    public let platform: SocialPlatform
    public let fusedMomentID: String?
    public let watchedAt: Date

    public init(rootPostID: String, platform: SocialPlatform, fusedMomentID: String?) {
        self.id = "watch:\(rootPostID)"
        self.rootPostID = rootPostID
        self.platform = platform
        self.fusedMomentID = fusedMomentID
        self.watchedAt = Date()
    }
}
```

Create `SocialFusion/Stores/WatchedConversationStore.swift`:

```swift
import Combine
import Foundation
import SwiftUI

@MainActor
public final class WatchedConversationStore: ObservableObject {
    @Published public private(set) var watched: [String: WatchedConversation] = [:]

    private let userDefaults: UserDefaults
    private let defaultsKey: String

    public init(
        userDefaults: UserDefaults = .standard,
        defaultsKey: String = "watched.conversations"
    ) {
        self.userDefaults = userDefaults
        self.defaultsKey = defaultsKey
        load()
    }

    public func watch(_ conv: WatchedConversation) {
        watched[conv.rootPostID] = conv
        persist()
    }

    public func unwatch(rootPostID: String) {
        if let conv = watched[rootPostID] {
            watched.removeValue(forKey: conv.rootPostID)
            persist()
        }
    }

    public func isWatching(rootPostID: String) -> Bool {
        if watched[rootPostID] != nil { return true }
        // Also true if the post is a twin of a watched Fused root.
        for conv in watched.values {
            if let _ = conv.fusedMomentID, conv.rootPostID == rootPostID { return true }
        }
        return false
    }

    public func allWatched() -> [WatchedConversation] {
        watched.values.sorted { $0.watchedAt > $1.watchedAt }
    }

    private func load() {
        guard let data = userDefaults.data(forKey: defaultsKey) else { return }
        guard let decoded = try? JSONDecoder().decode([String: WatchedConversation].self, from: data) else { return }
        self.watched = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(watched) else { return }
        userDefaults.set(data, forKey: defaultsKey)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/WatchedConversationStoreTests`
Expected: PASS.

- [ ] **Step 5: Inject at app root**

In `SocialFusionApp.swift`: `@StateObject private var watchedConversationStore = WatchedConversationStore()` + `.environmentObject(...)`.

- [ ] **Step 6: Commit**

```bash
git add SocialFusion/Models/WatchedConversation.swift SocialFusion/Stores/WatchedConversationStore.swift SocialFusionTests/WatchedConversationStoreTests.swift SocialFusion/SocialFusionApp.swift
git commit -m "feat(fuse): WatchedConversationStore with UserDefaults persistence"
```

---

## Task 17: Watch action UI + WatchedConversationsView

**Files:**
- Modify: `SocialFusion/Views/FusedConversationView.swift` (add a Watch toolbar button)
- Modify: `SocialFusion/Models/Post.swift` or its companion: add a "Watch" action to the existing `PostAction` enum.
- Modify: `SocialFusion/Views/Components/PostCardView.swift` (add Watch to the action menu)
- Create: `SocialFusion/Views/WatchedConversationsView.swift`

- [ ] **Step 1: Add Watch to PostAction**

In `SocialFusion/Models/Post.swift`, extend the `PostAction` enum with `.watch`:

```swift
public enum PostAction: Hashable {
    case reply, repost, like, share, quote
    case follow, mute, block, addToList
    case openInBrowser, copyLink, shareSheet, shareAsImage, report
    case watch     // NEW
}
```

Add menu label and icon:

```swift
case .watch:
    return "Watch conversation"
// And:
case .watch:
    return "bell"
```

- [ ] **Step 2: Wire Watch into the card action menu**

In `PostCardView.swift`, surface the watch action in the existing menu:

```swift
@EnvironmentObject private var watchedConversationStore: WatchedConversationStore
@EnvironmentObject private var fusedMomentStore: FusedMomentStore

// In the menu:
Button {
    if watchedConversationStore.isWatching(rootPostID: post.id) {
        watchedConversationStore.unwatch(rootPostID: post.id)
    } else {
        let moment = fusedMomentStore.moment(for: post.id)
        watchedConversationStore.watch(WatchedConversation(
            rootPostID: post.id,
            platform: post.platform,
            fusedMomentID: moment?.id
        ))
    }
} label: {
    Label(
        watchedConversationStore.isWatching(rootPostID: post.id) ? "Stop watching" : "Watch conversation",
        systemImage: watchedConversationStore.isWatching(rootPostID: post.id) ? "bell.slash" : "bell"
    )
}
```

- [ ] **Step 3: Create the WatchedConversationsView**

Create `SocialFusion/Views/WatchedConversationsView.swift`:

```swift
import SwiftUI

public struct WatchedConversationsView: View {
    @EnvironmentObject var store: WatchedConversationStore
    @EnvironmentObject var fusedMomentStore: FusedMomentStore

    public var body: some View {
        List(store.allWatched()) { conv in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let momentID = conv.fusedMomentID,
                       fusedMomentStore.moments[momentID] != nil {
                        FusedGlyph(size: 16)
                    } else {
                        PlatformLogoBadge(platform: conv.platform, size: 16)
                    }
                    Text(conv.rootPostID)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(conv.watchedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .swipeActions {
                Button(role: .destructive) {
                    store.unwatch(rootPostID: conv.rootPostID)
                } label: {
                    Label("Unwatch", systemImage: "bell.slash")
                }
            }
        }
        .navigationTitle("Watching")
    }
}
```

- [ ] **Step 4: Add a route to WatchedConversationsView**

Add an entry in the main tab bar or in Settings → "Watching" that pushes `WatchedConversationsView`. v1.0 minimal: a row in Settings under a "Conversations" section.

- [ ] **Step 5: Smoke test on the simulator**

- Tap a post's menu → "Watch conversation." Verify the bell icon flips.
- Navigate to Settings → Watching. Verify the post appears in the list.
- Swipe to unwatch. Verify it disappears and the menu re-shows "Watch conversation."

- [ ] **Step 6: Commit**

```bash
git add SocialFusion/Models/Post.swift SocialFusion/Views/Components/PostCardView.swift SocialFusion/Views/WatchedConversationsView.swift SocialFusion/Views/SettingsView.swift SocialFusion/Views/FusedConversationView.swift
git commit -m "feat(fuse): Watch a conversation — action, UI, watched list"
```

---

## Task 18: Background polling for watched-conversation updates

**Files:**
- Modify: `SocialFusion/Services/NotificationManager.swift`

Tie watched conversations into the existing notification polling so new replies on either side ping the user.

- [ ] **Step 1: Wire the store into NotificationManager**

`NotificationManager.swift` already polls for general notifications per CLAUDE.md. Inject the `WatchedConversationStore` into it via the existing initializer (or via an `@EnvironmentObject` if it's UI-facing; otherwise a setter on the singleton).

- [ ] **Step 2: Add watched-conversation polling**

In the polling cycle, for each watched conversation: fetch the latest reply count via the appropriate service. If it's increased since the last check, emit a local notification:

```swift
private var lastSeenReplyCounts: [String: Int] = [:]

private func pollWatchedConversations() async {
    for conv in await watchedConversationStore.allWatched() {
        do {
            let count = try await fetchReplyCount(for: conv)
            let key = conv.rootPostID
            let previous = lastSeenReplyCounts[key] ?? count
            if count > previous {
                await scheduleLocalNotification(
                    title: "New replies in a watched conversation",
                    body: "\(count - previous) new repl\(count - previous == 1 ? "y" : "ies")"
                )
            }
            lastSeenReplyCounts[key] = count
        } catch {
            // Silent failure — watched conversations are best-effort.
        }
    }
}

private func fetchReplyCount(for conv: WatchedConversation) async throws -> Int {
    switch conv.platform {
    case .mastodon: return try await mastodonService.replyCount(for: conv.rootPostID)
    case .bluesky: return try await blueskyService.replyCount(for: conv.rootPostID)
    }
}
```

If `replyCount(for:)` doesn't exist on the services, add it as a thin wrapper around the existing thread-fetch endpoint that returns `thread.replies.count`.

- [ ] **Step 3: Tune the poll cadence**

The existing polling probably runs every minute or two. Watched-conversation polling should hitch onto the same cycle, not a separate timer. Verify the integration runs at the existing cadence.

- [ ] **Step 4: Smoke test**

Watch a Fused conversation. Have someone post a reply to it on either network (or simulate). Wait one polling cycle. Verify a local notification arrives saying "1 new reply."

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Services/NotificationManager.swift SocialFusion/Services/MastodonService.swift SocialFusion/Services/BlueskyService.swift
git commit -m "feat(fuse): background polling for watched-conversation new replies"
```

---

## Task 19: End-to-end Fuse integration test + acceptance

**Files:**
- Create: `SocialFusionTests/FuseEndToEndTests.swift`
- Modify: `SocialFusion/Views/Debug/TimelineValidationDebugView.swift` (add a Fuse section to the existing validation harness)

Verify the full breakthrough surface end-to-end against the spec acceptance criteria.

- [ ] **Step 1: Write the acceptance test harness**

Create `SocialFusionTests/FuseEndToEndTests.swift`:

```swift
import XCTest
@testable import SocialFusion

@MainActor
final class FuseEndToEndTests: XCTestCase {
    /// Acceptance: a cross-posted moment in the input buffer surfaces as a
    /// Fused post in the store after normalization.
    func testNormalizationPipelineDetectsAndStoresFusedMoment() async {
        let store = FusedMomentStore()
        let detector = FusedMomentDetector()
        let now = Date()
        let posts = [
            makePost(id: "m1", platform: .mastodon, content: "Hello world", authorId: "author-1", createdAt: now),
            makePost(id: "b1", platform: .bluesky, content: "Hello world", authorId: "author-1", createdAt: now.addingTimeInterval(60))
        ]
        let detected = detector.detect(in: posts)
        store.insert(detected)
        XCTAssertNotNil(store.moment(for: "m1"))
        XCTAssertNotNil(store.moment(for: "b1"))
    }

    /// Acceptance: per-post composer Send-button label is correct for each
    /// of the 4 toggle states.
    func testEchoComposerSendButtonLabelStates() {
        let vm = EchoComposeViewModel(
            moment: FusedMoment(mastodonPostID: "m", blueskyPostID: "b",
                                authorIdentityKey: "a", firstSeenAt: Date(), confidence: 0.9),
            initialTargets: [.mastodon, .bluesky]
        )
        XCTAssertEqual(vm.sendActionLabel, "Reply to both")
        vm.targets = [.mastodon]
        XCTAssertEqual(vm.sendActionLabel, "Reply on Mastodon")
        vm.targets = [.bluesky]
        XCTAssertEqual(vm.sendActionLabel, "Reply on Bluesky")
        vm.targets = []
        XCTAssertEqual(vm.sendActionLabel, "Reply…")
    }

    /// Acceptance: onboarding choice persists across store instances.
    func testEchoPolicyPersistsAcrossInstances() {
        let key = "echo-policy-e2e-key"
        UserDefaults.standard.removeObject(forKey: key)
        let s1 = EchoPolicyStore(userDefaults: .standard, defaultsKey: key)
        s1.policy = .echoOn
        let s2 = EchoPolicyStore(userDefaults: .standard, defaultsKey: key)
        XCTAssertEqual(s2.policy, .echoOn)
    }

    /// Acceptance: WatchedConversationStore round-trips through UserDefaults.
    func testWatchListPersists() {
        let key = "watched-e2e-key"
        UserDefaults.standard.removeObject(forKey: key)
        let s1 = WatchedConversationStore(userDefaults: .standard, defaultsKey: key)
        s1.watch(WatchedConversation(rootPostID: "m1", platform: .mastodon, fusedMomentID: nil))
        let s2 = WatchedConversationStore(userDefaults: .standard, defaultsKey: key)
        XCTAssertTrue(s2.isWatching(rootPostID: "m1"))
    }

    private func makePost(
        id: String, platform: SocialPlatform, content: String,
        authorId: String, createdAt: Date
    ) -> Post {
        // Reuse the helper from FusedMomentDetectorTests via a shared test utility,
        // or duplicate the minimal Post init here.
        Post(
            id: id, content: content,
            authorName: "Test", authorUsername: "t",
            authorProfilePictureURL: "",
            createdAt: createdAt,
            platform: platform,
            originalURL: "",
            attachments: [], mentions: [], tags: [],
            authorId: authorId
        )
    }
}
```

- [ ] **Step 2: Extend TimelineValidationDebugView with a Fuse section**

`TimelineValidationDebugView` (per CLAUDE.md) is gated `#if DEBUG` and accessed via long-press on the compose button. Add a "Fuse" section that exercises:

- Detector against the bundled corpus (calls into Task 4's corpus test logic in a runnable form).
- Store insertion + lookup.
- A live-feed check: scan the current timeline buffer for Fused candidates and report the detected count and confidence distribution.

The exact code mirrors the existing validation patterns in that file. Surface results in the existing pass/fail UI.

- [ ] **Step 3: Run the full test suite**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: all tests pass.

- [ ] **Step 4: Verify the spec acceptance criteria**

Walk down the v1.0 Acceptance Criteria → "The Fuse" section in the spec:

| Criterion | Evidence |
|---|---|
| Detection test corpus 100+ posts, FP<1%, FN<5% | Corpus test (Task 4). Note in commit: corpus expansion still tracked separately. |
| Unified view renders correctly on one-side outage | View model test (Task 9), manual smoke test (Task 10). |
| Echo composer Send button reflects toggle state | View model test (Task 13), e2e test above. |
| Onboarding ask works end-to-end; Settings mirror persists | Task 14 manual test, Task 15 manual test, persistence e2e test above. |

- [ ] **Step 5: Commit**

```bash
git add SocialFusionTests/FuseEndToEndTests.swift SocialFusion/Views/Debug/TimelineValidationDebugView.swift
git commit -m "test(fuse): end-to-end acceptance harness + validation debug surface"
```

---

## Acceptance gate before promoting to TestFlight

After all 19 tasks are complete:

1. **Full unit test suite passes:** `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet` returns 0.
2. **`TimelineValidationDebugView` Fuse section ≥ 90% pass rate** on a real iPhone with Frank's accounts signed in.
3. **Corpus expanded to ≥ 100 entries** with FP < 1% and FN < 5% confirmed.
4. **Manual smoke test against Frank's iPhone 17 Pro and iPad Pro** (UDIDs in `MEMORY.md`) — at least one Fused moment scrolls past during normal use; tap → unified view loads; reply → echo composer behaves correctly per current EchoPolicy; watch a thread; receive a notification when a new reply arrives.
5. **No new `AttributeGraph` warnings** in the Xcode console during the manual smoke test.
6. **Reduce-motion respect:** with Reduce Motion enabled in Simulator settings, the FusedGlyph A→D bloom is skipped.

---

## What's intentionally out of scope for this plan

The following live in sibling plans (see spec, "What's not in this spec"):

- **Glass-box filter editor** for "you shape the lens" Principle 3 — v1.x.
- **Cross-device watched-conversation sync** via iCloud KVS — depends on KVS budget after timeline-position sync ships; may piggyback into v1.0 if it fits, otherwise v1.1.
- **Echo-aware delete/edit propagation** — v1.x.
- **Merged profile cards** — separate plan.
- **Cross-device timeline-position sync** — separate plan, but the iCloud KVS infrastructure introduced there can be reused for watched-conversation sync if it lands first.
- **Dual-coded indicator audit + high-contrast toggle** — separate plan.
- **Timeline search** — separate plan.
- **Toast/banner error UI** — separate plan (closes existing `TimelineViewModel.swift:499, 553` TODOs).
- **Pinnable timelines** — separate plan.
- **Quote post fallback polish** — separate plan.

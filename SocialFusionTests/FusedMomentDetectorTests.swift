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
        // The Post initializer lives at SocialFusion/Models/Post.swift:764+.
        // Argument order must match the declaration: authorId sits between
        // authorUsername and authorProfilePictureURL.
        Post(
            id: id,
            content: content,
            authorName: "Test Author",
            authorUsername: "testuser",
            authorId: authorId,
            authorProfilePictureURL: "",
            createdAt: createdAt,
            platform: platform,
            originalURL: "",
            attachments: [],
            mentions: [],
            tags: []
        )
    }

    func testMatchesPostsWithSameSignatureAndAuthorWithinWindow() {
        let now = Date()
        let mastoPost = makePost(
            id: "m1",
            platform: .mastodon,
            content: "Big news today, this is genuinely excellent!",
            authorId: "author-identity-1",
            createdAt: now
        )
        let bskyPost = makePost(
            id: "b1",
            platform: .bluesky,
            content: "Big news today, this is genuinely excellent! #news",
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

    /// Content long enough to clear the short-content penalty in
    /// `computeConfidence` — anything below 20 chars gets a 0.20
    /// penalty off the 0.85 baseline, which dips below the 0.75
    /// minConfidence and prevents detection regardless of timing.
    /// Using a 30+-char fixture keeps the boundary tests focused on
    /// the time window, not the confidence math.
    private static let longEnoughContent = "Detector boundary fixture — same content."

    /// Boundary pin: the detector uses `<= timeWindow`, so a delta
    /// exactly equal to the configured window must still match. Catching
    /// this is the difference between a deterministic boundary and a
    /// "depends on your local clock skew" feel.
    func testMatchesAtExactTimeWindowBoundary() {
        let detector = FusedMomentDetector(timeWindow: 60)
        let now = Date()
        let posts = [
            makePost(id: "m1", platform: .mastodon, content: Self.longEnoughContent,
                     authorId: "a", createdAt: now),
            makePost(id: "b1", platform: .bluesky, content: Self.longEnoughContent,
                     authorId: "a", createdAt: now.addingTimeInterval(60))
        ]
        XCTAssertEqual(detector.detect(in: posts).count, 1,
                       "Exactly-on-the-window pair must match — the window is inclusive.")
    }

    /// Symmetric pair: detect must work regardless of which side's
    /// timestamp is later. Otherwise the network whose timeline
    /// happened to be slower would never fuse with the fast side —
    /// directly contradicts "the conversation is the unit of
    /// attention" since arrival order is incidental.
    func testMatchesWhenBlueskyIsTheEarlierPost() {
        let detector = FusedMomentDetector(timeWindow: 60)
        let now = Date()
        let posts = [
            makePost(id: "m1", platform: .mastodon, content: Self.longEnoughContent,
                     authorId: "a", createdAt: now.addingTimeInterval(45)),
            makePost(id: "b1", platform: .bluesky, content: Self.longEnoughContent,
                     authorId: "a", createdAt: now)
        ]
        XCTAssertEqual(detector.detect(in: posts).count, 1)
    }

    func testMatchesPostsWithDifferentAuthorIdsWhenMergedIdentityMapsThem() {
        // This is the production-wiring case: real Mastodon accountIds and
        // real Bluesky DIDs never match, so without a merged-identity map the
        // detector would emit zero moments. Feeding the map routes both posts
        // into the same author bucket via the merged-identity stable `id`.
        let now = Date()
        let mastoPost = makePost(
            id: "m1",
            platform: .mastodon,
            content: "Big news today, this is genuinely excellent!",
            authorId: "masto-author-123",
            createdAt: now
        )
        let bskyPost = makePost(
            id: "b1",
            platform: .bluesky,
            content: "Big news today, this is genuinely excellent! #news",
            authorId: "did:plc:abc123def",
            createdAt: now.addingTimeInterval(120)
        )
        let identityMap: FusedMomentDetector.IdentityKeyMap = [
            "mastodon:masto-author-123": "merged:unified-key",
            "bluesky:did:plc:abc123def": "merged:unified-key"
        ]
        let detector = FusedMomentDetector()
        let result = detector.detect(in: [mastoPost, bskyPost], identityMap: identityMap)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.authorIdentityKey, "merged:unified-key")
    }
}

// MARK: - Corpus acceptance test

extension FusedMomentDetectorTests {
    fileprivate struct CorpusPost: Decodable {
        let id: String
        let content: String
        let authorId: String
        let createdAt: Date
    }

    fileprivate struct CorpusEntry: Decodable {
        let label: String
        let note: String
        let masto: CorpusPost
        let bsky: CorpusPost
        let expectFused: Bool
    }

    fileprivate struct Corpus: Decodable {
        let version: Int
        let examples: [CorpusEntry]
    }

    // MARK: - TODO before v1.0 promote-to-App-Store
    // Expand fused-moments-corpus.json from the 5-entry seed to >= 100 entries
    // with real-world variety: short posts, posts with media references, posts
    // with URLs, mentions, threads, near-duplicates. Maintain ~70/30 positive/
    // negative split. Pull real cross-post pairs from production feeds.

    func testCorpusFalsePositiveAndFalseNegativeRates() throws {
        let url = Bundle(for: type(of: self)).url(
            forResource: "fused-moments-corpus",
            withExtension: "json"
        )
        let data = try Data(contentsOf: XCTUnwrap(url, "Corpus fixture missing — verify Fixtures/fused-moments-corpus.json is added to SocialFusionTests target Resources build phase"))
        let decoder = JSONDecoder()
        // Accept ISO8601 with or without fractional seconds. The corpus is
        // hand-curated; real-world API timestamps (Mastodon, Bluesky) often
        // include `.000Z`, and we want them to round-trip without surprises.
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso8601NoFractional = ISO8601DateFormatter()
        iso8601NoFractional.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = iso8601.date(from: raw) ?? iso8601NoFractional.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO8601 date, got: \(raw)"
            )
        }
        let corpus = try decoder.decode(Corpus.self, from: data)

        let detector = FusedMomentDetector()
        var falsePositives = 0
        var falseNegatives = 0
        var positives = 0
        var negatives = 0
        var fpEntries: [String] = []
        var fnEntries: [String] = []

        for entry in corpus.examples {
            let m = makePost(
                id: entry.masto.id,
                platform: .mastodon,
                content: entry.masto.content,
                authorId: entry.masto.authorId,
                createdAt: entry.masto.createdAt
            )
            let b = makePost(
                id: entry.bsky.id,
                platform: .bluesky,
                content: entry.bsky.content,
                authorId: entry.bsky.authorId,
                createdAt: entry.bsky.createdAt
            )
            let detected = !detector.detect(in: [m, b]).isEmpty
            if entry.expectFused {
                positives += 1
                if !detected {
                    falseNegatives += 1
                    fnEntries.append("\(entry.masto.id)/\(entry.bsky.id) — \(entry.note)")
                }
            } else {
                negatives += 1
                if detected {
                    falsePositives += 1
                    fpEntries.append("\(entry.masto.id)/\(entry.bsky.id) — \(entry.note)")
                }
            }
        }

        let fpRate = negatives > 0 ? Double(falsePositives) / Double(negatives) : 0
        let fnRate = positives > 0 ? Double(falseNegatives) / Double(positives) : 0

        XCTAssertLessThan(
            fpRate, 0.01,
            "False-positive rate \(String(format: "%.3f", fpRate)) (\(falsePositives)/\(negatives)) exceeds spec ceiling 1%.\nMisclassified: \(fpEntries.joined(separator: "; "))"
        )
        XCTAssertLessThan(
            fnRate, 0.05,
            "False-negative rate \(String(format: "%.3f", fnRate)) (\(falseNegatives)/\(positives)) exceeds spec ceiling 5%.\nMisclassified: \(fnEntries.joined(separator: "; "))"
        )

        // Surface the rates even on pass so CI/local runs show the trend.
        print(
            "Fuse corpus — positives: \(positives), negatives: \(negatives), "
            + "FP: \(String(format: "%.3f", fpRate)), FN: \(String(format: "%.3f", fnRate))"
        )
    }
}

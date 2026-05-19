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

    // MARK: - Regression tests from Task 1 review

    func testTrailingHashtagsOnNewlineAreStripped() {
        // Cross-poster: Mastodon hard-wraps trailing hashtags onto a new line.
        XCTAssertEqual(
            ContentSignature.fingerprint(for: "Big news today!"),
            ContentSignature.fingerprint(for: "Big news today!\n\n#news #important")
        )
    }

    func testTrailingHashtagsOnTabAreStripped() {
        XCTAssertEqual(
            ContentSignature.fingerprint(for: "Big news today!"),
            ContentSignature.fingerprint(for: "Big news today!\t#news")
        )
    }

    func testURLTrailingPunctuationIsStripped() {
        // Cross-posters disagree on whether trailing punctuation is part of the URL.
        XCTAssertEqual(
            ContentSignature.fingerprint(for: "see https://example.com"),
            ContentSignature.fingerprint(for: "see https://example.com.")
        )
        XCTAssertEqual(
            ContentSignature.fingerprint(for: "see (https://example.com)"),
            ContentSignature.fingerprint(for: "see (https://example.com")
        )
    }

    func testMultipleURLsAreEachNormalized() {
        // Two URLs in one post, each with different cross-poster artifacts.
        let a = ContentSignature.fingerprint(for: "compare https://example.com/a#anchor and https://example.com/b/")
        let b = ContentSignature.fingerprint(for: "compare https://example.com/a and https://example.com/b")
        XCTAssertEqual(a, b)
    }

    func testDifferentURLsRemainDistinct() {
        // Guard against future over-normalization (e.g., dropping paths).
        XCTAssertNotEqual(
            ContentSignature.fingerprint(for: "Read https://example.com/article1"),
            ContentSignature.fingerprint(for: "Read https://example.com/article2")
        )
    }

    func testEmojiInContentSurvives() {
        let s = ContentSignature.fingerprint(for: "Big news 🎉 today!")
        XCTAssertTrue(s.contains("🎉"))
    }

    /// Bracket-balanced URLs (e.g. Wikipedia paths with parenthesized
    /// disambiguations) must keep their structural trailing `)` — the
    /// punctuation strip should only remove trailing closers that don't
    /// have a matching opener earlier in the URL.
    func testBalancedParenInURLIsPreserved() {
        let a = ContentSignature.fingerprint(
            for: "Read https://en.wikipedia.org/wiki/Macintosh_(computer)"
        )
        // The closing paren must remain in the fingerprint — otherwise the
        // URL would degrade to `Macintosh_(computer` and a Wikipedia link
        // wouldn't match itself across networks.
        XCTAssertTrue(a.contains("(computer)"),
                      "Balanced closing paren must be preserved in normalized URL.")
    }

    /// Unbalanced trailing punctuation (sentence-ending paren around a URL)
    /// still gets stripped — that was the original goal of the punctuation
    /// strip and is preserved by the bracket-balance check.
    func testUnbalancedTrailingParenStripped() {
        let a = ContentSignature.fingerprint(for: "Find it (at https://example.com)")
        let b = ContentSignature.fingerprint(for: "Find it (at https://example.com")
        XCTAssertEqual(a, b,
                       "Sentence-ending paren around a URL should be stripped — its opener is in the surrounding prose, not the URL itself.")
    }

    func testBalancedBracketsAndBraces() {
        // Same logic must work for [] and {} — RFC 3986 allows brackets in
        // hosts and uncommon paths use braces.
        let a = ContentSignature.fingerprint(for: "See https://example.com/path[1]")
        XCTAssertTrue(a.contains("[1]"),
                      "Balanced brackets in URL path must be preserved.")
        let b = ContentSignature.fingerprint(for: "See https://example.com/path{a}")
        XCTAssertTrue(b.contains("{a}"),
                      "Balanced braces in URL path must be preserved.")
    }

    /// Cross-posters that prepend a recipient `@handle.tld` on one network
    /// shouldn't break the fingerprint match.
    func testLeadingMentionIsStripped() {
        let a = ContentSignature.fingerprint(for: "Big thanks to the reviewers")
        let b = ContentSignature.fingerprint(for: "@reviewers.bsky.social Big thanks to the reviewers")
        XCTAssertEqual(a, b)
    }

    /// Multiple contiguous leading mentions get stripped together.
    func testMultipleLeadingMentionsAreStripped() {
        let a = ContentSignature.fingerprint(for: "Heads up about the release")
        let b = ContentSignature.fingerprint(for: "@alice.bsky.social @bob.example.com Heads up about the release")
        XCTAssertEqual(a, b)
    }

    /// Mid-text mentions are content, not noise — must not be touched.
    func testMidTextMentionsArePreserved() {
        let withMention = ContentSignature.fingerprint(
            for: "Talked with @brent.simmons today about NetNewsWire")
        XCTAssertTrue(
            withMention.contains("@brent.simmons"),
            "Mid-text mentions are semantic content and must survive fingerprinting.")
    }

    /// Trailing terminal punctuation (period vs no period) is the most
    /// common cross-poster trimming pattern; must not break the match.
    func testTrailingPeriodIsStripped() {
        let a = ContentSignature.fingerprint(for: "Shipped the feature today.")
        let b = ContentSignature.fingerprint(for: "Shipped the feature today")
        XCTAssertEqual(a, b)
    }

    func testTrailingExclamationIsStripped() {
        let a = ContentSignature.fingerprint(for: "What a day!")
        let b = ContentSignature.fingerprint(for: "What a day")
        XCTAssertEqual(a, b)
    }

    /// Multiple trailing punctuation marks all get stripped, so "Wow!!!"
    /// and "Wow." both normalize identically.
    func testMultipleTrailingPunctuationStripped() {
        let a = ContentSignature.fingerprint(for: "Wow")
        let b = ContentSignature.fingerprint(for: "Wow!!!")
        XCTAssertEqual(a, b)
    }

    /// Trailing punctuation strip runs AFTER trailing-token strip, so
    /// "Welcome. #onboarding" — where the hashtag was the cross-poster
    /// addition and the period was already there — still collapses to
    /// "welcome".
    func testTrailingPunctuationStripsAfterTrailingHashtags() {
        let a = ContentSignature.fingerprint(for: "Welcome")
        let b = ContentSignature.fingerprint(for: "Welcome. #onboarding")
        XCTAssertEqual(a, b)
    }
}

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
}

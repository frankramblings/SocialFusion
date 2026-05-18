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
}

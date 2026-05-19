import XCTest
@testable import SocialFusion

@MainActor
final class FetchQuotePostClassifyTests: XCTestCase {
    private func nsError(domain: String, code: Int, description: String = "") -> NSError {
        NSError(domain: domain, code: code,
                userInfo: description.isEmpty ? nil : [NSLocalizedDescriptionKey: description])
    }

    func testClassifyNilReturnsUnknown() {
        XCTAssertEqual(FetchQuotePostView.classify(error: nil), .unknown)
    }

    func testHTTP404IsDeleted() {
        let err = nsError(domain: "FetchQuotePostView", code: 404)
        XCTAssertEqual(FetchQuotePostView.classify(error: err), .deleted)
    }

    func testHTTP410IsDeleted() {
        let err = nsError(domain: "MastodonService", code: 410)
        XCTAssertEqual(FetchQuotePostView.classify(error: err), .deleted)
    }

    func testHTTP403IsBlocked() {
        let err = nsError(domain: "FetchQuotePostView", code: 403)
        XCTAssertEqual(FetchQuotePostView.classify(error: err), .blocked)
    }

    func testHTTP401IsBlocked() {
        let err = nsError(domain: "FetchQuotePostView", code: 401)
        XCTAssertEqual(FetchQuotePostView.classify(error: err), .blocked)
    }

    func testURLErrorNotConnectedIsNetwork() {
        let err = nsError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertEqual(FetchQuotePostView.classify(error: err), .network)
    }

    func testURLErrorTimedOutIsNetwork() {
        let err = nsError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        XCTAssertEqual(FetchQuotePostView.classify(error: err), .network)
    }

    /// Services that bury the HTTP status in the message rather than the
    /// NSError.code still need to be classifiable. "404 Not Found" wording
    /// is common enough across server stacks to match heuristically.
    func testDescriptionHeuristic404IsDeleted() {
        let err = nsError(domain: "FetchQuotePostView", code: 0,
                          description: "Server returned 404 Not Found")
        XCTAssertEqual(FetchQuotePostView.classify(error: err), .deleted)
    }

    func testDescriptionHeuristicForbiddenIsBlocked() {
        let err = nsError(domain: "FetchQuotePostView", code: 0,
                          description: "403 Forbidden: account is private")
        XCTAssertEqual(FetchQuotePostView.classify(error: err), .blocked)
    }

    /// JSON parsing failures surface as NSCocoaErrorDomain code 3840 — keep
    /// the malformed classification distinct from "deleted" so the user
    /// understands the post exists but we couldn't render it.
    func testCocoaJSONErrorIsMalformed() {
        let err = nsError(domain: NSCocoaErrorDomain, code: 3840)
        XCTAssertEqual(FetchQuotePostView.classify(error: err), .malformed)
    }

    func testUnrecognizedErrorIsUnknown() {
        let err = nsError(domain: "SomeOtherDomain", code: 999,
                          description: "wild and unexpected")
        XCTAssertEqual(FetchQuotePostView.classify(error: err), .unknown)
    }
}

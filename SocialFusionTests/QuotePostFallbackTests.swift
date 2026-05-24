import XCTest
@testable import SocialFusion

/// Coverage for FetchQuotePostView's failure classifier. The view itself owns
/// the `static func classify(error:) -> QuotePostUnavailableView.Reason`
/// method (rather than living in a separate `QuoteFailureClassifier` type) —
/// these tests pin the classifier's behavior so refactors that touch the
/// failure-routing logic don't silently lose categories.
final class QuotePostFallbackTests: XCTestCase {

    // MARK: - Network errors

    func testNotConnectedToInternetMapsToNetwork() {
        let error = URLError(.notConnectedToInternet)
        XCTAssertEqual(FetchQuotePostView.classify(error: error), .network)
    }

    func testTimeoutMapsToNetwork() {
        let error = URLError(.timedOut)
        XCTAssertEqual(FetchQuotePostView.classify(error: error), .network)
    }

    func testConnectionLostMapsToNetwork() {
        let error = URLError(.networkConnectionLost)
        XCTAssertEqual(FetchQuotePostView.classify(error: error), .network)
    }

    func testDNSFailureMapsToNetwork() {
        let error = URLError(.dnsLookupFailed)
        XCTAssertEqual(FetchQuotePostView.classify(error: error), .network)
    }

    // MARK: - Deleted

    func testHTTP404CodeMapsToDeleted() {
        let error = NSError(
            domain: "FetchQuotePostView",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "Not Found"]
        )
        XCTAssertEqual(FetchQuotePostView.classify(error: error), .deleted)
    }

    func testHTTP410CodeMapsToDeleted() {
        let error = NSError(
            domain: "FetchQuotePostView",
            code: 410,
            userInfo: [NSLocalizedDescriptionKey: "Gone"]
        )
        XCTAssertEqual(FetchQuotePostView.classify(error: error), .deleted)
    }

    func testNotFoundInLocalizedDescriptionMapsToDeleted() {
        let error = NSError(
            domain: "FetchQuotePostView",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Post not found (404)"]
        )
        XCTAssertEqual(FetchQuotePostView.classify(error: error), .deleted)
    }

    // MARK: - Blocked / unauthorized

    func testHTTP403CodeMapsToBlocked() {
        let error = NSError(
            domain: "FetchQuotePostView",
            code: 403,
            userInfo: [NSLocalizedDescriptionKey: "Forbidden"]
        )
        XCTAssertEqual(FetchQuotePostView.classify(error: error), .blocked)
    }

    func testHTTP401CodeMapsToBlocked() {
        let error = NSError(
            domain: "FetchQuotePostView",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Unauthorized"]
        )
        XCTAssertEqual(FetchQuotePostView.classify(error: error), .blocked)
    }

    func testForbiddenStringInDescriptionMapsToBlocked() {
        let error = NSError(
            domain: "FetchQuotePostView",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Forbidden: account is private"]
        )
        XCTAssertEqual(FetchQuotePostView.classify(error: error), .blocked)
    }

    // MARK: - Malformed

    func testCocoaJSONErrorMapsToMalformed() {
        // NSCocoaErrorDomain 3840 = NSPropertyListReadCorruptError / JSON parse error
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: 3840,
            userInfo: [NSLocalizedDescriptionKey: "JSON parse failure"]
        )
        XCTAssertEqual(FetchQuotePostView.classify(error: error), .malformed)
    }

    func testDecodingErrorMapsToMalformed() {
        // Synthesize a DecodingError via a minimal failure path.
        struct Sample: Decodable { let x: Int }
        let badJSON = Data("{}".utf8)
        do {
            _ = try JSONDecoder().decode(Sample.self, from: badJSON)
            XCTFail("Expected decode to throw")
        } catch {
            XCTAssertEqual(FetchQuotePostView.classify(error: error), .malformed)
        }
    }

    // MARK: - Unknown / nil

    func testNilErrorMapsToUnknown() {
        XCTAssertEqual(FetchQuotePostView.classify(error: nil), .unknown)
    }

    func testUnrecognizedErrorMapsToUnknown() {
        struct Mystery: Error {}
        XCTAssertEqual(FetchQuotePostView.classify(error: Mystery()), .unknown)
    }
}

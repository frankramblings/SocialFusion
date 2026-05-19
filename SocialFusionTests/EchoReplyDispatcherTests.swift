import XCTest
@testable import SocialFusion

@MainActor
final class EchoReplyDispatcherTests: XCTestCase {
    /// Both targets succeed → both appear in `succeeded`, `failed` is empty.
    func testBothTargetsSucceed() async {
        let result = await sendEchoedReply(
            targets: [.mastodon, .bluesky],
            sendToMastodon: { /* success */ },
            sendToBluesky: { /* success */ }
        )
        XCTAssertEqual(result.succeeded, [.mastodon, .bluesky])
        XCTAssertEqual(result.failed, [])
    }

    /// One target fails (Bluesky throws); the other still reports success.
    func testOneTargetFailsTheOtherSucceeds() async {
        let result = await sendEchoedReply(
            targets: [.mastodon, .bluesky],
            sendToMastodon: { /* success */ },
            sendToBluesky: { throw URLError(.notConnectedToInternet) }
        )
        XCTAssertEqual(result.succeeded, [.mastodon])
        XCTAssertEqual(result.failed, [.bluesky])
    }

    /// Only-one-target requested → the other closure is never invoked.
    /// Verified by setting an actor flag from inside the unrequested closure
    /// and asserting it stayed false.
    func testUnrequestedTargetIsNotInvoked() async {
        let bskyInvoked = ActorBool()
        let result = await sendEchoedReply(
            targets: [.mastodon],
            sendToMastodon: { /* success */ },
            sendToBluesky: { await bskyInvoked.set(true) }
        )
        XCTAssertEqual(result.succeeded, [.mastodon])
        XCTAssertEqual(result.failed, [])
        let wasInvoked = await bskyInvoked.value
        XCTAssertFalse(wasInvoked, "Bluesky closure should not run when bluesky is not in targets")
    }

    /// Both targets fail → both surface in `failed`, `succeeded` is empty.
    func testBothTargetsFail() async {
        let result = await sendEchoedReply(
            targets: [.mastodon, .bluesky],
            sendToMastodon: { throw URLError(.timedOut) },
            sendToBluesky: { throw URLError(.cannotConnectToHost) }
        )
        XCTAssertEqual(result.succeeded, [])
        XCTAssertEqual(result.failed, [.mastodon, .bluesky])
    }

    /// Empty target set → nothing dispatched, both sets are empty.
    /// Covers the no-op path used when pre-flight filters out every target.
    func testEmptyTargets() async {
        let result = await sendEchoedReply(
            targets: [],
            sendToMastodon: { XCTFail("should not be called") },
            sendToBluesky: { XCTFail("should not be called") }
        )
        XCTAssertEqual(result.succeeded, [])
        XCTAssertEqual(result.failed, [])
    }
}

/// Tiny actor so the closure-side-effect assertion in
/// `testUnrequestedTargetIsNotInvoked` doesn't depend on capturing a
/// mutable local from a Sendable closure.
private actor ActorBool {
    private(set) var value = false
    func set(_ v: Bool) { value = v }
}

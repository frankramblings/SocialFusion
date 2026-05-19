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

    /// Send-button gate: `canSend` must return false while an in-flight
    /// dispatch is running so a double-tap can't spawn a second send with
    /// the same text + targets.
    func testCanSendIsFalseWhileSending() {
        let vm = EchoComposeViewModel(
            moment: FusedMoment(mastodonPostID: "m1", blueskyPostID: "b1",
                                authorIdentityKey: "a", firstSeenAt: Date(), confidence: 0.9),
            initialTargets: [.mastodon]
        )
        vm.text = "ready"
        XCTAssertTrue(vm.canSend)

        vm.beginSending()
        XCTAssertFalse(vm.canSend, "Sending in flight must block further sends.")

        vm.finishSending()
        XCTAssertTrue(vm.canSend, "Once dispatch completes, the gate releases.")
    }
}

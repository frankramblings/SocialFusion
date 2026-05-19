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

    /// Spec acceptance criterion: per-network character limits gate the
    /// Send button only for *targeted* networks. Typing 350 chars and
    /// only checking Mastodon (500 limit) must keep Send live — but
    /// adding Bluesky to the targets must block it again. Catches the
    /// regression where canSend would conflate "any side over" with
    /// "any *selected* side over".
    func testCanSendOnlyBlocksWhenTargetedNetworkIsOver() {
        let vm = EchoComposeViewModel(
            moment: FusedMoment(mastodonPostID: "m1", blueskyPostID: "b1",
                                authorIdentityKey: "a", firstSeenAt: Date(), confidence: 0.9),
            initialTargets: [.mastodon]
        )
        vm.text = String(repeating: "x", count: 350)
        XCTAssertLessThan(vm.blueskyRemaining, 0, "Precondition: Bluesky is over.")
        XCTAssertGreaterThan(vm.mastodonRemaining, 0, "Precondition: Mastodon has room.")
        XCTAssertTrue(vm.canSend,
            "Bluesky is over but isn't targeted — Send must stay live for the Mastodon-only echo.")
        vm.targets = [.mastodon, .bluesky]
        XCTAssertFalse(vm.canSend,
            "Adding Bluesky to the targets must block Send since the Bluesky leg would fail.")
    }

    /// `sendStyle` drives the Send button's gradient (purple → cyan →
    /// blue for dual, solid purple for Mastodon-only, solid blue for
    /// Bluesky-only, gray for nothing-selected). The button color *is*
    /// the policy per the spec; this guards against the lookup table
    /// drifting out of sync with `sendActionLabel`.
    func testSendStyleMatchesTargetSelection() {
        let vm = EchoComposeViewModel(
            moment: FusedMoment(mastodonPostID: "m1", blueskyPostID: "b1",
                                authorIdentityKey: "a", firstSeenAt: Date(), confidence: 0.9),
            initialTargets: [.mastodon, .bluesky]
        )
        XCTAssertEqual(vm.sendStyle, .dual)
        vm.targets = [.mastodon]
        XCTAssertEqual(vm.sendStyle, .mastodonOnly)
        vm.targets = [.bluesky]
        XCTAssertEqual(vm.sendStyle, .blueskyOnly)
        vm.targets = []
        XCTAssertEqual(vm.sendStyle, .disabled)
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

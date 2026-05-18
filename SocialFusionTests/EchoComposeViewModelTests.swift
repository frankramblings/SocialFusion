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

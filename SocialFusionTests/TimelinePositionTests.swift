import XCTest
@testable import SocialFusion

final class TimelinePositionTests: XCTestCase {
    func testRoundTripsThroughJSON() throws {
        let original = TimelinePosition(
            lastReadPostID: "post-123",
            lastReadAt: Date(timeIntervalSince1970: 1_715_000_000),
            scrollOffset: 240.5
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TimelinePosition.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testScrollOffsetIsOptional() throws {
        let p = TimelinePosition(
            lastReadPostID: "post-1",
            lastReadAt: Date(),
            scrollOffset: nil
        )
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(TimelinePosition.self, from: data)
        XCTAssertNil(decoded.scrollOffset)
        XCTAssertEqual(decoded.lastReadPostID, "post-1")
    }

    func testKeyComposition() {
        XCTAssertEqual(
            TimelinePosition.kvsKey(accountID: "acct-1", timelineID: "unified"),
            "pos.acct-1.unified"
        )
        XCTAssertEqual(
            TimelinePosition.kvsKey(accountID: "acct-1", timelineID: "mastodon"),
            "pos.acct-1.mastodon"
        )
    }

    func testIsNewerThanComparesByLastReadAt() {
        let older = TimelinePosition(
            lastReadPostID: "a", lastReadAt: Date(timeIntervalSince1970: 1000), scrollOffset: nil
        )
        let newer = TimelinePosition(
            lastReadPostID: "b", lastReadAt: Date(timeIntervalSince1970: 2000), scrollOffset: nil
        )
        XCTAssertTrue(newer.isNewer(than: older))
        XCTAssertFalse(older.isNewer(than: newer))
        XCTAssertFalse(newer.isNewer(than: newer))
    }

    func testIsWithinDeadbandTrueIfBothPositionsAgreeWithin30Seconds() {
        let base = Date(timeIntervalSince1970: 1_715_000_000)
        let a = TimelinePosition(lastReadPostID: "x", lastReadAt: base, scrollOffset: nil)
        let b = TimelinePosition(
            lastReadPostID: "x",
            lastReadAt: base.addingTimeInterval(20),
            scrollOffset: nil
        )
        XCTAssertTrue(a.isWithinDeadband(of: b))
    }

    func testIsWithinDeadbandFalseIfPostIDsDiffer() {
        let now = Date()
        let a = TimelinePosition(lastReadPostID: "x", lastReadAt: now, scrollOffset: nil)
        let b = TimelinePosition(lastReadPostID: "y", lastReadAt: now, scrollOffset: nil)
        XCTAssertFalse(a.isWithinDeadband(of: b))
    }
}

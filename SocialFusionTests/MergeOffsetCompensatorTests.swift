import XCTest
@testable import SocialFusion

final class MergeOffsetCompensatorTests: XCTestCase {
    func testCompensationReturnsZeroBelowThreshold() {
        let delta = MergeOffsetCompensator.compensation(
            previousOffset: 10,
            currentOffset: 9.8,
            threshold: 0.5
        )
        XCTAssertEqual(delta, 0)
    }

    func testCompensationReturnsDeltaWhenAboveThreshold() {
        let delta = MergeOffsetCompensator.compensation(
            previousOffset: 10,
            currentOffset: 8,
            threshold: 0.5
        )
        XCTAssertEqual(delta, 2)
    }
}


import XCTest
@testable import SocialFusion

final class CacheHydrationPolicyTests: XCTestCase {
    func testHydratesOnlyOnceBeforePresentation() {
        let policy = CacheHydrationPolicy()

        XCTAssertTrue(policy.shouldHydrate(
            hasHydrated: false,
            hasPresented: false,
            isTimelineEmpty: true
        ))

        XCTAssertFalse(policy.shouldHydrate(
            hasHydrated: true,
            hasPresented: false,
            isTimelineEmpty: true
        ))

        XCTAssertFalse(policy.shouldHydrate(
            hasHydrated: false,
            hasPresented: true,
            isTimelineEmpty: true
        ))

        XCTAssertFalse(policy.shouldHydrate(
            hasHydrated: false,
            hasPresented: false,
            isTimelineEmpty: false
        ))
    }
}


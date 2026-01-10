import XCTest
import SwiftUI
@testable import SocialFusion

final class PostMenuActionRoutingTests: XCTestCase {
    func testMenuLabelsForSystemActions() {
        XCTAssertEqual(PostAction.openInBrowser.menuLabel, "Open in Browser")
        XCTAssertEqual(PostAction.copyLink.menuLabel, "Copy Link")
        XCTAssertEqual(PostAction.shareSheet.menuLabel, "Share")
        XCTAssertEqual(PostAction.report.menuLabel, "Report")
    }

    func testMenuIconsForSystemActions() {
        XCTAssertEqual(PostAction.openInBrowser.menuSystemImage, "arrow.up.right.square")
        XCTAssertEqual(PostAction.copyLink.menuSystemImage, "link")
        XCTAssertEqual(PostAction.shareSheet.menuSystemImage, "square.and.arrow.up")
        XCTAssertEqual(PostAction.report.menuSystemImage, "exclamationmark.triangle")
    }

    func testReportIsDestructive() {
        XCTAssertEqual(PostAction.report.menuRole, .destructive)
    }
}

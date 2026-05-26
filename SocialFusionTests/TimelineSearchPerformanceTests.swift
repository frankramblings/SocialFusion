import XCTest
@testable import SocialFusion

final class TimelineSearchPerformanceTests: XCTestCase {

    /// Hard threshold: a 500-post buffer must filter in under 100ms.
    /// The spec budget is "<100ms after typing stops"; the filter is the
    /// dominant cost inside that window.
    func test500PostBufferFiltersInUnder100ms() {
        let posts = makeBuffer(count: 500)
        let start = CFAbsoluteTimeGetCurrent()
        let hits = TimelineBufferFilter.filter(posts, query: "swift")
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertLessThan(elapsed, 0.100, "Filter took \(elapsed * 1000)ms — budget is 100ms")
        // Sanity: at least some of the buffer carries the keyword.
        XCTAssertGreaterThan(hits.count, 0)
    }

    /// XCTest measurement for trend tracking. Not a hard gate, but useful in CI.
    func testFilterMeasureBlock() {
        let posts = makeBuffer(count: 500)
        measure {
            _ = TimelineBufferFilter.filter(posts, query: "ios swift")
        }
    }

    /// Multi-token query should also stay under budget.
    func testMultiTokenFilterInUnder100ms() {
        let posts = makeBuffer(count: 500)
        let start = CFAbsoluteTimeGetCurrent()
        _ = TimelineBufferFilter.filter(posts, query: "hello swift world programming")
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertLessThan(elapsed, 0.100, "Multi-token filter took \(elapsed * 1000)ms")
    }

    // MARK: - Helpers

    private func makeBuffer(count: Int) -> [Post] {
        let contents = [
            "Hello world from Swift",
            "iOS development is fun",
            "Today in tech news",
            "Programming notes on Swift concurrency",
            "Generic post with no keywords here",
        ]
        return (0..<count).map { i in
            Post(
                id: "post-\(i)",
                content: contents[i % contents.count],
                authorName: "Author \(i % 50)",
                authorUsername: "@user\(i % 50)",
                authorId: "author-\(i % 50)",
                authorProfilePictureURL: "",
                createdAt: Date().addingTimeInterval(-Double(i) * 60),
                platform: i % 2 == 0 ? .mastodon : .bluesky,
                originalURL: "",
                attachments: [],
                mentions: [],
                tags: i % 3 == 0 ? ["swift", "ios"] : ["news"]
            )
        }
    }
}

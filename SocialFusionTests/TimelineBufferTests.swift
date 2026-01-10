import XCTest
@testable import SocialFusion

@MainActor
final class TimelineBufferTests: XCTestCase {
    private func makePost(id: String, platform: SocialPlatform, createdAt: Date) -> Post {
        Post(
            id: id,
            content: "Post \(id)",
            authorName: "Author \(id)",
            authorUsername: "author\(id)",
            authorProfilePictureURL: "",
            createdAt: createdAt,
            platform: platform,
            originalURL: "https://example.com/\(id)",
            platformSpecificId: id
        )
    }

    func testBufferDedupesAgainstVisiblePosts() {
        let buffer = TimelineBuffer()
        let now = Date()
        let visible = [makePost(id: "1", platform: .mastodon, createdAt: now)]
        let incoming = [
            makePost(id: "1", platform: .mastodon, createdAt: now),
            makePost(id: "2", platform: .mastodon, createdAt: now.addingTimeInterval(-10))
        ]

        let snapshot = buffer.append(incomingPosts: incoming, visiblePosts: visible)

        XCTAssertEqual(snapshot?.bufferCount, 1)
        XCTAssertEqual(snapshot?.bufferSources, [.mastodon])
    }

    func testBufferSortsByNewestFirst() {
        let buffer = TimelineBuffer()
        let newer = makePost(id: "new", platform: .bluesky, createdAt: Date())
        let older = makePost(id: "old", platform: .bluesky, createdAt: Date().addingTimeInterval(-60))

        _ = buffer.append(incomingPosts: [older, newer], visiblePosts: [])
        let drained = buffer.drain()

        XCTAssertEqual(drained.first?.id, "new")
        XCTAssertEqual(drained.last?.id, "old")
    }

    func testBufferClearEmptiesSnapshot() {
        let buffer = TimelineBuffer()
        let post = makePost(id: "1", platform: .mastodon, createdAt: Date())
        _ = buffer.append(incomingPosts: [post], visiblePosts: [])

        let snapshot = buffer.clear()

        XCTAssertEqual(snapshot.bufferCount, 0)
        XCTAssertNil(snapshot.bufferEarliestTimestamp)
        XCTAssertTrue(snapshot.bufferSources.isEmpty)
    }
}


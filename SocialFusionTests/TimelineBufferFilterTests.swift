import XCTest
@testable import SocialFusion

final class TimelineBufferFilterTests: XCTestCase {
    func testEmptyQueryReturnsEmptyArray() {
        let posts = [makePost(id: "1", content: "Hello world")]
        XCTAssertEqual(TimelineBufferFilter.filter(posts, query: "").count, 0)
        XCTAssertEqual(TimelineBufferFilter.filter(posts, query: "   ").count, 0)
    }

    func testContentSubstringMatchCaseInsensitive() {
        let posts = [
            makePost(id: "1", content: "Hello WORLD"),
            makePost(id: "2", content: "Goodbye"),
        ]
        let hits = TimelineBufferFilter.filter(posts, query: "world")
        XCTAssertEqual(hits.map(\.id), ["1"])
    }

    func testAuthorNameMatch() {
        let posts = [
            makePost(id: "1", authorName: "Frank Emanuele", content: "anything"),
            makePost(id: "2", authorName: "Jane Doe", content: "anything"),
        ]
        let hits = TimelineBufferFilter.filter(posts, query: "frank")
        XCTAssertEqual(hits.map(\.id), ["1"])
    }

    func testAuthorHandleMatch() {
        let posts = [
            makePost(id: "1", authorUsername: "@frank@mastodon.social", content: "x"),
            makePost(id: "2", authorUsername: "@jane.bsky.social", content: "x"),
        ]
        let hits = TimelineBufferFilter.filter(posts, query: "jane")
        XCTAssertEqual(hits.map(\.id), ["2"])
    }

    func testTagMatch() {
        let posts = [
            makePost(id: "1", content: "x", tags: ["swift", "ios"]),
            makePost(id: "2", content: "x", tags: ["android"]),
        ]
        let hits = TimelineBufferFilter.filter(posts, query: "swift")
        XCTAssertEqual(hits.map(\.id), ["1"])
    }

    func testHashtagPrefixRestrictsToTags() {
        let posts = [
            makePost(id: "1", content: "I love swift programming", tags: []),
            makePost(id: "2", content: "x", tags: ["swift"]),
        ]
        let hits = TimelineBufferFilter.filter(posts, query: "#swift")
        XCTAssertEqual(hits.map(\.id), ["2"])
    }

    func testAtPrefixRestrictsToAuthor() {
        let posts = [
            makePost(id: "1", authorUsername: "@frank", content: "frank is a name"),
            makePost(id: "2", authorUsername: "@jane", content: "frank is mentioned here"),
        ]
        let hits = TimelineBufferFilter.filter(posts, query: "@frank")
        XCTAssertEqual(hits.map(\.id), ["1"])
    }

    func testMultiTokenAllMustMatch() {
        let posts = [
            makePost(id: "1", content: "Hello world from Swift"),
            makePost(id: "2", content: "Hello Java"),
            makePost(id: "3", content: "Swift is fun"),
        ]
        let hits = TimelineBufferFilter.filter(posts, query: "hello swift")
        XCTAssertEqual(hits.map(\.id), ["1"])
    }

    func testNoMatchReturnsEmpty() {
        let posts = [makePost(id: "1", content: "Hello")]
        XCTAssertEqual(TimelineBufferFilter.filter(posts, query: "xyz").count, 0)
    }

    func testNoBufferGracefulEmpty() {
        XCTAssertEqual(TimelineBufferFilter.filter([], query: "anything").count, 0)
    }

    // MARK: - Helpers

    private func makePost(
        id: String,
        authorName: String = "Test Author",
        authorUsername: String = "@test",
        content: String,
        tags: [String] = []
    ) -> Post {
        Post(
            id: id,
            content: content,
            authorName: authorName,
            authorUsername: authorUsername,
            authorId: "author-\(id)",
            authorProfilePictureURL: "",
            createdAt: Date(),
            platform: .mastodon,
            originalURL: "",
            attachments: [],
            mentions: [],
            tags: tags
        )
    }
}

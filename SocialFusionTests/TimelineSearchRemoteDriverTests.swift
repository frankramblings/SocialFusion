import XCTest
@testable import SocialFusion

final class TimelineSearchRemoteDriverTests: XCTestCase {

    func testIssuesQueryToProviderAndReturnsResults() async throws {
        let stubPosts = [
            makePost(id: "m1", platform: .mastodon, content: "Server hit M"),
            makePost(id: "b1", platform: .bluesky, content: "Server hit B"),
        ]
        let provider = StubSearchProvider(posts: stubPosts)
        let driver = TimelineSearchRemoteDriver(provider: provider)

        let hits = try await driver.search(text: "hello", context: .unified)

        XCTAssertEqual(hits.map(\.post.id).sorted(), ["b1", "m1"])
        XCTAssertEqual(provider.receivedQueries.first?.text, "hello")
    }

    func testEmptyQueryReturnsEmptyWithoutCallingProvider() async throws {
        let provider = StubSearchProvider(posts: [])
        let driver = TimelineSearchRemoteDriver(provider: provider)

        let hits = try await driver.search(text: "   ", context: .unified)

        XCTAssertEqual(hits.count, 0)
        XCTAssertTrue(provider.receivedQueries.isEmpty)
    }

    func testPinnedContextRestrictsNetworkSelection() async throws {
        let provider = StubSearchProvider(posts: [])
        let driver = TimelineSearchRemoteDriver(provider: provider)
        let pinned = TimelineSearchContext(
            scope: .pinned(platforms: [.mastodon], label: "Tech List")
        )

        _ = try await driver.search(text: "swift", context: pinned)

        XCTAssertEqual(provider.receivedQueries.first?.networkSelection, .mastodon)
    }

    func testProviderErrorPropagates() async {
        let provider = StubSearchProvider(posts: [], error: TestError.fail)
        let driver = TimelineSearchRemoteDriver(provider: provider)
        do {
            _ = try await driver.search(text: "x", context: .unified)
            XCTFail("expected throw")
        } catch {
            // ok
        }
    }

    // MARK: - Helpers

    enum TestError: Error { case fail }

    private func makePost(id: String, platform: SocialPlatform, content: String) -> Post {
        Post(
            id: id,
            content: content,
            authorName: "T",
            authorUsername: "@t",
            authorId: "a",
            authorProfilePictureURL: "",
            createdAt: Date(),
            platform: platform,
            originalURL: "",
            attachments: [],
            mentions: [],
            tags: []
        )
    }

    private final class StubSearchProvider: SearchProviding {
        var receivedQueries: [SearchQuery] = []
        let posts: [Post]
        let error: Error?

        init(posts: [Post], error: Error? = nil) {
            self.posts = posts
            self.error = error
        }

        var capabilities: SearchCapabilities { SearchCapabilities() }
        var supportsSortTopLatest: Bool { true }
        var providerId: String { "stub" }

        func searchPosts(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
            receivedQueries.append(query)
            if let error { throw error }
            return SearchPage(items: posts.map { SearchResultItem.post($0) })
        }
        func searchUsersTypeahead(text: String, page: SearchPageToken?) async throws -> SearchPage {
            SearchPage(items: [])
        }
        func searchUsers(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
            SearchPage(items: [])
        }
        func searchTags(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
            SearchPage(items: [])
        }
        func resolveDirectOpen(input: String) async throws -> DirectOpenTarget? { nil }
    }
}

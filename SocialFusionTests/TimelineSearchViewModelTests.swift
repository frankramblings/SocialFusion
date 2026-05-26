import XCTest
@testable import SocialFusion

@MainActor
final class TimelineSearchViewModelTests: XCTestCase {

    func testEmptyQueryProducesIdlePhaseAndNoSections() async {
        let vm = makeVM(buffer: [makePost(id: "1", content: "Hi")], remote: [])
        vm.setQuery("")
        await vm.awaitSettled()
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertTrue(vm.sections.isEmpty)
    }

    func testClientSectionAppearsAfterDebounce() async {
        let vm = makeVM(
            buffer: [
                makePost(id: "1", content: "Hello world"),
                makePost(id: "2", content: "Other"),
            ],
            remote: []
        )
        vm.setQuery("hello")
        await vm.awaitSettled()

        let clientHits = vm.sections.first(where: { if case .client = $0 { return true } else { return false } })?.hits
        XCTAssertEqual(clientHits?.map(\.post.id), ["1"])
    }

    func testServerSectionAppearsGroupedByPlatform() async {
        let m = makePost(id: "m1", platform: .mastodon, content: "Server M")
        let b = makePost(id: "b1", platform: .bluesky, content: "Server B")
        let vm = makeVM(buffer: [], remote: [m, b])

        vm.setQuery("server")
        await vm.awaitSettled()

        let masto = vm.sections.first(where: {
            if case .remote(let p, _) = $0, p == .mastodon { return true } else { return false }
        })?.hits.map(\.post.id)
        let bsky = vm.sections.first(where: {
            if case .remote(let p, _) = $0, p == .bluesky { return true } else { return false }
        })?.hits.map(\.post.id)
        XCTAssertEqual(masto, ["m1"])
        XCTAssertEqual(bsky, ["b1"])
    }

    func testStaleRemoteResponseDiscarded() async {
        // Stub only responds to "foo" with the "stale" post; "bar" gets empty.
        // We let "foo"'s remote actually launch and reach its sleep, then
        // replace with "bar". If the generation check works, "foo"'s late
        // response is discarded and "stale" never appears.
        let provider = SlowStubProvider(
            delay: 0.2,
            posts: [makePost(id: "stale", content: "foo")],
            respondsTo: "foo"
        )
        let vm = TimelineSearchViewModel(
            bufferProvider: { [] },
            remoteDriver: TimelineSearchRemoteDriver(provider: provider),
            context: .unified,
            debounceMs: 0
        )
        vm.setQuery("foo")
        // Let foo's debounce task + remoteTask actually launch and hit await.
        for _ in 0..<5 { await Task.yield() }
        vm.setQuery("bar")
        await vm.awaitSettled()
        let allRemoteIds = vm.sections.flatMap(\.hits).map(\.post.id)
        XCTAssertFalse(allRemoteIds.contains("stale"))
    }

    func testServerFailureLeavesClientResultsVisible() async {
        let provider = FailingStubProvider()
        let vm = TimelineSearchViewModel(
            bufferProvider: { [self.makePost(id: "1", content: "Hello")] },
            remoteDriver: TimelineSearchRemoteDriver(provider: provider),
            context: .unified,
            debounceMs: 0
        )
        vm.setQuery("hello")
        await vm.awaitSettled()
        XCTAssertEqual(vm.phase, .clientResultsOnlyFailed)
        let clientHits = vm.sections.first(where: { if case .client = $0 { return true } else { return false } })?.hits
        XCTAssertEqual(clientHits?.map(\.post.id), ["1"])
    }

    func testNoBufferLoadedGracefullyHandled() async {
        let vm = makeVM(buffer: [], remote: [makePost(id: "m1", platform: .mastodon, content: "x")])
        vm.setQuery("x")
        await vm.awaitSettled()
        XCTAssertFalse(vm.sections.contains(where: {
            if case .client = $0 { return true } else { return false }
        }))
        XCTAssertTrue(vm.sections.contains(where: {
            if case .remote = $0 { return true } else { return false }
        }))
    }

    // MARK: - Helpers

    private func makeVM(buffer: [Post], remote: [Post]) -> TimelineSearchViewModel {
        let provider = StaticStubProvider(posts: remote)
        return TimelineSearchViewModel(
            bufferProvider: { buffer },
            remoteDriver: TimelineSearchRemoteDriver(provider: provider),
            context: .unified,
            debounceMs: 0
        )
    }

    fileprivate func makePost(
        id: String,
        platform: SocialPlatform = .mastodon,
        content: String
    ) -> Post {
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

    private final class StaticStubProvider: SearchProviding {
        let posts: [Post]
        init(posts: [Post]) { self.posts = posts }
        var capabilities: SearchCapabilities { SearchCapabilities() }
        var supportsSortTopLatest: Bool { true }
        var providerId: String { "stub" }
        func searchPosts(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
            SearchPage(items: posts.map { .post($0) })
        }
        func searchUsersTypeahead(text: String, page: SearchPageToken?) async throws -> SearchPage { SearchPage(items: []) }
        func searchUsers(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage { SearchPage(items: []) }
        func searchTags(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage { SearchPage(items: []) }
        func resolveDirectOpen(input: String) async throws -> DirectOpenTarget? { nil }
    }

    /// Returns `posts` only when the incoming query text matches `respondsTo`;
    /// otherwise returns an empty page. Used to verify that a slow in-flight
    /// query's results don't leak after the user retypes.
    private final class SlowStubProvider: SearchProviding {
        let delay: TimeInterval
        let posts: [Post]
        let respondsTo: String
        init(delay: TimeInterval, posts: [Post], respondsTo: String = "foo") {
            self.delay = delay
            self.posts = posts
            self.respondsTo = respondsTo
        }
        var capabilities: SearchCapabilities { SearchCapabilities() }
        var supportsSortTopLatest: Bool { true }
        var providerId: String { "slow" }
        func searchPosts(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard query.text == respondsTo else { return SearchPage(items: []) }
            return SearchPage(items: posts.map { .post($0) })
        }
        func searchUsersTypeahead(text: String, page: SearchPageToken?) async throws -> SearchPage { SearchPage(items: []) }
        func searchUsers(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage { SearchPage(items: []) }
        func searchTags(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage { SearchPage(items: []) }
        func resolveDirectOpen(input: String) async throws -> DirectOpenTarget? { nil }
    }

    private final class FailingStubProvider: SearchProviding {
        enum E: Error { case fail }
        var capabilities: SearchCapabilities { SearchCapabilities() }
        var supportsSortTopLatest: Bool { true }
        var providerId: String { "fail" }
        func searchPosts(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage { throw E.fail }
        func searchUsersTypeahead(text: String, page: SearchPageToken?) async throws -> SearchPage { SearchPage(items: []) }
        func searchUsers(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage { SearchPage(items: []) }
        func searchTags(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage { SearchPage(items: []) }
        func resolveDirectOpen(input: String) async throws -> DirectOpenTarget? { nil }
    }
}

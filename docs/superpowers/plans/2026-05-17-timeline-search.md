# Timeline Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship timeline-wide search — a two-layer experience that lets users find a post they remember scrolling past *and* find a post they never saw. Layer 1 is an instant client-side filter through the loaded `UnifiedTimelineController` buffer (<100ms after typing stops). Layer 2 is a parallel server-side query against the per-network search APIs that streams in below the client-side hits (<500ms). Search is a peer of the timeline, not a separate destination: a single search bar revealed by swipe-down on the timeline (Mail/Messages convention), two clearly labeled result sections, full keyboard-driven navigation. This is distinct from the existing in-conversation search and from the existing global `SearchView` (which is a discovery surface, not a "search what I'm looking at" surface).

**Architecture:** A new `TimelineSearchViewModel` (`@MainActor`, `ObservableObject`) owns the layered state. It holds a weak reference to the active `UnifiedTimelineController` so it can read its `posts` buffer in O(1) and run an in-memory filter. The filter is a single-pass scan of the buffer — content (case-insensitive substring), author display name / handle, and tags — that materializes a `[TimelineSearchHit]`. The server-side layer reuses the existing `SearchProviding` infrastructure (`UnifiedSearchProvider`, `MastodonSearchProvider`, `BlueskySearchProvider`) via a thin `TimelineSearchRemoteDriver` that calls `searchPosts(query:page:)` and exposes results as a Combine publisher. Typing is debounced ~250ms; the client-side pass fires immediately at the end of the debounce, and the server-side fan-out fires in parallel. Pinned-timeline scoping is honored by a `TimelineSearchContext` value passed to the VM at presentation time (carries the source platforms and, when applicable, the pin's account/feed scope). The search overlay is `TimelineSearchView` — a `safeAreaInset(.top)` chrome plus a `LazyVStack` of sections. The reveal is a swipe-down gesture on the timeline header plus a redundant search button for accessibility.

**Tech Stack:** Swift 5+, SwiftUI, Combine, XCTest. iOS 17+ floor. Reuses: `UnifiedTimelineController`, existing `SearchProviding` providers, `PlatformLogoBadge`, `PostCardView`, and standard `@MainActor` / `ObservableObject` patterns used elsewhere in the codebase. No new third-party dependencies.

**Spec reference:** `docs/superpowers/specs/2026-05-17-socialfusion-v1-vision-design.md` — see the Gap Map row "**No timeline / feed search**" (line 236) and the "Matches must-build" row "**Timeline search**" (line 173). Performance budgets quoted from the Acceptance Criteria, line 263: "Timeline search client-side filter < 100ms after typing stops."

**File map (creates/modifies):**

- Create: `SocialFusion/Models/TimelineSearchModels.swift`
- Create: `SocialFusion/Utilities/TimelineBufferFilter.swift`
- Create: `SocialFusion/Services/TimelineSearchRemoteDriver.swift`
- Create: `SocialFusion/ViewModels/TimelineSearchViewModel.swift`
- Create: `SocialFusion/Views/TimelineSearchView.swift`
- Create: `SocialFusion/Views/Components/TimelineSearchSectionHeader.swift`
- Create: `SocialFusionTests/TimelineBufferFilterTests.swift`
- Create: `SocialFusionTests/TimelineSearchRemoteDriverTests.swift`
- Create: `SocialFusionTests/TimelineSearchViewModelTests.swift`
- Create: `SocialFusionTests/TimelineSearchPerformanceTests.swift`
- Modify: `SocialFusion/Views/ConsolidatedTimelineView.swift` (gesture + overlay presentation + button)
- Modify: `SocialFusion/Controllers/UnifiedTimelineController.swift` (expose `bufferSnapshot()` if not already public-readable)

**Implementer assumptions to verify before each task:**

1. `Post` exposes `id`, `content`, `authorName`, `authorUsername`, `authorId`, `createdAt`, `platform`, `tags: [String]` as `public let` (verified in `SocialFusion/Models/Post.swift:244-256`).
2. `UnifiedTimelineController` is `@MainActor`, `ObservableObject`, and exposes `@Published private(set) var posts: [Post]` (verified in `SocialFusion/Controllers/UnifiedTimelineController.swift:7-13`). The plan reads from this property; `private(set)` is sufficient because reads from inside the package are allowed — if the controller's `posts` is not readable from a different module/target, Task 2 falls back to a `bufferSnapshot()` accessor (Task 1 covers this).
3. `SearchProviding.searchPosts(query:page:)` exists with signature `func searchPosts(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage` (verified in `SocialFusion/Services/Search/SearchProviding.swift`).
4. `SearchQuery(text:scope:networkSelection:sort:timeWindow:)` and `SearchPage` / `SearchResultItem.post(Post)` exist (verified in `SocialFusion/Models/SearchModels.swift`).
5. `PlatformLogoBadge(platform:size:)` renders the shape-coded network indicator (`SocialFusion/Views/Components/PlatformLogoBadge.swift:5`).
6. `PostCardView` accepts a `Post` and renders the standard timeline card. The exact init signature should be confirmed when wiring Task 9; the plan calls `PostCardView(post: post)` and lists the exact init line to inspect.
7. The test target is `SocialFusionTests`. Tests subclass `XCTestCase`. Build command for the repo is `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`; test command is the same with `test` instead of `build`.
8. `SocialPlatform` is `String`-backed with cases `.mastodon` and `.bluesky` (per CLAUDE.md).

---

## Task 1: Expose a stable timeline buffer snapshot

**Files:**
- Modify: `SocialFusion/Controllers/UnifiedTimelineController.swift`

`TimelineSearchViewModel` needs to read the loaded posts without triggering AttributeGraph cycles. The controller already publishes `posts` as `@Published private(set) var posts: [Post]`. Add a non-publishing `bufferSnapshot()` accessor so the search VM can take an O(1) copy on demand without observing the publisher (observation would re-run the filter every time the timeline merges, which is not what we want — the filter should re-run on user input, not on background timeline updates).

- [ ] **Step 1: Read the controller to confirm `posts` shape**

```bash
grep -n "var posts" SocialFusion/Controllers/UnifiedTimelineController.swift
```
Expected: one line, around line 12, reading `@Published private(set) var posts: [Post] = []`.

- [ ] **Step 2: Add the snapshot accessor**

Open `SocialFusion/Controllers/UnifiedTimelineController.swift`. Immediately under the `@Published` declarations block (after the `restorationAnchor` line at ~line 24), add:

```swift
    // MARK: - Search Buffer Access

    /// A point-in-time copy of the currently-loaded timeline posts for
    /// timeline search to filter over. Reads from `posts` without subscribing
    /// to its publisher — callers should call this on demand (e.g. when the
    /// search query changes), not observe it.
    func bufferSnapshot() -> [Post] {
        posts
    }
```

- [ ] **Step 3: Verify it compiles**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add SocialFusion/Controllers/UnifiedTimelineController.swift
git commit -m "feat(search): add bufferSnapshot() accessor on UnifiedTimelineController"
```

---

## Task 2: Timeline search models

**Files:**
- Create: `SocialFusion/Models/TimelineSearchModels.swift`

Define the small value types that flow through the search VM: the hit, the section, the context that governs scoping, and the search phase.

- [ ] **Step 1: Implement the models**

Create `SocialFusion/Models/TimelineSearchModels.swift`:

```swift
import Foundation

// MARK: - TimelineSearchHit

/// A single matched post surfaced by timeline search.
public struct TimelineSearchHit: Identifiable, Hashable {
    public enum Source: Hashable {
        /// Matched in the loaded `UnifiedTimelineController` buffer.
        case clientBuffer
        /// Returned by a network search API.
        case remote(platform: SocialPlatform)
    }

    public let post: Post
    public let source: Source

    public var id: String {
        switch source {
        case .clientBuffer:
            return "client:\(post.id)"
        case .remote(let platform):
            return "remote:\(platform.rawValue):\(post.id)"
        }
    }

    public static func == (lhs: TimelineSearchHit, rhs: TimelineSearchHit) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - TimelineSearchContext

/// The scope in which a timeline search runs. Set at presentation time.
/// When the user invokes search from the unified home timeline, `scope` is
/// `.unified`. When invoked from inside a pinned timeline, `scope` carries
/// that pin's platforms (and, in v1.x, its account/feed filter).
public struct TimelineSearchContext: Equatable {
    public enum Scope: Equatable {
        /// Unified home timeline — both networks.
        case unified
        /// A pinned timeline scoped to specific platforms.
        case pinned(platforms: Set<SocialPlatform>, label: String)
    }

    public let scope: Scope

    public init(scope: Scope) {
        self.scope = scope
    }

    public var platforms: Set<SocialPlatform> {
        switch scope {
        case .unified:
            return Set(SocialPlatform.allCases)
        case .pinned(let platforms, _):
            return platforms
        }
    }

    public var displayLabel: String? {
        switch scope {
        case .unified: return nil
        case .pinned(_, let label): return label
        }
    }

    public static let unified = TimelineSearchContext(scope: .unified)
}

// MARK: - TimelineSearchPhase

/// Lifecycle of the layered search.
public enum TimelineSearchPhase: Equatable {
    case idle                     // empty query
    case debouncing               // query typed, debounce window not yet elapsed
    case filtering                // client-side scan running
    case clientResultsOnly        // client-side done, server-side in flight
    case complete                 // both sides done
    case clientResultsOnlyFailed  // server failed; client results still shown
}

// MARK: - TimelineSearchSection

/// A renderable section in the results list.
public enum TimelineSearchSection: Identifiable, Equatable {
    /// "Already in your timeline" — client buffer hits.
    case client(hits: [TimelineSearchHit])
    /// "From <Network>" — server hits for a single platform.
    case remote(platform: SocialPlatform, hits: [TimelineSearchHit])

    public var id: String {
        switch self {
        case .client: return "client"
        case .remote(let platform, _): return "remote-\(platform.rawValue)"
        }
    }

    public var hits: [TimelineSearchHit] {
        switch self {
        case .client(let hits): return hits
        case .remote(_, let hits): return hits
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add SocialFusion/Models/TimelineSearchModels.swift
git commit -m "feat(search): add timeline search models (hit, context, phase, section)"
```

---

## Task 3: Buffer filter utility (TDD)

**Files:**
- Create: `SocialFusion/Utilities/TimelineBufferFilter.swift`
- Test: `SocialFusionTests/TimelineBufferFilterTests.swift`

The client-side filter is pure: in-memory string matching over an array of posts. It must be fast enough to scan 500 posts in well under 100ms (the spec budget). Match rules:

- Tokenize the query on whitespace; every token must match somewhere in the post.
- Per-token, a match is: case-insensitive substring of `content`, or `authorName`, or `authorUsername`, or any element of `tags`.
- Special prefixes: `@handle` restricts to author handle/name; `#tag` restricts to tags. Otherwise the token can match anywhere.

- [ ] **Step 1: Write the failing tests**

Create `SocialFusionTests/TimelineBufferFilterTests.swift`:

```swift
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
            authorProfilePictureURL: "",
            createdAt: Date(),
            platform: .mastodon,
            originalURL: "",
            attachments: [],
            mentions: [],
            tags: tags,
            authorId: "author-\(id)"
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/TimelineBufferFilterTests`
Expected: FAIL — `TimelineBufferFilter` not defined.

- [ ] **Step 3: Implement the filter**

Create `SocialFusion/Utilities/TimelineBufferFilter.swift`:

```swift
import Foundation

/// Pure in-memory filter over an array of `Post`. Used by timeline search
/// for its client-side layer. Must complete a 500-post scan in <100ms
/// (see `TimelineSearchPerformanceTests`).
public enum TimelineBufferFilter {

    /// Returns posts that match the given query, preserving input order.
    public static func filter(_ posts: [Post], query: String) -> [Post] {
        let tokens = tokenize(query)
        guard !tokens.isEmpty else { return [] }

        return posts.filter { post in
            tokens.allSatisfy { token in matches(post: post, token: token) }
        }
    }

    // MARK: - Tokenization

    /// Parsed token with a hint of where it must match.
    private struct Token {
        let needle: String              // lowercased, stripped of any sigil
        let restriction: Restriction
    }

    private enum Restriction {
        case any        // content, author, or tags
        case authorOnly // @ prefix
        case tagOnly    // # prefix
    }

    private static func tokenize(_ raw: String) -> [Token] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap { rawPart -> Token? in
                var s = String(rawPart)
                guard !s.isEmpty else { return nil }
                if s.hasPrefix("@") {
                    s.removeFirst()
                    guard !s.isEmpty else { return nil }
                    return Token(needle: s.lowercased(), restriction: .authorOnly)
                }
                if s.hasPrefix("#") {
                    s.removeFirst()
                    guard !s.isEmpty else { return nil }
                    return Token(needle: s.lowercased(), restriction: .tagOnly)
                }
                return Token(needle: s.lowercased(), restriction: .any)
            }
    }

    // MARK: - Matching

    private static func matches(post: Post, token: Token) -> Bool {
        let needle = token.needle
        switch token.restriction {
        case .authorOnly:
            return post.authorName.lowercased().contains(needle)
                || post.authorUsername.lowercased().contains(needle)
        case .tagOnly:
            return post.tags.contains(where: { $0.lowercased().contains(needle) })
        case .any:
            return post.content.lowercased().contains(needle)
                || post.authorName.lowercased().contains(needle)
                || post.authorUsername.lowercased().contains(needle)
                || post.tags.contains(where: { $0.lowercased().contains(needle) })
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/TimelineBufferFilterTests`
Expected: PASS, all 9 tests green.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Utilities/TimelineBufferFilter.swift SocialFusionTests/TimelineBufferFilterTests.swift
git commit -m "feat(search): add TimelineBufferFilter with content/author/tag matching"
```

---

## Task 4: Buffer filter performance test

**Files:**
- Create: `SocialFusionTests/TimelineSearchPerformanceTests.swift`

The spec's performance budget — *"Timeline search client-side filter < 100ms after typing stops"* (line 263) — has to be enforced by a test, not by hope.

- [ ] **Step 1: Write the performance test**

Create `SocialFusionTests/TimelineSearchPerformanceTests.swift`:

```swift
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
        // Sanity: half the buffer carries the keyword.
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
                authorProfilePictureURL: "",
                createdAt: Date().addingTimeInterval(-Double(i) * 60),
                platform: i % 2 == 0 ? .mastodon : .bluesky,
                originalURL: "",
                attachments: [],
                mentions: [],
                tags: i % 3 == 0 ? ["swift", "ios"] : ["news"],
                authorId: "author-\(i % 50)"
            )
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/TimelineSearchPerformanceTests`
Expected: PASS. If `test500PostBufferFiltersInUnder100ms` fails, the filter needs optimization (likely candidates: pre-lowercase the fields once, or short-circuit on first miss).

- [ ] **Step 3: Commit**

```bash
git add SocialFusionTests/TimelineSearchPerformanceTests.swift
git commit -m "test(search): assert TimelineBufferFilter scans 500 posts in <100ms"
```

---

## Task 5: Remote search driver (TDD)

**Files:**
- Create: `SocialFusion/Services/TimelineSearchRemoteDriver.swift`
- Test: `SocialFusionTests/TimelineSearchRemoteDriverTests.swift`

A thin wrapper around `SearchProviding` that translates a `(query, TimelineSearchContext)` pair into a `SearchQuery` and emits `(platform, [Post])` results. Keeping it separated from the VM means we can test it against a stub provider in isolation, and we can substitute the unified provider for per-platform providers later without touching the VM.

- [ ] **Step 1: Write the failing tests**

Create `SocialFusionTests/TimelineSearchRemoteDriverTests.swift`:

```swift
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
            id: id, content: content,
            authorName: "T", authorUsername: "@t",
            authorProfilePictureURL: "",
            createdAt: Date(),
            platform: platform,
            originalURL: "",
            attachments: [], mentions: [], tags: [],
            authorId: "a"
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
            return SearchPage(items: posts.map { SearchResultItem.post($0) }, nextPage: nil)
        }
        func searchUsersTypeahead(text: String, page: SearchPageToken?) async throws -> SearchPage {
            SearchPage(items: [], nextPage: nil)
        }
        func searchUsers(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
            SearchPage(items: [], nextPage: nil)
        }
        func searchTags(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
            SearchPage(items: [], nextPage: nil)
        }
        func resolveDirectOpen(input: String) async throws -> DirectOpenTarget? { nil }
    }
}
```

> Note: `SearchPage`'s exact init may differ. If the test fails to compile, inspect `SocialFusion/Models/SearchModels.swift` for the `SearchPage` struct and adjust the helper accordingly. `SearchCapabilities()` init likewise — use the zero-arg init if available, otherwise the smallest fixture that compiles.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/TimelineSearchRemoteDriverTests`
Expected: FAIL — `TimelineSearchRemoteDriver` not defined.

- [ ] **Step 3: Implement the driver**

Create `SocialFusion/Services/TimelineSearchRemoteDriver.swift`:

```swift
import Foundation

/// Thin wrapper around `SearchProviding` that adapts the timeline-search
/// VM's needs (text + context) into a `SearchQuery` and unwraps the result
/// into `TimelineSearchHit` values keyed by their platform of origin.
public final class TimelineSearchRemoteDriver {

    private let provider: SearchProviding

    public init(provider: SearchProviding) {
        self.provider = provider
    }

    /// Runs a single search. Returns hits in the order the provider returned
    /// them; callers are expected to group by platform for presentation.
    /// An empty/whitespace-only `text` short-circuits with zero hits and no
    /// network call.
    public func search(
        text: String,
        context: TimelineSearchContext
    ) async throws -> [TimelineSearchHit] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let networkSelection = networkSelection(for: context)
        let query = SearchQuery(
            text: trimmed,
            scope: .posts,
            networkSelection: networkSelection,
            sort: .latest,
            timeWindow: nil
        )

        let page = try await provider.searchPosts(query: query, page: nil)
        return page.items.compactMap { item -> TimelineSearchHit? in
            guard case .post(let post) = item else { return nil }
            return TimelineSearchHit(post: post, source: .remote(platform: post.platform))
        }
    }

    private func networkSelection(for context: TimelineSearchContext) -> SearchNetworkSelection {
        let platforms = context.platforms
        if platforms == Set(SocialPlatform.allCases) {
            return .unified
        }
        if platforms == [.mastodon] {
            return .mastodon
        }
        if platforms == [.bluesky] {
            return .bluesky
        }
        return .unified
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/TimelineSearchRemoteDriverTests`
Expected: PASS, all 4 tests green.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Services/TimelineSearchRemoteDriver.swift SocialFusionTests/TimelineSearchRemoteDriverTests.swift
git commit -m "feat(search): add TimelineSearchRemoteDriver over SearchProviding"
```

---

## Task 6: TimelineSearchViewModel — debounce + layered state (TDD)

**Files:**
- Create: `SocialFusion/ViewModels/TimelineSearchViewModel.swift`
- Test: `SocialFusionTests/TimelineSearchViewModelTests.swift`

The VM glues the two layers together: debounce typing, fire the client-side filter immediately at the end of the debounce, fire the server-side query in parallel, and stream both into a `sections: [TimelineSearchSection]` published value the view consumes.

Key behaviors:
- `query` is the user-facing input. Setting it kicks debounce.
- After 250ms of inactivity, the client-side filter runs synchronously (it's fast; we measured it in Task 4).
- A `Task` is launched to run the remote driver in parallel.
- A monotonic generation counter discards stale responses if the user keeps typing.

- [ ] **Step 1: Write the failing tests**

Create `SocialFusionTests/TimelineSearchViewModelTests.swift`:

```swift
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
        // Issue query "foo", then immediately retype "bar" before remote returns.
        let provider = SlowStubProvider(delay: 0.2, posts: [makePost(id: "stale", content: "foo")])
        let vm = TimelineSearchViewModel(
            bufferProvider: { [] },
            remoteDriver: TimelineSearchRemoteDriver(provider: provider),
            context: .unified,
            debounceMs: 0
        )
        vm.setQuery("foo")
        // Don't await settle; immediately replace.
        vm.setQuery("bar")
        await vm.awaitSettled()
        // The stale "foo" response must not have leaked into "bar"'s sections.
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
        // The spec calls this out: search must work when nothing's loaded yet.
        let vm = makeVM(buffer: [], remote: [makePost(id: "m1", platform: .mastodon, content: "x")])
        vm.setQuery("x")
        await vm.awaitSettled()
        // No client section (no buffer), but the remote section is present.
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

    private func makePost(
        id: String,
        platform: SocialPlatform = .mastodon,
        content: String
    ) -> Post {
        Post(
            id: id, content: content,
            authorName: "T", authorUsername: "@t",
            authorProfilePictureURL: "",
            createdAt: Date(),
            platform: platform,
            originalURL: "",
            attachments: [], mentions: [], tags: [],
            authorId: "a"
        )
    }

    private final class StaticStubProvider: SearchProviding {
        let posts: [Post]
        init(posts: [Post]) { self.posts = posts }
        var capabilities: SearchCapabilities { SearchCapabilities() }
        var supportsSortTopLatest: Bool { true }
        var providerId: String { "stub" }
        func searchPosts(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
            SearchPage(items: posts.map { .post($0) }, nextPage: nil)
        }
        func searchUsersTypeahead(text: String, page: SearchPageToken?) async throws -> SearchPage { SearchPage(items: [], nextPage: nil) }
        func searchUsers(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage { SearchPage(items: [], nextPage: nil) }
        func searchTags(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage { SearchPage(items: [], nextPage: nil) }
        func resolveDirectOpen(input: String) async throws -> DirectOpenTarget? { nil }
    }

    private final class SlowStubProvider: SearchProviding {
        let delay: TimeInterval
        let posts: [Post]
        init(delay: TimeInterval, posts: [Post]) { self.delay = delay; self.posts = posts }
        var capabilities: SearchCapabilities { SearchCapabilities() }
        var supportsSortTopLatest: Bool { true }
        var providerId: String { "slow" }
        func searchPosts(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            return SearchPage(items: posts.map { .post($0) }, nextPage: nil)
        }
        func searchUsersTypeahead(text: String, page: SearchPageToken?) async throws -> SearchPage { SearchPage(items: [], nextPage: nil) }
        func searchUsers(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage { SearchPage(items: [], nextPage: nil) }
        func searchTags(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage { SearchPage(items: [], nextPage: nil) }
        func resolveDirectOpen(input: String) async throws -> DirectOpenTarget? { nil }
    }

    private final class FailingStubProvider: SearchProviding {
        enum E: Error { case fail }
        var capabilities: SearchCapabilities { SearchCapabilities() }
        var supportsSortTopLatest: Bool { true }
        var providerId: String { "fail" }
        func searchPosts(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage { throw E.fail }
        func searchUsersTypeahead(text: String, page: SearchPageToken?) async throws -> SearchPage { SearchPage(items: [], nextPage: nil) }
        func searchUsers(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage { SearchPage(items: [], nextPage: nil) }
        func searchTags(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage { SearchPage(items: [], nextPage: nil) }
        func resolveDirectOpen(input: String) async throws -> DirectOpenTarget? { nil }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/TimelineSearchViewModelTests`
Expected: FAIL — `TimelineSearchViewModel` not defined.

- [ ] **Step 3: Implement the view model**

Create `SocialFusion/ViewModels/TimelineSearchViewModel.swift`:

```swift
import Foundation
import Combine

/// Drives the two-layer timeline search experience.
///
/// Layer 1 (client): in-memory filter over a snapshot of the timeline buffer.
/// Layer 2 (remote): async fan-out to `SearchProviding` via the remote driver.
///
/// Both layers feed into `sections`, in this order:
/// 1. `.client(hits:)` — "Already in your timeline"
/// 2. `.remote(platform: .mastodon, hits:)` — "From Mastodon"
/// 3. `.remote(platform: .bluesky, hits:)` — "From Bluesky"
@MainActor
public final class TimelineSearchViewModel: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var sections: [TimelineSearchSection] = []
    @Published public private(set) var phase: TimelineSearchPhase = .idle
    @Published public private(set) var query: String = ""

    // MARK: - Dependencies

    private let bufferProvider: () -> [Post]
    private let remoteDriver: TimelineSearchRemoteDriver
    private let context: TimelineSearchContext
    private let debounceMs: Int

    // MARK: - In-Flight Work

    private var debounceTask: Task<Void, Never>?
    private var remoteTask: Task<Void, Never>?
    /// Monotonically increasing token to discard stale responses.
    private var generation: UInt64 = 0
    private var lastIssuedGeneration: UInt64 = 0

    // MARK: - Init

    public init(
        bufferProvider: @escaping () -> [Post],
        remoteDriver: TimelineSearchRemoteDriver,
        context: TimelineSearchContext,
        debounceMs: Int = 250
    ) {
        self.bufferProvider = bufferProvider
        self.remoteDriver = remoteDriver
        self.context = context
        self.debounceMs = debounceMs
    }

    // MARK: - Public API

    /// Update the query. Kicks debounce; eventually runs both layers.
    public func setQuery(_ newValue: String) {
        query = newValue
        debounceTask?.cancel()
        remoteTask?.cancel()

        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            sections = []
            phase = .idle
            return
        }

        phase = .debouncing
        generation &+= 1
        let gen = generation

        debounceTask = Task { [weak self] in
            guard let self else { return }
            if self.debounceMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(self.debounceMs) * 1_000_000)
            }
            if Task.isCancelled || gen != self.generation { return }
            await self.runLayered(trimmedQuery: trimmed, generation: gen)
        }
    }

    /// Test seam: wait until the current debounce + any in-flight remote task
    /// have settled. Not for production use.
    public func awaitSettled() async {
        // Wait out debounce + remote.
        if let debounce = debounceTask { _ = await debounce.value }
        if let remote = remoteTask { _ = await remote.value }
    }

    // MARK: - Internal

    private func runLayered(trimmedQuery: String, generation gen: UInt64) async {
        // Layer 1: client-side filter, synchronous on this actor.
        phase = .filtering
        let buffer = bufferProvider()
        let clientHits = TimelineBufferFilter.filter(buffer, query: trimmedQuery)
            .map { TimelineSearchHit(post: $0, source: .clientBuffer) }

        // Build initial sections (just client).
        var nextSections: [TimelineSearchSection] = []
        if !clientHits.isEmpty {
            nextSections.append(.client(hits: clientHits))
        }
        sections = nextSections
        phase = .clientResultsOnly
        lastIssuedGeneration = gen

        // Layer 2: kick remote.
        remoteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let remoteHits = try await self.remoteDriver.search(
                    text: trimmedQuery, context: self.context
                )
                if Task.isCancelled || gen != self.generation { return }
                await self.applyRemote(hits: remoteHits, generation: gen)
            } catch {
                if Task.isCancelled || gen != self.generation { return }
                await self.applyRemoteFailure(generation: gen)
            }
        }
    }

    private func applyRemote(hits: [TimelineSearchHit], generation gen: UInt64) {
        guard gen == generation else { return }
        var grouped: [SocialPlatform: [TimelineSearchHit]] = [:]
        for hit in hits {
            if case .remote(let platform) = hit.source {
                grouped[platform, default: []].append(hit)
            }
        }
        var next = sections.filter {
            if case .client = $0 { return true } else { return false }
        }
        // Preserve a deterministic platform ordering.
        for platform in [SocialPlatform.mastodon, .bluesky] {
            if let h = grouped[platform], !h.isEmpty {
                next.append(.remote(platform: platform, hits: h))
            }
        }
        sections = next
        phase = .complete
    }

    private func applyRemoteFailure(generation gen: UInt64) {
        guard gen == generation else { return }
        phase = .clientResultsOnlyFailed
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/TimelineSearchViewModelTests`
Expected: PASS, all 6 tests green.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/ViewModels/TimelineSearchViewModel.swift SocialFusionTests/TimelineSearchViewModelTests.swift
git commit -m "feat(search): add TimelineSearchViewModel with debounced two-layer search"
```

---

## Task 7: Section header component

**Files:**
- Create: `SocialFusion/Views/Components/TimelineSearchSectionHeader.swift`

Each result section gets a header. Client section: title "Already in your timeline" with a SF Symbol. Remote section: a per-network sub-header with `PlatformLogoBadge` and the network name. This is its own small file so it can be tested visually in Xcode previews without dragging the whole search overlay in.

- [ ] **Step 1: Implement the header component**

Create `SocialFusion/Views/Components/TimelineSearchSectionHeader.swift`:

```swift
import SwiftUI

struct TimelineSearchSectionHeader: View {

    enum Kind: Equatable {
        case client
        case remote(platform: SocialPlatform)
    }

    let kind: Kind
    let resultCount: Int

    var body: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 18, height: 18)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(resultCount)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("\(resultCount) results"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder private var icon: some View {
        switch kind {
        case .client:
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
        case .remote(let platform):
            PlatformLogoBadge(platform: platform, size: 18)
        }
    }

    private var title: String {
        switch kind {
        case .client:
            return "Already in your timeline"
        case .remote(let platform):
            switch platform {
            case .mastodon: return "From Mastodon"
            case .bluesky: return "From Bluesky"
            }
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        TimelineSearchSectionHeader(kind: .client, resultCount: 3)
        TimelineSearchSectionHeader(kind: .remote(platform: .mastodon), resultCount: 12)
        TimelineSearchSectionHeader(kind: .remote(platform: .bluesky), resultCount: 7)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add SocialFusion/Views/Components/TimelineSearchSectionHeader.swift
git commit -m "feat(search): add TimelineSearchSectionHeader with PlatformLogoBadge"
```

---

## Task 8: TimelineSearchView — the overlay

**Files:**
- Create: `SocialFusion/Views/TimelineSearchView.swift`

The actual UI surface. It owns the `TimelineSearchViewModel`, hosts a `TextField` plumbed to `setQuery`, and renders the sections list. Reveal/dismiss is driven by a binding from the parent (`ConsolidatedTimelineView`).

Inspect `PostCardView`'s init before wiring:

```bash
grep -n "struct PostCardView" -A 10 SocialFusion/Views/Components/PostCardView.swift
```

The plan calls it as `PostCardView(post: post)`. If that initializer is not exactly that shape, use whichever public init takes a `Post` and renders the standard card.

- [ ] **Step 1: Implement the view**

Create `SocialFusion/Views/TimelineSearchView.swift`:

```swift
import SwiftUI

struct TimelineSearchView: View {

    @StateObject private var viewModel: TimelineSearchViewModel
    @Binding private var isPresented: Bool
    @FocusState private var fieldFocused: Bool

    init(
        viewModel: @autoclosure @escaping () -> TimelineSearchViewModel,
        isPresented: Binding<Bool>
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        _isPresented = isPresented
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)

            Divider()

            content
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear { fieldFocused = true }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search this timeline and beyond", text: Binding(
                get: { viewModel.query },
                set: { viewModel.setQuery($0) }
            ))
            .textFieldStyle(.plain)
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            .focused($fieldFocused)
            .accessibilityIdentifier("TimelineSearchField")

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.setQuery("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }

            Button("Cancel") {
                viewModel.setQuery("")
                isPresented = false
            }
            .accessibilityLabel("Dismiss search")
        }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch viewModel.phase {
        case .idle:
            idleState
        case .debouncing, .filtering:
            // Show whatever sections are already there (may be empty during first run).
            resultsList
                .overlay(alignment: .top) {
                    if viewModel.sections.isEmpty {
                        ProgressView().padding(.top, 16)
                    }
                }
        case .clientResultsOnly:
            VStack(spacing: 0) {
                resultsList
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Searching Mastodon and Bluesky…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        case .complete:
            resultsList
                .overlay(alignment: .center) {
                    if viewModel.sections.isEmpty {
                        emptyResultsState
                    }
                }
        case .clientResultsOnlyFailed:
            VStack(spacing: 0) {
                resultsList
                Text("Couldn't reach the networks. Showing only what's loaded.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
    }

    private var idleState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Search posts in your timeline and across Mastodon and Bluesky.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyResultsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No matches")
                .font(.subheadline.weight(.semibold))
            Text("Try a different word or check spelling.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(viewModel.sections) { section in
                    Section(header: header(for: section)) {
                        ForEach(section.hits) { hit in
                            PostCardView(post: hit.post)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func header(for section: TimelineSearchSection) -> some View {
        switch section {
        case .client(let hits):
            return TimelineSearchSectionHeader(kind: .client, resultCount: hits.count)
        case .remote(let platform, let hits):
            return TimelineSearchSectionHeader(
                kind: .remote(platform: platform),
                resultCount: hits.count
            )
        }
    }
}
```

> Note: `PostCardView(post:)` is assumed. If the call site fails to compile, run `grep -n "struct PostCardView" SocialFusion/Views/Components/PostCardView.swift` and adjust to the actual signature. Keep the substitution minimal — the goal here is "render the standard post card with our data."

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add SocialFusion/Views/TimelineSearchView.swift
git commit -m "feat(search): add TimelineSearchView overlay with two-section results"
```

---

## Task 9: Wire reveal gesture + button into ConsolidatedTimelineView

**Files:**
- Modify: `SocialFusion/Views/ConsolidatedTimelineView.swift`

The reveal pattern is Mail/Messages: swipe down at the top of the scroll surface or tap a search button. We add both. The swipe is implemented by detecting a downward drag while the scroll position is at the top; the button lives in the trailing toolbar slot.

The `TimelineSearchView` is presented as a `.sheet`. (We could use a `safeAreaInset(.top)` for a more inline reveal, but a sheet keeps the existing scroll position unchanged and avoids restructuring the timeline's complex layout — better for v1.0.)

- [ ] **Step 1: Add presentation state and the search VM factory**

In `SocialFusion/Views/ConsolidatedTimelineView.swift`, add to the `struct ConsolidatedTimelineView`'s state block (near the other `@State` declarations around line 130-150):

```swift
    @State private var showTimelineSearch = false
```

And add a helper, near the bottom of the struct (before `var body`):

```swift
    private func makeSearchViewModel() -> TimelineSearchViewModel {
        let driver = TimelineSearchRemoteDriver(
            provider: serviceManager.searchProvider()
        )
        // For v1.0 the only context is unified home; pin-scoped contexts arrive
        // with pinnable timelines.
        return TimelineSearchViewModel(
            bufferProvider: { [weak controller] in
                controller?.bufferSnapshot() ?? []
            },
            remoteDriver: driver,
            context: .unified
        )
    }
```

> If `serviceManager.searchProvider()` does not yet exist as a one-call factory, use whatever the existing `SearchView` uses to construct its provider. Inspect `SocialFusion/Views/SearchView.swift` for the canonical wiring and mirror it here. The goal is "one `SearchProviding` instance representing all signed-in accounts."

- [ ] **Step 2: Add the toolbar button**

In the `toolbar { ... }` block in `var body`, add a trailing item:

```swift
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showTimelineSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search timeline")
                }
```

- [ ] **Step 3: Add the swipe-down reveal**

At the bottom of the chained modifiers on `mainContent`, attach a high-priority gesture that fires only when the user is at the top of the timeline. Add (after the existing `.toolbar`):

```swift
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        // Only reveal if the user pulled down meaningfully while near the top.
                        let isNearTop = controller.isNearTop
                        if isNearTop, value.translation.height > 60, abs(value.translation.width) < 40 {
                            showTimelineSearch = true
                        }
                    }
            )
```

- [ ] **Step 4: Present the sheet**

After the existing `.fullScreenCover(...)` modifier on `mainContent`, add:

```swift
            .sheet(isPresented: $showTimelineSearch) {
                TimelineSearchView(
                    viewModel: makeSearchViewModel(),
                    isPresented: $showTimelineSearch
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
```

- [ ] **Step 5: Verify it compiles**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add SocialFusion/Views/ConsolidatedTimelineView.swift
git commit -m "feat(search): wire timeline search overlay into ConsolidatedTimelineView"
```

---

## Task 10: Manual smoke test on simulator

**Files:** *(no file changes)*

Verify the UX matches the spec before TestFlight. This is checklist-only; no code.

- [ ] **Step 1: Launch the app on iPhone 17 Pro simulator (UDID `5F253C05-C35E-4B29-A0F0-B8F8BF75B89B`).**

```bash
xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

Then run from Xcode (⌘R) with the simulator booted.

- [ ] **Step 2: Walk the path**

1. Open the app, sign in to at least one Mastodon and one Bluesky account.
2. Let the unified timeline load ~50+ posts.
3. Tap the search button (top-right magnifying glass). Sheet opens with the field focused.
4. Type a word you can see in the first few posts on screen. Within ~250ms after stopping, the "Already in your timeline" section should appear with that post.
5. Wait. Within ~500ms total, "From Mastodon" and "From Bluesky" sections should appear below.
6. Clear the query with the X button. Sections clear; field stays focused.
7. Dismiss with Cancel.
8. Swipe down from the very top of the timeline. The search sheet should reveal.
9. Type a nonsense string. Confirm the empty state appears in the "complete" phase.
10. Toggle Airplane Mode on, repeat a search. Client section still works; banner says "Couldn't reach the networks."

- [ ] **Step 3: Check the console**

No new `AttributeGraph` warnings during steps 1-10. The timeline's underlying `posts` should not be re-published due to search (search uses a snapshot, not an observation).

- [ ] **Step 4: Capture the result**

If any step fails, file the failure and stop. Otherwise, mark this task complete.

> *(No commit — manual test only.)*

---

## Task 11: Optional polish — pinned-timeline scoping handoff

**Files:** *(documentation-only diff in this plan; concrete code lands with pinnable timelines)*

The infrastructure for pin-scoping is in place: `TimelineSearchContext.pinned(platforms:label:)` flows through the driver into `SearchNetworkSelection`. When the pinnable-timelines plan lands, its presenter will:

1. Compute the pin's platforms from its definition (a Mastodon list is `[.mastodon]`; a Bluesky feed is `[.bluesky]`; an account-group pin is the union of its accounts' platforms).
2. Construct `TimelineSearchContext(scope: .pinned(platforms: ..., label: pin.title))`.
3. Pass it to `TimelineSearchView` instead of `.unified`.

No code change is required in this plan for v1.0 unified-only behavior; the seam is ready.

- [ ] **Step 1: Add an inline reminder to the search VM**

This is a one-line doc edit. In `SocialFusion/ViewModels/TimelineSearchViewModel.swift`, just under `private let context: TimelineSearchContext`, append a doc comment:

```swift
    /// The search scope. Currently `.unified` from the home timeline;
    /// `.pinned(...)` is honored when invoked from a pinned-timeline screen
    /// (see the pinnable-timelines plan).
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add SocialFusion/ViewModels/TimelineSearchViewModel.swift
git commit -m "docs(search): note pin-scoped context handoff for pinnable timelines"
```

---

## Task 12: Full test sweep + acceptance verification

**Files:** *(no code changes — acceptance gate)*

- [ ] **Step 1: Run the full timeline-search test target slice**

```bash
xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SocialFusionTests/TimelineBufferFilterTests \
  -only-testing:SocialFusionTests/TimelineSearchRemoteDriverTests \
  -only-testing:SocialFusionTests/TimelineSearchViewModelTests \
  -only-testing:SocialFusionTests/TimelineSearchPerformanceTests \
  -quiet
```

Expected: all green.

- [ ] **Step 2: Run the full test suite to catch regressions**

```bash
xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

Expected: all green, no new failures.

- [ ] **Step 3: Walk the acceptance criteria from the spec**

| Spec criterion (line in spec) | Evidence |
|---|---|
| Timeline search client-side filter < 100ms after typing stops (line 263) | `TimelineSearchPerformanceTests.test500PostBufferFiltersInUnder100ms` |
| Two-layer: client + server (lines 173, 236) | `TimelineSearchViewModelTests.testClientSectionAppearsAfterDebounce` + `testServerSectionAppearsGroupedByPlatform` |
| Server-side query budget <500ms (line 173) | Bounded by `SearchProviding` providers' existing perf characteristics; verified by manual smoke test step 5. No new code path here other than the driver, which adds ~0 overhead. |
| Pinned-timeline scoping (line 173) | `TimelineSearchRemoteDriverTests.testPinnedContextRestrictsNetworkSelection`; seam wired in Task 11. |
| Search bar revealed via swipe-down or button (Mail/Messages convention) | Task 9 implementation; verified in manual smoke test steps 3 and 8. |
| Two result sections with per-network sub-headers + PlatformLogoBadge | `TimelineSearchSectionHeader` (Task 7); used in Task 8. |
| Graceful behavior with no posts loaded | `TimelineSearchViewModelTests.testNoBufferLoadedGracefullyHandled` |
| No `AttributeGraph` warnings | Manual smoke test step 3. |

- [ ] **Step 4: Confirm and check off**

If every row above has passing evidence, the gate is met.

---

## Acceptance gate before promoting to TestFlight

After Tasks 1-12 are complete:

1. **Unit test suite passes:** `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet` returns 0.
2. **Performance gate met:** `TimelineSearchPerformanceTests.test500PostBufferFiltersInUnder100ms` passes on the iPhone 17 Pro simulator. Spec budget: **<100ms client-side** (spec line 263).
3. **Remote roundtrip budget met:** Manual smoke test step 5 — server-side sections appear within **<500ms** of typing stopping on a reasonable network (spec line 173). If the simulator's perceived latency is dominated by the providers themselves, file a follow-up against the providers rather than the search VM.
4. **Manual smoke test passes** on Frank's iPhone 17 Pro (UDID `00008150-000139C63480401C`) — all 10 steps in Task 10 succeed with at least one signed-in account on each network.
5. **No new `AttributeGraph` warnings** in the Xcode console during the manual smoke test.
6. **VoiceOver pass:** field reads as "Search timeline and beyond"; section headers announce result counts; clear-button announces "Clear search"; cancel announces "Dismiss search."

---

## What's intentionally out of scope for this plan

The following are deliberately deferred — track in sibling plans or v1.x:

- **Pinned-timeline scoping UI** — the model and driver support it; the actual handoff arrives with the pinnable-timelines plan. (The seam is in `TimelineSearchContext.pinned(...)`.)
- **Recent / pinned searches in the timeline-search overlay** — the global `SearchStore` already handles recents for discovery search; replicating it here is a small follow-up if user-research shows it's wanted.
- **Filter chips (date, has-media, network filter inside the overlay)** — v1.x.
- **Highlighting matched substrings inside `PostCardView`** — would require either a wrapper view or a `PostCardView` API change. Defer to a focused readability pass.
- **Server-side pagination ("Load more from Mastodon")** — v1.0 ships first-page results. Pagination is straightforward to bolt on via the existing `SearchPageToken` infrastructure when needed.
- **Top-of-timeline inline (non-sheet) reveal** — a `safeAreaInset(.top)` variant. The sheet ships in v1.0; the inline variant can land in v1.x once the timeline's layout tolerates it without scroll-position regressions.
- **Searching inside threads / quoted posts inside the buffer** — Today the filter scans the top-level post's content. Drilling into `parent` / `quotedPost` / `originalPost` chains is a known want but multiplies the filter cost; defer until measured.
- **Persistent search history** — v1.x. Recents would live alongside the existing `RecentSearchesStorage` used by `SearchStore`.
- **Search inside notifications / messages from this surface** — those have their own searches; cross-surface search is not in scope.

import XCTest
@testable import SocialFusion

@MainActor
final class WatchedConversationStoreTests: XCTestCase {
    private let key = "watched-conversations-test-key"

    override func setUp() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    func testWatchAndUnwatchToggle() {
        let store = WatchedConversationStore(userDefaults: .standard, defaultsKey: key)
        let conv = WatchedConversation(rootPostID: "m1", platform: .mastodon, fusedMomentID: "fused:m1+b1")
        XCTAssertFalse(store.isWatching(rootPostID: "m1"))
        store.watch(conv)
        XCTAssertTrue(store.isWatching(rootPostID: "m1"))
        store.unwatch(rootPostID: "m1")
        XCTAssertFalse(store.isWatching(rootPostID: "m1"))
    }

    func testPersistsAcrossInstances() {
        let s1 = WatchedConversationStore(userDefaults: .standard, defaultsKey: key)
        s1.watch(WatchedConversation(rootPostID: "m1", platform: .mastodon, fusedMomentID: nil))
        let s2 = WatchedConversationStore(userDefaults: .standard, defaultsKey: key)
        XCTAssertTrue(s2.isWatching(rootPostID: "m1"))
    }

    /// Summary (author + preview) must round-trip through UserDefaults so the
    /// human-readable Watching list row survives a cold launch.
    func testSummaryRoundTripsThroughPersistence() {
        let s1 = WatchedConversationStore(userDefaults: .standard, defaultsKey: key)
        let summary = WatchedConversation.Summary(
            authorName: "Brent Simmons",
            contentPreview: "Working on the next version of NetNewsWire."
        )
        s1.watch(WatchedConversation(
            rootPostID: "m1",
            platform: .mastodon,
            fusedMomentID: nil,
            summary: summary
        ))
        let s2 = WatchedConversationStore(userDefaults: .standard, defaultsKey: key)
        let reloaded = s2.allWatched().first
        XCTAssertEqual(reloaded?.summary?.authorName, "Brent Simmons")
        XCTAssertEqual(reloaded?.summary?.contentPreview,
                       "Working on the next version of NetNewsWire.")
    }

    /// Pre-summary watched records written by older builds must decode
    /// cleanly: `summary` is optional and the new field's absence in the
    /// JSON should yield `summary == nil`, not a decode failure.
    /// Regression guard for the new model field.
    /// The Summary type caps contentPreview at 140 chars at init time so a
    /// caller that forgets to truncate at the source can't blow out the
    /// stored size. Belt-and-suspenders; the call site in ActionBar does
    /// pass the full post.content.
    func testSummaryContentPreviewIsCappedAt140Chars() {
        let longContent = String(repeating: "x", count: 500)
        let summary = WatchedConversation.Summary(
            authorName: "Test Author",
            contentPreview: longContent
        )
        XCTAssertEqual(summary.contentPreview.count, 140,
                       "Summary should cap contentPreview at 140 characters at init.")
        XCTAssertTrue(summary.contentPreview.allSatisfy { $0 == "x" },
                      "The prefix should be the start of the input, not a different sample.")
    }

    /// Callers pass `post.content` raw — Mastodon ships HTML markup —
    /// so the model must strip tags + decode entities at the boundary
    /// or the Watching list row renders `<p>…</p>` and `&#8217;`
    /// literally. Belt-and-suspenders matching the strip applied in
    /// other post-body surfaces (RootPostHeader, ReplyRow, etc).
    func testSummaryContentPreviewStripsHTMLAndEntities() {
        let summary = WatchedConversation.Summary(
            authorName: "Test Author",
            contentPreview: "<p>I&#8217;m so excited to ship this</p>"
        )
        XCTAssertEqual(
            summary.contentPreview, "I\u{2019}m so excited to ship this",
            "Tags stripped, &#8217; decoded to the curl quote.")
    }

    /// Trim runs after the strip/decode passes so the cap counts
    /// visible content, not whitespace from the inner HTML structure.
    func testSummaryContentPreviewTrimsAfterStripping() {
        let summary = WatchedConversation.Summary(
            authorName: "Test Author",
            contentPreview: "<p>   hello world   </p>"
        )
        XCTAssertEqual(summary.contentPreview, "hello world")
    }

    /// Re-watching an already-watched conversation must upsert, not
    /// duplicate. The store is keyed by `rootPostID`, so a second
    /// `watch(_:)` call with the same id replaces — this is what lets
    /// the action bar refresh a stale summary (author, content preview)
    /// without needing a separate "update" API.
    func testWatchingExistingIDUpdatesSummaryInPlace() {
        let store = WatchedConversationStore(userDefaults: .standard, defaultsKey: key)
        let initial = WatchedConversation(
            rootPostID: "m1",
            platform: .mastodon,
            fusedMomentID: nil,
            summary: WatchedConversation.Summary(authorName: "Old", contentPreview: "old preview")
        )
        store.watch(initial)
        let updated = WatchedConversation(
            rootPostID: "m1",
            platform: .mastodon,
            fusedMomentID: nil,
            summary: WatchedConversation.Summary(authorName: "New", contentPreview: "new preview")
        )
        store.watch(updated)

        XCTAssertEqual(store.allWatched().count, 1, "Upsert must not duplicate.")
        XCTAssertEqual(store.allWatched().first?.summary?.authorName, "New")
        XCTAssertEqual(store.allWatched().first?.summary?.contentPreview, "new preview")
    }

    func testDecodesLegacyRecordWithoutSummary() throws {
        // Hand-rolled legacy JSON shaped like a record from before the
        // Summary field existed. UserDefaults stores the store's
        // `[String: WatchedConversation]` map, so the test wraps the
        // legacy fields in that same envelope.
        let legacy = """
        {
          "m1": {
            "id": "watch:m1",
            "rootPostID": "m1",
            "platform": "mastodon",
            "fusedMomentID": "fused:m1+b1",
            "watchedAt": -978307200
          }
        }
        """.data(using: .utf8)!
        UserDefaults.standard.set(legacy, forKey: key)

        let store = WatchedConversationStore(userDefaults: .standard, defaultsKey: key)
        let reloaded = store.allWatched().first
        XCTAssertNotNil(reloaded, "Legacy record should decode without error")
        XCTAssertEqual(reloaded?.rootPostID, "m1")
        XCTAssertNil(reloaded?.summary,
                     "Missing summary in JSON should decode as nil, not fail")
    }
}

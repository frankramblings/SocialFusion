import XCTest
@testable import SocialFusion

@MainActor
final class PinnedTimelineStoreTests: XCTestCase {
    private let key = "pinned-timelines-test-key"

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: key)
        try await super.tearDown()
    }

    private func makeStore() -> PinnedTimelineStore {
        PinnedTimelineStore(userDefaults: .standard, defaultsKey: key)
    }

    func testEmptyByDefault() {
        let store = makeStore()
        XCTAssertEqual(store.pins, [])
    }

    func testAddPinAppendsAndPersists() {
        let store = makeStore()
        let pin = PinnedTimeline(
            displayName: "Work",
            kind: .mastodonList(accountId: "acct-1", listId: "list-99")
        )
        store.add(pin)
        XCTAssertEqual(store.pins.count, 1)
        XCTAssertEqual(store.pins.first?.displayName, "Work")

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.pins.count, 1)
        XCTAssertEqual(reloaded.pins.first?.id, pin.id)
    }

    func testRenamePin() {
        let store = makeStore()
        let pin = PinnedTimeline(
            displayName: "Old",
            kind: .blueskyFeed(accountId: "acct-2", feedUri: "at://feed")
        )
        store.add(pin)
        store.rename(id: pin.id, to: "New")
        XCTAssertEqual(store.pins.first?.displayName, "New")
    }

    func testRenameTrimmedToEmptyIsNoOp() {
        let store = makeStore()
        let pin = PinnedTimeline(
            displayName: "Keep",
            kind: .blueskyFeed(accountId: "acct-2", feedUri: "at://feed")
        )
        store.add(pin)
        store.rename(id: pin.id, to: "   ")
        XCTAssertEqual(store.pins.first?.displayName, "Keep")
    }

    func testRemovePin() {
        let store = makeStore()
        let pin = PinnedTimeline(
            displayName: "Doomed",
            kind: .accountGroup(accountIds: ["a", "b"])
        )
        store.add(pin)
        store.remove(id: pin.id)
        XCTAssertEqual(store.pins, [])
    }

    func testReorderPins() {
        let store = makeStore()
        let a = PinnedTimeline(displayName: "A", kind: .accountGroup(accountIds: ["a"]))
        let b = PinnedTimeline(displayName: "B", kind: .accountGroup(accountIds: ["b"]))
        let c = PinnedTimeline(displayName: "C", kind: .accountGroup(accountIds: ["c"]))
        store.add(a)
        store.add(b)
        store.add(c)
        // Move C (offset 2) to before A (offset 0).
        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(store.pins.map(\.displayName), ["C", "A", "B"])
    }

    func testIsAlreadyPinnedDetectsExistingKind() {
        let store = makeStore()
        let pin = PinnedTimeline(
            displayName: "Tech",
            kind: .mastodonList(accountId: "acct-1", listId: "list-7")
        )
        store.add(pin)
        XCTAssertTrue(store.isPinned(kind: .mastodonList(accountId: "acct-1", listId: "list-7")))
        XCTAssertFalse(store.isPinned(kind: .mastodonList(accountId: "acct-1", listId: "list-8")))
    }

    func testLookupByID() {
        let store = makeStore()
        let pin = PinnedTimeline(
            displayName: "P",
            kind: .blueskyList(accountId: "acct-3", listUri: "at://list")
        )
        store.add(pin)
        XCTAssertEqual(store.pin(id: pin.id)?.displayName, "P")
        XCTAssertNil(store.pin(id: "nonexistent"))
    }

    func testAddIgnoresDuplicateKind() {
        let store = makeStore()
        let a = PinnedTimeline(
            displayName: "A",
            kind: .mastodonList(accountId: "acct-1", listId: "list-7")
        )
        let b = PinnedTimeline(
            displayName: "B-duplicate",
            kind: .mastodonList(accountId: "acct-1", listId: "list-7")
        )
        store.add(a)
        store.add(b)
        XCTAssertEqual(store.pins.count, 1, "Second pin with identical kind must be ignored.")
        XCTAssertEqual(store.pins.first?.displayName, "A")
    }
}

import XCTest
@testable import SocialFusion

@MainActor
final class PinnedTimelineEditorViewModelTests: XCTestCase {
    private let key = "pinned-editor-test-key"

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

    func testCreateAccountGroupPinRequiresNameAndAtLeastOneAccount() {
        let store = makeStore()
        let vm = PinnedTimelineEditorViewModel(store: store)
        XCTAssertFalse(vm.canCreateAccountGroup, "Empty name + empty accounts = invalid")
        vm.draftName = "Work"
        XCTAssertFalse(vm.canCreateAccountGroup, "Empty accounts = invalid")
        vm.draftSelectedAccountIDs = ["m1"]
        XCTAssertTrue(vm.canCreateAccountGroup)
    }

    func testWhitespaceOnlyNameIsInvalid() {
        let store = makeStore()
        let vm = PinnedTimelineEditorViewModel(store: store)
        vm.draftName = "   "
        vm.draftSelectedAccountIDs = ["m1"]
        XCTAssertFalse(vm.canCreateAccountGroup)
    }

    func testCreateAccountGroupPinAppendsToStoreAndClearsDraft() {
        let store = makeStore()
        let vm = PinnedTimelineEditorViewModel(store: store)
        vm.draftName = "Work"
        vm.draftSelectedAccountIDs = ["m1", "b1"]
        vm.createAccountGroupPin()
        XCTAssertEqual(store.pins.count, 1)
        guard case .accountGroup(let ids) = store.pins.first?.kind else {
            return XCTFail("Expected accountGroup kind")
        }
        XCTAssertEqual(ids.sorted(), ["b1", "m1"])
        XCTAssertEqual(vm.draftName, "")
        XCTAssertEqual(vm.draftSelectedAccountIDs, [])
    }

    func testCreateAccountGroupPinTrimsNameWhitespace() {
        let store = makeStore()
        let vm = PinnedTimelineEditorViewModel(store: store)
        vm.draftName = "  Mind the gap  "
        vm.draftSelectedAccountIDs = ["m1"]
        vm.createAccountGroupPin()
        XCTAssertEqual(store.pins.first?.displayName, "Mind the gap")
    }

    func testRenameTrimsWhitespaceAndIgnoresEmpty() {
        let store = makeStore()
        let pin = PinnedTimeline(
            displayName: "Original",
            kind: .accountGroup(accountIds: ["a"])
        )
        store.add(pin)
        let vm = PinnedTimelineEditorViewModel(store: store)
        vm.commitRename(id: pin.id, to: "  Renamed  ")
        XCTAssertEqual(store.pins.first?.displayName, "Renamed")
        vm.commitRename(id: pin.id, to: "   ")
        XCTAssertEqual(store.pins.first?.displayName, "Renamed", "Empty rename must be ignored.")
    }

    func testDeletePin() {
        let store = makeStore()
        let pin = PinnedTimeline(
            displayName: "Doomed",
            kind: .accountGroup(accountIds: ["a"])
        )
        store.add(pin)
        let vm = PinnedTimelineEditorViewModel(store: store)
        vm.delete(id: pin.id)
        XCTAssertEqual(store.pins, [])
    }

    func testToggleAccountSelection() {
        let store = makeStore()
        let vm = PinnedTimelineEditorViewModel(store: store)
        vm.toggleAccountSelection("a")
        XCTAssertEqual(vm.draftSelectedAccountIDs, ["a"])
        vm.toggleAccountSelection("a")
        XCTAssertEqual(vm.draftSelectedAccountIDs, [])
        vm.toggleAccountSelection("a")
        vm.toggleAccountSelection("b")
        XCTAssertEqual(vm.draftSelectedAccountIDs, ["a", "b"])
    }

    func testPinExistingReturnsAndAppends() {
        let store = makeStore()
        let vm = PinnedTimelineEditorViewModel(store: store)
        let pin = vm.pinExisting(
            kind: .mastodonList(accountId: "m1", listId: "list-7"),
            suggestedName: "Friends"
        )
        XCTAssertEqual(store.pins.count, 1)
        XCTAssertEqual(store.pins.first?.id, pin.id)
        XCTAssertEqual(pin.displayName, "Friends")
    }
}

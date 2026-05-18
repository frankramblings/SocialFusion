# Pinnable Timelines Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship v1.0 "medium depth" pinnable timelines — let users pin Mastodon Lists, Bluesky Lists, Bluesky Custom Feeds, and Account-Group pins (which can span both networks), surface them in the existing `TimelineFeedPickerPopover`, and edit them (create, rename, reorder, delete) from a dedicated editor sheet. No keyword/hashtag rules in v1.0 — that lives in the deferred v1.1 glass-box filter editor.

**Architecture:** Side-channel store pattern, identical in shape to `PostActionStore` / `FusedMomentStore`. A new `PinnedTimelineStore` (MainActor, ObservableObject, UserDefaults-backed) holds the ordered list of `PinnedTimeline` values. The store is constructed as a `@StateObject` in `SocialFusionApp` and injected into views via `@EnvironmentObject`. Pinned timelines integrate into the existing fetch pipeline by adding a new case to `TimelineFeedSelection` (`.pinned(id:)`) and a matching `TimelineFetchPlan` arm (`.pinned(pin:resolution:)`). The fetch resolves the pin's `kind` and `sourceRefs` into one or more existing per-account list/feed/home calls and merges the results — reusing `MastodonService.fetchListTimeline`, the new `BlueskyService.fetchListFeed`, `BlueskyService.fetchCustomFeed`, and `MastodonService.fetchHomeTimeline` / `BlueskyService.fetchHomeTimeline` for account-group pins. The picker popover gains a "Pinned" section above the existing root rows; long-press on a pinnable destination ("Pin this") is the primary capture surface; an "Edit Pins…" row at the bottom of the Pinned section opens `PinnedTimelinesEditorView`.

**Tech Stack:** Swift 5+, SwiftUI, Combine, XCTest. iOS 17+ floor. Reuses existing patterns: side-channel stores, `@MainActor` published state, `ObservableObject` view models, `TimelineFeedSelection` / `TimelineFetchPlan` enum-driven routing, `MastodonList` / `BlueskyFeedGenerator` / `SocialAccount` models, `NavBarPillDropdown` rendering inside `TimelineFeedPickerPopover`.

**Spec reference:** `docs/superpowers/specs/2026-05-17-socialfusion-v1-vision-design.md` — see "Principle 3 — You shape the lens" and the v1.0 Q3 answer "medium depth — existing lists/feeds + account groups. Full editor at v1.1."

**File map (creates/modifies):**

- Create: `SocialFusion/Models/PinnedTimeline.swift`
- Create: `SocialFusion/Stores/PinnedTimelineStore.swift`
- Create: `SocialFusion/ViewModels/PinnedTimelineEditorViewModel.swift`
- Create: `SocialFusion/Views/PinnedTimelinesEditorView.swift`
- Create: `SocialFusionTests/PinnedTimelineStoreTests.swift`
- Create: `SocialFusionTests/PinnedTimelineEditorViewModelTests.swift`
- Create: `SocialFusionTests/PinnedTimelineFetchPlanTests.swift`
- Modify: `SocialFusion/Models/TimelineFeedSelection.swift` (add `.pinned(id:)` selection + `.pinned` fetch plan arm)
- Modify: `SocialFusion/Services/SocialServiceManager.swift` (resolve `.pinned` selections, dispatch fetch fan-out)
- Modify: `SocialFusion/Services/BlueskyService.swift` (add `fetchListFeed`, `fetchUserLists`)
- Modify: `SocialFusion/Models/BlueskyModels.swift` (add `BlueskyList` model)
- Modify: `SocialFusion/ViewModels/TimelineFeedPickerViewModel.swift` (load Bluesky lists, capture-pin helper)
- Modify: `SocialFusion/Views/Components/TimelineFeedPickerPopover.swift` (Pinned section + long-press capture + Edit Pins row)
- Modify: `SocialFusion/Views/ConsolidatedTimelineView.swift` (feedTitle for pinned selections)
- Modify: `SocialFusion/SocialFusionApp.swift` (instantiate + inject store)
- Modify: `SocialFusion/Views/SettingsView.swift` (link to PinnedTimelinesEditorView)

**Implementer assumptions to verify before each task:**

1. `TimelineFeedSelection` is `Hashable, Codable` with cases `.unified`, `.allMastodon`, `.allBluesky`, `.mastodon(accountId:feed:)`, `.bluesky(accountId:feed:)` (verified in `SocialFusion/Models/TimelineFeedSelection.swift:65-71`).
2. `TimelineFetchPlan` is a non-Codable enum used by `SocialServiceManager.resolveTimelineFetchPlan()` (verified at `SocialFusion/Services/SocialServiceManager.swift:443`).
3. `SocialPlatform` is a `String`-backed enum with cases `.mastodon` and `.bluesky` (per `CLAUDE.md` memory).
4. `MastodonList` exists at `SocialFusion/Models/MastodonModels.swift:463` with `id: String, title: String, repliesPolicy: String`.
5. `BlueskyFeedGenerator` exists at `SocialFusion/Models/BlueskyModels.swift:50` with `uri: String, displayName: String, description: String?`.
6. There is **no** existing `BlueskyList` model or `fetchListFeed` API call — this plan adds both (Task 4).
7. `MastodonService.fetchListTimeline(for:listId:limit:maxId:)` returns `TimelineResult` (verified at `SocialFusion/Services/MastodonService.swift:1143`).
8. `BlueskyService.fetchCustomFeed(for:feedURI:limit:cursor:)` returns `TimelineResult` (verified at `SocialFusion/Services/BlueskyService.swift:666`).
9. `SocialAccount` has `id: String, platform: SocialPlatform, serverURL: URL?, getAccessToken() -> String?` / `getValidAccessToken() async throws -> String`.
10. `TimelineFeedPickerPopover` (file `SocialFusion/Views/Components/TimelineFeedPickerPopover.swift:3`) renders root via `NavBarPillDropdown(sections:width:)` and accepts `onSelect: (TimelineFeedSelection) -> Void`.
11. `SocialFusionApp` is the `@main` struct that already creates `@StateObject` services and injects them via `.environmentObject(_:)` (per `CLAUDE.md`).
12. The test target is `SocialFusionTests`. Tests subclass `XCTestCase`.

---

## Task 1: PinnedTimeline data model

**Files:**
- Create: `SocialFusion/Models/PinnedTimeline.swift`

A single `PinnedTimeline` struct with a `kind` enum is far easier to persist and reason about than a class hierarchy. Account-group pins span networks by storing account IDs (which already encode platform via the `SocialAccount.platform` lookup against `SocialServiceManager.accounts`).

- [ ] **Step 1: Implement the model**

Create `SocialFusion/Models/PinnedTimeline.swift`:

```swift
import Foundation

/// The kind of pinned timeline and its associated source references.
///
/// `sourceRefs` semantics by kind:
/// - `.mastodonList(accountId, listId)` — one Mastodon account + one list ID.
/// - `.blueskyList(accountId, listUri)` — one Bluesky account + one list AT-URI.
/// - `.blueskyFeed(accountId, feedUri)` — one Bluesky account + one feed AT-URI.
/// - `.accountGroup(accountIds)` — N account IDs across both networks; the
///   pin's timeline is the merged home timeline of those accounts only.
public enum PinnedTimelineKind: Hashable, Codable {
    case mastodonList(accountId: String, listId: String)
    case blueskyList(accountId: String, listUri: String)
    case blueskyFeed(accountId: String, feedUri: String)
    case accountGroup(accountIds: [String])

    /// Stable storage key for cache / pagination keying.
    public var storageKey: String {
        switch self {
        case .mastodonList(let acct, let id):
            return "mastodonList:\(acct):\(id)"
        case .blueskyList(let acct, let uri):
            return "blueskyList:\(acct):\(uri)"
        case .blueskyFeed(let acct, let uri):
            return "blueskyFeed:\(acct):\(uri)"
        case .accountGroup(let ids):
            return "accountGroup:\(ids.sorted().joined(separator: ","))"
        }
    }
}

/// A user-pinned timeline. Persists in `PinnedTimelineStore`.
public struct PinnedTimeline: Identifiable, Hashable, Codable {
    /// Stable UUID assigned at creation. Used as the persistence key and
    /// referenced by `TimelineFeedSelection.pinned(id:)`.
    public let id: String

    /// User-visible name. Defaults to the underlying list/feed/group label
    /// at creation time; editable via `PinnedTimelinesEditorView`.
    public var displayName: String

    public let kind: PinnedTimelineKind

    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        displayName: String,
        kind: PinnedTimelineKind,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add SocialFusion/Models/PinnedTimeline.swift
git commit -m "feat(pins): add PinnedTimeline model with kind enum"
```

---

## Task 2: Extend TimelineFeedSelection with .pinned

**Files:**
- Modify: `SocialFusion/Models/TimelineFeedSelection.swift`

The selection enum drives every routing decision the timeline makes. Adding a single `.pinned(id:)` case keeps callers minimal — they don't need to know what the pin resolves to, only that "this selection is a pin."

- [ ] **Step 1: Add the case**

Open `SocialFusion/Models/TimelineFeedSelection.swift`. After the existing `.bluesky(accountId:feed:)` case (currently line 70), add `.pinned`:

```swift
enum TimelineFeedSelection: Hashable, Codable {
    case unified
    case allMastodon
    case allBluesky
    case mastodon(accountId: String, feed: MastodonTimelineFeed)
    case bluesky(accountId: String, feed: BlueskyTimelineFeed)
    case pinned(id: String)
}
```

And add a matching `.pinned` arm to `TimelineFetchPlan`. The plan needs the *resolved* pin (kind + the actual `SocialAccount` objects) so downstream fetch code never re-walks the store:

```swift
enum TimelineFetchPlan {
    case unified(accounts: [SocialAccount])
    case allMastodon(accounts: [SocialAccount])
    case allBluesky(accounts: [SocialAccount])
    case mastodon(account: SocialAccount, feed: MastodonTimelineFeed)
    case bluesky(account: SocialAccount, feed: BlueskyTimelineFeed)
    case pinned(pin: PinnedTimeline, resolution: PinnedTimelineResolution)
}

/// The runtime-resolved sources a pinned timeline expands into.
enum PinnedTimelineResolution {
    case mastodonList(account: SocialAccount, listId: String)
    case blueskyList(account: SocialAccount, listUri: String)
    case blueskyFeed(account: SocialAccount, feedUri: String)
    case accountGroup(accounts: [SocialAccount])
}
```

- [ ] **Step 2: Verify the build**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

Expected: BUILD SUCCEEDED. The new enum cases are additive; no existing call site needs updating yet because the compiler-exhaustive switches in `SocialServiceManager.resolveTimelineFetchPlan()` and `paginationTokenKey(for:selection:)` will be extended in Task 5.

> If the build fails because a `switch` over `TimelineFeedSelection` somewhere is non-exhaustive, that means an existing switch is missing a `default`. Add `case .pinned: fatalError("unreachable until Task 5")` to those switches as a temporary guard. Task 5 deletes the fatalErrors.

- [ ] **Step 3: Commit**

```bash
git add SocialFusion/Models/TimelineFeedSelection.swift
git commit -m "feat(pins): add .pinned selection + fetch plan arm with resolution"
```

---

## Task 3: PinnedTimelineStore with persistence

**Files:**
- Create: `SocialFusion/Stores/PinnedTimelineStore.swift`
- Create: `SocialFusionTests/PinnedTimelineStoreTests.swift`

UserDefaults-backed (v1.0 — iCloud KVS is deferred). MainActor isolated, ObservableObject, follows the `EchoPolicyStore` / `WatchedConversationStore` shape established in the Fuse plan.

- [ ] **Step 1: Write the failing tests**

Create `SocialFusionTests/PinnedTimelineStoreTests.swift`:

```swift
import XCTest
@testable import SocialFusion

@MainActor
final class PinnedTimelineStoreTests: XCTestCase {
    private let key = "pinned-timelines-test-key"

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: key)
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/PinnedTimelineStoreTests`

Expected: FAIL — `PinnedTimelineStore` not defined.

- [ ] **Step 3: Implement the store**

Create `SocialFusion/Stores/PinnedTimelineStore.swift`:

```swift
import Combine
import Foundation
import SwiftUI

/// Side-channel store of user-pinned timelines.
///
/// MainActor-isolated, ObservableObject, UserDefaults-backed. Follows the
/// pattern established by `EchoPolicyStore` / `WatchedConversationStore`.
/// iCloud KVS sync is intentionally deferred to v1.1 along with the full
/// glass-box filter editor.
@MainActor
public final class PinnedTimelineStore: ObservableObject {
    @Published public private(set) var pins: [PinnedTimeline] = []

    private let userDefaults: UserDefaults
    private let defaultsKey: String

    public init(
        userDefaults: UserDefaults = .standard,
        defaultsKey: String = "pinned.timelines.v1"
    ) {
        self.userDefaults = userDefaults
        self.defaultsKey = defaultsKey
        load()
    }

    // MARK: - Public mutations

    /// Appends a pin. Ignored (no-op) if a pin with the same `kind` already
    /// exists — duplicate prevention is at the kind level, not the id level,
    /// so re-pinning the same list/feed/group from a different surface is
    /// idempotent.
    public func add(_ pin: PinnedTimeline) {
        guard !isPinned(kind: pin.kind) else { return }
        pins.append(pin)
        persist()
    }

    public func remove(id: String) {
        pins.removeAll { $0.id == id }
        persist()
    }

    public func rename(id: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = pins.firstIndex(where: { $0.id == id }) else { return }
        pins[idx].displayName = trimmed
        persist()
    }

    /// SwiftUI `.onMove` adapter.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        pins.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    // MARK: - Public lookups

    public func pin(id: String) -> PinnedTimeline? {
        pins.first { $0.id == id }
    }

    public func isPinned(kind: PinnedTimelineKind) -> Bool {
        pins.contains { $0.kind == kind }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = userDefaults.data(forKey: defaultsKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([PinnedTimeline].self, from: data) {
            pins = decoded
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(pins) {
            userDefaults.set(data, forKey: defaultsKey)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/PinnedTimelineStoreTests`

Expected: PASS, all 8 tests green.

- [ ] **Step 5: Inject the store at app root**

Open `SocialFusion/SocialFusionApp.swift`. Locate the `@main SocialFusionApp` struct's existing `@StateObject` declarations. Add:

```swift
@StateObject private var pinnedTimelineStore = PinnedTimelineStore()
```

And in the same `.environmentObject(_:)` chain where other stores are injected:

```swift
.environmentObject(pinnedTimelineStore)
```

- [ ] **Step 6: Commit**

```bash
git add SocialFusion/Stores/PinnedTimelineStore.swift SocialFusionTests/PinnedTimelineStoreTests.swift SocialFusion/SocialFusionApp.swift
git commit -m "feat(pins): PinnedTimelineStore (MainActor, UserDefaults-backed)"
```

---

## Task 4: Bluesky list support (model + APIs)

**Files:**
- Modify: `SocialFusion/Models/BlueskyModels.swift` (add `BlueskyList`)
- Modify: `SocialFusion/Services/BlueskyService.swift` (add `fetchUserLists`, `fetchListFeed`)

Mastodon lists already work end-to-end (`MastodonService.fetchLists`, `MastodonService.fetchListTimeline`, `BlueskyService.fetchCustomFeed`). What's missing is **Bluesky lists** — neither the model nor the fetcher exists. Bluesky has two relevant XRPC endpoints: `app.bsky.graph.getLists` (the lists *owned by* an actor) and `app.bsky.feed.getListFeed` (the timeline of posts from members of a list).

- [ ] **Step 1: Add the BlueskyList model**

Open `SocialFusion/Models/BlueskyModels.swift`. After the existing `BlueskyFeedGenerator` struct (around line 56), add:

```swift
public struct BlueskyList: Identifiable, Hashable, Codable {
    public let uri: String          // at://did:plc:.../app.bsky.graph.list/abc
    public let cid: String
    public let name: String
    public let purpose: String?     // "app.bsky.graph.defs#curatelist" or "modlist"
    public let description: String?

    public var id: String { uri }

    public enum CodingKeys: String, CodingKey {
        case uri, cid, name, purpose, description
    }
}

/// Envelope for `app.bsky.graph.getLists`.
public struct BlueskyListsResponse: Codable {
    public let lists: [BlueskyList]
    public let cursor: String?
}
```

- [ ] **Step 2: Add the Bluesky list-fetching service methods**

Open `SocialFusion/Services/BlueskyService.swift`. Locate `fetchCustomFeed(for:feedURI:limit:cursor:)` (line 666). Immediately after that method, add:

```swift
/// Fetch the lists owned by an actor. Used by the pinnable-timelines
/// editor to populate the user's available Bluesky lists.
public func fetchUserLists(for account: SocialAccount) async throws -> [BlueskyList] {
    let accessToken = try await account.getValidAccessToken()

    var serverURLString = account.serverURL?.absoluteString ?? "bsky.social"
    if serverURLString.hasPrefix("https://") {
        serverURLString = String(serverURLString.dropFirst(8))
    }

    var components = URLComponents(
        string: "https://\(serverURLString)/xrpc/app.bsky.graph.getLists")!
    components.queryItems = [
        URLQueryItem(name: "actor", value: account.username),
        URLQueryItem(name: "limit", value: "50"),
    ]

    var request = URLRequest(url: components.url!)
    request.httpMethod = "GET"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw NetworkError.apiError("Fetch Bluesky lists failed")
    }
    let decoded = try JSONDecoder().decode(BlueskyListsResponse.self, from: data)
    return decoded.lists
}

/// Fetch the merged timeline of posts from members of a Bluesky list.
/// Mirrors `fetchCustomFeed`'s shape — paginated, returns `TimelineResult`.
public func fetchListFeed(
    for account: SocialAccount,
    listURI: String,
    limit: Int = 40,
    cursor: String? = nil
) async throws -> TimelineResult {
    let accessToken = try await account.getValidAccessToken()

    var serverURLString = account.serverURL?.absoluteString ?? "bsky.social"
    if serverURLString.hasPrefix("https://") {
        serverURLString = String(serverURLString.dropFirst(8))
    }

    var components = URLComponents(
        string: "https://\(serverURLString)/xrpc/app.bsky.feed.getListFeed")!
    var queryItems = [
        URLQueryItem(name: "list", value: listURI),
        URLQueryItem(name: "limit", value: String(limit)),
    ]
    if let cursor = cursor {
        queryItems.append(URLQueryItem(name: "cursor", value: cursor))
    }
    components.queryItems = queryItems

    var request = URLRequest(url: components.url!)
    request.httpMethod = "GET"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw NetworkError.apiError("Fetch Bluesky list feed failed")
    }
    return try await processFeedDataWithPagination(data, account: account)
}
```

> The call to `processFeedDataWithPagination(_:account:)` is the same private method `fetchCustomFeed` uses (verified at `SocialFusion/Services/BlueskyService.swift:699`). If its access level is `fileprivate` or `private`, leave it as-is — both new methods live in the same file. If it is `private` *and* the file uses extensions, ensure `fetchListFeed` is in the same extension scope.

- [ ] **Step 3: Verify the build**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Smoke test against a real account**

Boot the app on the simulator with Frank's Bluesky account signed in. In a temporary `#if DEBUG` block at the top of `ConsolidatedTimelineView.swift`'s `onAppear`, add:

```swift
#if DEBUG
Task {
    if let bsky = serviceManager.blueskyAccounts.first {
        do {
            let lists = try await serviceManager.blueskySvc.fetchUserLists(for: bsky)
            print("[Pins] Bluesky lists for \(bsky.username): \(lists.map(\.name))")
        } catch {
            print("[Pins] fetchUserLists error: \(error)")
        }
    }
}
#endif
```

Run on the simulator. Verify the console emits the list names — even an empty array is success (Frank may have no Bluesky lists yet). Remove the debug block before committing.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Models/BlueskyModels.swift SocialFusion/Services/BlueskyService.swift
git commit -m "feat(pins): add BlueskyList model + fetchUserLists/fetchListFeed APIs"
```

---

## Task 5: Resolve .pinned selections in SocialServiceManager

**Files:**
- Modify: `SocialFusion/Services/SocialServiceManager.swift`

The fetch pipeline routes through `resolveTimelineFetchPlan()`. Add a `.pinned` arm that walks the `PinnedTimelineStore`, validates the referenced accounts still exist, and builds the matching `PinnedTimelineResolution`.

- [ ] **Step 1: Hold a weak reference to the store**

`SocialServiceManager` is constructed before the view tree, but the store is owned by `SocialFusionApp` as a `@StateObject`. Inject the store after construction via a setter — this matches how other stores get wired into the manager today.

Open `SocialFusion/Services/SocialServiceManager.swift`. Near the top of the class, alongside the other `private weak var` or `private let` store references, add:

```swift
public weak var pinnedTimelineStore: PinnedTimelineStore?
```

(`weak` because the store lives on `SocialFusionApp`; the manager must not retain it.)

In `SocialFusionApp.swift`, where the manager is constructed, add a line that assigns the store after both objects exist:

```swift
.onAppear {
    serviceManager.pinnedTimelineStore = pinnedTimelineStore
}
```

Apply this `.onAppear` to the root view where both `@StateObject`s are in scope (typically the top-level `WindowGroup` content).

- [ ] **Step 2: Add the .pinned arm to resolveTimelineFetchPlan()**

In `SocialFusion/Services/SocialServiceManager.swift`, find `resolveTimelineFetchPlan()` (line 443). Add the new case at the end of the switch:

```swift
func resolveTimelineFetchPlan() -> TimelineFetchPlan? {
    let selection = currentTimelineFeedSelection
    switch selection {
    case .unified:
        return .unified(accounts: accounts)
    case .allMastodon:
        let mastodon = accounts.filter { $0.platform == .mastodon }
        return mastodon.isEmpty ? nil : .allMastodon(accounts: mastodon)
    case .allBluesky:
        let bluesky = accounts.filter { $0.platform == .bluesky }
        return bluesky.isEmpty ? nil : .allBluesky(accounts: bluesky)
    case .mastodon(let accountId, let feed):
        guard let account = accounts.first(where: { $0.id == accountId }) else { return nil }
        return .mastodon(account: account, feed: feed)
    case .bluesky(let accountId, let feed):
        guard let account = accounts.first(where: { $0.id == accountId }) else { return nil }
        return .bluesky(account: account, feed: feed)
    case .pinned(let id):
        guard let pin = pinnedTimelineStore?.pin(id: id) else { return nil }
        guard let resolution = resolvePin(pin) else { return nil }
        return .pinned(pin: pin, resolution: resolution)
    }
}

/// Resolves a `PinnedTimeline` against the current account list. Returns
/// nil if any required account has been removed since the pin was created.
private func resolvePin(_ pin: PinnedTimeline) -> PinnedTimelineResolution? {
    switch pin.kind {
    case .mastodonList(let accountId, let listId):
        guard let account = accounts.first(where: { $0.id == accountId && $0.platform == .mastodon })
        else { return nil }
        return .mastodonList(account: account, listId: listId)
    case .blueskyList(let accountId, let listUri):
        guard let account = accounts.first(where: { $0.id == accountId && $0.platform == .bluesky })
        else { return nil }
        return .blueskyList(account: account, listUri: listUri)
    case .blueskyFeed(let accountId, let feedUri):
        guard let account = accounts.first(where: { $0.id == accountId && $0.platform == .bluesky })
        else { return nil }
        return .blueskyFeed(account: account, feedUri: feedUri)
    case .accountGroup(let ids):
        let resolved = ids.compactMap { id in accounts.first(where: { $0.id == id }) }
        // Allow partial resolution as long as at least one account remains.
        return resolved.isEmpty ? nil : .accountGroup(accounts: resolved)
    }
}
```

- [ ] **Step 3: Extend the pagination-token keyer**

Find `paginationTokenKey(for:selection:)` (line 1866). Add the new case:

```swift
private func paginationTokenKey(for account: SocialAccount, selection: TimelineFeedSelection)
    -> String
{
    switch selection {
    case .unified, .allMastodon, .allBluesky:
        return account.id
    case .mastodon(_, let feed):
        return "\(account.id):\(feed.cacheKey)"
    case .bluesky(_, let feed):
        return "\(account.id):\(feed.cacheKey)"
    case .pinned(let id):
        return "\(account.id):pinned:\(id)"
    }
}
```

- [ ] **Step 4: Add the fetch dispatcher for .pinned plans**

Locate the timeline-fetch entry point that already switches on `TimelineFetchPlan` — it lives near `fetchMastodonTimeline(...)` / `fetchBlueskyTimeline(...)` (the file's mid-1800s line range). Search for `case .mastodon(let account, let feed)` inside a `switch` over a fetch plan to find the dispatch site.

Add the new arm:

```swift
case .pinned(let pin, let resolution):
    return try await fetchPinnedTimeline(pin: pin, resolution: resolution)
```

Then implement the dispatcher in the same file, near `fetchBlueskyTimeline(...)`:

```swift
private func fetchPinnedTimeline(
    pin: PinnedTimeline,
    resolution: PinnedTimelineResolution
) async throws -> TimelineResult {
    switch resolution {
    case .mastodonList(let account, let listId):
        return try await mastodonService.fetchListTimeline(
            for: account,
            listId: listId,
            maxId: nil
        )
    case .blueskyList(let account, let listUri):
        return try await blueskyService.fetchListFeed(
            for: account,
            listURI: listUri,
            cursor: nil
        )
    case .blueskyFeed(let account, let feedUri):
        return try await blueskyService.fetchCustomFeed(
            for: account,
            feedURI: feedUri,
            cursor: nil
        )
    case .accountGroup(let groupAccounts):
        return try await fetchAccountGroupTimeline(accounts: groupAccounts)
    }
}

/// Merges the home timelines of the supplied accounts into a single
/// time-ordered result. Each account is fetched in parallel; one-side
/// failures don't fail the whole pin.
private func fetchAccountGroupTimeline(accounts: [SocialAccount]) async throws -> TimelineResult {
    let results: [TimelineResult] = await withTaskGroup(of: TimelineResult?.self) { group in
        for account in accounts {
            group.addTask { [weak self] in
                guard let self else { return nil }
                do {
                    switch account.platform {
                    case .mastodon:
                        return try await self.mastodonService.fetchHomeTimeline(
                            for: account,
                            maxId: nil
                        )
                    case .bluesky:
                        return try await self.blueskyService.fetchHomeTimeline(
                            for: account,
                            cursor: nil
                        )
                    }
                } catch {
                    return nil
                }
            }
        }
        var collected: [TimelineResult] = []
        for await result in group {
            if let result { collected.append(result) }
        }
        return collected
    }

    // Merge: posts authored by one of the group's accounts only (filter), then
    // sort descending by createdAt. Reposts/boosts are kept regardless of
    // who the underlying author is — the user opted into the *group's
    // timeline*, not just "posts by these people."
    let merged = results.flatMap(\.posts).sorted { $0.createdAt > $1.createdAt }
    // De-duplicate by post id (parallel fetches occasionally double-list cross-network mentions).
    var seen = Set<String>()
    let deduped = merged.filter { seen.insert($0.id).inserted }
    return TimelineResult(
        posts: deduped,
        pagination: PaginationInfo(hasNextPage: false, nextPageToken: nil)
    )
}
```

> v1.0 ships account-group pagination as a single page (40 posts per source). Pagination across a merged fan-out is non-trivial — each source has its own cursor — and the medium-depth scope explicitly defers that complexity to v1.1.

- [ ] **Step 5: Remove any Task 2 fatalError guards**

If Task 2 required temporary `fatalError("unreachable until Task 5")` lines, delete them now — every `TimelineFeedSelection` switch in the codebase should compile cleanly with the new `.pinned` case handled.

Search the workspace for `unreachable until Task 5` and remove every occurrence.

- [ ] **Step 6: Verify the build**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add SocialFusion/Services/SocialServiceManager.swift SocialFusion/SocialFusionApp.swift
git commit -m "feat(pins): resolve .pinned selections + dispatch fan-out fetch"
```

---

## Task 6: Fetch-plan unit tests

**Files:**
- Create: `SocialFusionTests/PinnedTimelineFetchPlanTests.swift`

Unit-test the new pure resolution logic in isolation — without hitting the network — to lock in the contract: account-group with one missing account still resolves; account-group with zero remaining accounts returns nil; pin-by-id returns nil when the store doesn't have it.

- [ ] **Step 1: Write the tests**

Create `SocialFusionTests/PinnedTimelineFetchPlanTests.swift`:

```swift
import XCTest
@testable import SocialFusion

@MainActor
final class PinnedTimelineFetchPlanTests: XCTestCase {
    private func makeAccount(id: String, platform: SocialPlatform) -> SocialAccount {
        // The SocialAccount initializer signature lives in
        // SocialFusion/Models/SocialAccount.swift. Construct with the minimum
        // fields needed for identity + platform.
        SocialAccount(
            id: id,
            username: "user-\(id)",
            displayName: "User \(id)",
            serverURL: URL(string: "https://example.test"),
            platform: platform
        )
    }

    func testResolveMastodonListPinReturnsAccount() async {
        let manager = SocialServiceManager()
        let pinStore = PinnedTimelineStore(
            userDefaults: .standard,
            defaultsKey: "pin-fetch-plan-test-\(UUID().uuidString)"
        )
        manager.pinnedTimelineStore = pinStore
        let acct = makeAccount(id: "m1", platform: .mastodon)
        manager.accounts = [acct]

        let pin = PinnedTimeline(
            displayName: "Friends",
            kind: .mastodonList(accountId: "m1", listId: "list-7")
        )
        pinStore.add(pin)
        manager.setTimelineFeedSelection(.pinned(id: pin.id))

        let plan = manager.resolveTimelineFetchPlan()
        guard case .pinned(let resolvedPin, let resolution) = plan else {
            return XCTFail("Expected .pinned plan, got \(String(describing: plan))")
        }
        XCTAssertEqual(resolvedPin.id, pin.id)
        if case .mastodonList(let account, let listId) = resolution {
            XCTAssertEqual(account.id, "m1")
            XCTAssertEqual(listId, "list-7")
        } else {
            XCTFail("Expected .mastodonList resolution, got \(resolution)")
        }
    }

    func testResolveAccountGroupWithOneMissingAccountStillReturnsRemaining() async {
        let manager = SocialServiceManager()
        let pinStore = PinnedTimelineStore(
            userDefaults: .standard,
            defaultsKey: "pin-fetch-plan-test-\(UUID().uuidString)"
        )
        manager.pinnedTimelineStore = pinStore
        let m1 = makeAccount(id: "m1", platform: .mastodon)
        let b1 = makeAccount(id: "b1", platform: .bluesky)
        manager.accounts = [m1, b1]

        let pin = PinnedTimeline(
            displayName: "Work",
            kind: .accountGroup(accountIds: ["m1", "b1", "deleted-account"])
        )
        pinStore.add(pin)
        manager.setTimelineFeedSelection(.pinned(id: pin.id))

        let plan = manager.resolveTimelineFetchPlan()
        guard case .pinned(_, .accountGroup(let resolved)) = plan else {
            return XCTFail("Expected .pinned/.accountGroup, got \(String(describing: plan))")
        }
        XCTAssertEqual(resolved.map(\.id).sorted(), ["b1", "m1"])
    }

    func testResolveAccountGroupWithZeroRemainingAccountsReturnsNil() async {
        let manager = SocialServiceManager()
        let pinStore = PinnedTimelineStore(
            userDefaults: .standard,
            defaultsKey: "pin-fetch-plan-test-\(UUID().uuidString)"
        )
        manager.pinnedTimelineStore = pinStore
        manager.accounts = [] // all accounts removed

        let pin = PinnedTimeline(
            displayName: "Ghost",
            kind: .accountGroup(accountIds: ["m1"])
        )
        pinStore.add(pin)
        manager.setTimelineFeedSelection(.pinned(id: pin.id))

        XCTAssertNil(manager.resolveTimelineFetchPlan(),
                     "Pin pointing at no-longer-existing accounts must resolve to nil.")
    }

    func testResolveByUnknownIDReturnsNil() async {
        let manager = SocialServiceManager()
        manager.pinnedTimelineStore = PinnedTimelineStore(
            userDefaults: .standard,
            defaultsKey: "pin-fetch-plan-test-\(UUID().uuidString)"
        )
        manager.accounts = [makeAccount(id: "m1", platform: .mastodon)]
        manager.setTimelineFeedSelection(.pinned(id: "nonexistent-pin-id"))

        XCTAssertNil(manager.resolveTimelineFetchPlan())
    }
}
```

> **Implementer note:** the test instantiates `SocialServiceManager()` directly. If the real initializer requires arguments (likely — it owns many sub-stores), introduce a test convenience `init()` in `#if DEBUG` that defaults all sub-stores to inert empties. The Fuse plan's stub-service approach (Task 9 there) is the same idea. Verify `SocialAccount`'s `init` signature in `SocialFusion/Models/SocialAccount.swift` before pasting the test as-is — adjust the call to match.

- [ ] **Step 2: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/PinnedTimelineFetchPlanTests`

Expected: PASS, all 4 tests green.

- [ ] **Step 3: Commit**

```bash
git add SocialFusionTests/PinnedTimelineFetchPlanTests.swift
git commit -m "test(pins): fetch-plan resolution coverage (lists, groups, missing accounts)"
```

---

## Task 7: TimelineFeedPickerViewModel — Bluesky lists + capture helpers

**Files:**
- Modify: `SocialFusion/ViewModels/TimelineFeedPickerViewModel.swift`

The picker already lazy-loads Mastodon lists and Bluesky custom feeds per-account. Add the same shape for Bluesky lists, plus a synchronous `capturePin(for:)` helper that derives a sensible default `displayName` from any pinnable destination.

- [ ] **Step 1: Add Bluesky lists state + loader**

Open `SocialFusion/ViewModels/TimelineFeedPickerViewModel.swift`. Below the existing `blueskyFeedsByAccount` published state, add:

```swift
@Published var blueskyListsByAccount: [String: [BlueskyList]] = [:]
@Published var loadingBlueskyListsForAccount: String? = nil

var blueskyLists: [BlueskyList] { blueskyListsByAccount.values.flatMap { $0 } }

func loadBlueskyLists(for account: SocialAccount) async {
    guard loadingBlueskyListsForAccount != account.id else { return }
    guard blueskyListsByAccount[account.id] == nil else { return }
    loadingBlueskyListsForAccount = account.id
    defer { loadingBlueskyListsForAccount = nil }
    do {
        blueskyListsByAccount[account.id] = try await serviceManager.blueskySvc.fetchUserLists(for: account)
    } catch {
        blueskyListsByAccount[account.id] = []
    }
}

func isLoadingBlueskyLists(for accountId: String) -> Bool {
    loadingBlueskyListsForAccount == accountId
}

func blueskyLists(for accountId: String) -> [BlueskyList] {
    blueskyListsByAccount[accountId] ?? []
}
```

> If the `SocialServiceManager` doesn't expose `blueskySvc` publicly, either expose it (it almost certainly already is — `AccountTimelineController` uses it at line 42 of `AccountTimelineController.swift`) or add a `serviceManager.fetchBlueskyLists(account:)` wrapper next to the existing `fetchBlueskySavedFeeds(account:)` (line 3638 of `SocialServiceManager.swift`) and call that instead. Wrapper version is cleaner — match the existing pattern.

If you prefer the wrapper, add to `SocialServiceManager.swift` immediately after `fetchBlueskySavedFeeds(account:)` (line 3638):

```swift
/// Fetch the lists owned by a Bluesky account
public func fetchBlueskyLists(account: SocialAccount) async throws -> [BlueskyList] {
    guard account.platform == .bluesky else {
        throw ServiceError.unsupportedPlatform
    }
    return try await blueskyService.fetchUserLists(for: account)
}
```

And change the view model's loader call to `serviceManager.fetchBlueskyLists(account: account)`.

- [ ] **Step 2: Add the capture-pin default-name helper**

Append to the same view model:

```swift
/// Produces a sensible default `displayName` for a new pin captured from
/// the picker. Returns nil if the selection isn't pinnable in v1.0 (e.g.
/// `.unified`, `.allMastodon`, `.allBluesky` — those are already top-level).
func suggestedPinName(for selection: TimelineFeedSelection) -> String? {
    switch selection {
    case .unified, .allMastodon, .allBluesky:
        return nil
    case .mastodon(let accountId, let feed):
        switch feed {
        case .list(_, let title):
            return title ?? "Mastodon list"
        case .home, .local, .federated:
            return nil // home timelines aren't pinnable individually
        case .instance(let server):
            return server
        }
        _ = accountId
    case .bluesky(_, let feed):
        switch feed {
        case .following:
            return nil
        case .custom(_, let name):
            return name ?? "Bluesky feed"
        }
    case .pinned:
        return nil // already a pin
    }
}

/// Converts a pinnable selection into the matching `PinnedTimelineKind`.
/// Returns nil for non-pinnable selections.
func pinKind(for selection: TimelineFeedSelection) -> PinnedTimelineKind? {
    switch selection {
    case .mastodon(let accountId, .list(let listId, _)):
        return .mastodonList(accountId: accountId, listId: listId)
    case .bluesky(let accountId, .custom(let uri, _)):
        return .blueskyFeed(accountId: accountId, feedUri: uri)
    default:
        return nil
    }
}

/// Direct helper used by the picker's "Pin this Bluesky list" row.
func pinKindForBlueskyList(accountId: String, listURI: String) -> PinnedTimelineKind {
    .blueskyList(accountId: accountId, listUri: listURI)
}
```

- [ ] **Step 3: Verify the build**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add SocialFusion/ViewModels/TimelineFeedPickerViewModel.swift SocialFusion/Services/SocialServiceManager.swift
git commit -m "feat(pins): TimelineFeedPickerViewModel Bluesky-list load + pin-capture helpers"
```

---

## Task 8: PinnedTimelineEditorViewModel + tests

**Files:**
- Create: `SocialFusion/ViewModels/PinnedTimelineEditorViewModel.swift`
- Create: `SocialFusionTests/PinnedTimelineEditorViewModelTests.swift`

The editor view model orchestrates create / rename / reorder / delete on top of the store. It also drives the "create account-group pin" flow — multi-select across both networks' accounts plus a name field.

- [ ] **Step 1: Write the failing tests**

Create `SocialFusionTests/PinnedTimelineEditorViewModelTests.swift`:

```swift
import XCTest
@testable import SocialFusion

@MainActor
final class PinnedTimelineEditorViewModelTests: XCTestCase {
    private let key = "pinned-editor-test-key"

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: key)
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

    func testCreateAccountGroupPinAppendsToStore() {
        let store = makeStore()
        let vm = PinnedTimelineEditorViewModel(store: store)
        vm.draftName = "Work"
        vm.draftSelectedAccountIDs = ["m1", "b1"]
        vm.createAccountGroupPin()
        XCTAssertEqual(store.pins.count, 1)
        if case .accountGroup(let ids) = store.pins.first?.kind {
            XCTAssertEqual(ids.sorted(), ["b1", "m1"])
        } else {
            XCTFail("Expected accountGroup kind")
        }
        XCTAssertEqual(vm.draftName, "")
        XCTAssertEqual(vm.draftSelectedAccountIDs, [])
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/PinnedTimelineEditorViewModelTests`

Expected: FAIL — `PinnedTimelineEditorViewModel` not defined.

- [ ] **Step 3: Implement the view model**

Create `SocialFusion/ViewModels/PinnedTimelineEditorViewModel.swift`:

```swift
import Combine
import Foundation
import SwiftUI

/// Drives `PinnedTimelinesEditorView`. Holds transient draft state for
/// creating an account-group pin (name + selected account IDs) and forwards
/// rename/delete/reorder operations to the store.
@MainActor
public final class PinnedTimelineEditorViewModel: ObservableObject {
    @Published public var draftName: String = ""
    @Published public var draftSelectedAccountIDs: Set<String> = []

    public let store: PinnedTimelineStore

    public init(store: PinnedTimelineStore) {
        self.store = store
    }

    // MARK: - Account-group pin creation

    public var canCreateAccountGroup: Bool {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !draftSelectedAccountIDs.isEmpty
    }

    public func toggleAccountSelection(_ accountId: String) {
        if draftSelectedAccountIDs.contains(accountId) {
            draftSelectedAccountIDs.remove(accountId)
        } else {
            draftSelectedAccountIDs.insert(accountId)
        }
    }

    public func createAccountGroupPin() {
        guard canCreateAccountGroup else { return }
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let pin = PinnedTimeline(
            displayName: name,
            kind: .accountGroup(accountIds: Array(draftSelectedAccountIDs).sorted())
        )
        store.add(pin)
        draftName = ""
        draftSelectedAccountIDs = []
    }

    // MARK: - Existing-pin operations

    public func commitRename(id: String, to newName: String) {
        store.rename(id: id, to: newName)
    }

    public func delete(id: String) {
        store.remove(id: id)
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        store.move(fromOffsets: source, toOffset: destination)
    }

    /// Add a pin captured from a non-account-group source (Mastodon list,
    /// Bluesky list, Bluesky feed) using a suggested display name. Used by
    /// the picker's "Pin this" capture surface.
    public func pinExisting(
        kind: PinnedTimelineKind,
        suggestedName: String
    ) -> PinnedTimeline {
        let pin = PinnedTimeline(displayName: suggestedName, kind: kind)
        store.add(pin)
        return pin
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/PinnedTimelineEditorViewModelTests`

Expected: PASS, all 5 tests green.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/ViewModels/PinnedTimelineEditorViewModel.swift SocialFusionTests/PinnedTimelineEditorViewModelTests.swift
git commit -m "feat(pins): PinnedTimelineEditorViewModel with draft state + tests"
```

---

## Task 9: PinnedTimelinesEditorView

**Files:**
- Create: `SocialFusion/Views/PinnedTimelinesEditorView.swift`

The editor sheet. Three sections in a single `List`: existing pins (rename, reorder, delete via swipe), a "Create account group" form, and a compact info footer pointing to the future v1.1 glass-box editor.

- [ ] **Step 1: Implement the view**

Create `SocialFusion/Views/PinnedTimelinesEditorView.swift`:

```swift
import SwiftUI

public struct PinnedTimelinesEditorView: View {
    @StateObject var viewModel: PinnedTimelineEditorViewModel
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @Environment(\.dismiss) private var dismiss
    @State private var renamingID: String? = nil
    @State private var renameDraft: String = ""

    public init(viewModel: PinnedTimelineEditorViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            List {
                existingPinsSection
                createAccountGroupSection
                footerSection
            }
            .navigationTitle("Edit Pins")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Existing pins section

    private var existingPinsSection: some View {
        Section("Your pins") {
            if viewModel.store.pins.isEmpty {
                Text("No pinned timelines yet. Pin a list or feed from the timeline picker, or create an account group below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.store.pins) { pin in
                    pinRow(pin)
                }
                .onDelete { offsets in
                    for index in offsets {
                        viewModel.delete(id: viewModel.store.pins[index].id)
                    }
                }
                .onMove { source, destination in
                    viewModel.move(fromOffsets: source, toOffset: destination)
                }
            }
        }
    }

    @ViewBuilder
    private func pinRow(_ pin: PinnedTimeline) -> some View {
        if renamingID == pin.id {
            HStack {
                TextField("Name", text: $renameDraft, onCommit: {
                    viewModel.commitRename(id: pin.id, to: renameDraft)
                    renamingID = nil
                })
                .textFieldStyle(.roundedBorder)
                Button("Save") {
                    viewModel.commitRename(id: pin.id, to: renameDraft)
                    renamingID = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("Cancel") { renamingID = nil }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: kindIcon(for: pin.kind))
                    .foregroundStyle(.tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pin.displayName)
                        .font(.body)
                    Text(kindDescription(for: pin.kind))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    renameDraft = pin.displayName
                    renamingID = pin.id
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Rename \(pin.displayName)")
            }
        }
    }

    private func kindIcon(for kind: PinnedTimelineKind) -> String {
        switch kind {
        case .mastodonList: return "list.bullet.rectangle"
        case .blueskyList: return "list.bullet.rectangle"
        case .blueskyFeed: return "antenna.radiowaves.left.and.right"
        case .accountGroup: return "person.3.fill"
        }
    }

    private func kindDescription(for kind: PinnedTimelineKind) -> String {
        switch kind {
        case .mastodonList: return "Mastodon list"
        case .blueskyList: return "Bluesky list"
        case .blueskyFeed: return "Bluesky feed"
        case .accountGroup(let ids):
            let count = ids.count
            return "Account group (\(count) account\(count == 1 ? "" : "s"))"
        }
    }

    // MARK: - Create account-group section

    private var createAccountGroupSection: some View {
        Section("Create account group") {
            TextField("Pin name (e.g. Work)", text: $viewModel.draftName)
                .textInputAutocapitalization(.words)
            ForEach(serviceManager.accounts, id: \.id) { account in
                Button {
                    viewModel.toggleAccountSelection(account.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: viewModel.draftSelectedAccountIDs.contains(account.id)
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(viewModel.draftSelectedAccountIDs.contains(account.id)
                                             ? .tint : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(account.displayName)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text("@\(account.username) · \(account.platform == .mastodon ? "Mastodon" : "Bluesky")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            Button {
                viewModel.createAccountGroupPin()
            } label: {
                Label("Create pin", systemImage: "plus.circle.fill")
            }
            .disabled(!viewModel.canCreateAccountGroup)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pinnable timelines are the entry point to the lens that shapes your feed. The full glass-box rule editor — keyword filters, hashtag rules, mute lists — arrives in a later update.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}
```

- [ ] **Step 2: Verify the build**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Smoke test the preview**

In Xcode, open `PinnedTimelinesEditorView.swift`. Add a `#if DEBUG` preview at the bottom of the file:

```swift
#if DEBUG
struct PinnedTimelinesEditorView_Previews: PreviewProvider {
    static var previews: some View {
        let store = PinnedTimelineStore(
            userDefaults: .standard,
            defaultsKey: "pins-preview-\(UUID().uuidString)"
        )
        store.add(PinnedTimeline(displayName: "Work", kind: .accountGroup(accountIds: ["m1", "b1"])))
        store.add(PinnedTimeline(displayName: "Tech news", kind: .mastodonList(accountId: "m1", listId: "list-7")))
        return PinnedTimelinesEditorView(viewModel: PinnedTimelineEditorViewModel(store: store))
            .environmentObject(SocialServiceManager())
    }
}
#endif
```

Resume the canvas. Verify the list shows both seed pins with correct icons, the rename button toggles the inline TextField, and the "Create account group" section disables the Create button until both name and accounts are populated.

- [ ] **Step 4: Commit**

```bash
git add SocialFusion/Views/PinnedTimelinesEditorView.swift
git commit -m "feat(pins): PinnedTimelinesEditorView with rename/reorder/delete + group creation"
```

---

## Task 10: TimelineFeedPickerPopover — Pinned section and capture

**Files:**
- Modify: `SocialFusion/Views/Components/TimelineFeedPickerPopover.swift`

Add the Pinned section to the root step. Each pin row is selectable (becomes the current `.pinned(id:)` selection) and long-pressable (jumps into the editor with that pin's rename field pre-armed). Capture-pin actions on existing pinnable destinations (Mastodon list rows, Bluesky list rows, Bluesky feed rows) get a trailing pin-button.

- [ ] **Step 1: Inject the store and add capture handler**

Open `SocialFusion/Views/Components/TimelineFeedPickerPopover.swift`. Near the top of the struct, alongside the existing `@ObservedObject var viewModel` declaration, add:

```swift
@EnvironmentObject private var pinnedTimelineStore: PinnedTimelineStore
@State private var showingEditor: Bool = false
```

And extend the existing `onSelect` callback contract by adding a new sibling callback. **Do not break the existing `onSelect` signature.** Add:

```swift
let onEditPins: () -> Void
```

(Callers will pass a closure that sets a `@State` `showingPinEditor` flag in their parent.)

- [ ] **Step 2: Add the Pinned section to rootSections**

Find the `rootSections` computed property (line 50). After the existing `topItems` block but before the function returns, build a pinned-section block:

```swift
private var pinnedSection: NavBarPillDropdownSection? {
    guard !pinnedTimelineStore.pins.isEmpty else { return nil }
    var items: [NavBarPillDropdownItem] = pinnedTimelineStore.pins.map { pin in
        NavBarPillDropdownItem(
            id: "pinned-\(pin.id)",
            title: pin.displayName,
            isSelected: selection == .pinned(id: pin.id),
            iconSystemName: iconSystemName(for: pin.kind),
            action: { select(.pinned(id: pin.id)) }
        )
    }
    items.append(
        NavBarPillDropdownItem(
            id: "edit-pins",
            title: "Edit Pins…",
            isSelected: false,
            iconSystemName: "pencil",
            action: {
                isPresented = false
                onEditPins()
            }
        )
    )
    return NavBarPillDropdownSection(title: "Pinned", items: items)
}

private func iconSystemName(for kind: PinnedTimelineKind) -> String {
    switch kind {
    case .mastodonList, .blueskyList: return "list.bullet.rectangle"
    case .blueskyFeed: return "antenna.radiowaves.left.and.right"
    case .accountGroup: return "person.3.fill"
    }
}
```

Then in the existing `rootSections` computed property, insert `pinnedSection` at the top of the assembled sections list (before the existing "All accounts" section). The exact construction depends on the existing local — if the function ends with `return [section1, section2, ...]`, prefix with `pinnedSection.map { [$0] } ?? []`:

```swift
private var rootSections: [NavBarPillDropdownSection] {
    var sections: [NavBarPillDropdownSection] = []
    if let pinned = pinnedSection { sections.append(pinned) }
    // ... existing assembly of topItems / per-account sections continues here ...
    return sections
}
```

> The exact splice point depends on the existing function shape. Read the existing `rootSections` body before editing — preserve the existing sections verbatim and only prepend `pinnedSection` if present. `NavBarPillDropdownItem` accepts `iconSystemName:` per the existing rendering convention; if it doesn't, drop the parameter — the pin label alone is sufficient.

- [ ] **Step 3: Add "Pin this" capture in detail steps**

Inside `listsView(for:)` (the function that renders a Mastodon account's lists), each list row should grow a trailing button. Find the list-row builder; for each row add a trailing capture action:

```swift
// Inside the list-row HStack, after the title text:
Spacer()
Button {
    let kind = PinnedTimelineKind.mastodonList(accountId: account.id, listId: list.id)
    if !pinnedTimelineStore.isPinned(kind: kind) {
        pinnedTimelineStore.add(PinnedTimeline(displayName: list.title, kind: kind))
    }
} label: {
    Image(systemName: pinnedTimelineStore.isPinned(
        kind: .mastodonList(accountId: account.id, listId: list.id)
    ) ? "pin.fill" : "pin")
        .foregroundStyle(.tint)
}
.buttonStyle(.borderless)
.accessibilityLabel("Pin \(list.title)")
```

Apply the same shape inside `feedsView(for:)` (Bluesky custom feeds) — capture builds `.blueskyFeed(accountId: account.id, feedUri: feed.uri)` and uses `feed.displayName` as the default name.

Add a new step `case .blueskyLists(SocialAccount)` to the `Step` enum at the top of the file (mirror of the existing `.mastodonLists`), wire it into the `switch step` in `body`, and implement `blueskyListsView(for:)` the same way — fetch via `viewModel.loadBlueskyLists(for:)`, render rows from `viewModel.blueskyLists(for:)`, capture with `.blueskyList(accountId: account.id, listUri: list.uri)`.

In the per-account detail view (`accountDetailView(for:)`), where the existing rows already navigate to `mastodonLists` for Mastodon and `blueskyFeeds` for Bluesky, add the new "Lists" row for Bluesky accounts pointing at `.blueskyLists(account)`.

- [ ] **Step 4: Verify the build**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

Expected: BUILD SUCCEEDED.

> If the build fails because `TimelineFeedPickerPopover` is constructed at `ConsolidatedTimelineView.swift:478` without the new `onEditPins` callback, Task 11 wires it up. For now, you can either temporarily default the argument to `{ }` to make the build green, then remove the default in Task 11, or accept the build failure and proceed to Task 11 immediately.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Views/Components/TimelineFeedPickerPopover.swift
git commit -m "feat(pins): picker Pinned section + per-row pin-this capture + Bluesky lists step"
```

---

## Task 11: ConsolidatedTimelineView — present the editor + label pinned selections

**Files:**
- Modify: `SocialFusion/Views/ConsolidatedTimelineView.swift`

The picker now reports an `onEditPins` event. The host view presents `PinnedTimelinesEditorView` in response. Also: when the current selection is `.pinned(id:)`, the navigation pill needs to show the pin's display name, not the placeholder.

- [ ] **Step 1: Inject the store**

In `SocialFusion/Views/ConsolidatedTimelineView.swift`, near the existing `@EnvironmentObject` declarations, add:

```swift
@EnvironmentObject private var pinnedTimelineStore: PinnedTimelineStore
@State private var showingPinEditor: Bool = false
```

- [ ] **Step 2: Pass onEditPins into the popover**

Find the existing `TimelineFeedPickerPopover(...)` construction (line 478). Add the new closure argument:

```swift
TimelineFeedPickerPopover(
    viewModel: feedPickerViewModel,
    isPresented: $showFeedPicker,
    selection: serviceManager.currentTimelineFeedSelection,
    accounts: serviceManager.accounts,
    mastodonAccounts: serviceManager.mastodonAccounts,
    blueskyAccounts: serviceManager.blueskyAccounts,
    onSelect: handleFeedSelection(_:),
    onEditPins: { showingPinEditor = true }
)
```

- [ ] **Step 3: Present the editor sheet**

Attach a `.sheet` modifier to the same view where other modal presentations live (search the file for the existing `.sheet(item:` or `.sheet(isPresented:` chain — typically near the bottom of the main `body`):

```swift
.sheet(isPresented: $showingPinEditor) {
    PinnedTimelinesEditorView(
        viewModel: PinnedTimelineEditorViewModel(store: pinnedTimelineStore)
    )
    .environmentObject(serviceManager)
}
```

- [ ] **Step 4: Make feedTitle handle .pinned**

Find `feedTitle(for selection: TimelineFeedSelection) -> String` (line 664). Add the `.pinned` arm:

```swift
private func feedTitle(for selection: TimelineFeedSelection) -> String {
    switch selection {
    case .unified: return "Unified"
    case .allMastodon: return "All Mastodon"
    case .allBluesky: return "All Bluesky"
    case .mastodon(_, let feed): return feedTitle(for: feed)
    case .bluesky(_, let feed): return feedTitle(for: feed)
    case .pinned(let id):
        return pinnedTimelineStore.pin(id: id)?.displayName ?? "Pinned"
    }
}
```

(Preserve the existing `mastodon` / `bluesky` arms verbatim — only the `.pinned` arm is new. If the existing function doesn't already have `.allMastodon` / `.allBluesky` cases or differs in shape, edit additively rather than replacing.)

- [ ] **Step 5: Verify the build**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add SocialFusion/Views/ConsolidatedTimelineView.swift
git commit -m "feat(pins): present editor sheet + show pin name in nav pill"
```

---

## Task 12: SettingsView entry point

**Files:**
- Modify: `SocialFusion/Views/SettingsView.swift`

The picker is the primary surface (one tap to "Edit Pins…"), but Settings is the discoverable home for "I want to manage all my pins" intent. Add a navigation row.

- [ ] **Step 1: Add the Pinned Timelines row**

Open `SocialFusion/Views/SettingsView.swift`. Locate a section that holds account- or timeline-related rows (likely a "Timeline" or "Accounts" section — search the file for `Section(` and pick the most thematically appropriate, or create a new `Section("Timeline")` if none fits). Insert:

```swift
@EnvironmentObject private var pinnedTimelineStore: PinnedTimelineStore
@State private var showingPinEditor = false

// ... inside the appropriate Section { ... }:
Button {
    showingPinEditor = true
} label: {
    HStack {
        Label("Pinned Timelines", systemImage: "pin.fill")
        Spacer()
        if !pinnedTimelineStore.pins.isEmpty {
            Text("\(pinnedTimelineStore.pins.count)")
                .foregroundStyle(.secondary)
        }
        Image(systemName: "chevron.right")
            .foregroundStyle(.tertiary)
            .font(.caption.weight(.semibold))
    }
}
.buttonStyle(.plain)
```

And attach the sheet at the root of the Settings view body (or wherever existing `.sheet` modifiers in the file live):

```swift
.sheet(isPresented: $showingPinEditor) {
    PinnedTimelinesEditorView(
        viewModel: PinnedTimelineEditorViewModel(store: pinnedTimelineStore)
    )
    .environmentObject(serviceManager)
}
```

- [ ] **Step 2: Verify the build**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add SocialFusion/Views/SettingsView.swift
git commit -m "feat(pins): Settings entry point with pin-count badge"
```

---

## Task 13: End-to-end smoke test on the simulator + device

**Files:**
- (no source changes — this is the validation pass)

Run the full app and exercise every pinnable surface.

- [ ] **Step 1: Build and install**

Run:

```bash
xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

Then install + launch via the project's standard simulator commands (from `MEMORY.md`):

```bash
xcrun simctl install booted <built-app-path>
xcrun simctl launch booted com.socialfusionapp.app
```

- [ ] **Step 2: Walk the surfaces**

With Frank's Mastodon + Bluesky accounts signed in:

1. Open the timeline picker. Confirm no Pinned section appears (the user has no pins yet).
2. Drill into the Mastodon account → Lists. Tap the pin icon next to one list. Close the picker.
3. Open the picker again. Confirm the Pinned section now exists with that list as the only row. Confirm its icon is `list.bullet.rectangle`.
4. Tap the pinned row. The timeline switches to fetching that list. Confirm posts load. Confirm the nav pill title now shows the pin's display name (= the list's original title).
5. Re-open the picker. Drill into the Bluesky account → Feeds. Pin a custom feed. Confirm the Pinned section now has 2 rows.
6. Tap "Edit Pins…". Confirm `PinnedTimelinesEditorView` opens with both existing pins listed.
7. Tap the pencil icon on a pin. Rename it. Confirm the new name appears in the picker after dismissing.
8. Reorder via drag-handle. Confirm new order persists after force-quitting the app.
9. In the same editor, create an Account Group pin — type "Work", select one Mastodon and one Bluesky account. Tap "Create pin." Confirm the new pin appears with icon `person.3.fill`.
10. Tap the new account-group pin. Confirm the timeline becomes the merged home feeds of those two accounts only.
11. Open Settings → Pinned Timelines. Confirm the same editor opens with the correct pin count badge.

- [ ] **Step 3: Force-quit / cold-launch persistence check**

Force-quit (swipe up). Re-launch. Open the picker. Confirm all three pins still exist in the same order. Open Settings → Pinned Timelines. Confirm the count.

- [ ] **Step 4: Cross-device check on Frank's iPhone 17 Pro**

Build for device (UDID in `MEMORY.md`):

```bash
xcodebuild build -scheme SocialFusion -destination "id=00008150-000139C63480401C"
```

Install and repeat steps 2–3. Verify the same flow works on real hardware. Pinned timelines are local-only in v1.0 — no cross-device sync, so device pins are independent from simulator pins. This is expected.

- [ ] **Step 5: No commit needed for this validation task**

If any issue surfaces during the smoke test, file a follow-up task rather than amending this plan in-flight.

---

## Task 14: Acceptance harness in TimelineValidationDebugView

**Files:**
- Modify: `SocialFusion/Views/Debug/TimelineValidationDebugView.swift`

The existing `#if DEBUG`-gated validation view (long-press the compose button) is the project's pattern for runnable acceptance checks. Add a "Pinned Timelines" section.

- [ ] **Step 1: Add the section**

Open `SocialFusion/Views/Debug/TimelineValidationDebugView.swift`. Find the existing pattern for adding a validation section (search for an existing `Section(` or a `Group { Text("...") }` header). Add a new Pinned Timelines section that exercises:

```swift
private var pinnedTimelinesSection: some View {
    Section("Pinned Timelines") {
        Button("Create test pin") {
            let pin = PinnedTimeline(
                displayName: "Validation test \(Int.random(in: 1000...9999))",
                kind: .accountGroup(accountIds: serviceManager.accounts.prefix(1).map(\.id))
            )
            pinnedTimelineStore.add(pin)
        }
        Button("Clear all pins") {
            for pin in pinnedTimelineStore.pins {
                pinnedTimelineStore.remove(id: pin.id)
            }
        }
        Text("Pins: \(pinnedTimelineStore.pins.count)")
            .font(.caption.monospacedDigit())
        ForEach(pinnedTimelineStore.pins) { pin in
            HStack {
                Text(pin.displayName).font(.caption2)
                Spacer()
                Text(pin.kind.storageKey)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}
```

Add the store as an `@EnvironmentObject` at the top of the view if not already present, and include `pinnedTimelinesSection` in the main `Form`/`List` body.

- [ ] **Step 2: Build and run validation**

Build, install, launch. Long-press the compose button. Confirm the Pinned Timelines section renders, the buttons mutate the store, and the count updates live.

- [ ] **Step 3: Commit**

```bash
git add SocialFusion/Views/Debug/TimelineValidationDebugView.swift
git commit -m "test(pins): TimelineValidationDebugView Pinned Timelines section"
```

---

## Acceptance gate before promoting to TestFlight

After all 14 tasks are complete:

1. **Full unit test suite passes:** `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet` returns 0. Specifically, `PinnedTimelineStoreTests`, `PinnedTimelineEditorViewModelTests`, and `PinnedTimelineFetchPlanTests` all green.
2. **Manual smoke test (Task 13) passes on both simulator and Frank's iPhone 17 Pro** — every step completes, no crashes, no AttributeGraph console warnings.
3. **Pin persistence survives cold launch and OS-level force-quit.**
4. **Picker Pinned section is hidden when no pins exist** — the empty state is the absence of the section, not an empty-state placeholder. Validate with a fresh install.
5. **Pin pointing at a removed account resolves to nil gracefully** — the timeline falls back to whatever was loaded previously, and the pin still appears in the editor so the user can delete it. (Account-group pins with at least one surviving account continue to work.)
6. **Picker pin-this icon reflects current state** — `pin.fill` when already pinned, `pin` outline otherwise. Tapping when already pinned is a no-op (no duplicate added).
7. **`xcodegen` regeneration is unnecessary** — none of the changes in this plan add resources or target settings that need to be reflected in `project.yml`.

---

## What's intentionally out of scope for this plan

The following live in sibling plans (see spec, "What's not in this spec" and "v1.x trajectory"):

- **Full glass-box filter editor** — the v1.1 power-user UI with keyword rules, hashtag includes/excludes, mute lists. v1.0 pinnable timelines (this plan) is the entry point.
- **Cross-device pin sync via iCloud KVS** — depends on the KVS budget after timeline-position sync ships; deferred to v1.1.
- **Per-source pagination across account-group pins** — v1.0 ships first-page-only for account groups; merged-cursor pagination is v1.1.
- **Pin reordering via drag-and-drop in the picker itself** — only available in the editor in v1.0. Picker order = editor order.
- **Pin sharing / export** — share a pin definition as a URL or file. Out of scope.
- **Pin-scoped notification settings** — separate plan.
- **Account-group pin showing only original posts (not boosts/reposts)** — v1.0 ships the merged home timeline verbatim; rule-based filtering belongs in the v1.1 editor.
- **Bluesky modlist pins** — `BlueskyList.purpose == "modlist"` lists are surfaced in `fetchUserLists` results but pinning them as timelines is meaningless. The editor UI should optionally filter `purpose != "modlist"` if Frank confirms the user-facing list count is cleaner that way; if so, add the filter in a follow-up.
- **Timeline search scoped to a pin** — covered in the separate Timeline Search plan.

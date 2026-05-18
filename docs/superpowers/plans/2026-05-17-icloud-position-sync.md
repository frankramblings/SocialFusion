# iCloud Timeline-Position Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync the user's last-read position per `(accountID, timelineID)` across their iPhone and iPad (and, in v1.1, Mac) via Apple's `NSUbiquitousKeyValueStore` — no backend server, no third-party service. Open another device, the timeline lands exactly where you left it on the previous one.

**Architecture:** A new `PositionSyncService` (MainActor-isolated, `ObservableObject`) owns a `[String: TimelinePosition]` map keyed on `pos.{accountID}.{timelineID}` and persists each entry through an injected `KeyValueStorageBacking` (a thin protocol over `NSUbiquitousKeyValueStore`). On launch the service hydrates from the backing, on scroll settle it debounces writes to ≤1 per 3s per key, on `NSUbiquitousKeyValueStoreDidChangeExternallyNotification` it merges remote updates by last-write-wins on `lastReadAt` (with a 30-second deadband to suppress micro-jumps). The existing `SmartPositionManager` keeps owning *in-session* scroll-history heuristics — `PositionSyncService` is the *cross-device* layer that records its authoritative anchor and replays it on cold start. `UnifiedTimelineController` calls a single new `recordPosition(accountID:timelineID:postID:offset:)` method on scroll settle and a `restorePosition(accountID:timelineID:)` method during initial hydration; both delegate to `SmartPositionManager` for in-session work and to `PositionSyncService` for cross-device sync. The protocol abstraction lets unit tests run against an in-memory `FakeKeyValueStorageBacking` while integration tests exercise the real `iCloudKVSBacking` against the simulator's iCloud sandbox.

**Tech Stack:** Swift 5+, SwiftUI, Combine, `NSUbiquitousKeyValueStore`, `NotificationCenter`, XCTest. iOS 17+ floor. Reuses existing patterns: `@MainActor` published state, `ObservableObject` services injected as `@EnvironmentObject`, side-channel store shape (`PostActionStore`, `FusedMomentStore`).

**Spec reference:** `docs/superpowers/specs/2026-05-17-socialfusion-v1-vision-design.md` — see "Gap Map → Cross-device timeline position sync" and "Principle 6: Open by default — no backend server we control."

**File map (creates/modifies):**

- Create: `SocialFusion/Models/TimelinePosition.swift`
- Create: `SocialFusion/Services/KeyValueStorageBacking.swift`
- Create: `SocialFusion/Services/PositionSyncService.swift`
- Create: `SocialFusionTests/TimelinePositionTests.swift`
- Create: `SocialFusionTests/FakeKeyValueStorageBacking.swift`
- Create: `SocialFusionTests/PositionSyncServiceTests.swift`
- Create: `SocialFusionTests/iCloudKVSBackingIntegrationTests.swift`
- Modify: `SocialFusion/SocialFusionApp.swift` (instantiate `PositionSyncService`, inject as `@EnvironmentObject`)
- Modify: `SocialFusion/Controllers/UnifiedTimelineController.swift` (record on settle, restore on hydrate)
- Modify: `project.yml` (add Key-Value Storage entitlement, register iCloud capability)
- Modify: `SocialFusion/SocialFusion.entitlements` (or create if absent — declare `com.apple.developer.ubiquity-kvstore-identifier`)

**Implementer assumptions to verify before each task:**

1. `SocialAccount` has `public let id: String` (verified in `SocialFusion/Models/SocialAccount.swift:112`). The account ID is the stable key for the `accountID` portion of the KVS key.
2. `SocialPlatform` is a `String`-backed enum with rawValues `"mastodon"` and `"bluesky"` (per `CLAUDE.md` MEMORY). For per-platform "all of platform X" feeds the timeline ID is the rawValue; for the unified feed it is `"unified"`; for pinned timelines (sibling plan) it is the pin's stable ID.
3. `SmartPositionManager` (at `SocialFusion/State/SmartPositionManager.swift`) is the existing in-session scroll-history tracker. It already has a half-built CloudKit path that is **disabled** (`self.cloudContainer = nil` at line 29). This plan does **not** revive that path — `PositionSyncService` is the new cross-device layer and `SmartPositionManager` stays in-session-only. The integration point is `UnifiedTimelineController` calling both layers.
4. `UnifiedTimelineController` already publishes `restorationAnchor: String?` (line 24) and assigns it at line 214. That anchor is what `PositionSyncService` will write into KVS on settle and read out of KVS on hydrate.
5. The test target is `SocialFusionTests`. Tests subclass `XCTestCase`. `@MainActor`-isolated tests use `@MainActor final class … : XCTestCase`.
6. **iCloud entitlement is not yet configured for this app.** Before Task 9 ships, the implementer must:
   - In Apple Developer portal, enable iCloud → Key-Value Storage for the `com.socialfusionapp.app` App ID.
   - In `project.yml`, add the `com.apple.developer.icloud-services` (`["CloudKit"]` is **not** required — only `["KeyValueStorage"]`) and `com.apple.developer.ubiquity-kvstore-identifier` (default `$(TeamIdentifierPrefix)com.socialfusionapp.app`) to the SocialFusion target.
   - Run `xcodegen` to regenerate `project.pbxproj` per `CLAUDE.md`.
   - Verify the entitlements file is signed into the build (the build log must show "Code Signing Entitlements" pointing at the file).
   - On real-device sync verification (Task 10), both Frank's iPhone 17 Pro and iPad Pro must be signed into the same iCloud account with iCloud Drive enabled.

---

## Task 1: TimelinePosition model

**Files:**
- Create: `SocialFusion/Models/TimelinePosition.swift`
- Test: `SocialFusionTests/TimelinePositionTests.swift`

The Codable record that flows in and out of KVS. Carries everything we need to restore: which post the user last reached, when, and (optionally) the fine-grained scroll offset.

- [ ] **Step 1: Write the failing tests**

Create `SocialFusionTests/TimelinePositionTests.swift`:

```swift
import XCTest
@testable import SocialFusion

final class TimelinePositionTests: XCTestCase {
    func testRoundTripsThroughJSON() throws {
        let original = TimelinePosition(
            lastReadPostID: "post-123",
            lastReadAt: Date(timeIntervalSince1970: 1_715_000_000),
            scrollOffset: 240.5
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TimelinePosition.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testScrollOffsetIsOptional() throws {
        let p = TimelinePosition(
            lastReadPostID: "post-1",
            lastReadAt: Date(),
            scrollOffset: nil
        )
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(TimelinePosition.self, from: data)
        XCTAssertNil(decoded.scrollOffset)
        XCTAssertEqual(decoded.lastReadPostID, "post-1")
    }

    func testKeyComposition() {
        XCTAssertEqual(
            TimelinePosition.kvsKey(accountID: "acct-1", timelineID: "unified"),
            "pos.acct-1.unified"
        )
        XCTAssertEqual(
            TimelinePosition.kvsKey(accountID: "acct-1", timelineID: "mastodon"),
            "pos.acct-1.mastodon"
        )
    }

    func testIsNewerThanComparesByLastReadAt() {
        let older = TimelinePosition(
            lastReadPostID: "a", lastReadAt: Date(timeIntervalSince1970: 1000), scrollOffset: nil
        )
        let newer = TimelinePosition(
            lastReadPostID: "b", lastReadAt: Date(timeIntervalSince1970: 2000), scrollOffset: nil
        )
        XCTAssertTrue(newer.isNewer(than: older))
        XCTAssertFalse(older.isNewer(than: newer))
        XCTAssertFalse(newer.isNewer(than: newer))
    }

    func testIsWithinDeadbandTrueIfBothPositionsAgreeWithin30Seconds() {
        let base = Date(timeIntervalSince1970: 1_715_000_000)
        let a = TimelinePosition(lastReadPostID: "x", lastReadAt: base, scrollOffset: nil)
        let b = TimelinePosition(
            lastReadPostID: "x",
            lastReadAt: base.addingTimeInterval(20),
            scrollOffset: nil
        )
        XCTAssertTrue(a.isWithinDeadband(of: b))
    }

    func testIsWithinDeadbandFalseIfPostIDsDiffer() {
        let now = Date()
        let a = TimelinePosition(lastReadPostID: "x", lastReadAt: now, scrollOffset: nil)
        let b = TimelinePosition(lastReadPostID: "y", lastReadAt: now, scrollOffset: nil)
        XCTAssertFalse(a.isWithinDeadband(of: b))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/TimelinePositionTests`
Expected: FAIL — `TimelinePosition` not defined.

- [ ] **Step 3: Implement the model**

Create `SocialFusion/Models/TimelinePosition.swift`:

```swift
import Foundation

/// A cross-device record of where the user last left a given timeline.
///
/// Stored as a single JSON-encoded value per `(accountID, timelineID)` key in
/// `NSUbiquitousKeyValueStore`. Designed to stay well under 1 KB so the
/// 1 MB total KVS budget can comfortably hold hundreds of timelines.
public struct TimelinePosition: Codable, Hashable {
    /// ID of the topmost post the user had read when the timeline last settled.
    public let lastReadPostID: String

    /// Timestamp the position was recorded. Authoritative for last-write-wins merge.
    public let lastReadAt: Date

    /// Optional fine-grained scroll offset in points, relative to `lastReadPostID`.
    /// Nil when only the anchor post is known.
    public let scrollOffset: Double?

    public init(lastReadPostID: String, lastReadAt: Date, scrollOffset: Double?) {
        self.lastReadPostID = lastReadPostID
        self.lastReadAt = lastReadAt
        self.scrollOffset = scrollOffset
    }

    /// Composes the canonical KVS key for an `(accountID, timelineID)` pair.
    public static func kvsKey(accountID: String, timelineID: String) -> String {
        "pos.\(accountID).\(timelineID)"
    }

    /// True when `self.lastReadAt > other.lastReadAt`.
    public func isNewer(than other: TimelinePosition) -> Bool {
        lastReadAt > other.lastReadAt
    }

    /// True when both positions point to the same post and were recorded
    /// within 30 seconds of each other. Used to suppress no-op jumps when a
    /// remote update arrives that essentially agrees with local state.
    public func isWithinDeadband(of other: TimelinePosition, seconds: TimeInterval = 30) -> Bool {
        lastReadPostID == other.lastReadPostID
            && abs(lastReadAt.timeIntervalSince(other.lastReadAt)) <= seconds
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/TimelinePositionTests`
Expected: PASS, all 6 tests green.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Models/TimelinePosition.swift SocialFusionTests/TimelinePositionTests.swift
git commit -m "feat(position-sync): add TimelinePosition model + KVS key composition"
```

---

## Task 2: KeyValueStorageBacking protocol + fake

**Files:**
- Create: `SocialFusion/Services/KeyValueStorageBacking.swift`
- Create: `SocialFusionTests/FakeKeyValueStorageBacking.swift`

Abstract the `NSUbiquitousKeyValueStore` so unit tests don't talk to iCloud. Real implementation lives in this file too (`iCloudKVSBacking`); a `FakeKeyValueStorageBacking` for tests lives in the test target.

- [ ] **Step 1: Implement the protocol + real backing**

Create `SocialFusion/Services/KeyValueStorageBacking.swift`:

```swift
import Foundation

/// Abstraction over a key-value blob store with external-change notifications.
///
/// Production binds to `NSUbiquitousKeyValueStore`; tests bind to an in-memory
/// fake. All access is expected to be on the main actor — `PositionSyncService`
/// enforces that contract.
public protocol KeyValueStorageBacking: AnyObject {
    /// Reads the raw Data for a key. Nil if the key is unset.
    func data(forKey key: String) -> Data?

    /// Writes raw Data for a key.
    func set(_ data: Data?, forKey key: String)

    /// Removes a key entirely (used when trimming to stay under the 1 MB cap).
    func removeObject(forKey key: String)

    /// Returns every currently known key in the store. Used for trimming.
    func allKeys() -> [String]

    /// Synchronously requests the store flush pending writes. Returns true on success.
    @discardableResult
    func synchronize() -> Bool

    /// Approximate total size of all stored values + keys in bytes. Used to
    /// detect when we're approaching the 1 MB KVS budget.
    func approximateByteCount() -> Int

    /// Registers a handler called when iCloud reports an externally-pushed
    /// change. Handler receives the array of changed keys (may be empty when
    /// the cause is `accountChange` or `quotaViolationChange`).
    func observeExternalChanges(
        _ handler: @escaping (_ changedKeys: [String], _ reason: ExternalChangeReason) -> Void
    )
}

/// Why an external-change notification fired. Mirrors
/// `NSUbiquitousKeyValueStore.ChangeReason` so callers don't have to import Foundation directly.
public enum ExternalChangeReason {
    case serverChange
    case initialSyncChange
    case quotaViolationChange
    case accountChange
    case unknown
}

/// Real backing wrapped around `NSUbiquitousKeyValueStore`.
public final class iCloudKVSBacking: KeyValueStorageBacking {
    private let store: NSUbiquitousKeyValueStore
    private var observer: NSObjectProtocol?

    public init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func data(forKey key: String) -> Data? {
        store.data(forKey: key)
    }

    public func set(_ data: Data?, forKey key: String) {
        store.set(data, forKey: key)
    }

    public func removeObject(forKey key: String) {
        store.removeObject(forKey: key)
    }

    public func allKeys() -> [String] {
        store.dictionaryRepresentation.keys.map(String.init)
    }

    @discardableResult
    public func synchronize() -> Bool {
        store.synchronize()
    }

    public func approximateByteCount() -> Int {
        var total = 0
        for (key, value) in store.dictionaryRepresentation {
            total += key.utf8.count
            if let d = value as? Data {
                total += d.count
            } else if let s = value as? String {
                total += s.utf8.count
            } else {
                // Fall back to a rough estimate for primitives.
                total += 16
            }
        }
        return total
    }

    public func observeExternalChanges(
        _ handler: @escaping ([String], ExternalChangeReason) -> Void
    ) {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { note in
            let changedKeys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey]
                as? [String] ?? []
            let rawReason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            let reason: ExternalChangeReason = {
                switch rawReason {
                case NSUbiquitousKeyValueStoreServerChange: return .serverChange
                case NSUbiquitousKeyValueStoreInitialSyncChange: return .initialSyncChange
                case NSUbiquitousKeyValueStoreQuotaViolationChange: return .quotaViolationChange
                case NSUbiquitousKeyValueStoreAccountChange: return .accountChange
                default: return .unknown
                }
            }()
            handler(changedKeys, reason)
        }
        // Per Apple docs: prompt the store to fetch on first observation.
        store.synchronize()
    }
}
```

- [ ] **Step 2: Create the test fake**

Create `SocialFusionTests/FakeKeyValueStorageBacking.swift`:

```swift
import Foundation
@testable import SocialFusion

/// In-memory implementation of `KeyValueStorageBacking` for unit tests.
/// Lets tests simulate external changes by calling `simulateExternalChange(_:reason:)`.
public final class FakeKeyValueStorageBacking: KeyValueStorageBacking {
    private var storage: [String: Data] = [:]
    private var externalChangeHandler: (([String], ExternalChangeReason) -> Void)?

    public private(set) var synchronizeCallCount = 0
    public private(set) var setCallCount = 0

    public init() {}

    public func data(forKey key: String) -> Data? { storage[key] }

    public func set(_ data: Data?, forKey key: String) {
        setCallCount += 1
        if let data {
            storage[key] = data
        } else {
            storage.removeValue(forKey: key)
        }
    }

    public func removeObject(forKey key: String) { storage.removeValue(forKey: key) }

    public func allKeys() -> [String] { Array(storage.keys) }

    @discardableResult
    public func synchronize() -> Bool {
        synchronizeCallCount += 1
        return true
    }

    public func approximateByteCount() -> Int {
        storage.reduce(0) { $0 + $1.key.utf8.count + $1.value.count }
    }

    public func observeExternalChanges(
        _ handler: @escaping ([String], ExternalChangeReason) -> Void
    ) {
        externalChangeHandler = handler
    }

    /// Writes a value directly into storage and fires the external-change
    /// handler — simulating a push from another device.
    public func simulateExternalChange(
        key: String,
        data: Data?,
        reason: ExternalChangeReason = .serverChange
    ) {
        if let data {
            storage[key] = data
        } else {
            storage.removeValue(forKey: key)
        }
        externalChangeHandler?([key], reason)
    }
}
```

- [ ] **Step 3: Verify build**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED. (No tests yet — they come in Task 3.)

- [ ] **Step 4: Commit**

```bash
git add SocialFusion/Services/KeyValueStorageBacking.swift SocialFusionTests/FakeKeyValueStorageBacking.swift
git commit -m "feat(position-sync): add KeyValueStorageBacking protocol + iCloud + fake impls"
```

---

## Task 3: PositionSyncService — read/write happy path

**Files:**
- Create: `SocialFusion/Services/PositionSyncService.swift`
- Create: `SocialFusionTests/PositionSyncServiceTests.swift`

The service that owns the in-memory cache and routes through the backing. Start with the simplest behavior: write goes to the backing, read comes back from cache.

- [ ] **Step 1: Write the failing tests**

Create `SocialFusionTests/PositionSyncServiceTests.swift`:

```swift
import XCTest
@testable import SocialFusion

@MainActor
final class PositionSyncServiceTests: XCTestCase {
    func testRecordPositionWritesToBacking() {
        let backing = FakeKeyValueStorageBacking()
        let service = PositionSyncService(backing: backing, clock: { Date(timeIntervalSince1970: 1000) })

        service.recordPosition(
            accountID: "acct-1",
            timelineID: "unified",
            postID: "post-A",
            scrollOffset: 100,
            now: Date(timeIntervalSince1970: 1000)
        )
        service.flushPendingWrites()

        let key = "pos.acct-1.unified"
        XCTAssertNotNil(backing.data(forKey: key))
        let decoded = try? JSONDecoder().decode(
            TimelinePosition.self, from: XCTUnwrap(backing.data(forKey: key))
        )
        XCTAssertEqual(decoded?.lastReadPostID, "post-A")
        XCTAssertEqual(decoded?.scrollOffset, 100)
    }

    func testPositionForReturnsCachedRecord() {
        let backing = FakeKeyValueStorageBacking()
        let service = PositionSyncService(backing: backing)

        service.recordPosition(
            accountID: "acct-1", timelineID: "unified",
            postID: "post-A", scrollOffset: nil,
            now: Date(timeIntervalSince1970: 1000)
        )
        service.flushPendingWrites()

        let p = service.position(accountID: "acct-1", timelineID: "unified")
        XCTAssertEqual(p?.lastReadPostID, "post-A")
    }

    func testHydrateLoadsExistingKeysFromBacking() throws {
        let backing = FakeKeyValueStorageBacking()
        let existing = TimelinePosition(
            lastReadPostID: "pre-existing",
            lastReadAt: Date(timeIntervalSince1970: 999),
            scrollOffset: 12
        )
        let data = try JSONEncoder().encode(existing)
        backing.set(data, forKey: "pos.acct-1.mastodon")

        let service = PositionSyncService(backing: backing)
        service.hydrate()

        let p = service.position(accountID: "acct-1", timelineID: "mastodon")
        XCTAssertEqual(p?.lastReadPostID, "pre-existing")
    }

    func testKeysUnrelatedToPositionAreIgnoredDuringHydrate() throws {
        let backing = FakeKeyValueStorageBacking()
        backing.set(Data("not a position".utf8), forKey: "some.other.key")
        let service = PositionSyncService(backing: backing)
        service.hydrate() // must not crash or pollute the cache
        XCTAssertNil(service.position(accountID: "some", timelineID: "other"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/PositionSyncServiceTests`
Expected: FAIL — `PositionSyncService` not defined.

- [ ] **Step 3: Implement the service (happy path only — debounce + merge land in later tasks)**

Create `SocialFusion/Services/PositionSyncService.swift`:

```swift
import Combine
import Foundation
import SwiftUI

/// Cross-device timeline-position sync via `NSUbiquitousKeyValueStore`.
///
/// One record per `(accountID, timelineID)`. Reads/writes happen on MainActor.
/// Writes are debounced per-key to ≤1 every 3s (see Task 4). External pushes
/// from iCloud are merged last-write-wins on `lastReadAt` with a 30s deadband
/// (see Task 5). Total storage is defensively bounded to stay under the 1 MB
/// KVS budget (see Task 6).
@MainActor
public final class PositionSyncService: ObservableObject {
    /// All known positions keyed on the full KVS key (`pos.{accountID}.{timelineID}`).
    @Published public private(set) var positions: [String: TimelinePosition] = [:]

    /// Debounce window between successive writes to the same key.
    public let debounceInterval: TimeInterval

    /// Defensive ceiling — when total stored bytes pass this threshold, trim
    /// oldest entries until we're back below.
    public let storageBudgetBytes: Int

    private let backing: KeyValueStorageBacking
    private let clock: () -> Date

    /// Pending writes (key → most recent position) waiting for debounce window.
    private var pendingWrites: [String: TimelinePosition] = [:]
    /// Last time we flushed each key.
    private var lastFlushAt: [String: Date] = [:]
    /// One timer per pending key.
    private var flushTimers: [String: Timer] = [:]

    public init(
        backing: KeyValueStorageBacking = iCloudKVSBacking(),
        debounceInterval: TimeInterval = 3.0,
        storageBudgetBytes: Int = 900_000, // leave headroom below the 1 MB hard cap
        clock: @escaping () -> Date = Date.init
    ) {
        self.backing = backing
        self.debounceInterval = debounceInterval
        self.storageBudgetBytes = storageBudgetBytes
        self.clock = clock
    }

    // MARK: - Public API

    /// Reads from the in-memory cache. Returns nil if no record exists.
    public func position(accountID: String, timelineID: String) -> TimelinePosition? {
        let key = TimelinePosition.kvsKey(accountID: accountID, timelineID: timelineID)
        return positions[key]
    }

    /// Records a new position. Will be flushed to the backing after the
    /// debounce window. `now` is exposed so tests can inject deterministic time.
    public func recordPosition(
        accountID: String,
        timelineID: String,
        postID: String,
        scrollOffset: Double?,
        now: Date? = nil
    ) {
        let timestamp = now ?? clock()
        let key = TimelinePosition.kvsKey(accountID: accountID, timelineID: timelineID)
        let new = TimelinePosition(
            lastReadPostID: postID,
            lastReadAt: timestamp,
            scrollOffset: scrollOffset
        )
        positions[key] = new
        scheduleFlush(key: key, position: new)
    }

    /// Hydrates the cache from whatever is currently in the backing. Call
    /// once on launch before any UI requests a position.
    public func hydrate() {
        for key in backing.allKeys() where key.hasPrefix("pos.") {
            guard let data = backing.data(forKey: key) else { continue }
            guard let decoded = try? JSONDecoder().decode(TimelinePosition.self, from: data) else {
                continue
            }
            positions[key] = decoded
        }
    }

    /// Forces an immediate flush of all pending writes. Used by tests and on
    /// app background.
    public func flushPendingWrites() {
        let snapshot = pendingWrites
        pendingWrites.removeAll()
        for (key, position) in snapshot {
            writeToBacking(key: key, position: position)
        }
        for timer in flushTimers.values { timer.invalidate() }
        flushTimers.removeAll()
    }

    // MARK: - Internals

    private func scheduleFlush(key: String, position: TimelinePosition) {
        pendingWrites[key] = position

        // If we've never flushed this key, or the debounce window has elapsed,
        // flush immediately. Otherwise schedule a deferred flush.
        let last = lastFlushAt[key] ?? .distantPast
        if clock().timeIntervalSince(last) >= debounceInterval {
            flush(key: key)
        } else {
            flushTimers[key]?.invalidate()
            flushTimers[key] = Timer.scheduledTimer(
                withTimeInterval: debounceInterval,
                repeats: false
            ) { [weak self] _ in
                Task { @MainActor in self?.flush(key: key) }
            }
        }
    }

    private func flush(key: String) {
        guard let position = pendingWrites.removeValue(forKey: key) else { return }
        writeToBacking(key: key, position: position)
        lastFlushAt[key] = clock()
        flushTimers[key]?.invalidate()
        flushTimers[key] = nil
    }

    private func writeToBacking(key: String, position: TimelinePosition) {
        guard let data = try? JSONEncoder().encode(position) else { return }
        backing.set(data, forKey: key)
        backing.synchronize()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/PositionSyncServiceTests`
Expected: PASS, 4 tests green.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Services/PositionSyncService.swift SocialFusionTests/PositionSyncServiceTests.swift
git commit -m "feat(position-sync): add PositionSyncService — record/hydrate happy path"
```

---

## Task 4: Debounce per-key writes to ≤1 per 3 seconds

**Files:**
- Modify: `SocialFusionTests/PositionSyncServiceTests.swift` (add debounce tests)
- The implementation in Task 3 already supports debounce — these tests verify it.

The spec says "Don't write position changes more than once per 3 seconds." Verify burst writes collapse to a single backing write.

- [ ] **Step 1: Write the failing tests**

Append to `SocialFusionTests/PositionSyncServiceTests.swift`:

```swift
extension PositionSyncServiceTests {
    func testBurstWritesCollapseToOneBackingWritePerKey() {
        let backing = FakeKeyValueStorageBacking()
        // Use a 3s debounce; drive time with an injected clock so the burst lands
        // inside the window.
        var now = Date(timeIntervalSince1970: 1000)
        let service = PositionSyncService(
            backing: backing,
            debounceInterval: 3.0,
            clock: { now }
        )

        // First write — passes through immediately (no prior flush).
        service.recordPosition(
            accountID: "acct-1", timelineID: "unified",
            postID: "p1", scrollOffset: nil, now: now
        )
        XCTAssertEqual(backing.setCallCount, 1, "First write should flush immediately.")

        // Five more writes within the debounce window — must not flush.
        for i in 2...6 {
            now = now.addingTimeInterval(0.4)
            service.recordPosition(
                accountID: "acct-1", timelineID: "unified",
                postID: "p\(i)", scrollOffset: nil, now: now
            )
        }
        XCTAssertEqual(backing.setCallCount, 1,
                       "Burst writes within debounce window must coalesce.")

        // Force the flush and verify the *latest* value won.
        service.flushPendingWrites()
        XCTAssertEqual(backing.setCallCount, 2)
        let decoded = try? JSONDecoder().decode(
            TimelinePosition.self,
            from: backing.data(forKey: "pos.acct-1.unified")!
        )
        XCTAssertEqual(decoded?.lastReadPostID, "p6",
                       "After flush, the most recent burst value must be persisted.")
    }

    func testWritesToDifferentKeysAreNotDebouncedAgainstEachOther() {
        let backing = FakeKeyValueStorageBacking()
        let now = Date(timeIntervalSince1970: 1000)
        let service = PositionSyncService(
            backing: backing, debounceInterval: 3.0, clock: { now }
        )

        service.recordPosition(
            accountID: "acct-1", timelineID: "unified",
            postID: "p1", scrollOffset: nil, now: now
        )
        service.recordPosition(
            accountID: "acct-1", timelineID: "mastodon",
            postID: "p2", scrollOffset: nil, now: now
        )

        // Both keys are fresh → both flush on first write.
        XCTAssertEqual(backing.setCallCount, 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/PositionSyncServiceTests`
Expected: PASS — Task 3's implementation already debounces correctly. (If these fail, fix `scheduleFlush` in `PositionSyncService.swift` before proceeding.)

- [ ] **Step 3: Commit**

```bash
git add SocialFusionTests/PositionSyncServiceTests.swift
git commit -m "test(position-sync): verify per-key 3s debounce of writes"
```

---

## Task 5: Merge external changes with last-write-wins + 30s deadband

**Files:**
- Modify: `SocialFusion/Services/PositionSyncService.swift` (subscribe to external changes, implement merge)
- Modify: `SocialFusionTests/PositionSyncServiceTests.swift` (add merge tests)

When iCloud pushes a remote change, merge into local state by `lastReadAt`. If local and remote agree on `lastReadPostID` within 30 seconds, keep local (no scroll jump).

- [ ] **Step 1: Write the failing tests**

Append to `SocialFusionTests/PositionSyncServiceTests.swift`:

```swift
extension PositionSyncServiceTests {
    func testExternalChangeWithNewerTimestampReplacesLocal() throws {
        let backing = FakeKeyValueStorageBacking()
        let service = PositionSyncService(backing: backing)

        // Local: post-A at t=1000
        service.recordPosition(
            accountID: "acct-1", timelineID: "unified",
            postID: "post-A", scrollOffset: nil,
            now: Date(timeIntervalSince1970: 1000)
        )
        service.flushPendingWrites()
        service.startObservingExternalChanges()

        // Simulate a push from another device: post-B at t=2000.
        let remote = TimelinePosition(
            lastReadPostID: "post-B",
            lastReadAt: Date(timeIntervalSince1970: 2000),
            scrollOffset: nil
        )
        let data = try JSONEncoder().encode(remote)
        backing.simulateExternalChange(key: "pos.acct-1.unified", data: data)

        XCTAssertEqual(
            service.position(accountID: "acct-1", timelineID: "unified")?.lastReadPostID,
            "post-B",
            "Newer remote position must win."
        )
    }

    func testExternalChangeWithOlderTimestampIsDiscarded() throws {
        let backing = FakeKeyValueStorageBacking()
        let service = PositionSyncService(backing: backing)

        service.recordPosition(
            accountID: "acct-1", timelineID: "unified",
            postID: "post-A", scrollOffset: nil,
            now: Date(timeIntervalSince1970: 2000)
        )
        service.flushPendingWrites()
        service.startObservingExternalChanges()

        let stale = TimelinePosition(
            lastReadPostID: "post-OLD",
            lastReadAt: Date(timeIntervalSince1970: 1000),
            scrollOffset: nil
        )
        let data = try JSONEncoder().encode(stale)
        backing.simulateExternalChange(key: "pos.acct-1.unified", data: data)

        XCTAssertEqual(
            service.position(accountID: "acct-1", timelineID: "unified")?.lastReadPostID,
            "post-A",
            "Older remote position must be discarded."
        )
    }

    func testExternalChangeWithinDeadbandDoesNotPublishChange() throws {
        let backing = FakeKeyValueStorageBacking()
        let service = PositionSyncService(backing: backing)

        // Local: post-A at t=1000
        service.recordPosition(
            accountID: "acct-1", timelineID: "unified",
            postID: "post-A", scrollOffset: nil,
            now: Date(timeIntervalSince1970: 1000)
        )
        service.flushPendingWrites()
        service.startObservingExternalChanges()

        var publishCount = 0
        let cancellable = service.externalUpdatesPublisher.sink { _ in publishCount += 1 }

        // Remote: same post, 20 seconds later → deadband → no publish.
        let nearby = TimelinePosition(
            lastReadPostID: "post-A",
            lastReadAt: Date(timeIntervalSince1970: 1020),
            scrollOffset: nil
        )
        let data = try JSONEncoder().encode(nearby)
        backing.simulateExternalChange(key: "pos.acct-1.unified", data: data)

        XCTAssertEqual(publishCount, 0, "Deadband suppresses publish of near-identical positions.")
        cancellable.cancel()
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the same `PositionSyncServiceTests` target.
Expected: FAIL — `startObservingExternalChanges()` and `externalUpdatesPublisher` don't exist yet.

- [ ] **Step 3: Extend the service**

Insert into `SocialFusion/Services/PositionSyncService.swift` (after the existing public API section):

```swift
extension PositionSyncService {
    /// Emits an event each time a remote push results in an actually-applied
    /// local change (after deadband). Use this in UI code to know when to
    /// silently re-anchor scroll.
    public struct ExternalUpdate {
        public let accountID: String
        public let timelineID: String
        public let position: TimelinePosition
    }
}

// MARK: - External-change observation

@MainActor
extension PositionSyncService {
    /// Subscribers to remote-push merges. Stored as a Combine subject so the
    /// view layer can react without owning a delegate.
    public var externalUpdatesPublisher: AnyPublisher<ExternalUpdate, Never> {
        externalUpdatesSubject.eraseToAnyPublisher()
    }

    /// Begin observing external KVS changes. Safe to call multiple times —
    /// only the first call subscribes; subsequent calls no-op.
    public func startObservingExternalChanges() {
        guard !hasStartedObserving else { return }
        hasStartedObserving = true
        backing.observeExternalChanges { [weak self] keys, reason in
            Task { @MainActor in
                self?.handleExternalChange(keys: keys, reason: reason)
            }
        }
    }

    private func handleExternalChange(keys: [String], reason: ExternalChangeReason) {
        // Account changes invalidate everything — clear the cache and bail.
        if reason == .accountChange {
            positions.removeAll()
            return
        }
        for key in keys where key.hasPrefix("pos.") {
            mergeExternal(key: key)
        }
    }

    private func mergeExternal(key: String) {
        guard let data = backing.data(forKey: key),
              let remote = try? JSONDecoder().decode(TimelinePosition.self, from: data)
        else { return }

        if let local = positions[key] {
            // Deadband: same post, within 30s → no-op (suppress scroll micro-jump).
            if local.isWithinDeadband(of: remote) { return }
            // Last-write-wins.
            guard remote.isNewer(than: local) else { return }
        }
        positions[key] = remote
        if let parsed = Self.parseKey(key) {
            externalUpdatesSubject.send(ExternalUpdate(
                accountID: parsed.accountID,
                timelineID: parsed.timelineID,
                position: remote
            ))
        }
    }

    /// Parses `pos.{accountID}.{timelineID}`. Returns nil for malformed keys
    /// or keys whose `accountID` itself contains a literal `.` (we use a
    /// rsplit so trailing segments after the *first* dot become the timelineID
    /// only if the accountID is a single segment — accounts use UUID-like IDs
    /// without dots, so this is safe in practice).
    static func parseKey(_ key: String) -> (accountID: String, timelineID: String)? {
        guard key.hasPrefix("pos.") else { return nil }
        let trimmed = String(key.dropFirst("pos.".count))
        guard let dot = trimmed.firstIndex(of: ".") else { return nil }
        let accountID = String(trimmed[..<dot])
        let timelineID = String(trimmed[trimmed.index(after: dot)...])
        guard !accountID.isEmpty, !timelineID.isEmpty else { return nil }
        return (accountID, timelineID)
    }
}
```

And add the supporting stored properties near the top of the class, just under the existing private properties:

```swift
private var hasStartedObserving = false
private let externalUpdatesSubject = PassthroughSubject<ExternalUpdate, Never>()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/PositionSyncServiceTests`
Expected: PASS, all merge + previous tests green.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Services/PositionSyncService.swift SocialFusionTests/PositionSyncServiceTests.swift
git commit -m "feat(position-sync): merge external changes — last-write-wins with 30s deadband"
```

---

## Task 6: Defensive trimming when approaching the 1 MB KVS budget

**Files:**
- Modify: `SocialFusion/Services/PositionSyncService.swift` (trim oldest entries before write when over budget)
- Modify: `SocialFusionTests/PositionSyncServiceTests.swift` (add budget tests)

Apple's KVS has a 1 MB hard cap. Each `TimelinePosition` is < 1 KB so we have plenty of headroom for hundreds of timelines, but defensively trim when we're approaching the budget — log a warning, drop the oldest entries until we're back under 90% of the soft ceiling.

- [ ] **Step 1: Write the failing tests**

Append to `SocialFusionTests/PositionSyncServiceTests.swift`:

```swift
extension PositionSyncServiceTests {
    func testTrimsOldestEntriesWhenOverBudget() throws {
        let backing = FakeKeyValueStorageBacking()
        // Set a tiny budget so we can trigger trimming with a handful of entries.
        let service = PositionSyncService(
            backing: backing,
            debounceInterval: 0,         // flush immediately for this test
            storageBudgetBytes: 400      // ~3-4 entries fit
        )

        // Insert 6 entries with monotonically-increasing timestamps.
        for i in 1...6 {
            service.recordPosition(
                accountID: "acct-\(i)", timelineID: "unified",
                postID: "p\(i)", scrollOffset: nil,
                now: Date(timeIntervalSince1970: TimeInterval(i * 100))
            )
        }
        service.flushPendingWrites()

        // Service must have trimmed at least one entry to stay under budget.
        let remainingKeys = backing.allKeys().filter { $0.hasPrefix("pos.") }
        XCTAssertLessThan(remainingKeys.count, 6,
                          "Service must trim at least one entry when over budget.")

        // The trimmed entries must be the *oldest* — newest entry survives.
        XCTAssertTrue(remainingKeys.contains("pos.acct-6.unified"),
                      "Newest entry must always survive trimming.")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the `PositionSyncServiceTests` target.
Expected: FAIL — no trimming logic exists yet.

- [ ] **Step 3: Add trimming to the write path**

In `SocialFusion/Services/PositionSyncService.swift`, modify `writeToBacking(key:position:)` and add a private `trimIfNeeded()`:

```swift
private func writeToBacking(key: String, position: TimelinePosition) {
    guard let data = try? JSONEncoder().encode(position) else { return }
    backing.set(data, forKey: key)
    trimIfNeeded(protectedKey: key)
    backing.synchronize()
}

private func trimIfNeeded(protectedKey: String) {
    var bytes = backing.approximateByteCount()
    guard bytes > storageBudgetBytes else { return }

    #if DEBUG
    print("⚠️ PositionSyncService approaching KVS budget: \(bytes) bytes. Trimming.")
    #endif

    // Collect all position keys with their `lastReadAt` so we can drop oldest first.
    var candidates: [(key: String, when: Date)] = backing.allKeys()
        .filter { $0.hasPrefix("pos.") && $0 != protectedKey }
        .compactMap { key in
            guard let data = backing.data(forKey: key),
                  let p = try? JSONDecoder().decode(TimelinePosition.self, from: data)
            else { return nil }
            return (key, p.lastReadAt)
        }
    candidates.sort { $0.when < $1.when } // oldest first

    while bytes > Int(Double(storageBudgetBytes) * 0.9), let oldest = candidates.first {
        backing.removeObject(forKey: oldest.key)
        positions.removeValue(forKey: oldest.key)
        candidates.removeFirst()
        bytes = backing.approximateByteCount()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/PositionSyncServiceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Services/PositionSyncService.swift SocialFusionTests/PositionSyncServiceTests.swift
git commit -m "feat(position-sync): trim oldest entries when approaching 1 MB KVS budget"
```

---

## Task 7: Inject `PositionSyncService` at app root + hydrate on launch

**Files:**
- Modify: `SocialFusion/SocialFusionApp.swift`

Wire the service into the SwiftUI environment so views and controllers can pick it up. Hydrate on cold launch, start observing external changes once, flush on background.

- [ ] **Step 1: Add the state object + injection**

In `SocialFusion/SocialFusionApp.swift`, alongside the other `@StateObject`s in the `@main` `SocialFusionApp` struct, add:

```swift
@StateObject private var positionSyncService = PositionSyncService()
```

Inject into the environment near the other `.environmentObject(...)` modifiers on the root view:

```swift
.environmentObject(positionSyncService)
```

Hydrate on first appearance and wire scene-phase handling. Add this modifier chain near the root view (or extend the existing `onAppear` + `onChange(of: scenePhase)` blocks if they already exist):

```swift
.onAppear {
    positionSyncService.hydrate()
    positionSyncService.startObservingExternalChanges()
}
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .background || newPhase == .inactive {
        positionSyncService.flushPendingWrites()
    }
}
```

(If `scenePhase` isn't already imported via `@Environment(\.scenePhase)`, add it.)

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Smoke test — verify hydrate runs**

Temporarily add a `print("🟣 PositionSyncService hydrated \(positions.count) entries")` at the end of `hydrate()`. Boot the app on the simulator, sign in, scroll, kill, relaunch — verify the console emits the hydrate log with the right count.

Remove the print before committing.

- [ ] **Step 4: Commit**

```bash
git add SocialFusion/SocialFusionApp.swift
git commit -m "feat(position-sync): inject PositionSyncService at app root + hydrate on launch"
```

---

## Task 8: Integrate `UnifiedTimelineController` with the sync service

**Files:**
- Modify: `SocialFusion/Controllers/UnifiedTimelineController.swift`

`UnifiedTimelineController` already tracks `restorationAnchor: String?` and assigns it as the user scrolls (lines 24 and 214). Two new responsibilities:

1. On scroll settle, call `positionSyncService.recordPosition(...)` with the current anchor.
2. On hydration after launch (or on external-update from another device), seed `restorationAnchor` from the service so the scroll view restores to that anchor.

`SmartPositionManager` stays the in-session source — `PositionSyncService` is the cross-device layer.

- [ ] **Step 1: Add the dependency**

Add a non-published property near the existing `private let serviceManager: SocialServiceManager`:

```swift
private let positionSyncService: PositionSyncService?
```

Extend the initializer signature. Existing call sites pass `nil` for the optional and continue working:

```swift
init(serviceManager: SocialServiceManager, positionSyncService: PositionSyncService? = nil) {
    self.serviceManager = serviceManager
    self.positionSyncService = positionSyncService
    self.actionStore = serviceManager.postActionStore
    self.actionCoordinator = serviceManager.postActionCoordinator
    self.relationshipStore = serviceManager.relationshipStore
    self.timelineContextProvider = serviceManager.timelineContextProvider
    setupBindings()
    setupPositionSyncBindings()
}
```

Update the construction sites that need cross-device sync (typically `ContentView` or wherever the controller is built) to inject the service from the environment:

```swift
@EnvironmentObject private var positionSyncService: PositionSyncService
// ...
UnifiedTimelineController(
    serviceManager: serviceManager,
    positionSyncService: positionSyncService
)
```

- [ ] **Step 2: Record on scroll settle**

Locate the existing site that updates `restorationAnchor` (around line 214). Replace it (or add a sibling call) with:

```swift
self.restorationAnchor = anchorId
recordPositionToSync(anchorID: anchorId)
```

Add the helper:

```swift
private func recordPositionToSync(anchorID: String?) {
    guard let anchorID,
          let accountID = activeAccountIDForSync(),
          let timelineID = activeTimelineIDForSync()
    else { return }
    positionSyncService?.recordPosition(
        accountID: accountID,
        timelineID: timelineID,
        postID: anchorID,
        scrollOffset: nil
    )
}

/// The active account ID this controller is reporting for. For the unified
/// feed we use the literal "unified" timelineID and the primary account ID;
/// for per-platform feeds the account associated with that platform.
private func activeAccountIDForSync() -> String? {
    serviceManager.primaryAccountID
}

/// The timeline ID composes the second segment of the KVS key. Returns
/// "unified" for the default feed, or the platform rawValue for an
/// all-of-platform feed. Pinned timelines (sibling plan) substitute the
/// pin's stable ID here.
private func activeTimelineIDForSync() -> String {
    "unified"
}
```

> If `serviceManager.primaryAccountID` doesn't exist, add it as a one-liner computed property on `SocialServiceManager` returning the first signed-in account's ID. Match the existing access pattern in that file.

- [ ] **Step 3: Hydrate restorationAnchor from the service on first load**

Inside `setupBindings()` (or a new `setupPositionSyncBindings()`), after the existing subscription:

```swift
private func setupPositionSyncBindings() {
    guard let positionSyncService else { return }

    // On first non-empty posts list, if we don't yet have an in-session anchor,
    // seed from the cross-device service.
    $posts
        .filter { !$0.isEmpty }
        .first()
        .sink { [weak self] _ in
            guard let self,
                  self.restorationAnchor == nil,
                  let accountID = self.activeAccountIDForSync()
            else { return }
            let saved = positionSyncService.position(
                accountID: accountID,
                timelineID: self.activeTimelineIDForSync()
            )
            if let saved {
                self.restorationAnchor = saved.lastReadPostID
            }
        }
        .store(in: &cancellables)

    // React to remote pushes from another device.
    positionSyncService.externalUpdatesPublisher
        .filter { [weak self] update in
            guard let self else { return false }
            return update.accountID == self.activeAccountIDForSync()
                && update.timelineID == self.activeTimelineIDForSync()
        }
        .sink { [weak self] update in
            // Only re-anchor if the post is actually present in the loaded buffer.
            // Otherwise the next pagination will pick it up.
            guard let self,
                  self.posts.contains(where: { $0.id == update.position.lastReadPostID })
            else { return }
            self.restorationAnchor = update.position.lastReadPostID
        }
        .store(in: &cancellables)
}
```

- [ ] **Step 4: Verify build**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add SocialFusion/Controllers/UnifiedTimelineController.swift SocialFusion/Services/SocialServiceManager.swift
git commit -m "feat(position-sync): wire UnifiedTimelineController to PositionSyncService"
```

---

## Task 9: Configure iCloud entitlement + capability

**Files:**
- Modify: `project.yml` (add iCloud capability + entitlements file path)
- Create: `SocialFusion/SocialFusion.entitlements` (if not already present — see verification step)

Apple-mediated sync needs the Key-Value Storage entitlement. Without it, every `NSUbiquitousKeyValueStore` call silently no-ops and reads return nil.

- [ ] **Step 1: Verify whether an entitlements file already exists**

Search the repo: `find . -name "*.entitlements" -not -path "*/.git/*"`. If `SocialFusion.entitlements` exists, edit it. If not, create one.

- [ ] **Step 2: Set the entitlements**

`SocialFusion/SocialFusion.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudDocuments</string>
    </array>
    <key>com.apple.developer.ubiquity-kvstore-identifier</key>
    <string>$(TeamIdentifierPrefix)com.socialfusionapp.app</string>
</dict>
</plist>
```

> Note: "CloudDocuments" in the services array is the Apple-prescribed value that unlocks the Key-Value Store specifically. You do **not** need to also list "CloudKit" — this plan uses only `NSUbiquitousKeyValueStore`, not CloudKit. If the file already declares other entitlements (App Group, Keychain Sharing, etc.), preserve them and add only these two keys.

- [ ] **Step 3: Wire the entitlements file into `project.yml`**

Per CLAUDE.md, `project.yml` regenerates `project.pbxproj` in CI. Add under the SocialFusion target's settings:

```yaml
SocialFusion:
  settings:
    CODE_SIGN_ENTITLEMENTS: SocialFusion/SocialFusion.entitlements
```

(If `settings:` already exists, append the key.)

Run `xcodegen` to regenerate the project, then commit both `project.yml` and the regenerated `project.pbxproj`.

- [ ] **Step 4: Verify in Apple Developer portal**

This step is **manual** and must be performed by the implementer:

1. Sign in to `developer.apple.com`.
2. Identifiers → select `com.socialfusionapp.app`.
3. Enable iCloud → "Include CloudKit support" can stay off; "Key-Value Storage" is enabled implicitly by the entitlement.
4. Save. Regenerate the provisioning profile if Xcode prompts.

- [ ] **Step 5: Build for device + verify entitlements signed in**

Run: `xcodebuild build -scheme SocialFusion -destination "id=00008150-000139C63480401C"` (Frank's iPhone 17 Pro, per MEMORY.md).

Look in the build log for "Code Signing Entitlements" and confirm the path points to `SocialFusion/SocialFusion.entitlements`. The log should also show the `com.apple.developer.ubiquity-kvstore-identifier` value being embedded.

- [ ] **Step 6: Commit**

```bash
git add SocialFusion/SocialFusion.entitlements project.yml project.pbxproj
git commit -m "build: enable iCloud Key-Value Storage entitlement for position sync"
```

---

## Task 10: iCloudKVSBacking integration test + two-device smoke test

**Files:**
- Create: `SocialFusionTests/iCloudKVSBackingIntegrationTests.swift`

A thin integration test that exercises the real `NSUbiquitousKeyValueStore` against the simulator's iCloud sandbox. This test is **gated** — it only runs when the simulator is signed into iCloud, and it cleans up after itself.

- [ ] **Step 1: Write the integration test**

Create `SocialFusionTests/iCloudKVSBackingIntegrationTests.swift`:

```swift
import XCTest
@testable import SocialFusion

/// Integration test that exercises the real `NSUbiquitousKeyValueStore`.
/// Skipped when the simulator isn't signed into iCloud.
@MainActor
final class iCloudKVSBackingIntegrationTests: XCTestCase {
    private let testKey = "pos.test-acct.test-timeline"

    override func tearDown() async throws {
        NSUbiquitousKeyValueStore.default.removeObject(forKey: testKey)
        NSUbiquitousKeyValueStore.default.synchronize()
        try await super.tearDown()
    }

    func testRealKVSRoundTrip() throws {
        try XCTSkipIf(
            !isiCloudAvailable(),
            "iCloud not available in this simulator. Sign in to test."
        )

        let backing = iCloudKVSBacking()
        let position = TimelinePosition(
            lastReadPostID: "integration-post",
            lastReadAt: Date(),
            scrollOffset: 42
        )
        let data = try JSONEncoder().encode(position)
        backing.set(data, forKey: testKey)
        XCTAssertTrue(backing.synchronize())

        let readback = try XCTUnwrap(backing.data(forKey: testKey))
        let decoded = try JSONDecoder().decode(TimelinePosition.self, from: readback)
        XCTAssertEqual(decoded, position)
    }

    func testByteCountReturnsPositiveAfterWrite() throws {
        try XCTSkipIf(!isiCloudAvailable(), "iCloud not available.")
        let backing = iCloudKVSBacking()
        backing.set(Data("hello".utf8), forKey: testKey)
        backing.synchronize()
        XCTAssertGreaterThan(backing.approximateByteCount(), 0)
    }

    private func isiCloudAvailable() -> Bool {
        // Heuristic: write a probe, read it back, clean up. If the readback
        // is nil, KVS isn't functional (typically no iCloud signin).
        let probeKey = "kvs-probe.\(UUID().uuidString)"
        NSUbiquitousKeyValueStore.default.set("ok", forKey: probeKey)
        NSUbiquitousKeyValueStore.default.synchronize()
        let value = NSUbiquitousKeyValueStore.default.string(forKey: probeKey)
        NSUbiquitousKeyValueStore.default.removeObject(forKey: probeKey)
        NSUbiquitousKeyValueStore.default.synchronize()
        return value == "ok"
    }
}
```

- [ ] **Step 2: Run the integration test on a simulator signed into iCloud**

Sign the iPhone 17 Pro simulator into iCloud (Settings → Sign in to your iPhone). Then:

Run: `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/iCloudKVSBackingIntegrationTests`
Expected: PASS (or SKIP with a clear message if iCloud isn't configured).

- [ ] **Step 3: Manual two-device smoke test**

This is the real proof. Per MEMORY.md, Frank has an iPhone 17 Pro and an iPad Pro signed into the same iCloud account.

1. Install the app on both devices (`xcodebuild build -scheme SocialFusion -destination "id=00008150-000139C63480401C"` then again with the iPad UDID `00008027-000858493684002E`).
2. On the iPhone: scroll the unified timeline 20-30 posts down. Wait 5 seconds (well past the 3s debounce).
3. Background the app on the iPhone (forces `flushPendingWrites()` per Task 7).
4. Cold-launch the app on the iPad.
5. The iPad's unified timeline should restore to approximately the same anchor post the iPhone left off at.

Acceptance: the iPad lands within ±2 posts of the iPhone anchor.

If the iPad lands at the top, dump KVS state on both devices via the debug log added in Task 7 and confirm the keys are written/read as expected.

- [ ] **Step 4: Commit**

```bash
git add SocialFusionTests/iCloudKVSBackingIntegrationTests.swift
git commit -m "test(position-sync): real-KVS integration test + manual two-device verification"
```

---

## Acceptance gate before promoting to TestFlight

After all 10 tasks are complete:

1. **Full unit test suite passes:** `xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet` returns 0.
2. **iCloud entitlement confirmed:** build log shows the entitlements file is signed in, and the Apple Developer portal shows iCloud enabled for `com.socialfusionapp.app`.
3. **Two-device manual smoke test passes** (Task 10, Step 3): position recorded on iPhone → restored on iPad within ±2 posts, and vice-versa.
4. **Storage budget stays sane:** after 1 week of normal use, `backing.approximateByteCount()` (logged in DEBUG) reports < 10 KB total. If it's growing without bound, investigate.
5. **No new `AttributeGraph` warnings** in the Xcode console during normal scrolling.
6. **Quota violation handled gracefully:** in DEBUG, simulate `quotaViolationChange` (call `simulateExternalChange` with that reason in a debug-only menu) and confirm the app doesn't crash and logs a warning.
7. **Account-change handled gracefully:** signing out of iCloud on the device must not crash the app; positions silently fall back to in-session-only via `SmartPositionManager`.

---

## What's intentionally out of scope for this plan

The following live in sibling plans or future versions (see spec, "What's not in this spec"):

- **macOS sync** — the same `NSUbiquitousKeyValueStore` API works on macOS; v1.1 plan will add the Mac target and verify three-device sync.
- **Watched-conversation sync** — the Fuse plan (Task 17 of `2026-05-17-the-fuse-breakthrough.md`) says watched-conversation sync via KVS may piggyback here if budget allows; with our ~< 10 KB typical usage there's room. Track as a follow-up that *adds keys with a `watched.` prefix* using the same `KeyValueStorageBacking` abstraction, but ship the position-sync plan independently first.
- **Reviving the half-built `SmartPositionManager` CloudKit path** — explicitly out of scope. CloudKit is the wrong tool for tiny per-device state; KVS is what Apple recommends for exactly this use case. The CloudKit code in `SmartPositionManager.swift:316-433` should be **deleted in a separate cleanup commit** once `PositionSyncService` is shipping and verified, not as part of this plan.
- **Per-platform feed sync (`pos.{accountID}.mastodon`, `pos.{accountID}.bluesky`)** — the infrastructure supports it (the timeline ID is parameterized), but the v1.0 hook in `UnifiedTimelineController` only records `"unified"`. Per-platform recording lands when the platform-filter UI does.
- **Pinned timeline sync** — covered structurally (timeline ID can be any string), but the recorder side comes online with the pinnable-timelines plan.
- **Conflict UX** — if two devices write within the deadband, we silently use last-write-wins. The spec doesn't ask for a conflict prompt, and the deadband suppresses the visible cases. If complaints surface in beta, revisit.
- **Encryption beyond what iCloud provides** — iCloud KVS is end-to-end encrypted in the user's iCloud account by default. We add no additional encryption layer.

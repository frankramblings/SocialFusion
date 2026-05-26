import Combine
import XCTest
@testable import SocialFusion

@MainActor
final class PositionSyncServiceTests: XCTestCase {

    // MARK: - Task 3: record / hydrate happy path

    func testRecordPositionWritesToBacking() throws {
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
        let data = try XCTUnwrap(backing.data(forKey: key))
        let decoded = try JSONDecoder().decode(TimelinePosition.self, from: data)
        XCTAssertEqual(decoded.lastReadPostID, "post-A")
        XCTAssertEqual(decoded.scrollOffset, 100)
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

    func testKeysUnrelatedToPositionAreIgnoredDuringHydrate() {
        let backing = FakeKeyValueStorageBacking()
        backing.set(Data("not a position".utf8), forKey: "some.other.key")
        let service = PositionSyncService(backing: backing)
        service.hydrate() // must not crash or pollute the cache
        XCTAssertNil(service.position(accountID: "some", timelineID: "other"))
    }

    // MARK: - Task 4: debounce

    func testBurstWritesCollapseToOneBackingWritePerKey() throws {
        let backing = FakeKeyValueStorageBacking()
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

        service.flushPendingWrites()
        XCTAssertEqual(backing.setCallCount, 2)
        let data = try XCTUnwrap(backing.data(forKey: "pos.acct-1.unified"))
        let decoded = try JSONDecoder().decode(TimelinePosition.self, from: data)
        XCTAssertEqual(decoded.lastReadPostID, "p6",
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

    // MARK: - Task 5: external-change merge with deadband

    func testExternalChangeWithNewerTimestampReplacesLocal() async throws {
        let backing = FakeKeyValueStorageBacking()
        let service = PositionSyncService(backing: backing)

        service.recordPosition(
            accountID: "acct-1", timelineID: "unified",
            postID: "post-A", scrollOffset: nil,
            now: Date(timeIntervalSince1970: 1000)
        )
        service.flushPendingWrites()
        service.startObservingExternalChanges()

        let remote = TimelinePosition(
            lastReadPostID: "post-B",
            lastReadAt: Date(timeIntervalSince1970: 2000),
            scrollOffset: nil
        )
        let data = try JSONEncoder().encode(remote)
        backing.simulateExternalChange(key: "pos.acct-1.unified", data: data)

        // External change handler hops to MainActor via Task — let it run.
        await Task.yield()

        XCTAssertEqual(
            service.position(accountID: "acct-1", timelineID: "unified")?.lastReadPostID,
            "post-B",
            "Newer remote position must win."
        )
    }

    func testExternalChangeWithOlderTimestampIsDiscarded() async throws {
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

        await Task.yield()

        XCTAssertEqual(
            service.position(accountID: "acct-1", timelineID: "unified")?.lastReadPostID,
            "post-A",
            "Older remote position must be discarded."
        )
    }

    func testExternalChangeWithinDeadbandDoesNotPublishChange() async throws {
        let backing = FakeKeyValueStorageBacking()
        let service = PositionSyncService(backing: backing)

        service.recordPosition(
            accountID: "acct-1", timelineID: "unified",
            postID: "post-A", scrollOffset: nil,
            now: Date(timeIntervalSince1970: 1000)
        )
        service.flushPendingWrites()
        service.startObservingExternalChanges()

        var publishCount = 0
        let cancellable = service.externalUpdatesPublisher.sink { _ in publishCount += 1 }

        let nearby = TimelinePosition(
            lastReadPostID: "post-A",
            lastReadAt: Date(timeIntervalSince1970: 1020),
            scrollOffset: nil
        )
        let data = try JSONEncoder().encode(nearby)
        backing.simulateExternalChange(key: "pos.acct-1.unified", data: data)

        await Task.yield()

        XCTAssertEqual(publishCount, 0, "Deadband suppresses publish of near-identical positions.")
        cancellable.cancel()
    }

    // MARK: - Task 6: trimming

    func testTrimsOldestEntriesWhenOverBudget() {
        let backing = FakeKeyValueStorageBacking()
        // nil scrollOffset is omitted from JSON (encodeIfPresent), so each entry
        // is ~65 bytes (47-byte value + 18-byte key). 6 entries ≈ 390 bytes —
        // budget needs to be below that to force trimming.
        let service = PositionSyncService(
            backing: backing,
            debounceInterval: 0,
            storageBudgetBytes: 250
        )

        for i in 1...6 {
            service.recordPosition(
                accountID: "acct-\(i)", timelineID: "unified",
                postID: "p\(i)", scrollOffset: nil,
                now: Date(timeIntervalSince1970: TimeInterval(i * 100))
            )
        }
        service.flushPendingWrites()

        let remainingKeys = backing.allKeys().filter { $0.hasPrefix("pos.") }
        XCTAssertLessThan(remainingKeys.count, 6,
                          "Service must trim at least one entry when over budget.")
        XCTAssertTrue(remainingKeys.contains("pos.acct-6.unified"),
                      "Newest entry must always survive trimming.")
    }
}

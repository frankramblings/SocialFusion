import Combine
import Foundation
import SwiftUI

/// Cross-device timeline-position sync via `NSUbiquitousKeyValueStore`.
///
/// One record per `(accountID, timelineID)`. Reads/writes happen on MainActor.
/// Writes are debounced per-key to ≤1 every 3s. External pushes from iCloud
/// are merged last-write-wins on `lastReadAt` with a 30s deadband. Total
/// storage is defensively bounded to stay under the 1 MB KVS budget.
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

    private var hasStartedObserving = false
    private let externalUpdatesSubject = PassthroughSubject<ExternalUpdate, Never>()

    public init(
        backing: KeyValueStorageBacking = iCloudKVSBacking(),
        debounceInterval: TimeInterval = 3.0,
        storageBudgetBytes: Int = 900_000,
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
            lastFlushAt[key] = clock()
        }
        for timer in flushTimers.values { timer.invalidate() }
        flushTimers.removeAll()
    }

    // MARK: - Internals

    private func scheduleFlush(key: String, position: TimelinePosition) {
        pendingWrites[key] = position

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
        trimIfNeeded(protectedKey: key)
        backing.synchronize()
    }

    private func trimIfNeeded(protectedKey: String) {
        var bytes = backing.approximateByteCount()
        guard bytes > storageBudgetBytes else { return }

        #if DEBUG
        print("⚠️ PositionSyncService approaching KVS budget: \(bytes) bytes. Trimming.")
        #endif

        var candidates: [(key: String, when: Date)] = backing.allKeys()
            .filter { $0.hasPrefix("pos.") && $0 != protectedKey }
            .compactMap { key in
                guard let data = backing.data(forKey: key),
                      let p = try? JSONDecoder().decode(TimelinePosition.self, from: data)
                else { return nil }
                return (key, p.lastReadAt)
            }
        candidates.sort { $0.when < $1.when } // oldest first

        let ceiling = Int(Double(storageBudgetBytes) * 0.9)
        while bytes > ceiling, let oldest = candidates.first {
            backing.removeObject(forKey: oldest.key)
            positions.removeValue(forKey: oldest.key)
            candidates.removeFirst()
            bytes = backing.approximateByteCount()
        }
    }
}

// MARK: - External-change observation

extension PositionSyncService {
    /// Emitted each time a remote push results in an actually-applied local
    /// change (after deadband). Use this in UI code to know when to silently
    /// re-anchor scroll.
    public struct ExternalUpdate {
        public let accountID: String
        public let timelineID: String
        public let position: TimelinePosition
    }

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
            if local.isWithinDeadband(of: remote) { return }
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

    /// Parses `pos.{accountID}.{timelineID}`. Returns nil for malformed keys.
    /// Splits on the first `.` after the `pos.` prefix; account IDs are UUID-
    /// like (no embedded dots) so this is safe in practice.
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

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

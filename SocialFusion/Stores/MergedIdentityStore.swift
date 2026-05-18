import Combine
import Foundation

/// Side-channel store of detected and user-confirmed merged identities.
///
/// Keyed on each side's `(platform, accountID)` storage key so any UI surface
/// that holds a `UserProfile` can ask the store whether the profile is bound
/// to a twin on the other network. Follows the established pattern from
/// `PostActionStore` / `FusedMomentStore`.
///
/// Persistence: user-confirmed merges and explicit unmerges (tombstones)
/// persist to `UserDefaults`. Heuristic merges are recomputed each session
/// via `IdentityMatcher` and inserted with `insert(_:)`. Tombstones block
/// re-detection of a pair the user explicitly unmerged.
@MainActor
public final class MergedIdentityStore: ObservableObject {
    /// All known merges by their stable ID.
    @Published public private(set) var merges: [String: MergedIdentity] = [:]

    /// Index from per-side storage key → merge ID (both sides).
    private var sideToMerge: [String: String] = [:]

    /// IDs of merges the user explicitly unmerged. These block re-insertion
    /// from heuristic detection so the user's choice is respected.
    @Published public private(set) var tombstones: Set<String> = []

    private let userDefaults: UserDefaults
    private let defaultsKey: String

    private struct Persisted: Codable {
        var userConfirmed: [MergedIdentity]
        var tombstones: [String]
    }

    public init(
        userDefaults: UserDefaults = .standard,
        defaultsKey: String = "MergedIdentityStore.v1"
    ) {
        self.userDefaults = userDefaults
        self.defaultsKey = defaultsKey
        load()
    }

    // MARK: - Mutations

    /// Inserts a batch of merges (typically from the heuristic matcher).
    /// Idempotent. Merges whose `id` appears in `tombstones` are skipped.
    /// A pre-existing user-confirmed merge for the same side is never
    /// replaced by a heuristic merge.
    public func insert(_ batch: [MergedIdentity]) {
        for incoming in batch {
            if tombstones.contains(incoming.id) { continue }
            if let existingID = sideToMerge[incoming.mastodon.storageKey] ?? sideToMerge[incoming.bluesky.storageKey],
               let existing = merges[existingID],
               existing.provenance == .userConfirmed {
                continue
            }
            indexMerge(incoming)
        }
        objectWillChange.send()
    }

    /// Records a user-confirmed merge. Always wins over any heuristic merge
    /// previously stored for either side. Clears the tombstone for this pair
    /// if it existed.
    public func confirmMerge(mastodon: MergedIdentityKey, bluesky: MergedIdentityKey) {
        let merge = MergedIdentity(
            mastodon: mastodon,
            bluesky: bluesky,
            provenance: .userConfirmed,
            confidence: 1.0
        )
        // Evict any prior merge attached to either side.
        if let prior = sideToMerge[mastodon.storageKey], let priorMerge = merges[prior] {
            evictMerge(priorMerge)
        }
        if let prior = sideToMerge[bluesky.storageKey], let priorMerge = merges[prior] {
            evictMerge(priorMerge)
        }
        tombstones.remove(merge.id)
        indexMerge(merge)
        save()
        objectWillChange.send()
    }

    /// Removes a merge by ID and records a tombstone so heuristics can't
    /// re-add the same pair.
    public func unmerge(id: String) {
        guard let merge = merges[id] else { return }
        evictMerge(merge)
        tombstones.insert(id)
        save()
        objectWillChange.send()
    }

    // MARK: - Lookups

    public func merge(forPlatform platform: SocialPlatform, accountID: String) -> MergedIdentity? {
        let key = Self.storageKey(platform: platform, accountID: accountID)
        guard let mergeID = sideToMerge[key] else { return nil }
        return merges[mergeID]
    }

    /// Returns the twin key on the opposite network, or `nil` if no merge exists.
    public func twin(forPlatform platform: SocialPlatform, accountID: String) -> MergedIdentityKey? {
        guard let merge = merge(forPlatform: platform, accountID: accountID) else { return nil }
        return merge.twin(of: platform)
    }

    /// Returns a snapshot of all known merges.
    /// Order is unspecified (dictionary iteration order).
    public func allMerges() -> [MergedIdentity] {
        Array(merges.values)
    }

    /// All user-confirmed merges, used for the Settings management UI.
    public func userConfirmedMerges() -> [MergedIdentity] {
        merges.values.filter { $0.provenance == .userConfirmed }
    }

    // MARK: - Private

    /// Centralized storage-key construction. The lookup APIs build a key from
    /// `(platform, accountID)` without going through a full `MergedIdentityKey`
    /// (which would require a fake `handle`).
    private static func storageKey(platform: SocialPlatform, accountID: String) -> String {
        "\(platform.rawValue):\(accountID)"
    }

    private func indexMerge(_ merge: MergedIdentity) {
        merges[merge.id] = merge
        sideToMerge[merge.mastodon.storageKey] = merge.id
        sideToMerge[merge.bluesky.storageKey] = merge.id
    }

    private func evictMerge(_ merge: MergedIdentity) {
        merges.removeValue(forKey: merge.id)
        sideToMerge.removeValue(forKey: merge.mastodon.storageKey)
        sideToMerge.removeValue(forKey: merge.bluesky.storageKey)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = userDefaults.data(forKey: defaultsKey),
              let persisted = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        for merge in persisted.userConfirmed {
            indexMerge(merge)
        }
        tombstones = Set(persisted.tombstones)
    }

    private func save() {
        let userConfirmed = merges.values.filter { $0.provenance == .userConfirmed }
        let persisted = Persisted(
            userConfirmed: Array(userConfirmed),
            tombstones: Array(tombstones)
        )
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        userDefaults.set(data, forKey: defaultsKey)
    }
}

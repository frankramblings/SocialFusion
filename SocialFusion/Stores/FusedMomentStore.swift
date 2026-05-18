import Combine
import Foundation

/// Side-channel store of detected Fused moments.
///
/// Keyed on the underlying post IDs (both sides) so any UI surface that
/// holds a post can ask the store whether the post participates in a moment.
/// Follows the established pattern from `PostActionStore`.

// MARK: - Future
//
// v1.0 has no eviction policy: `moments` and `postToMoment` grow with the
// loaded timeline. The timeline buffer is bounded so unbounded growth is
// not a v1.0 concern. If/when an eviction or sign-out reset API is added,
// any cleanup must remove BOTH `moments[id]` AND the two `postToMoment`
// entries for the moment's underlying post IDs, or stale orphans will
// accumulate in the reverse index.

@MainActor
public final class FusedMomentStore: ObservableObject {
    /// All known moments by their stable ID.
    @Published public private(set) var moments: [String: FusedMoment] = [:]

    /// Index from underlying post ID → moment ID (both sides).
    private var postToMoment: [String: String] = [:]

    /// IDs of moments whose D-state bloom hasn't played yet. Read once by
    /// the timeline card; cleared on first appearance.
    @Published public private(set) var pendingBloom: Set<String> = []

    public init() {}

    /// Inserts a batch of moments.
    ///
    /// Idempotent on the bloom set — re-inserting an already-known moment ID
    /// does NOT re-prime the bloom (so the timeline glyph doesn't pulse on
    /// every refresh). The stored moment IS updated, so a future detector
    /// pass that refines `confidence` or `firstSeenAt` for the same pair
    /// replaces the prior value. The reverse index is set once per ID and
    /// is invariant under refinement (post IDs never change for a moment).
    public func insert(_ batch: [FusedMoment]) {
        for moment in batch {
            let id = moment.id
            let isNew = moments[id] == nil
            moments[id] = moment
            if isNew {
                postToMoment[moment.mastodonPostID] = id
                postToMoment[moment.blueskyPostID] = id
                pendingBloom.insert(id)
            }
        }
    }

    public func moment(for postID: String) -> FusedMoment? {
        guard let momentID = postToMoment[postID] else { return nil }
        return moments[momentID]
    }

    public func twinPostID(for postID: String, on platform: SocialPlatform) -> String? {
        guard let moment = moment(for: postID) else { return nil }
        return moment.twinPostID(for: platform)
    }

    /// Returns a snapshot of all known moments.
    ///
    /// Order is unspecified (dictionary iteration order). Callers requiring
    /// chronological order should sort by `firstSeenAt`.
    public func allMoments() -> [FusedMoment] {
        Array(moments.values)
    }

    /// Called by the Fused post card the first time it appears on screen.
    /// Returns true once per moment — true when the D-bloom should play,
    /// false on every subsequent appearance.
    public func consumePendingBloom(for momentID: String) -> Bool {
        if pendingBloom.contains(momentID) {
            pendingBloom.remove(momentID)
            return true
        }
        return false
    }
}

import Combine
import Foundation
import SwiftUI

/// Side-channel store of detected Fused moments.
///
/// Keyed on the underlying post IDs (both sides) so any UI surface that
/// holds a post can ask the store whether the post participates in a moment.
/// Follows the established pattern from `PostActionStore`.
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

    /// Inserts a batch of moments. Idempotent — re-inserting the same moment
    /// has no effect, and in particular does NOT re-prime the bloom set
    /// (already-known moments don't pulse on subsequent timeline refreshes).
    public func insert(_ batch: [FusedMoment]) {
        for moment in batch {
            let id = moment.id
            if moments[id] == nil {
                moments[id] = moment
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

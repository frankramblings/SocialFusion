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

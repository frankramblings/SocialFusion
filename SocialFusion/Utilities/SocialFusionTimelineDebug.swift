import Foundation

/// Debug singleton to track timeline posts and diagnostics for SocialFusion
final class SocialFusionTimelineDebug {
    static let shared = SocialFusionTimelineDebug()
    private init() {}

    /// The current array of Bluesky posts in the timeline
    private(set) var blueskyPosts: [Post] = []
    /// The current array of Mastodon posts in the timeline
    private(set) var mastodonPosts: [Post] = []
    /// The last time the timeline was refreshed
    private(set) var lastRefresh: Date?
    /// Any debug notes or messages
    private(set) var debugNotes: [String] = []

    private let queue = DispatchQueue(
        label: "SocialFusionTimelineDebug.queue", attributes: .concurrent)

    // MARK: - Public API

    func setBlueskyPosts(_ posts: [Post]) {
        queue.async(flags: .barrier) {
            self.blueskyPosts = posts
            self.lastRefresh = Date()
        }
    }

    func setMastodonPosts(_ posts: [Post]) {
        queue.async(flags: .barrier) {
            self.mastodonPosts = posts
            self.lastRefresh = Date()
        }
    }

    func addDebugNote(_ note: String) {
        queue.async(flags: .barrier) {
            self.debugNotes.append("[\(Date())] \(note)")
        }
    }

    func getBlueskyPosts() -> [Post] {
        queue.sync { blueskyPosts }
    }

    func getMastodonPosts() -> [Post] {
        queue.sync { mastodonPosts }
    }

    func getDebugNotes() -> [String] {
        queue.sync { debugNotes }
    }

    func getLastRefresh() -> Date? {
        queue.sync { lastRefresh }
    }
}

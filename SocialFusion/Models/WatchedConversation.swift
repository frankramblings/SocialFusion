import Foundation

public struct WatchedConversation: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let rootPostID: String
    public let platform: SocialPlatform
    public let fusedMomentID: String?
    public let watchedAt: Date
    /// Snapshot of who you're watching and what they said — captured at
    /// watch-time so the watched-list row can render a human label
    /// without a service round-trip. Optional for backward compatibility
    /// with watches persisted before this field was added; rows with
    /// `summary == nil` fall back to a platform-only label.
    public let summary: Summary?

    public struct Summary: Codable, Hashable, Sendable {
        public let authorName: String
        public let contentPreview: String

        public init(authorName: String, contentPreview: String) {
            self.authorName = authorName
            // Cap the preview so cold-launch decode stays bounded even
            // if a future caller forgets to truncate at the source.
            self.contentPreview = String(contentPreview.prefix(140))
        }
    }

    public init(
        rootPostID: String,
        platform: SocialPlatform,
        fusedMomentID: String?,
        summary: Summary? = nil
    ) {
        self.id = "watch:\(rootPostID)"
        self.rootPostID = rootPostID
        self.platform = platform
        self.fusedMomentID = fusedMomentID
        self.watchedAt = Date()
        self.summary = summary
    }
}

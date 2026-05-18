import Foundation

public struct WatchedConversation: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let rootPostID: String
    public let platform: SocialPlatform
    public let fusedMomentID: String?
    public let watchedAt: Date

    public init(rootPostID: String, platform: SocialPlatform, fusedMomentID: String?) {
        self.id = "watch:\(rootPostID)"
        self.rootPostID = rootPostID
        self.platform = platform
        self.fusedMomentID = fusedMomentID
        self.watchedAt = Date()
    }
}

import Foundation

public struct DraftPost: Identifiable, Codable, Equatable {
    public let id: UUID
    public var posts: [ThreadPostDraft]
    public var selectedPlatforms: Set<SocialPlatform>
    public var replyingToId: String?
    public var createdAt: Date
    
    public init(
        id: UUID = UUID(),
        posts: [ThreadPostDraft] = [],
        selectedPlatforms: Set<SocialPlatform> = [.mastodon, .bluesky],
        replyingToId: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.posts = posts
        self.selectedPlatforms = selectedPlatforms
        self.replyingToId = replyingToId
        self.createdAt = createdAt
    }
    
    public static func == (lhs: DraftPost, rhs: DraftPost) -> Bool {
        return lhs.id == rhs.id
    }
}

public struct ThreadPostDraft: Identifiable, Codable, Equatable {
    public let id: UUID
    public var text: String
    public var mediaData: [Data]
    
    public init(id: UUID = UUID(), text: String = "", mediaData: [Data] = []) {
        self.id = id
        self.text = text
        self.mediaData = mediaData
    }
}


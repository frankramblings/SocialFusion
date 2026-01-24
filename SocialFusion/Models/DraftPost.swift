import Foundation

public struct DraftPost: Identifiable, Codable, Equatable {
    public let id: UUID
    public var posts: [ThreadPostDraft]
    public var selectedPlatforms: Set<SocialPlatform>
    public var replyingToId: String?
    public var createdAt: Date
    public var cwEnabled: Bool // Legacy support - also stored per-post
    public var cwText: String // Legacy support - also stored per-post
    public var name: String?
    public var isPinned: Bool
    public var selectedAccounts: [SocialPlatform: String] = [:] // Per-platform account overrides
    
    public init(
        id: UUID = UUID(),
        posts: [ThreadPostDraft] = [],
        selectedPlatforms: Set<SocialPlatform> = [.mastodon, .bluesky],
        replyingToId: String? = nil,
        createdAt: Date = Date(),
        cwEnabled: Bool = false,
        cwText: String = ""
    ) {
        self.id = id
        self.posts = posts
        self.selectedPlatforms = selectedPlatforms
        self.replyingToId = replyingToId
        self.createdAt = createdAt
        self.cwEnabled = cwEnabled
        self.cwText = cwText
        self.name = nil
        self.isPinned = false
        self.selectedAccounts = [:]
    }
    
    public static func == (lhs: DraftPost, rhs: DraftPost) -> Bool {
        return lhs.id == rhs.id
    }
}

public struct ThreadPostDraft: Identifiable, Codable, Equatable {
    public let id: UUID
    public var text: String
    public var mediaData: [Data]
    public var cwEnabled: Bool
    public var cwText: String
    public var attachmentAltTexts: [String] // Per-attachment alt text
    public var attachmentSensitiveFlags: [Bool] // Per-attachment sensitive flags
    
    public init(
        id: UUID = UUID(),
        text: String = "",
        mediaData: [Data] = [],
        cwEnabled: Bool = false,
        cwText: String = "",
        attachmentAltTexts: [String] = [],
        attachmentSensitiveFlags: [Bool] = []
    ) {
        self.id = id
        self.text = text
        self.mediaData = mediaData
        self.cwEnabled = cwEnabled
        self.cwText = cwText
        self.attachmentAltTexts = attachmentAltTexts
        self.attachmentSensitiveFlags = attachmentSensitiveFlags
    }
    
    /// Computed property for draft sensitive flag
    public var draftSensitive: Bool {
        return cwEnabled || attachmentSensitiveFlags.contains(true)
    }
}


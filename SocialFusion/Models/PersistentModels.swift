import Foundation
import SwiftData

@available(iOS 17.0, *)
@Model
final class CachedPost {
    @Attribute(.unique) var id: String
    var content: String
    var authorName: String
    var authorUsername: String
    var authorAvatarURL: String?
    var createdAt: Date
    var platformValue: String
    var replyCount: Int
    var repostCount: Int
    var likeCount: Int
    
    // Simplified attachments for caching
    var attachmentURLs: [String] = []
    
    init(id: String, content: String, authorName: String, authorUsername: String, authorAvatarURL: String?, createdAt: Date, platform: SocialPlatform, replyCount: Int, repostCount: Int, likeCount: Int, attachmentURLs: [String]) {
        self.id = id
        self.content = content
        self.authorName = authorName
        self.authorUsername = authorUsername
        self.authorAvatarURL = authorAvatarURL
        self.createdAt = createdAt
        self.platformValue = platform.rawValue
        self.replyCount = replyCount
        self.repostCount = repostCount
        self.likeCount = likeCount
        self.attachmentURLs = attachmentURLs
    }
}


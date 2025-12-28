import Foundation
import SwiftData

@available(iOS 17.0, *)
@Model
final class CachedPost {
    @Attribute(.unique) var id: String
    var content: String
    var authorName: String
    var authorUsername: String
    var authorProfilePictureURL: String
    var createdAt: Date
    var platformValue: String
    var originalURL: String
    var replyCount: Int
    var repostCount: Int
    var likeCount: Int
    
    // Simplified attachments for caching
    var attachmentURLs: [String] = []
    
    init(id: String, content: String, authorName: String, authorUsername: String, authorProfilePictureURL: String, createdAt: Date, platform: SocialPlatform, originalURL: String, replyCount: Int, repostCount: Int, likeCount: Int, attachmentURLs: [String]) {
        self.id = id
        self.content = content
        self.authorName = authorName
        self.authorUsername = authorUsername
        self.authorProfilePictureURL = authorProfilePictureURL
        self.createdAt = createdAt
        self.platformValue = platform.rawValue
        self.originalURL = originalURL
        self.replyCount = replyCount
        self.repostCount = repostCount
        self.likeCount = likeCount
        self.attachmentURLs = attachmentURLs
    }
}


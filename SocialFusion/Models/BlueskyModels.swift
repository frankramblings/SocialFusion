import Foundation
import UIKit

// MARK: - Bluesky API Models

// Authentication Response
public struct BlueskyAuthResponse: Codable {
    public let accessJwt: String
    public let refreshJwt: String
    public let handle: String
    public let did: String
    public let email: String?

    public var expirationDate: Date {
        // JWT tokens typically last longer than 2 hours - use 24 hours for better UX
        return Date().addingTimeInterval(24 * 60 * 60)
    }
}

// Profile View
public struct BlueskyProfile: Codable {
    public let did: String
    public let handle: String
    public let displayName: String?
    public let description: String?
    public let avatar: String?
    public let banner: String?
    public let followsCount: Int
    public let followersCount: Int
    public let postsCount: Int
    public let indexedAt: String

    public enum CodingKeys: String, CodingKey {
        case did, handle, description, avatar, banner
        case displayName = "displayName"
        case followsCount = "followsCount"
        case followersCount = "followersCount"
        case postsCount = "postsCount"
        case indexedAt = "indexedAt"
    }
}

// Timeline Feed
public struct BlueskyFeed: Codable {
    public let feed: [BlueskyFeedItem]
    public let cursor: String?
}

// Feed Item
public struct BlueskyFeedItem: Codable {
    public let post: BlueskyPostDTO
    public let reply: BlueskyReply?
    public let reason: BlueskyReason?
}

// Post
public struct BlueskyPostDTO: Codable {
    public let uri: String
    public let cid: String
    public let author: BlueskyActor
    public let record: BlueskyPostRecord
    public let embed: BlueskyEmbed?
    public let replyCount: Int
    public let repostCount: Int
    public let likeCount: Int
    public let indexedAt: String
    public let viewer: BlueskyViewer?

    public enum CodingKeys: String, CodingKey {
        case uri, cid, author, record, embed
        case replyCount = "replyCount"
        case repostCount = "repostCount"
        case likeCount = "likeCount"
        case indexedAt = "indexedAt"
        case viewer
    }

    public var embedImages: [BlueskyImage]? {
        return embed?.images
    }
}

// Post Record
public struct BlueskyPostRecord: Codable {
    public let text: String
    public let createdAt: String
    public let reply: BlueskyPostReplyRef?

    public enum CodingKeys: String, CodingKey {
        case text
        case createdAt = "createdAt"
        case reply
    }
}

// Post Reply Reference
public struct BlueskyPostReplyRef: Codable {
    public let parent: BlueskyStrongRef
    public let root: BlueskyStrongRef
}

// Strong Reference
public struct BlueskyStrongRef: Codable {
    public let uri: String
    public let cid: String
}

// Actor (User)
public struct BlueskyActor: Codable {
    public let did: String
    public let handle: String
    public let displayName: String?
    public let avatar: String?
    public let viewer: BlueskyViewer?

    public enum CodingKeys: String, CodingKey {
        case did, handle, avatar, viewer
        case displayName = "displayName"
    }
}

// Viewer State
public struct BlueskyViewer: Codable {
    public let muted: Bool?
    public let blockedBy: Bool?
    public let following: String?
    public let followedBy: String?
    public let likeUri: String?
    public let repostUri: String?

    public enum CodingKeys: String, CodingKey {
        case muted
        case blockedBy = "blockedBy"
        case following, followedBy
        case likeUri = "likeUri"
        case repostUri = "repostUri"
    }
}

// Reply
public struct BlueskyReply: Codable {
    public let root: BlueskyPostDTO
    public let parent: BlueskyPostDTO
}

// Reason (for repost)
public struct BlueskyReason: Codable {
    public let by: BlueskyActor
    public let indexedAt: String

    public enum CodingKeys: String, CodingKey {
        case by
        case indexedAt = "indexedAt"
    }
}

// Embed (Media)
public struct BlueskyEmbed: Codable {
    public let images: [BlueskyImage]?
    public let external: BlueskyExternal?
    public let record: BlueskyEmbedRecord?

    public enum CodingKeys: String, CodingKey {
        case images, external, record
    }
}

// Image
public struct BlueskyImage: Codable {
    public let alt: String
    public let image: BlueskyImageRef

    public enum CodingKeys: String, CodingKey {
        case alt, image
    }
}

// Image Reference
public struct BlueskyImageRef: Codable {
    public let ref: [String: String]?
    public let mimeType: String?
    public let size: Int?

    public enum CodingKeys: String, CodingKey {
        case ref
        case mimeType = "mimeType"
        case size
    }
}

// External Link
public struct BlueskyExternal: Codable {
    public let uri: String
    public let title: String?
    public let description: String?
    public let thumb: BlueskyImageRef?

    public enum CodingKeys: String, CodingKey {
        case uri, title, description, thumb
    }
}

// Embed Record
public struct BlueskyEmbedRecord: Codable {
    public let record: BlueskyStrongRef

    public enum CodingKeys: String, CodingKey {
        case record
    }
}

// Error Response
public struct BlueskyAPIErrorDTO: Codable, Error {
    public let error: String
    public let message: String?

    public enum CodingKeys: String, CodingKey {
        case error, message
    }
}

// Timeline Response (DTO; keep name unique to avoid clashes with API client private type)
public struct BlueskyTimelineResponseDTO: Codable {
    public let feed: [BlueskyFeedItem]
    public let cursor: String?
}

// Search Responses
public struct BlueskySearchPostsResponse: Codable {
    public let posts: [BlueskyPostDTO]
    public let cursor: String?
    
    public init(posts: [BlueskyPostDTO], cursor: String?) {
        self.posts = posts
        self.cursor = cursor
    }
}

public struct BlueskySearchActorsResponse: Codable {
    public let actors: [BlueskyActor]
    public let cursor: String?
    
    public init(actors: [BlueskyActor], cursor: String?) {
        self.actors = actors
        self.cursor = cursor
    }
}

// Notifications
public struct BlueskyNotificationsResponse: Codable {
    public let notifications: [BlueskyNotificationDTO]
    public let cursor: String?
    
    public init(notifications: [BlueskyNotificationDTO], cursor: String?) {
        self.notifications = notifications
        self.cursor = cursor
    }
}

public struct BlueskyNotificationDTO: Codable {
    public let uri: String
    public let cid: String
    public let author: BlueskyActor
    public let reason: String
    public let reasonSubject: String?
    public let record: [String: AnyCodable]?
    public let isRead: Bool
    public let indexedAt: String
    
    public enum CodingKeys: String, CodingKey {
        case uri, cid, author, reason, record, indexedAt
        case reasonSubject = "reasonSubject"
        case isRead = "isRead"
    }
}

// AnyCodable helper for heterogeneous records
public struct AnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Bool.self) { value = x }
        else if let x = try? container.decode(Int.self) { value = x }
        else if let x = try? container.decode(Double.self) { value = x }
        else if let x = try? container.decode(String.self) { value = x }
        else if let x = try? container.decode([String: AnyCodable].self) { value = x.mapValues { $0.value } }
        else if let x = try? container.decode([AnyCodable].self) { value = x.map { $0.value } }
        else { throw DecodingError.typeMismatch(AnyCodable.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for AnyCodable")) }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let x = value as? Bool { try container.encode(x) }
        else if let x = value as? Int { try container.encode(x) }
        else if let x = value as? Double { try container.encode(x) }
        else if let x = value as? String { try container.encode(x) }
        else if let x = value as? [String: Any] { try container.encode(x.mapValues { AnyCodable($0) }) }
        else if let x = value as? [Any] { try container.encode(x.map { AnyCodable($0) }) }
        else { throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Cannot encode AnyCodable")) }
    }
}

// MARK: - Chat Models

public struct BlueskyConvoResponse: Codable {
    public let convos: [BlueskyConvo]
    public let cursor: String?
}

public struct BlueskyConvo: Codable, Identifiable {
    public let id: String
    public let rev: String
    public let members: [BlueskyActor]
    public let lastMessage: BlueskyChatMessage?
    public let muted: Bool
    public let unreadCount: Int
    
    public enum CodingKeys: String, CodingKey {
        case id, rev, members, lastMessage, muted, unreadCount
    }
}

public struct BlueskyChatMessageResponse: Codable {
    public let messages: [BlueskyChatMessage]
    public let cursor: String?
}

public enum BlueskyChatMessage: Codable, Identifiable {
    public var id: String {
        switch self {
        case .message(let msg): return msg.id
        case .deleted(let del): return del.id
        }
    }
    
    case message(BlueskyMessageView)
    case deleted(BlueskyDeletedMessageView)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(BlueskyMessageView.self) {
            self = .message(x)
        } else if let x = try? container.decode(BlueskyDeletedMessageView.self) {
            self = .deleted(x)
        } else {
            throw DecodingError.typeMismatch(BlueskyChatMessage.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for BlueskyChatMessage"))
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .message(let x): try container.encode(x)
        case .deleted(let x): try container.encode(x)
        }
    }
}

public struct BlueskyMessageView: Codable, Identifiable {
    public let id: String
    public let rev: String
    public let text: String
    public let sender: BlueskyActor
    public let sentAt: String
    
    public enum CodingKeys: String, CodingKey {
        case id, rev, text, sender, sentAt
    }
}

public struct BlueskyDeletedMessageView: Codable, Identifiable {
    public let id: String
    public let rev: String
    public let sender: BlueskyActor
    public let sentAt: String
    
    public enum CodingKeys: String, CodingKey {
        case id, rev, sender, sentAt
    }
}

// Thread Response
public struct BlueskyThreadResponse: Codable {
    public let thread: BlueskyThreadView
}

public class BlueskyThreadView: Codable {
    public let post: BlueskyPostDTO?
    public let parent: BlueskyThreadParent?
    public let replies: [BlueskyThreadView]?

    public enum CodingKeys: String, CodingKey {
        case post, parent, replies
    }
}

public struct BlueskyThreadParent: Codable {
    public let post: BlueskyPostDTO?
    public let replies: [BlueskyThreadView]?
}

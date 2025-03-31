import Foundation

// MARK: - Bluesky API Models

// Authentication Response
struct BlueskyAuthResponse: Codable {
    let accessJwt: String
    let refreshJwt: String
    let handle: String
    let did: String
    let email: String?

    var expirationDate: Date {
        // JWT tokens typically expire after 2 hours
        return Date().addingTimeInterval(2 * 60 * 60)
    }
}

// Profile View
struct BlueskyProfile: Codable {
    let did: String
    let handle: String
    let displayName: String?
    let description: String?
    let avatar: String?
    let banner: String?
    let followsCount: Int
    let followersCount: Int
    let postsCount: Int
    let indexedAt: String

    enum CodingKeys: String, CodingKey {
        case did, handle, description, avatar, banner
        case displayName = "displayName"
        case followsCount = "followsCount"
        case followersCount = "followersCount"
        case postsCount = "postsCount"
        case indexedAt = "indexedAt"
    }
}

// Timeline Feed
struct BlueskyFeed: Codable {
    let feed: [BlueskyFeedItem]
    let cursor: String?
}

// Feed Item
struct BlueskyFeedItem: Codable {
    let post: BlueskyPost
    let reply: BlueskyReply?
    let reason: BlueskyReason?
}

// Post
struct BlueskyPost: Codable {
    let uri: String
    let cid: String
    let author: BlueskyActor
    let record: BlueskyPostRecord
    let embed: BlueskyEmbed?
    let replyCount: Int
    let repostCount: Int
    let likeCount: Int
    let indexedAt: String
    let viewer: BlueskyViewer?

    enum CodingKeys: String, CodingKey {
        case uri, cid, author, record, embed
        case replyCount = "replyCount"
        case repostCount = "repostCount"
        case likeCount = "likeCount"
        case indexedAt = "indexedAt"
        case viewer
    }

    var embedImages: [BlueskyImage]? {
        return embed?.images
    }
}

// Post Record
struct BlueskyPostRecord: Codable {
    let text: String
    let createdAt: String
    let reply: BlueskyPostReplyRef?

    enum CodingKeys: String, CodingKey {
        case text
        case createdAt = "createdAt"
        case reply
    }
}

// Post Reply Reference
struct BlueskyPostReplyRef: Codable {
    let parent: BlueskyStrongRef
    let root: BlueskyStrongRef
}

// Strong Reference
struct BlueskyStrongRef: Codable {
    let uri: String
    let cid: String
}

// Actor (User)
struct BlueskyActor: Codable {
    let did: String
    let handle: String
    let displayName: String?
    let avatar: String?
    let viewer: BlueskyViewer?

    enum CodingKeys: String, CodingKey {
        case did, handle, avatar, viewer
        case displayName = "displayName"
    }
}

// Viewer State
struct BlueskyViewer: Codable {
    let muted: Bool?
    let blockedBy: Bool?
    let following: String?
    let followedBy: String?
    let likeUri: String?
    let repostUri: String?

    enum CodingKeys: String, CodingKey {
        case muted
        case blockedBy = "blockedBy"
        case following, followedBy
        case likeUri = "likeUri"
        case repostUri = "repostUri"
    }
}

// Reply
struct BlueskyReply: Codable {
    let root: BlueskyPost
    let parent: BlueskyPost
}

// Reason (for repost)
struct BlueskyReason: Codable {
    let by: BlueskyActor
    let indexedAt: String

    enum CodingKeys: String, CodingKey {
        case by
        case indexedAt = "indexedAt"
    }
}

// Embed (Media)
struct BlueskyEmbed: Codable {
    let images: [BlueskyImage]?
    let external: BlueskyExternal?
    let record: BlueskyEmbedRecord?

    enum CodingKeys: String, CodingKey {
        case images, external, record
    }
}

// Image
struct BlueskyImage: Codable {
    let alt: String
    let image: BlueskyImageRef

    enum CodingKeys: String, CodingKey {
        case alt, image
    }
}

// Image Reference
struct BlueskyImageRef: Codable {
    let ref: [String: String]?
    let mimeType: String?
    let size: Int?

    enum CodingKeys: String, CodingKey {
        case ref
        case mimeType = "mimeType"
        case size
    }
}

// External Link
struct BlueskyExternal: Codable {
    let uri: String
    let title: String?
    let description: String?
    let thumb: BlueskyImageRef?

    enum CodingKeys: String, CodingKey {
        case uri, title, description, thumb
    }
}

// Embed Record
struct BlueskyEmbedRecord: Codable {
    let record: BlueskyStrongRef

    enum CodingKeys: String, CodingKey {
        case record
    }
}

// Error Response
struct BlueskyError: Codable, Error {
    let error: String
    let message: String?

    enum CodingKeys: String, CodingKey {
        case error, message
    }
}

// Timeline Response
struct BlueskyTimelineResponse: Codable {
    let feed: [BlueskyFeedItem]
    let cursor: String?
}

// Thread Response
struct BlueskyThreadResponse: Codable {
    let thread: BlueskyThreadView
}

class BlueskyThreadView: Codable {
    let post: BlueskyPost?
    let parent: BlueskyThreadParent?
    let replies: [BlueskyThreadView]?

    enum CodingKeys: String, CodingKey {
        case post, parent, replies
    }
}

struct BlueskyThreadParent: Codable {
    let post: BlueskyPost?
    let replies: [BlueskyThreadView]?
}

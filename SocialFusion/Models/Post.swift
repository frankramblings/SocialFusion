import Foundation
import SwiftUI
import UIKit

// MARK: - Post visibility level
public enum PostVisibilityType: String, Codable {
    case public_
    case unlisted
    case private_
    case direct

    // Map values from the API response to our enum cases
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "public": self = .public_
        case "unlisted": self = .unlisted
        case "private": self = .private_
        case "direct": self = .direct
        default: self = .public_
        }
    }

    // Map our enum cases to values for API requests
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .public_: try container.encode("public")
        case .unlisted: try container.encode("unlisted")
        case .private_: try container.encode("private")
        case .direct: try container.encode("direct")
        }
    }
}

// MARK: - Author struct
/// Represents the creator of a post on a social network
public struct Author: Codable, Identifiable, Equatable {
    public let id: String
    public let username: String
    public let displayName: String
    public let profileImageURL: URL?
    public let platform: SocialPlatform
    public let platformSpecificId: String

    public var avatarURL: URL? {
        return profileImageURL
    }

    public init(
        id: String, username: String, displayName: String, profileImageURL: URL? = nil,
        platform: SocialPlatform, platformSpecificId: String = ""
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.profileImageURL = profileImageURL
        self.platform = platform
        self.platformSpecificId = platformSpecificId.isEmpty ? id : platformSpecificId
    }

    public static func == (lhs: Author, rhs: Author) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Media Type enum
public enum MediaType: String, Codable {
    case image
    case video
    case animatedGIF
    case audio
    case unknown
}

// MARK: - Media Attachment struct
public struct MediaAttachment: Codable, Identifiable, Equatable {
    public let id: String
    public let url: URL
    public let previewURL: URL?
    public let altText: String?
    public let type: MediaType

    public init(
        id: String, url: URL, previewURL: URL? = nil, altText: String? = nil,
        type: MediaType = .unknown
    ) {
        self.id = id
        self.url = url
        self.previewURL = previewURL
        self.altText = altText
        self.type = type
    }

    // For backward compatibility with existing code that uses 'description'
    public var description: String? {
        return altText
    }

    public static func == (lhs: MediaAttachment, rhs: MediaAttachment) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Post class
public class Post: Identifiable, Codable, Equatable {
    public let id: String
    public let content: String
    public let authorName: String
    public let authorUsername: String
    public let authorProfilePictureURL: String
    public let createdAt: Date
    public let platform: SocialPlatform
    public let originalURL: String
    public let attachments: [Attachment]
    public let mentions: [String]
    public let tags: [String]

    // New properties for boosted/reposted content
    public var originalPost: Post?
    public var isReposted: Bool = false
    public var isLiked: Bool = false
    public var likeCount: Int = 0
    public var repostCount: Int = 0

    // Properties for reply and boost functionality
    public var boostedBy: String?
    public var parent: Post?
    public var inReplyToID: String?

    // Platform-specific IDs for API operations
    public let platformSpecificId: String

    public struct Attachment: Identifiable, Codable {
        public var id: String { url }  // Use URL as unique identifier
        public let url: String
        public let type: AttachmentType
        public let altText: String?

        public enum AttachmentType: String, Codable {
            case image
            case video
            case audio
            case gifv
        }
    }

    public static func == (lhs: Post, rhs: Post) -> Bool {
        return lhs.id == rhs.id
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case content
        case authorName
        case authorUsername
        case authorProfilePictureURL
        case createdAt
        case platform
        case originalURL
        case attachments
        case mentions
        case tags
        case originalPost
        case isReposted
        case isLiked
        case repostCount
        case likeCount
        case platformSpecificId
        case boostedBy
        case parent
        case inReplyToID
    }

    public init(
        id: String,
        content: String,
        authorName: String,
        authorUsername: String,
        authorProfilePictureURL: String,
        createdAt: Date,
        platform: SocialPlatform,
        originalURL: String,
        attachments: [Attachment] = [],
        mentions: [String] = [],
        tags: [String] = [],
        originalPost: Post? = nil,
        isReposted: Bool = false,
        isLiked: Bool = false,
        likeCount: Int = 0,
        repostCount: Int = 0,
        platformSpecificId: String = "",
        boostedBy: String? = nil,
        parent: Post? = nil,
        inReplyToID: String? = nil
    ) {
        self.id = id
        self.content = content
        self.authorName = authorName
        self.authorUsername = authorUsername
        self.authorProfilePictureURL = authorProfilePictureURL
        self.createdAt = createdAt
        self.platform = platform
        self.originalURL = originalURL
        self.attachments = attachments
        self.mentions = mentions
        self.tags = tags
        self.originalPost = originalPost
        self.isReposted = isReposted
        self.isLiked = isLiked
        self.likeCount = likeCount
        self.repostCount = repostCount
        self.platformSpecificId = platformSpecificId
        self.boostedBy = boostedBy
        self.parent = parent
        self.inReplyToID = inReplyToID
    }

    // Sample posts for previews and testing
    public static var samplePosts: [Post] = [
        Post(
            id: "1",
            content: "This is a sample post from Mastodon. #SocialFusion",
            authorName: "User One",
            authorUsername: "user1@mastodon.social",
            authorProfilePictureURL: "https://picsum.photos/200",
            createdAt: Date().addingTimeInterval(-3600),
            platform: .mastodon,
            originalURL: "https://mastodon.social/@user1/123456",
            attachments: [],
            mentions: [],
            tags: ["SocialFusion"],
            isLiked: true,
            likeCount: 5,
            repostCount: 2,
            platformSpecificId: ""
        ),
        Post(
            id: "2",
            content: "Hello from Bluesky! Testing out the SocialFusion app.",
            authorName: "User Two",
            authorUsername: "user2.bsky.social",
            authorProfilePictureURL: "https://picsum.photos/201",
            createdAt: Date().addingTimeInterval(-7200),
            platform: .bluesky,
            originalURL: "https://bsky.app/profile/user2.bsky.social/post/abcdef",
            attachments: [
                Attachment(
                    url: "https://picsum.photos/400",
                    type: .image,
                    altText: "A sample image"
                )
            ],
            mentions: [],
            tags: [],
            likeCount: 3,
            repostCount: 1,
            platformSpecificId: ""
        ),
        // Sample boosted post (Mastodon)
        Post(
            id: "3",
            content: "",
            authorName: "User Three",
            authorUsername: "user3@mastodon.social",
            authorProfilePictureURL: "https://picsum.photos/202",
            createdAt: Date().addingTimeInterval(-1800),
            platform: .mastodon,
            originalURL: "https://mastodon.social/@user3/boost/789012",
            attachments: [],
            mentions: [],
            tags: [],
            originalPost: Post(
                id: "4",
                content:
                    "This is the original post that was boosted. It contains original content from another user. #Mastodon",
                authorName: "Original User",
                authorUsername: "original@mastodon.social",
                authorProfilePictureURL: "https://picsum.photos/203",
                createdAt: Date().addingTimeInterval(-5400),
                platform: .mastodon,
                originalURL: "https://mastodon.social/@original/789012",
                attachments: [
                    Attachment(
                        url: "https://picsum.photos/401",
                        type: .image,
                        altText: "Image in boosted post"
                    )
                ],
                mentions: [],
                tags: ["Mastodon"],
                likeCount: 12,
                repostCount: 5,
                platformSpecificId: ""
            ),
            isReposted: true,
            repostCount: 5,
            platformSpecificId: ""
        ),
        // Sample boosted post (Bluesky)
        Post(
            id: "5",
            content: "",
            authorName: "User Four",
            authorUsername: "user4.bsky.social",
            authorProfilePictureURL: "https://picsum.photos/204",
            createdAt: Date().addingTimeInterval(-900),
            platform: .bluesky,
            originalURL: "https://bsky.app/profile/user4.bsky.social/post/repost/ghijkl",
            attachments: [],
            mentions: [],
            tags: [],
            originalPost: Post(
                id: "6",
                content: "Check out this photo from my latest hike! #Bluesky #Outdoors",
                authorName: "Original Bluesky User",
                authorUsername: "hiker.bsky.social",
                authorProfilePictureURL: "https://picsum.photos/205",
                createdAt: Date().addingTimeInterval(-10800),
                platform: .bluesky,
                originalURL: "https://bsky.app/profile/hiker.bsky.social/post/ghijkl",
                attachments: [
                    Attachment(
                        url: "https://picsum.photos/600/400",
                        type: .image,
                        altText: "Mountain landscape with trees"
                    )
                ],
                mentions: [],
                tags: ["Bluesky", "Outdoors"],
                isLiked: true,
                likeCount: 25,
                repostCount: 8,
                platformSpecificId: ""
            ),
            isReposted: true,
            repostCount: 8,
            platformSpecificId: ""
        ),
    ]

    /// Create a copy of the post with a new ID
    func copy(with newId: String) -> Post {
        return Post(
            id: newId,
            content: self.content,
            authorName: self.authorName,
            authorUsername: self.authorUsername,
            authorProfilePictureURL: self.authorProfilePictureURL,
            createdAt: self.createdAt,
            platform: self.platform,
            originalURL: self.originalURL,
            attachments: self.attachments,
            mentions: self.mentions,
            tags: self.tags,
            originalPost: self.originalPost,
            isReposted: self.isReposted,
            isLiked: self.isLiked,
            likeCount: self.likeCount,
            repostCount: self.repostCount,
            platformSpecificId: newId  // Update the platform-specific ID too
        )
    }
}

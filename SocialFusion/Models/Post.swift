import Foundation
import SwiftUI
import UIKit

// MARK: - Post visibility level
enum PostVisibilityType: String, Codable {
    case public_
    case unlisted
    case private_
    case direct

    // Map values from the API response to our enum cases
    init(from decoder: Decoder) throws {
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
    func encode(to encoder: Encoder) throws {
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
struct Author: Codable, Identifiable, Equatable {
    let id: String
    let username: String
    let displayName: String
    let profileImageURL: URL?
    let platform: SocialPlatform
    let platformSpecificId: String
    
    var avatarURL: URL? {
        return profileImageURL
    }
    
    init(id: String, username: String, displayName: String, profileImageURL: URL? = nil, platform: SocialPlatform, platformSpecificId: String = "") {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.profileImageURL = profileImageURL
        self.platform = platform
        self.platformSpecificId = platformSpecificId.isEmpty ? id : platformSpecificId
    }
    
    static func == (lhs: Author, rhs: Author) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Media Type enum
enum MediaType: String, Codable {
    case image
    case video
    case animatedGIF
    case audio
    case unknown
}

// MARK: - Media Attachment struct
struct MediaAttachment: Codable, Identifiable, Equatable {
    let id: String
    let url: URL
    let previewURL: URL?
    let altText: String?
    let type: MediaType

    init(
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
    var description: String? {
        return altText
    }

    static func == (lhs: MediaAttachment, rhs: MediaAttachment) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Post class
class Post: Identifiable, ObservableObject, Equatable {
    let id: String
    let platform: SocialPlatform
    let author: Author
    let content: String
    let mediaAttachments: [MediaAttachment]
    let createdAt: Date
    var visibility: PostVisibilityType
    var likeCount: Int
    var repostCount: Int
    var replyCount: Int
    @Published var isLiked: Bool
    @Published var isReposted: Bool
    let inReplyToID: String?
    var platformSpecificId: String

    init(
        id: String, platform: SocialPlatform, author: Author, content: String,
        mediaAttachments: [MediaAttachment] = [], createdAt: Date = Date(),
        visibility: PostVisibilityType = .public_,
        likeCount: Int = 0, repostCount: Int = 0, replyCount: Int = 0,
        isLiked: Bool = false, isReposted: Bool = false, inReplyToID: String? = nil,
        platformSpecificId: String = ""
    ) {
        self.id = id
        self.platform = platform
        self.author = author
        self.content = content
        self.mediaAttachments = mediaAttachments
        self.createdAt = createdAt
        self.visibility = visibility
        self.likeCount = likeCount
        self.repostCount = repostCount
        self.replyCount = replyCount
        self.isLiked = isLiked
        self.isReposted = isReposted
        self.inReplyToID = inReplyToID
        self.platformSpecificId = platformSpecificId.isEmpty ? id : platformSpecificId
    }

    static func == (lhs: Post, rhs: Post) -> Bool {
        return lhs.id == rhs.id && lhs.platform == rhs.platform
    }

    // Sample posts for previews and testing
    static var samplePosts: [Post] = [
        Post(
            id: "1",
            platform: .mastodon,
            author: Author(
                id: "1",
                username: "user1@mastodon.social",
                displayName: "User One",
                profileImageURL: URL(string: "https://picsum.photos/200"),
                platform: .mastodon,
                platformSpecificId: ""
            ),
            content: "This is a sample post from Mastodon. #SocialFusion",
            mediaAttachments: [],
            createdAt: Date().addingTimeInterval(-3600),
            visibility: .public_,
            likeCount: 5,
            repostCount: 2,
            replyCount: 1,
            isLiked: false,
            isReposted: false
        ),
        Post(
            id: "2",
            platform: .bluesky,
            author: Author(
                id: "2",
                username: "user2.bsky.social",
                displayName: "User Two",
                profileImageURL: URL(string: "https://picsum.photos/201"),
                platform: .bluesky,
                platformSpecificId: ""
            ),
            content: "Hello from Bluesky! Testing out the SocialFusion app.",
            mediaAttachments: [
                MediaAttachment(
                    id: "media1",
                    url: URL(string: "https://picsum.photos/400")!,
                    previewURL: URL(string: "https://picsum.photos/100")!,
                    altText: "A sample image",
                    type: .image
                )
            ],
            createdAt: Date().addingTimeInterval(-7200),
            visibility: .public_,
            likeCount: 10,
            repostCount: 3,
            replyCount: 2,
            isLiked: true,
            isReposted: false
        ),
    ]
}

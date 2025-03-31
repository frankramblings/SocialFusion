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

    init(
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

// MARK: - Post struct
struct Post: Identifiable, Equatable {
    let id: String
    let content: String
    let authorName: String
    let authorUsername: String
    let authorProfilePictureURL: String
    let createdAt: Date
    let platform: SocialPlatform
    let originalURL: String
    let attachments: [Attachment]
    let mentions: [Mention]
    let tags: [String]

    // Nested types for attachments and mentions
    struct Attachment: Identifiable, Equatable {
        var id: String { url }
        let url: String
        let type: AttachmentType
        let altText: String

        enum AttachmentType: String, Codable {
            case image
            case video
            case audio
            case unknown
        }

        static func == (lhs: Attachment, rhs: Attachment) -> Bool {
            lhs.url == rhs.url
        }
    }

    struct Mention: Identifiable, Equatable {
        var id: String { url }
        let username: String
        let displayName: String
        let url: String

        static func == (lhs: Mention, rhs: Mention) -> Bool {
            lhs.url == rhs.url
        }
    }

    static func == (lhs: Post, rhs: Post) -> Bool {
        lhs.id == rhs.id && lhs.platform == rhs.platform
    }

    // Sample posts for previews and testing
    static var samplePosts: [Post] = [
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
            tags: ["SocialFusion"]
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
            tags: []
        ),
    ]
}

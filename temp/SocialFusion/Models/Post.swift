import Foundation

enum SocialPlatform: String, Codable, CaseIterable {
    case mastodon = "Mastodon"
    case bluesky = "Bluesky"

    var color: String {
        switch self {
        case .mastodon:
            return "PrimaryColor"  // Mastodon Purple
        case .bluesky:
            return "SecondaryColor"  // Bluesky Blue
        }
    }

    var icon: String {
        switch self {
        case .mastodon:
            return "bubble.left.fill"
        case .bluesky:
            return "cloud.fill"
        }
    }
}

struct Post: Identifiable, Equatable {
    let id: String
    let platform: SocialPlatform
    let author: Author
    let content: String
    let mediaAttachments: [MediaAttachment]
    let createdAt: Date
    let likeCount: Int
    let repostCount: Int
    let replyCount: Int
    let isLiked: Bool
    let isReposted: Bool
    let originalPost: Post?

    // Platform-specific IDs for API operations
    let platformSpecificId: String

    let quotedPostUri: String?
    let quotedPostAuthorHandle: String?

    static func == (lhs: Post, rhs: Post) -> Bool {
        lhs.id == rhs.id
    }
}

struct Author: Identifiable, Equatable {
    let id: String
    let username: String
    let displayName: String
    let avatarURL: URL?
    let platform: SocialPlatform

    // Platform-specific IDs for API operations
    let platformSpecificId: String

    static func == (lhs: Author, rhs: Author) -> Bool {
        lhs.id == rhs.id
    }
}

struct MediaAttachment: Identifiable {
    let id: String
    let url: URL
    let type: MediaType
    let altText: String?

    enum MediaType: String, Codable {
        case image
        case video
        case audio
        case gifv
    }
}

// MARK: - Sample Data
extension Post {
    static var samplePosts: [Post] {
        [
            Post(
                id: "1",
                platform: .mastodon,
                author: Author(
                    id: "author1",
                    username: "elonmusk",
                    displayName: "Elon Musk",
                    avatarURL: URL(string: "https://placekitten.com/200/200"),
                    platform: .mastodon,
                    platformSpecificId: "author1_mastodon"
                ),
                content: "Just had a great meeting with the SpaceX team about Starship progress!",
                mediaAttachments: [],
                createdAt: Date().addingTimeInterval(-3600),  // 1 hour ago
                likeCount: 1024,
                repostCount: 512,
                replyCount: 128,
                isLiked: false,
                isReposted: false,
                originalPost: nil,
                platformSpecificId: "post1_mastodon",
                quotedPostUri: nil,
                quotedPostAuthorHandle: nil
            ),
            Post(
                id: "2",
                platform: .bluesky,
                author: Author(
                    id: "author2",
                    username: "timcook",
                    displayName: "Tim Cook",
                    avatarURL: URL(string: "https://placekitten.com/201/201"),
                    platform: .bluesky,
                    platformSpecificId: "author2_bluesky"
                ),
                content: "Excited to announce the new iPhone 15 Pro with revolutionary features!",
                mediaAttachments: [
                    MediaAttachment(
                        id: "media1",
                        url: URL(string: "https://placekitten.com/500/300")!,
                        type: .image,
                        altText: "iPhone 15 Pro"
                    )
                ],
                createdAt: Date().addingTimeInterval(-7200),  // 2 hours ago
                likeCount: 2048,
                repostCount: 1024,
                replyCount: 256,
                isLiked: true,
                isReposted: false,
                originalPost: nil,
                platformSpecificId: "post2_bluesky",
                quotedPostUri: nil,
                quotedPostAuthorHandle: nil
            ),
            Post(
                id: "3",
                platform: .mastodon,
                author: Author(
                    id: "author3",
                    username: "sundarpichai",
                    displayName: "Sundar Pichai",
                    avatarURL: URL(string: "https://placekitten.com/202/202"),
                    platform: .mastodon,
                    platformSpecificId: "author3_mastodon"
                ),
                content: "Google I/O is coming up! Can't wait to share what we've been working on.",
                mediaAttachments: [],
                createdAt: Date().addingTimeInterval(-10800),  // 3 hours ago
                likeCount: 1536,
                repostCount: 768,
                replyCount: 192,
                isLiked: false,
                isReposted: true,
                originalPost: nil,
                platformSpecificId: "post3_mastodon",
                quotedPostUri: nil,
                quotedPostAuthorHandle: nil
            ),
        ]
    }
}

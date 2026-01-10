import Foundation

/// A model representing a Bluesky post
public struct BlueskyPost: Codable, Identifiable {
    // MARK: - Properties

    public let uri: String
    public let cid: String
    public let author: BlueskyAuthor
    public let record: BlueskyRecord
    public let embed: BlueskyEmbed?
    public let replyCount: Int
    public let repostCount: Int
    public let likeCount: Int
    public let indexedAt: String
    public let labels: [String]?
    public let viewer: BlueskyViewer?

    // MARK: - Nested Types

    public struct BlueskyAuthor: Codable {
        public let did: String
        public let handle: String
        public let displayName: String?
        public let avatar: String?
        public let viewer: BlueskyViewer?
        public let labels: [String]?
    }

    public struct BlueskyRecord: Codable {
        public let text: String
        public let type: String
        public let createdAt: String
        public let langs: [String]?
        public let labels: [String]?
        public let reply: BlueskyReply?
        // Removed embed from record to avoid recursive value-type cycles
    }

    public struct BlueskyReply: Codable {
        public let parent: BlueskyReference
        public let root: BlueskyReference
    }

    public struct BlueskyReference: Codable {
        public let uri: String
        public let cid: String
    }

    public struct BlueskyEmbed: Codable {
        public let type: String
        // Use a reference to avoid recursion
        public let record: BlueskyReference?
        public let images: [BlueskyImage]?
        public let external: BlueskyExternal?
        public let recordWithMedia: BlueskyRecordWithMedia?
    }

    public struct BlueskyImage: Codable {
        public let alt: String
        public let fullsize: String
        public let thumb: String
    }

    public struct BlueskyExternal: Codable {
        public let uri: String
        public let title: String
        public let description: String
        public let thumb: String?
    }

    public struct BlueskyRecordWithMedia: Codable {
        // Use a simplified record to avoid recursion back to embed
        public let record: BlueskySimpleRecord
        public let media: SimpleMedia
    }

    public struct SimpleMedia: Codable {
        public let images: [BlueskyImage]?
        public let external: BlueskyExternal?
    }

    public struct BlueskySimpleRecord: Codable {
        public let text: String
        public let createdAt: String
    }

    public struct BlueskyViewer: Codable {
        public let like: String?
        public let repost: String?
        public let muted: Bool?
        public let blockedBy: Bool?
        public let following: String?
        public let followedBy: String?
    }
}

// MARK: - Identifiable
extension BlueskyPost {
    public var id: String { uri }
}

// MARK: - Preview Helper
extension BlueskyPost {
    static var preview: BlueskyPost {
        BlueskyPost(
            uri: "at://did:plc:123/app.bsky.feed.post/456",
            cid: "bafyreiabcdefghijklmnopqrstuvwxyz",
            author: BlueskyAuthor(
                did: "did:plc:123",
                handle: "username.bsky.social",
                displayName: "User Name",
                avatar: "https://bsky.social/avatar.png",
                viewer: nil,
                labels: nil
            ),
            record: BlueskyRecord(
                text: "Hello, world!",
                type: "app.bsky.feed.post",
                createdAt: "2024-03-20T12:00:00Z",
                langs: ["en"],
                labels: nil,
                reply: nil
            ),
            embed: nil,
            replyCount: 2,
            repostCount: 5,
            likeCount: 10,
            indexedAt: "2024-03-20T12:00:00Z",
            labels: nil,
            viewer: BlueskyViewer(
                like: nil,
                repost: nil,
                muted: false,
                blockedBy: false,
                following: nil,
                followedBy: nil
            )
        )
    }
}

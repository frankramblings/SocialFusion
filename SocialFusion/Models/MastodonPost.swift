import Foundation

/// A model representing a Mastodon post
public struct MastodonPost: Codable, Identifiable {
    // MARK: - Properties

    public let id: String
    public let uri: String
    public let url: String
    public let content: String
    public let createdAt: String
    public let account: MastodonAccount
    public let mediaAttachments: [MastodonMediaAttachment]
    public let mentions: [MastodonMention]
    public let tags: [MastodonTag]
    public let favouritesCount: Int
    public let reblogsCount: Int
    public let repliesCount: Int
    public let favourited: Bool
    public let reblogged: Bool
    public let sensitive: Bool
    public let spoilerText: String?
    public let visibility: String
    public let inReplyToId: String?
    public let inReplyToAccountId: String?
    public let reblog: MastodonReblog?

    // MARK: - Nested Types

    public struct MastodonAccount: Codable {
        public let id: String
        public let username: String
        public let acct: String
        public let displayName: String?
        public let avatar: String
        public let avatarStatic: String
        public let header: String
        public let headerStatic: String
        public let locked: Bool
        public let bot: Bool
        public let discoverable: Bool
        public let group: Bool
        public let createdAt: String
        public let note: String
        public let url: String
        public let followersCount: Int
        public let followingCount: Int
        public let statusesCount: Int
        public let lastStatusAt: String?

        enum CodingKeys: String, CodingKey {
            case id, username, acct, avatar, header, locked, bot, discoverable, group, note, url
            case displayName = "display_name"
            case avatarStatic = "avatar_static"
            case headerStatic = "header_static"
            case createdAt = "created_at"
            case followersCount = "followers_count"
            case followingCount = "following_count"
            case statusesCount = "statuses_count"
            case lastStatusAt = "last_status_at"
        }
    }

    public struct MastodonMediaAttachment: Codable {
        public let id: String
        public let type: String
        public let url: String
        public let previewUrl: String?  // Optional - some media attachments don't have preview_url
        public let remoteUrl: String?
        public let textUrl: String?
        public let description: String?
        public let blurhash: String?
    }

    public struct MastodonMention: Codable {
        public let id: String
        public let username: String
        public let url: String
        public let acct: String
    }

    public struct MastodonTag: Codable {
        public let name: String
        public let url: String
    }
}

// Lightweight reblog model to avoid recursive stored property on value type
public struct MastodonReblog: Codable {
    public let id: String?
    public let uri: String?
    public let url: String?
    public let content: String?
    public let createdAt: String?
    public let account: MastodonPost.MastodonAccount?
    public let mediaAttachments: [MastodonPost.MastodonMediaAttachment]?
    public let mentions: [MastodonPost.MastodonMention]?
    public let tags: [MastodonPost.MastodonTag]?
    public let emojis: [MastodonEmoji]?  // Custom emoji used in reblogged post content

    enum CodingKeys: String, CodingKey {
        case id, uri, url, content, account, mentions, tags, emojis
        case createdAt = "created_at"
        case mediaAttachments = "media_attachments"
    }
}

// MARK: - Preview Helper
extension MastodonPost {
    static var preview: MastodonPost {
        MastodonPost(
            id: "123456",
            uri: "https://mastodon.social/users/username/statuses/123456",
            url: "https://mastodon.social/@username/123456",
            content: "Hello, world!",
            createdAt: "2024-03-20T12:00:00Z",
            account: MastodonAccount(
                id: "789",
                username: "username",
                acct: "username@mastodon.social",
                displayName: "User Name",
                avatar: "https://mastodon.social/avatar.png",
                avatarStatic: "https://mastodon.social/avatar.png",
                header: "https://mastodon.social/header.png",
                headerStatic: "https://mastodon.social/header.png",
                locked: false,
                bot: false,
                discoverable: true,
                group: false,
                createdAt: "2024-01-01T00:00:00Z",
                note: "Bio",
                url: "https://mastodon.social/@username",
                followersCount: 100,
                followingCount: 50,
                statusesCount: 200,
                lastStatusAt: "2024-03-20T12:00:00Z"
            ),
            mediaAttachments: [],
            mentions: [],
            tags: [],
            favouritesCount: 10,
            reblogsCount: 5,
            repliesCount: 2,
            favourited: false,
            reblogged: false,
            sensitive: false,
            spoilerText: nil,
            visibility: "public",
            inReplyToId: nil,
            inReplyToAccountId: nil,
            reblog: nil
        )
    }
}

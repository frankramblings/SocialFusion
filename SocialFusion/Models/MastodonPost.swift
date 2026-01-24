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
    public let poll: MastodonPoll?

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
        public let meta: MastodonMediaMeta?  // Contains dimension info from Mastodon API

        enum CodingKeys: String, CodingKey {
            case id, type, url, description, blurhash, meta
            case previewUrl = "preview_url"
            case remoteUrl = "remote_url"
            case textUrl = "text_url"
        }

        /// Best available width from meta.small or meta.original
        public var bestWidth: Int? {
            meta?.small?.width ?? meta?.original?.width
        }

        /// Best available height from meta.small or meta.original
        public var bestHeight: Int? {
            meta?.small?.height ?? meta?.original?.height
        }

        /// Computed aspect ratio from best available dimensions
        public var aspectRatio: Double? {
            // First try meta.small or meta.original aspect if directly provided
            if let aspect = meta?.small?.aspect ?? meta?.original?.aspect, aspect > 0 {
                return aspect
            }
            // Otherwise compute from dimensions
            guard let w = bestWidth, let h = bestHeight, h > 0 else { return nil }
            return Double(w) / Double(h)
        }
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
    public let poll: MastodonPoll?

    enum CodingKeys: String, CodingKey {
        case id, uri, url, content, account, mentions, tags, emojis, poll
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
            reblog: nil,
            poll: nil
        )
    }
}

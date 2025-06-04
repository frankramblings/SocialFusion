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
    public let reblog: MastodonPost?

    // MARK: - Nested Types

    public struct MastodonAccount: Codable {
        public let id: String
        public let username: String
        public let acct: String
        public let displayName: String
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
    }

    public struct MastodonMediaAttachment: Codable {
        public let id: String
        public let type: String
        public let url: String
        public let previewUrl: String
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

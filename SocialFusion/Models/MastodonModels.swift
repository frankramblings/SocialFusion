import Foundation

// MARK: - Mastodon API Models

// Application Registration Response
public struct MastodonApp: Codable {
    public let id: String
    public let clientId: String
    public let clientSecret: String
    public let redirectUri: String

    public enum CodingKeys: String, CodingKey {
        case id
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case redirectUri = "redirect_uri"
    }
}

// OAuth Token Response
public struct MastodonToken: Codable {
    public let accessToken: String
    public let tokenType: String
    public let scope: String
    public let createdAt: Int
    public let refreshToken: String?
    public let expiresIn: Int?

    public enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case createdAt = "created_at"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }

    public var expirationDate: Date? {
        guard let expiresIn = expiresIn else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(createdAt + expiresIn))
    }
}

// Account Information
public struct MastodonAccount: Codable {
    public let id: String
    public let username: String
    public let acct: String
    public let displayName: String?
    public let note: String?
    public let url: String
    public let avatar: String
    public let avatarStatic: String?  // Optional - not always present in search results
    public let header: String?  // Optional - not always present in search results
    public let headerStatic: String?  // Optional - not always present in search results
    public let followersCount: Int?  // Optional - not always present in search results
    public let followingCount: Int?  // Optional - not always present in search results
    public let statusesCount: Int?  // Optional - not always present in search results
    public let lastStatusAt: String?
    public let emojis: [MastodonEmoji]?  // Optional - not always present in search results
    public let fields: [MastodonField]?

    public enum CodingKeys: String, CodingKey {
        case id, username, acct, url, avatar, header, note, emojis, fields
        case displayName = "display_name"
        case avatarStatic = "avatar_static"
        case headerStatic = "header_static"
        case followersCount = "followers_count"
        case followingCount = "following_count"
        case statusesCount = "statuses_count"
        case lastStatusAt = "last_status_at"
    }
}

// Preview Card (link preview)
public struct MastodonCard: Codable {
    public let url: String
    public let title: String
    public let description: String
    public let image: String?
    public let type: String  // "link", "photo", "video", "rich"
    public let authorName: String?
    public let authorUrl: String?
    public let providerName: String?
    public let providerUrl: String?
    public let html: String?
    public let width: Int?
    public let height: Int?
    
    public enum CodingKeys: String, CodingKey {
        case url, title, description, image, type, html, width, height
        case authorName = "author_name"
        case authorUrl = "author_url"
        case providerName = "provider_name"
        case providerUrl = "provider_url"
    }
}

// Poll
public struct MastodonPoll: Codable {
    public struct MastodonPollOption: Codable {
        public let title: String
        public let votesCount: Int?

        public enum CodingKeys: String, CodingKey {
            case title
            case votesCount = "votes_count"
        }
    }

    public let id: String
    public let expiresAt: String?
    public let expired: Bool
    public let multiple: Bool
    public let votesCount: Int
    public let votersCount: Int?
    public let voted: Bool?
    public let ownVotes: [Int]?
    public let options: [MastodonPollOption]

    public enum CodingKeys: String, CodingKey {
        case id, expired, multiple, voted, options
        case expiresAt = "expires_at"
        case votesCount = "votes_count"
        case votersCount = "voters_count"
        case ownVotes = "own_votes"
    }
}

// Status (Post)
public class MastodonStatus: Codable {
    public let id: String
    public let createdAt: String
    public let content: String
    public let visibility: String
    public let sensitive: Bool
    public let spoilerText: String
    public let mediaAttachments: [MastodonMediaAttachment]
    public let application: MastodonApplication?
    public let mentions: [MastodonMention]
    public let tags: [MastodonTag]
    public let emojis: [MastodonEmoji]
    public let reblogsCount: Int
    public let favouritesCount: Int
    public let repliesCount: Int
    public let url: String?
    public let inReplyToId: String?
    public let inReplyToAccountId: String?
    public let reblog: MastodonReblog?
    public let account: MastodonAccount
    public let favourited: Bool?
    public let reblogged: Bool?
    public let bookmarked: Bool?
    public let card: MastodonCard?  // Link preview card
    public let poll: MastodonPoll?

    public init(
        id: String,
        createdAt: String,
        content: String,
        visibility: String,
        sensitive: Bool,
        spoilerText: String,
        mediaAttachments: [MastodonMediaAttachment],
        application: MastodonApplication?,
        mentions: [MastodonMention],
        tags: [MastodonTag],
        emojis: [MastodonEmoji],
        reblogsCount: Int,
        favouritesCount: Int,
        repliesCount: Int,
        url: String?,
        inReplyToId: String?,
        inReplyToAccountId: String?,
        reblog: MastodonReblog?,
        account: MastodonAccount,
        favourited: Bool?,
        reblogged: Bool?,
        bookmarked: Bool?,
        card: MastodonCard? = nil,
        poll: MastodonPoll? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.content = content
        self.visibility = visibility
        self.sensitive = sensitive
        self.spoilerText = spoilerText
        self.mediaAttachments = mediaAttachments
        self.application = application
        self.mentions = mentions
        self.tags = tags
        self.emojis = emojis
        self.reblogsCount = reblogsCount
        self.favouritesCount = favouritesCount
        self.repliesCount = repliesCount
        self.url = url
        self.inReplyToId = inReplyToId
        self.inReplyToAccountId = inReplyToAccountId
        self.reblog = reblog
        self.account = account
        self.favourited = favourited
        self.reblogged = reblogged
        self.bookmarked = bookmarked
        self.card = card
        self.poll = poll
    }

    public enum CodingKeys: String, CodingKey {
        case id, content, visibility, sensitive, mentions, tags, emojis, application, account, url,
            reblog, card
        case createdAt = "created_at"
        case spoilerText = "spoiler_text"
        case mediaAttachments = "media_attachments"
        case reblogsCount = "reblogs_count"
        case favouritesCount = "favourites_count"
        case repliesCount = "replies_count"
        case inReplyToId = "in_reply_to_id"
        case inReplyToAccountId = "in_reply_to_account_id"
        case favourited, reblogged, bookmarked
        case poll
    }
}

// Reblogged Status is modeled as a lightweight struct in `MastodonPost.swift`

// Media Attachment
public struct MastodonMediaAttachment: Codable {
    public let id: String
    public let type: String
    public let url: String
    public let previewUrl: String?  // Optional - some media attachments don't have preview_url
    public let remoteUrl: String?
    public let description: String?

    public enum CodingKeys: String, CodingKey {
        case id, type, url, description
        case previewUrl = "preview_url"
        case remoteUrl = "remote_url"
    }
}

// Application Information
public struct MastodonApplication: Codable {
    public let name: String
    public let website: String?
}

// Mention
public struct MastodonMention: Codable {
    public let id: String
    public let username: String
    public let url: String
    public let acct: String
}

// Tag
public struct MastodonTag: Codable {
    public let name: String
    public let url: String
}

// Search Results
public struct MastodonSearchResult: Codable {
    public let accounts: [MastodonAccount]
    public let statuses: [MastodonStatus]
    public let hashtags: [MastodonTag]

    public init(accounts: [MastodonAccount], statuses: [MastodonStatus], hashtags: [MastodonTag]) {
        self.accounts = accounts
        self.statuses = statuses
        self.hashtags = hashtags
    }
}

// Notification
public struct MastodonNotification: Codable {
    public let id: String
    public let type: String
    public let createdAt: String
    public let account: MastodonAccount
    public let status: MastodonStatus?

    public enum CodingKeys: String, CodingKey {
        case id, type, account, status
        case createdAt = "created_at"
    }
}

// Emoji
public struct MastodonEmoji: Codable {
    public let shortcode: String
    public let url: String
    public let staticUrl: String
    public let visibleInPicker: Bool

    public enum CodingKeys: String, CodingKey {
        case shortcode, url
        case staticUrl = "static_url"
        case visibleInPicker = "visible_in_picker"
    }
}

// Profile Field
public struct MastodonField: Codable {
    public let name: String
    public let value: String
    public let verifiedAt: String?

    public enum CodingKeys: String, CodingKey {
        case name, value
        case verifiedAt = "verified_at"
    }
}

// Relationship (Follow status, etc.)
public struct MastodonRelationship: Codable {
    public let id: String
    public let following: Bool
    public let followedBy: Bool
    public let blocking: Bool
    public let blockedBy: Bool
    public let muting: Bool
    public let mutingNotifications: Bool
    public let requested: Bool
    public let domainBlocking: Bool
    public let showingReblogs: Bool
    public let endorsing: Bool
    public let note: String?

    public enum CodingKeys: String, CodingKey {
        case id, following, blocking, muting, requested, endorsing, note
        case followedBy = "followed_by"
        case blockedBy = "blocked_by"
        case mutingNotifications = "muting_notifications"
        case domainBlocking = "domain_blocking"
        case showingReblogs = "showing_reblogs"
    }
}

// Error Response DTO (renamed to avoid clash with public MastodonError)
public struct MastodonAPIError: Codable, Error, LocalizedError {
    public let error: String
    public let errorDescription: String?

    public enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }

    public var localizedDescription: String {
        if let description = errorDescription {
            return "\(error): \(description)"
        }
        return error
    }
}

// Back-compat alias for existing call sites
public typealias MastodonError = MastodonAPIError

// List
public struct MastodonList: Codable, Identifiable {
    public let id: String
    public let title: String
    public let repliesPolicy: String

    public enum CodingKeys: String, CodingKey {
        case id, title
        case repliesPolicy = "replies_policy"
    }
}

// Conversation (DM)
public struct MastodonConversation: Codable, Identifiable {
    public let id: String
    public let unread: Bool
    public let accounts: [MastodonAccount]
    public let lastStatus: MastodonStatus

    public enum CodingKeys: String, CodingKey {
        case id, unread, accounts
        case lastStatus = "last_status"
    }
}

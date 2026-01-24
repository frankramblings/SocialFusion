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

// Media Attachment Metadata - contains dimension info
public struct MastodonMediaMeta: Codable {
    public struct MediaMetaSize: Codable {
        public let width: Int?
        public let height: Int?
        public let size: String?  // e.g. "800x600"
        public let aspect: Double?  // Aspect ratio as a number
    }

    public let small: MediaMetaSize?
    public let original: MediaMetaSize?
    public let focus: MediaMetaFocus?

    public struct MediaMetaFocus: Codable {
        public let x: Double?
        public let y: Double?
    }
}

// Media Attachment
public struct MastodonMediaAttachment: Codable {
    public let id: String
    public let type: String
    public let url: String
    public let previewUrl: String?  // Optional - some media attachments don't have preview_url
    public let remoteUrl: String?
    public let description: String?
    public let meta: MastodonMediaMeta?  // Contains dimension info from Mastodon API

    public enum CodingKeys: String, CodingKey {
        case id, type, url, description, meta
        case previewUrl = "preview_url"
        case remoteUrl = "remote_url"
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
    public let requestedBy: Bool
    public let domainBlocking: Bool
    public let showingReblogs: Bool
    public let endorsing: Bool
    public let notifying: Bool
    public let languages: [String]?
    public let note: String?

    public enum CodingKeys: String, CodingKey {
        case id, following, blocking, muting, requested, endorsing, endorsed, notifying, languages, note
        case followedBy = "followed_by"
        case blockedBy = "blocked_by"
        case mutingNotifications = "muting_notifications"
        case domainBlocking = "domain_blocking"
        case showingReblogs = "showing_reblogs"
        case requestedBy = "requested_by"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        following = try container.decodeIfPresent(Bool.self, forKey: .following) ?? false
        followedBy = try container.decodeIfPresent(Bool.self, forKey: .followedBy) ?? false
        blocking = try container.decodeIfPresent(Bool.self, forKey: .blocking) ?? false
        blockedBy = try container.decodeIfPresent(Bool.self, forKey: .blockedBy) ?? false
        muting = try container.decodeIfPresent(Bool.self, forKey: .muting) ?? false
        mutingNotifications =
            try container.decodeIfPresent(Bool.self, forKey: .mutingNotifications) ?? false
        requested = try container.decodeIfPresent(Bool.self, forKey: .requested) ?? false
        requestedBy = try container.decodeIfPresent(Bool.self, forKey: .requestedBy) ?? false
        domainBlocking = try container.decodeIfPresent(Bool.self, forKey: .domainBlocking) ?? false
        showingReblogs = try container.decodeIfPresent(Bool.self, forKey: .showingReblogs) ?? true
        endorsing =
            try container.decodeIfPresent(Bool.self, forKey: .endorsed)
            ?? container.decodeIfPresent(Bool.self, forKey: .endorsing)
            ?? false
        notifying = try container.decodeIfPresent(Bool.self, forKey: .notifying) ?? false
        languages = try container.decodeIfPresent([String].self, forKey: .languages)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(following, forKey: .following)
        try container.encode(followedBy, forKey: .followedBy)
        try container.encode(blocking, forKey: .blocking)
        try container.encode(blockedBy, forKey: .blockedBy)
        try container.encode(muting, forKey: .muting)
        try container.encode(mutingNotifications, forKey: .mutingNotifications)
        try container.encode(requested, forKey: .requested)
        try container.encode(requestedBy, forKey: .requestedBy)
        try container.encode(domainBlocking, forKey: .domainBlocking)
        try container.encode(showingReblogs, forKey: .showingReblogs)
        try container.encode(endorsing, forKey: .endorsing)
        try container.encode(notifying, forKey: .notifying)
        try container.encodeIfPresent(languages, forKey: .languages)
        try container.encodeIfPresent(note, forKey: .note)
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

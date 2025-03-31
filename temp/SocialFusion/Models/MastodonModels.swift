import Foundation

// MARK: - Mastodon API Models

// Application Registration Response
struct MastodonApp: Codable {
    let id: String
    let clientId: String
    let clientSecret: String
    let redirectUri: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case redirectUri = "redirect_uri"
    }
}

// OAuth Token Response
struct MastodonToken: Codable {
    let accessToken: String
    let tokenType: String
    let scope: String
    let createdAt: Int
    let refreshToken: String?
    let expiresIn: Int?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case createdAt = "created_at"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
    
    var expirationDate: Date? {
        guard let expiresIn = expiresIn else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(createdAt + expiresIn))
    }
}

// Account Information
struct MastodonAccount: Codable {
    let id: String
    let username: String
    let acct: String
    let displayName: String
    let note: String
    let url: String
    let avatar: String
    let avatarStatic: String
    let header: String
    let headerStatic: String
    let followersCount: Int
    let followingCount: Int
    let statusesCount: Int
    let lastStatusAt: String?
    let emojis: [MastodonEmoji]
    let fields: [MastodonField]?
    
    enum CodingKeys: String, CodingKey {
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

// Status (Post)
struct MastodonStatus: Codable {
    let id: String
    let createdAt: String
    let content: String
    let visibility: String
    let sensitive: Bool
    let spoilerText: String
    let mediaAttachments: [MastodonMediaAttachment]
    let application: MastodonApplication?
    let mentions: [MastodonMention]
    let tags: [MastodonTag]
    let emojis: [MastodonEmoji]
    let reblogsCount: Int
    let favouritesCount: Int
    let repliesCount: Int
    let url: String?
    let inReplyToId: String?
    let inReplyToAccountId: String?
    let reblog: MastodonReblog?
    let account: MastodonAccount
    let favourited: Bool?
    let reblogged: Bool?
    let bookmarked: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id, content, visibility, sensitive, mentions, tags, emojis, application, account, url, reblog
        case createdAt = "created_at"
        case spoilerText = "spoiler_text"
        case mediaAttachments = "media_attachments"
        case reblogsCount = "reblogs_count"
        case favouritesCount = "favourites_count"
        case repliesCount = "replies_count"
        case inReplyToId = "in_reply_to_id"
        case inReplyToAccountId = "in_reply_to_account_id"
        case favourited, reblogged, bookmarked
    }
}

// Reblogged Status
typealias MastodonReblog = MastodonStatus

// Media Attachment
struct MastodonMediaAttachment: Codable {
    let id: String
    let type: String
    let url: String
    let previewUrl: String
    let remoteUrl: String?
    let description: String?
    
    enum CodingKeys: String, CodingKey {
        case id, type, url, description
        case previewUrl = "preview_url"
        case remoteUrl = "remote_url"
    }
}

// Application Information
struct MastodonApplication: Codable {
    let name: String
    let website: String?
}

// Mention
struct MastodonMention: Codable {
    let id: String
    let username: String
    let url: String
    let acct: String
}

// Tag
struct MastodonTag: Codable {
    let name: String
    let url: String
}

// Emoji
struct MastodonEmoji: Codable {
    let shortcode: String
    let url: String
    let staticUrl: String
    let visibleInPicker: Bool
    
    enum CodingKeys: String, CodingKey {
        case shortcode, url
        case staticUrl = "static_url"
        case visibleInPicker = "visible_in_picker"
    }
}

// Profile Field
struct MastodonField: Codable {
    let name: String
    let value: String
    let verifiedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case name, value
        case verifiedAt = "verified_at"
    }
}

// Error Response
struct MastodonError: Codable, Error {
    let error: String
    let errorDescription: String?
    
    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
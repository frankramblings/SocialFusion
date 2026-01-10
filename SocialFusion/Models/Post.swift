import Combine
import Foundation
import SwiftUI
// MARK: - AttributedTextOverlay for per-segment tap support
import UIKit

// MARK: - Post Actions
public enum PostAction: Hashable {
    case reply
    case repost
    case like
    case share
    case quote
    case follow
    case mute
    case block
    case addToList
    case openInBrowser
    case copyLink
    case shareSheet
    case report
}

extension PostAction {
    var menuLabel: String {
        switch self {
        case .follow:
            return "Follow"
        case .mute:
            return "Mute"
        case .block:
            return "Block"
        case .addToList:
            return "Add to Lists"
        case .openInBrowser:
            return "Open in Browser"
        case .copyLink:
            return "Copy Link"
        case .shareSheet:
            return "Share"
        case .report:
            return "Report"
        case .reply:
            return "Reply"
        case .repost:
            return "Repost"
        case .like:
            return "Like"
        case .share:
            return "Share"
        case .quote:
            return "Quote"
        }
    }

    var menuSystemImage: String {
        switch self {
        case .follow:
            return "person.badge.plus"
        case .mute:
            return "speaker.slash"
        case .block:
            return "hand.raised"
        case .addToList:
            return "list.bullet"
        case .openInBrowser:
            return "arrow.up.right.square"
        case .copyLink:
            return "link"
        case .shareSheet:
            return "square.and.arrow.up"
        case .report:
            return "exclamationmark.triangle"
        case .reply:
            return "arrowshape.turn.up.left"
        case .repost:
            return "arrow.2.squarepath"
        case .like:
            return "heart"
        case .share:
            return "square.and.arrow.up"
        case .quote:
            return "quote.bubble"
        }
    }

    var menuRole: ButtonRole? {
        switch self {
        case .report:
            return .destructive
        default:
            return nil
        }
    }

    static func platformActions(for post: Post) -> [PostAction] {
        var actions: [PostAction] = [.follow, .mute, .block]
        if post.platform == .mastodon {
            actions.append(.addToList)
        }
        return actions
    }
}

// MARK: - Post visibility level
public enum PostVisibilityType: String, Codable {
    case public_
    case unlisted
    case private_
    case direct

    // Map values from the API response to our enum cases
    public init(from decoder: Decoder) throws {
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
    public func encode(to encoder: Encoder) throws {
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
public struct Author: Codable, Identifiable, Equatable {
    public let id: String
    public let username: String
    public let displayName: String
    public let profileImageURL: URL?
    public let platform: SocialPlatform
    public let platformSpecificId: String

    public var avatarURL: URL? {
        return profileImageURL
    }

    public init(
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

    public static func == (lhs: Author, rhs: Author) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Media Type enum
public enum MediaType: String, Codable {
    case image
    case video
    case animatedGIF
    case audio
    case unknown
}

// MARK: - Media Attachment struct
public struct MediaAttachment: Codable, Identifiable, Equatable {
    public let id: String
    public let url: URL
    public let previewURL: URL?
    public let altText: String?
    public let type: MediaType

    public init(
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
    public var description: String? {
        return altText
    }

    public static func == (lhs: MediaAttachment, rhs: MediaAttachment) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Post class
public class Post: Identifiable, Codable, Equatable, ObservableObject, @unchecked Sendable {
    public let id: String
    public let content: String
    public let authorName: String
    public let authorUsername: String
    public let authorId: String
    public let authorProfilePictureURL: String
    public let createdAt: Date
    public let platform: SocialPlatform
    public let originalURL: String
    public let attachments: [Attachment]
    public let mentions: [String]
    public let tags: [String]

    // New properties for boosted/reposted content - these should NOT be @Published
    // to prevent cycles when Posts contain other Posts
    public var originalPost: Post? {
        didSet {
            // CRITICAL FIX: Removed objectWillChange.send() from didSet to prevent "Publishing changes from within view updates" warnings
            // Post is already ObservableObject, so SwiftUI will automatically observe property changes
            // Calling objectWillChange.send() in didSet triggers warnings when properties are set during view updates
            
            // Only check for cycles if we're actually setting a non-nil value
            // CRITICAL: Preserve existing originalPost - don't clear it unless we detect a real cycle
            if let original = originalPost {
                // Only detect cycles if we're setting a NEW originalPost (different from oldValue)
                // This prevents clearing originalPost when it's being set to the same value
                if oldValue?.id != original.id {
                    if Post.detectCycle(start: self, next: original) {
                        print(
                            "[Post] ⚠️ Cycle detected in originalPost chain for post id: \(id). Breaking cycle."
                        )
                        // CRITICAL: Defer clearing originalPost to prevent triggering didSet during view updates
                        Task { @MainActor [weak self] in
                            try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2 second delay
                            self?.originalPost = nil
                        }
                    }
                }
            }
        }
    }
    @Published public var isReposted: Bool = false
    @Published public var isLiked: Bool = false
    @Published public var isReplied: Bool = false
    @Published public var isQuoted: Bool = false
    @Published public var likeCount: Int = 0
    @Published public var repostCount: Int = 0
    @Published public var replyCount: Int = 0
    @Published public var isFollowingAuthor: Bool = false
    @Published public var isMutedAuthor: Bool = false
    @Published public var isBlockedAuthor: Bool = false

    // Properties for reply and boost functionality - these should NOT be @Published
    // to prevent cycles when Posts contain other Posts
    public var boostedBy: String? {
        didSet {
            // CRITICAL FIX: Removed objectWillChange.send() from didSet to prevent "Publishing changes from within view updates" warnings
            // Post is already ObservableObject, so SwiftUI will automatically observe property changes
            // Calling objectWillChange.send() in didSet triggers warnings when properties are set during view updates
        }
    }
    public var parent: Post? {
        didSet {
            if let parentPost = parent, Post.detectCycle(start: self, next: parentPost) {
                print("[Post] Cycle detected in parent chain for post id: \(id). Breaking cycle.")
                parent = nil
            }
        }
    }
    public var inReplyToID: String? {
        didSet {
            // CRITICAL FIX: Removed objectWillChange.send() from didSet to prevent "Publishing changes from within view updates" warnings
            // Post is already ObservableObject, so SwiftUI will automatically observe property changes
        }
    }
    public var inReplyToUsername: String? {
        didSet {
            // CRITICAL FIX: Removed objectWillChange.send() from didSet to prevent "Publishing changes from within view updates" warnings
            // Post is already ObservableObject, so SwiftUI will automatically observe property changes
        }
    }

    // Quoted post support - NOT @Published to prevent cycles
    public var quotedPost: Post? = nil

    // Poll support
    @Published public var poll: Poll? = nil

    // Computed properties for convenience
    public var authorHandle: String {
        return authorUsername
    }

    // Platform-specific IDs for API operations
    public let platformSpecificId: String

    let quotedPostUri: String?
    let quotedPostAuthorHandle: String?

    public var cid: String?  // Bluesky only, optional for backward compatibility

    // Pre-extracted primary link for previews (e.g. Bluesky external embed or Mastodon card)
    public var primaryLinkURL: URL?
    public var primaryLinkTitle: String?
    public var primaryLinkDescription: String?
    public var primaryLinkThumbnailURL: URL?

    // Bluesky AT Protocol record URIs for unlike/unrepost functionality
    public var blueskyLikeRecordURI: String?  // URI of the like record created by this user
    public var blueskyRepostRecordURI: String?  // URI of the repost record created by this user

    // Custom emoji support (Mastodon/Fediverse)
    // Maps emoji shortcode (e.g., "neofox_floof") to its image URL
    public var customEmojiMap: [String: String]?
    
    // Author display name emoji - for emoji in the author's name
    public var authorEmojiMap: [String: String]?
    
    // Booster display name emoji - for emoji in the booster's name (reblog/boost scenarios)
    public var boosterEmojiMap: [String: String]?

    // Client/application name (e.g., "Ivory for Mac", "IceCubes for iOS", "Bluesky Web")
    public var clientName: String?

    // Computed property for a stable unique identifier
    public var stableId: String {
        if isReposted, let original = originalPost {
            return "\(platform.rawValue)-repost-\(authorUsername)-\(original.platformSpecificId)"
        }
        return "\(platform.rawValue)-\(platformSpecificId)"
    }

    public struct Attachment: Identifiable, Codable {
        public var id: String { url }  // Use URL as unique identifier
        public let url: String
        public let type: AttachmentType
        public let altText: String?
        public let thumbnailURL: String?
        public let width: Int?
        public let height: Int?

        public var aspectRatio: Double? {
            guard let w = width, let h = height, h > 0 else { return nil }
            return Double(w) / Double(h)
        }

        public init(
            url: String, type: AttachmentType, altText: String? = nil, thumbnailURL: String? = nil,
            width: Int? = nil, height: Int? = nil
        ) {
            self.url = url
            self.type = type
            self.altText = altText
            self.thumbnailURL = thumbnailURL
            self.width = width
            self.height = height
        }

        public enum AttachmentType: String, Codable {
            case image
            case video
            case audio
            case gifv
            case animatedGIF
        }
    }

    public static func == (lhs: Post, rhs: Post) -> Bool {
        return lhs.stableId == rhs.stableId
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case content
        case authorName
        case authorUsername
        case authorId
        case authorProfilePictureURL
        case createdAt
        case platform
        case originalURL
        case attachments
        case mentions
        case tags
        case originalPost
        case isReposted
        case isLiked
        case isReplied
        case repostCount
        case likeCount
        case replyCount
        case isFollowingAuthor
        case isMutedAuthor
        case isBlockedAuthor
        case platformSpecificId
        case boostedBy
        case parent
        case inReplyToID
        case inReplyToUsername
        case quotedPostUri
        case quotedPostAuthorHandle
        case cid
        case primaryLinkURL
        case primaryLinkTitle
        case primaryLinkDescription
        case primaryLinkThumbnailURL
        case quotedPost
        case poll
        case blueskyLikeRecordURI
        case blueskyRepostRecordURI
        case customEmojiMap
        case authorEmojiMap
        case boosterEmojiMap
        case clientName
    }

    // MARK: - Poll Support (nested types for UI components)
    public struct Poll: Identifiable, Equatable, Codable {
        public struct PollOption: Identifiable, Equatable, Codable {
            public var id: String { title }
            public let title: String
            public let votesCount: Int?

            public init(title: String, votesCount: Int? = nil) {
                self.title = title
                self.votesCount = votesCount
            }
        }

        public let id: String
        public let expiresAt: Date?
        public let expired: Bool
        public let multiple: Bool
        public let votesCount: Int
        public let votersCount: Int?
        public let voted: Bool?
        public let ownVotes: [Int]?
        public let options: [PollOption]

        public init(
            id: String,
            expiresAt: Date? = nil,
            expired: Bool = false,
            multiple: Bool = false,
            votesCount: Int,
            votersCount: Int? = nil,
            voted: Bool? = nil,
            ownVotes: [Int]? = nil,
            options: [PollOption]
        ) {
            self.id = id
            self.expiresAt = expiresAt
            self.expired = expired
            self.multiple = multiple
            self.votesCount = votesCount
            self.votersCount = votersCount
            self.voted = voted
            self.ownVotes = ownVotes
            self.options = options
        }
    }

    public required convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let content = try container.decode(String.self, forKey: .content)
        let authorName = try container.decode(String.self, forKey: .authorName)
        let authorUsername = try container.decode(String.self, forKey: .authorUsername)
        let authorId =
            try container.decodeIfPresent(String.self, forKey: .authorId) ?? authorUsername
        let authorProfilePictureURL = try container.decode(
            String.self, forKey: .authorProfilePictureURL)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        let platform = try container.decode(SocialPlatform.self, forKey: .platform)
        let originalURL = try container.decode(String.self, forKey: .originalURL)
        let attachments = try container.decode([Attachment].self, forKey: .attachments)
        let mentions = try container.decode([String].self, forKey: .mentions)
        let tags = try container.decode([String].self, forKey: .tags)
        let originalPost = try container.decodeIfPresent(Post.self, forKey: .originalPost)
        let isReposted = try container.decode(Bool.self, forKey: .isReposted)
        let isLiked = try container.decode(Bool.self, forKey: .isLiked)
        let isReplied = try container.decode(Bool.self, forKey: .isReplied)
        let likeCount = try container.decode(Int.self, forKey: .likeCount)
        let repostCount = try container.decode(Int.self, forKey: .repostCount)
        let replyCount = try container.decodeIfPresent(Int.self, forKey: .replyCount) ?? 0
        let isFollowingAuthor =
            try container.decodeIfPresent(Bool.self, forKey: .isFollowingAuthor) ?? false
        let isMutedAuthor =
            try container.decodeIfPresent(Bool.self, forKey: .isMutedAuthor) ?? false
        let isBlockedAuthor =
            try container.decodeIfPresent(Bool.self, forKey: .isBlockedAuthor) ?? false
        let platformSpecificId = try container.decode(String.self, forKey: .platformSpecificId)
        let boostedBy = try container.decodeIfPresent(String.self, forKey: .boostedBy)
        let parent = try container.decodeIfPresent(Post.self, forKey: .parent)
        let inReplyToID = try container.decodeIfPresent(String.self, forKey: .inReplyToID)
        let inReplyToUsername = try container.decodeIfPresent(
            String.self, forKey: .inReplyToUsername)
        let quotedPostUri = try container.decodeIfPresent(String.self, forKey: .quotedPostUri)
        let quotedPostAuthorHandle = try container.decodeIfPresent(
            String.self, forKey: .quotedPostAuthorHandle)
        let cid = try container.decodeIfPresent(String.self, forKey: .cid)
        let primaryLinkURL = try container.decodeIfPresent(URL.self, forKey: .primaryLinkURL)
        let primaryLinkTitle = try container.decodeIfPresent(String.self, forKey: .primaryLinkTitle)
        let primaryLinkDescription = try container.decodeIfPresent(
            String.self, forKey: .primaryLinkDescription)
        let primaryLinkThumbnailURL = try container.decodeIfPresent(
            URL.self, forKey: .primaryLinkThumbnailURL)
        let quotedPost = try container.decodeIfPresent(Post.self, forKey: .quotedPost)
        let poll = try container.decodeIfPresent(Poll.self, forKey: .poll)
        let blueskyLikeRecordURI = try container.decodeIfPresent(
            String.self, forKey: .blueskyLikeRecordURI)
        let blueskyRepostRecordURI = try container.decodeIfPresent(
            String.self, forKey: .blueskyRepostRecordURI)
        let customEmojiMap = try container.decodeIfPresent(
            [String: String].self, forKey: .customEmojiMap)
        let authorEmojiMap = try container.decodeIfPresent(
            [String: String].self, forKey: .authorEmojiMap)
        let boosterEmojiMap = try container.decodeIfPresent(
            [String: String].self, forKey: .boosterEmojiMap)
        let clientName = try container.decodeIfPresent(String.self, forKey: .clientName)
        self.init(
            id: id,
            content: content,
            authorName: authorName,
            authorUsername: authorUsername,
            authorProfilePictureURL: authorProfilePictureURL,
            createdAt: createdAt,
            platform: platform,
            originalURL: originalURL,
            attachments: attachments,
            mentions: mentions,
            tags: tags,
            originalPost: originalPost,
            isReposted: isReposted,
            isLiked: isLiked,
            isReplied: isReplied,
            likeCount: likeCount,
            repostCount: repostCount,
            replyCount: replyCount,
            isFollowingAuthor: isFollowingAuthor,
            isMutedAuthor: isMutedAuthor,
            isBlockedAuthor: isBlockedAuthor,
            platformSpecificId: platformSpecificId,
            boostedBy: boostedBy,
            parent: parent,
            inReplyToID: inReplyToID,
            inReplyToUsername: inReplyToUsername,
            quotedPostUri: quotedPostUri,
            quotedPostAuthorHandle: quotedPostAuthorHandle,
            quotedPost: quotedPost,
            poll: poll,
            cid: cid,
            primaryLinkURL: primaryLinkURL,
            primaryLinkTitle: primaryLinkTitle,
            primaryLinkDescription: primaryLinkDescription,
            primaryLinkThumbnailURL: primaryLinkThumbnailURL,
            blueskyLikeRecordURI: blueskyLikeRecordURI,
            blueskyRepostRecordURI: blueskyRepostRecordURI,
            customEmojiMap: customEmojiMap,
            authorEmojiMap: authorEmojiMap,
            boosterEmojiMap: boosterEmojiMap,
            clientName: clientName
        )
        self.cid = cid
        self.primaryLinkURL = primaryLinkURL
        self.primaryLinkTitle = primaryLinkTitle
        self.primaryLinkDescription = primaryLinkDescription
        self.quotedPost = quotedPost
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(authorName, forKey: .authorName)
        try container.encode(authorUsername, forKey: .authorUsername)
        try container.encode(authorId, forKey: .authorId)
        try container.encode(authorProfilePictureURL, forKey: .authorProfilePictureURL)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(platform, forKey: .platform)
        try container.encode(originalURL, forKey: .originalURL)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(mentions, forKey: .mentions)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(originalPost, forKey: .originalPost)
        try container.encode(isReposted, forKey: .isReposted)
        try container.encode(isLiked, forKey: .isLiked)
        try container.encode(isReplied, forKey: .isReplied)
        try container.encode(likeCount, forKey: .likeCount)
        try container.encode(repostCount, forKey: .repostCount)
        try container.encode(replyCount, forKey: .replyCount)
        try container.encode(isFollowingAuthor, forKey: .isFollowingAuthor)
        try container.encode(isMutedAuthor, forKey: .isMutedAuthor)
        try container.encode(isBlockedAuthor, forKey: .isBlockedAuthor)
        try container.encode(platformSpecificId, forKey: .platformSpecificId)
        try container.encodeIfPresent(boostedBy, forKey: .boostedBy)
        try container.encodeIfPresent(parent, forKey: .parent)
        try container.encodeIfPresent(inReplyToID, forKey: .inReplyToID)
        try container.encodeIfPresent(inReplyToUsername, forKey: .inReplyToUsername)
        try container.encodeIfPresent(quotedPostUri, forKey: .quotedPostUri)
        try container.encodeIfPresent(quotedPostAuthorHandle, forKey: .quotedPostAuthorHandle)
        try container.encodeIfPresent(cid, forKey: .cid)
        try container.encodeIfPresent(primaryLinkURL, forKey: .primaryLinkURL)
        try container.encodeIfPresent(primaryLinkTitle, forKey: .primaryLinkTitle)
        try container.encodeIfPresent(primaryLinkDescription, forKey: .primaryLinkDescription)
        try container.encodeIfPresent(primaryLinkThumbnailURL, forKey: .primaryLinkThumbnailURL)
        try container.encodeIfPresent(quotedPost, forKey: .quotedPost)
        try container.encodeIfPresent(poll, forKey: .poll)
        try container.encodeIfPresent(blueskyLikeRecordURI, forKey: .blueskyLikeRecordURI)
        try container.encodeIfPresent(blueskyRepostRecordURI, forKey: .blueskyRepostRecordURI)
        try container.encodeIfPresent(customEmojiMap, forKey: .customEmojiMap)
        try container.encodeIfPresent(authorEmojiMap, forKey: .authorEmojiMap)
        try container.encodeIfPresent(boosterEmojiMap, forKey: .boosterEmojiMap)
        try container.encodeIfPresent(clientName, forKey: .clientName)
    }

    public init(
        id: String,
        content: String,
        authorName: String,
        authorUsername: String,
        authorId: String = "",
        authorProfilePictureURL: String,
        createdAt: Date,
        platform: SocialPlatform,
        originalURL: String,
        attachments: [Attachment] = [],
        mentions: [String] = [],
        tags: [String] = [],
        originalPost: Post? = nil,
        isReposted: Bool = false,
        isLiked: Bool = false,
        isReplied: Bool = false,
        likeCount: Int = 0,
        repostCount: Int = 0,
        replyCount: Int = 0,
        isFollowingAuthor: Bool = false,
        isMutedAuthor: Bool = false,
        isBlockedAuthor: Bool = false,
        platformSpecificId: String = "",
        boostedBy: String? = nil,
        parent: Post? = nil,
        inReplyToID: String? = nil,
        inReplyToUsername: String? = nil,
        quotedPostUri: String? = nil,
        quotedPostAuthorHandle: String? = nil,
        quotedPost: Post? = nil,
        poll: Poll? = nil,
        cid: String? = nil,
        primaryLinkURL: URL? = nil,
        primaryLinkTitle: String? = nil,
        primaryLinkDescription: String? = nil,
        primaryLinkThumbnailURL: URL? = nil,
        blueskyLikeRecordURI: String? = nil,
        blueskyRepostRecordURI: String? = nil,
        customEmojiMap: [String: String]? = nil,
        authorEmojiMap: [String: String]? = nil,
        boosterEmojiMap: [String: String]? = nil,
        clientName: String? = nil
    ) {
        self.id = id
        self.content = content
        self.authorName = authorName
        self.authorUsername = authorUsername
        self.authorId = authorId.isEmpty ? authorUsername : authorId
        self.authorProfilePictureURL = authorProfilePictureURL
        self.createdAt = createdAt
        self.platform = platform
        self.originalURL = originalURL
        self.attachments = attachments
        self.mentions = mentions
        self.tags = tags
        self.isReposted = isReposted
        self.isLiked = isLiked
        self.isReplied = isReplied
        self.likeCount = likeCount
        self.repostCount = repostCount
        self.replyCount = replyCount
        self.isFollowingAuthor = isFollowingAuthor
        self.isMutedAuthor = isMutedAuthor
        self.isBlockedAuthor = isBlockedAuthor
        self.platformSpecificId = platformSpecificId.isEmpty ? id : platformSpecificId
        self.boostedBy = boostedBy
        self.inReplyToID = inReplyToID
        self.inReplyToUsername = inReplyToUsername
        self.quotedPostUri = quotedPostUri
        self.quotedPostAuthorHandle = quotedPostAuthorHandle
        self.quotedPost = quotedPost
        self.poll = poll
        self.cid = cid
        self.primaryLinkURL = primaryLinkURL
        self.primaryLinkTitle = primaryLinkTitle
        self.primaryLinkDescription = primaryLinkDescription
        self.primaryLinkThumbnailURL = primaryLinkThumbnailURL
        self.blueskyLikeRecordURI = blueskyLikeRecordURI
        self.blueskyRepostRecordURI = blueskyRepostRecordURI
        self.customEmojiMap = customEmojiMap
        self.authorEmojiMap = authorEmojiMap
        self.boosterEmojiMap = boosterEmojiMap
        self.clientName = clientName
        // Defensive: prevent self-reference on construction
        if let parent = parent, parent.id == id {
            print(
                "[Post] Attempted to construct post with itself as parent (id: \(id)). Setting parent to nil."
            )
            self.parent = nil
        } else {
            self.parent = parent
        }
        if let originalPost = originalPost, originalPost.id == id {
            print(
                "[Post] Attempted to construct post with itself as originalPost (id: \(id)). Setting originalPost to nil."
            )
            self.originalPost = nil
        } else {
            self.originalPost = originalPost
        }
    }

    // Sample posts for previews and testing
    public static var samplePosts: [Post] = [
        Post(
            id: "1",
            content: "This is a sample post from Mastodon. #SocialFusion",
            authorName: "User One",
            authorUsername: "user1@mastodon.social",
            authorId: "user1-id",
            authorProfilePictureURL: "https://picsum.photos/200",
            createdAt: Date().addingTimeInterval(-3600),
            platform: .mastodon,
            originalURL: "https://mastodon.social/@user1/123456",
            attachments: [],
            mentions: [],
            tags: ["SocialFusion"],
            isLiked: true,
            likeCount: 5,
            repostCount: 2,
            replyCount: 0,
            platformSpecificId: "1",
            quotedPostUri: nil,
            quotedPostAuthorHandle: nil
        ),
        Post(
            id: "2",
            content: "Hello from Bluesky! Testing out the SocialFusion app.",
            authorName: "User Two",
            authorUsername: "user2.bsky.social",
            authorId: "did:plc:user2",
            authorProfilePictureURL: "https://picsum.photos/201",
            createdAt: Date().addingTimeInterval(-7200),
            platform: .bluesky,
            originalURL: "https://bsky.app/profile/user2.bsky.social/post/abcdef",
            attachments: [
                Attachment(
                    url: "https://httpbin.org/image/jpeg",
                    type: .image,
                    altText: "A sample image"
                )
            ],
            mentions: [],
            tags: [],
            likeCount: 3,
            repostCount: 1,
            platformSpecificId: "at://did:plc:user2/app.bsky.feed.post/abcdef",
            quotedPostUri: nil,
            quotedPostAuthorHandle: nil
        ),
        // Sample post with quote post (Bluesky)
        Post(
            id: "quote-test",
            content: "This is a great point! Quoting this for visibility.",
            authorName: "Quote User",
            authorUsername: "quoteuser.bsky.social",
            authorId: "did:plc:quoteuser",
            authorProfilePictureURL: "https://picsum.photos/204",
            createdAt: Date().addingTimeInterval(-1200),
            platform: .bluesky,
            originalURL: "https://bsky.app/profile/quoteuser.bsky.social/post/quoteid",
            attachments: [],
            mentions: [],
            tags: [],
            likeCount: 8,
            repostCount: 3,
            platformSpecificId: "at://did:plc:quoteuser/app.bsky.feed.post/quoteid",
            quotedPostUri: "at://did:plc:originalauthor/app.bsky.feed.post/originalid",
            quotedPostAuthorHandle: "original.bsky.social",
            quotedPost: Post(
                id: "quoted-original",
                content:
                    "Quote posts are a powerful way to add context and commentary to existing posts. They help facilitate meaningful discussions!",
                authorName: "Original Author",
                authorUsername: "original.bsky.social",
                authorId: "did:plc:originalauthor",
                authorProfilePictureURL: "https://picsum.photos/205",
                createdAt: Date().addingTimeInterval(-3600),
                platform: .bluesky,
                originalURL: "https://bsky.app/profile/original.bsky.social/post/originalid",
                attachments: [
                    Attachment(
                        url: "https://httpbin.org/image/png",
                        type: .image,
                        altText: "Quote post example image"
                    )
                ],
                mentions: [],
                tags: [],
                likeCount: 15,
                repostCount: 7,
                platformSpecificId: "at://did:plc:originalauthor/app.bsky.feed.post/originalid"
            )
        ),
        // Sample boosted post (Mastodon)
        Post(
            id: "3",
            content: "",
            authorName: "User Three",
            authorUsername: "user3@mastodon.social",
            authorId: "user3-id",
            authorProfilePictureURL: "https://picsum.photos/202",
            createdAt: Date().addingTimeInterval(-1800),
            platform: .mastodon,
            originalURL: "https://mastodon.social/@user3/boost/789012",
            attachments: [],
            mentions: [],
            tags: [],
            originalPost: Post(
                id: "4",
                content:
                    "This is the original post that was boosted. It contains original content from another user. #Mastodon",
                authorName: "Original User",
                authorUsername: "original@mastodon.social",
                authorId: "original-id",
                authorProfilePictureURL: "https://picsum.photos/203",
                createdAt: Date().addingTimeInterval(-5400),
                platform: .mastodon,
                originalURL: "https://mastodon.social/@original/789012",
                attachments: [
                    Attachment(
                        url: "https://httpbin.org/image/png",
                        type: .image,
                        altText: "Image in boosted post"
                    )
                ],
                mentions: [],
                tags: ["Mastodon"],
                likeCount: 12,
                repostCount: 5,
                platformSpecificId: "4",
                quotedPostUri: nil,
                quotedPostAuthorHandle: nil
            ),
            isReposted: true,
            repostCount: 5,
            platformSpecificId: "3",
            quotedPostUri: nil,
            quotedPostAuthorHandle: nil
        ),
        // Sample boosted post (Bluesky)
        Post(
            id: "5",
            content: "",
            authorName: "User Four",
            authorUsername: "user4.bsky.social",
            authorId: "did:plc:user4",
            authorProfilePictureURL: "https://picsum.photos/204",
            createdAt: Date().addingTimeInterval(-900),
            platform: .bluesky,
            originalURL: "https://bsky.app/profile/user4.bsky.social/post/repost/ghijkl",
            attachments: [],
            mentions: [],
            tags: [],
            originalPost: Post(
                id: "6",
                content: "Check out this photo from my latest hike! #Bluesky #Outdoors",
                authorName: "Original Bluesky User",
                authorUsername: "hiker.bsky.social",
                authorId: "did:plc:hiker",
                authorProfilePictureURL: "https://picsum.photos/205",
                createdAt: Date().addingTimeInterval(-10800),
                platform: .bluesky,
                originalURL: "https://bsky.app/profile/hiker.bsky.social/post/ghijkl",
                attachments: [
                    Attachment(
                        url: "https://httpbin.org/image/webp",
                        type: .image,
                        altText: "Mountain landscape with trees"
                    )
                ],
                mentions: [],
                tags: ["Bluesky", "Outdoors"],
                isLiked: true,
                likeCount: 25,
                repostCount: 8,
                platformSpecificId: "at://did:plc:hiker/app.bsky.feed.post/ghijkl"
            ),
            isReposted: true,
            repostCount: 8,
            platformSpecificId: "at://did:plc:user4/app.bsky.feed.repost/repostid"
        ),
    ]

    /// Create a copy of the post with a new ID
    func copy(with newId: String) -> Post {
        return Post(
            id: newId,
            content: self.content,
            authorName: self.authorName,
            authorUsername: self.authorUsername,
            authorId: self.authorId,
            authorProfilePictureURL: self.authorProfilePictureURL,
            createdAt: self.createdAt,
            platform: self.platform,
            originalURL: self.originalURL,
            attachments: self.attachments,
            mentions: self.mentions,
            tags: self.tags,
            originalPost: self.originalPost,
            isReposted: self.isReposted,
            isLiked: self.isLiked,
            isReplied: self.isReplied,
            likeCount: self.likeCount,
            repostCount: self.repostCount,
            replyCount: self.replyCount,
            isFollowingAuthor: self.isFollowingAuthor,
            isMutedAuthor: self.isMutedAuthor,
            isBlockedAuthor: self.isBlockedAuthor,
            platformSpecificId: newId,  // Update the platform-specific ID too
            boostedBy: self.boostedBy,
            parent: self.parent,
            inReplyToID: self.inReplyToID,
            inReplyToUsername: self.inReplyToUsername,
            quotedPostUri: self.quotedPostUri,
            quotedPostAuthorHandle: self.quotedPostAuthorHandle,
            quotedPost: self.quotedPost,
            poll: self.poll,
            cid: self.cid,
            primaryLinkURL: self.primaryLinkURL,
            primaryLinkTitle: self.primaryLinkTitle,
            primaryLinkDescription: self.primaryLinkDescription,
            primaryLinkThumbnailURL: self.primaryLinkThumbnailURL
        )
    }

    /// Create a deep copy of this post to prevent reference sharing issues
    func deepCopy() -> Post {
        return Post(
            id: self.id,
            content: self.content,
            authorName: self.authorName,
            authorUsername: self.authorUsername,
            authorId: self.authorId,
            authorProfilePictureURL: self.authorProfilePictureURL,
            createdAt: self.createdAt,
            platform: self.platform,
            originalURL: self.originalURL,
            attachments: self.attachments,
            mentions: self.mentions,
            tags: self.tags,
            originalPost: self.originalPost?.deepCopy(),  // Deep copy nested posts too
            isReposted: self.isReposted,
            isLiked: self.isLiked,
            isReplied: self.isReplied,
            likeCount: self.likeCount,
            repostCount: self.repostCount,
            replyCount: self.replyCount,
            isFollowingAuthor: self.isFollowingAuthor,
            isMutedAuthor: self.isMutedAuthor,
            isBlockedAuthor: self.isBlockedAuthor,
            platformSpecificId: self.platformSpecificId,
            boostedBy: self.boostedBy,
            parent: self.parent?.deepCopy(),  // Deep copy parent too
            inReplyToID: self.inReplyToID,
            inReplyToUsername: self.inReplyToUsername,
            quotedPostUri: self.quotedPostUri,
            quotedPostAuthorHandle: self.quotedPostAuthorHandle,
            quotedPost: self.quotedPost?.deepCopy(),  // Deep copy quoted posts too
            cid: self.cid,
            primaryLinkURL: self.primaryLinkURL,
            primaryLinkTitle: self.primaryLinkTitle,
            primaryLinkDescription: self.primaryLinkDescription,
            primaryLinkThumbnailURL: self.primaryLinkThumbnailURL,
            blueskyLikeRecordURI: self.blueskyLikeRecordURI,
            blueskyRepostRecordURI: self.blueskyRepostRecordURI
        )
    }

    var firstQuoteOrPreviewCardView: AnyView? {
        // Helper to check if a URL is a self-link
        func isSelfLink(_ url: URL, post: Post) -> Bool {
            guard let postURL = URL(string: post.originalURL) else { return false }
            return url.absoluteString == postURL.absoluteString
        }

        // 1. Bluesky: Prefer official quote
        if platform == .bluesky,
            let quotedUri = quotedPostUri,
            let quotedHandle = quotedPostAuthorHandle
        {
            let postId = quotedUri.split(separator: "/").last ?? ""
            if let url = URL(string: "https://bsky.app/profile/\(quotedHandle)/post/\(postId)") {
                return AnyView(FetchQuotePostView(url: url))
            }
        }

        // 2. For both Bluesky and Mastodon: look for first valid post link (not self-link)
        if let links = extractLinks(from: content) {
            for link in links {
                let isBlueskyPost = URLServiceWrapper.shared.isBlueskyPostURL(link)
                let isMastodonPost = URLServiceWrapper.shared.isMastodonPostURL(link)
                if (platform == .bluesky && isBlueskyPost)
                    || (platform == .mastodon && isMastodonPost)
                {
                    if !isSelfLink(link, post: self) {
                        return AnyView(FetchQuotePostView(url: link))
                    }
                }
            }
            // 3. Otherwise, show link preview for first valid previewable link (not self-link)
            for link in links {
                if !isSelfLink(link, post: self) {
                    // Check if it's a YouTube video
                    if URLServiceWrapper.shared.isYouTubeURL(link),
                        let videoID = URLServiceWrapper.shared.extractYouTubeVideoID(from: link)
                    {
                        return AnyView(YouTubeVideoPreview(url: link, videoID: videoID))
                    } else if !URLServiceWrapper.shared.isGIFURL(link) {
                        // Only show link preview if it's not a GIF URL
                        return AnyView(StabilizedLinkPreview(url: link, idealHeight: 140))
                    }
                }
            }
        }
        return nil
    }

    /// Returns a SwiftUI View for Bluesky content with tappable mentions and links (SwiftUI-native, no SwiftUIX)
    func blueskyContentView(onMentionTap: ((String) -> Void)? = nil) -> some View {
        let text = self.content
        let mentionRegex = try! NSRegularExpression(
            pattern: "@([A-Za-z0-9_]+)(\\.[A-Za-z0-9_]+)?", options: [])
        let urlRegex = try! NSRegularExpression(
            pattern: "https?://[A-Za-z0-9./?=_%-]+", options: [])
        let nsText = text as NSString
        var ranges: [(range: NSRange, type: String, value: String, extra: String?)] = []

        // Find mentions
        for match in mentionRegex.matches(
            in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        {
            let usernameRange = match.range(at: 1)
            let username = nsText.substring(with: usernameRange)
            var domain: String? = nil
            if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
                domain = nsText.substring(with: match.range(at: 2))
            }
            let punctuationSet = CharacterSet(charactersIn: ".,!?;:")
            let cleanDomain = domain?.trimmingCharacters(in: punctuationSet)
            ranges.append((match.range, "mention", username, cleanDomain))
        }
        // Find links
        for match in urlRegex.matches(
            in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        {
            var value = nsText.substring(with: match.range)
            while let last = value.last, ".,!?;:".contains(last) {
                value = String(value.dropLast())
            }
            ranges.append((match.range, "link", value, nil))
        }
        ranges.sort { $0.range.location < $1.range.location }

        // Build segments
        var segments: [(type: String, value: String, extra: String?)] = []
        var lastLoc = 0
        for r in ranges {
            if r.range.location > lastLoc {
                let plain = nsText.substring(
                    with: NSRange(location: lastLoc, length: r.range.location - lastLoc))
                segments.append(("plain", plain, nil))
            }
            segments.append((r.type, r.value, r.extra))
            lastLoc = r.range.location + r.range.length
        }
        if lastLoc < nsText.length {
            let plain = nsText.substring(from: lastLoc)
            segments.append(("plain", plain, nil))
        }

        // Build a single Text view for proper wrapping
        var textView = Text("")
        for seg in segments {
            switch seg.type {
            case "mention":
                let mentionText = Text("@" + seg.value)
                    .foregroundColor(.blue)
                    .bold()
                textView = textView + mentionText
                if let domain = seg.extra, !domain.isEmpty {
                    textView = textView + Text(domain)
                }
            case "link":
                let linkText = Text(seg.value)
                    .foregroundColor(.blue)
                    .underline()
                textView = textView + linkText
            default:
                textView = textView + Text(seg.value)
            }
        }
        return textView
    }

    public var isPlaceholder: Bool {
        return authorUsername == "unknown.bsky.social" || authorUsername == "unknown"
    }

    /// Helper to detect cycles in parent/originalPost chains
    public static func detectCycle(start: Post, next: Post?) -> Bool {
        var visited = Set<String>()
        var current = next
        while let node = current {
            if node.id == start.id { return true }
            if visited.contains(node.id) { return false }  // already checked
            visited.insert(node.id)
            // Check both parent and originalPost chains
            if let parent = node.parent, parent.id != node.id {
                current = parent
            } else if let orig = node.originalPost, orig.id != node.id {
                current = orig
            } else {
                break
            }
        }
        return false
    }
}

private class PostViewModelInternal: ObservableObject, Identifiable {
    enum Kind: Equatable {
        case normal
        case boost(boostedBy: String)
        case reply(parentId: String?)
    }

    @Published var post: Post
    @Published var isLiked: Bool
    @Published var isReposted: Bool
    @Published var isReplied: Bool
    @Published var likeCount: Int
    @Published var repostCount: Int
    @Published var replyCount: Int
    @Published var isLoading: Bool = false
    @Published var error: AppError? = nil

    // Timeline context
    let kind: Kind
    @Published var isParentExpanded: Bool = false
    @Published var isLoadingParent: Bool = false
    @Published var effectiveParentPost: Post? = nil

    var id: String { post.id }

    private var serviceManager: SocialServiceManager
    private var cancellables = Set<AnyCancellable>()

    init(post: Post, serviceManager: SocialServiceManager, kind: Kind? = nil) {
        self.post = post
        self.isLiked = post.isLiked
        self.isReposted = post.isReposted
        self.isReplied = post.isReplied
        self.likeCount = post.likeCount
        self.repostCount = post.repostCount
        self.replyCount = post.replyCount
        self.serviceManager = serviceManager
        // Determine kind if not provided
        if let kind = kind {
            self.kind = kind
        } else if let boostedBy = post.boostedBy {
            self.kind = .boost(boostedBy: boostedBy)
        } else if post.inReplyToID != nil {
            self.kind = .reply(parentId: post.inReplyToID)
        } else {
            self.kind = .normal
        }
        // Set initial value directly to avoid AttributeGraph cycles
        self.effectiveParentPost = post.parent
        // Removed parent observer that was causing AttributeGraph cycles
        // by creating feedback loops between @Published properties
    }

    @MainActor
    func like() async {
        // Prevent state modification during view updates to avoid AttributeGraph cycles
        guard !isLoading else { return }

        // Store original values for potential revert
        let prevLiked = isLiked
        let prevCount = likeCount

        // Optimistic UI update
        isLiked.toggle()
        likeCount += isLiked ? 1 : -1
        isLoading = true

        do {
            let updatedPost = try await serviceManager.likePost(post)
            // Update with server response
            post.isLiked = updatedPost.isLiked
            post.likeCount = updatedPost.likeCount
            self.isLiked = updatedPost.isLiked
            self.likeCount = updatedPost.likeCount
            self.isLoading = false
        } catch {
            // Revert UI on error
            isLiked = prevLiked
            likeCount = prevCount
            self.isLoading = false
            self.error = AppError(
                type: .general, message: error.localizedDescription, underlyingError: error)
        }
    }

    @MainActor
    func repost() async {
        // Prevent state modification during view updates to avoid AttributeGraph cycles
        guard !isLoading else { return }

        // Store original values for potential revert
        let prevReposted = isReposted
        let prevCount = repostCount

        // Optimistic UI update
        isReposted.toggle()
        repostCount += isReposted ? 1 : -1
        isLoading = true

        do {
            let updatedPost = try await serviceManager.repostPost(post)
            // Update with server response
            post.isReposted = updatedPost.isReposted
            post.repostCount = updatedPost.repostCount
            self.isReposted = updatedPost.isReposted
            self.repostCount = updatedPost.repostCount
            self.isLoading = false
        } catch {
            // Revert UI on error
            isReposted = prevReposted
            repostCount = prevCount
            self.isLoading = false
            self.error = AppError(
                type: .general, message: error.localizedDescription, underlyingError: error)
        }
    }

    func share() {
        let url = URL(string: post.originalURL) ?? URL(string: "https://example.com")!
        let activityController = UIActivityViewController(
            activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first,
            let rootViewController = window.rootViewController
        {
            rootViewController.present(activityController, animated: true, completion: nil)
        } else {
            self.error = AppError(
                type: .general, message: "Unable to present share sheet", underlyingError: nil)
        }
    }
}

// MARK: - Hashable Conformance
extension Post: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Thread Context

/// Represents a post's thread context with ancestors (parent posts) and descendants (replies)
struct ThreadContext {
    /// The main post that was the target of the thread request
    let mainPost: Post?

    /// Posts that come before this post in the thread (ancestors/parents)
    let ancestors: [Post]

    /// Posts that come after this post in the thread (replies/descendants)
    let descendants: [Post]

    /// Initialize a thread context
    /// - Parameters:
    ///   - mainPost: The target post (optional)
    ///   - ancestors: Parent posts in chronological order (oldest first)
    ///   - descendants: Reply posts in chronological order (newest first)
    init(mainPost: Post? = nil, ancestors: [Post] = [], descendants: [Post] = []) {
        self.mainPost = mainPost
        self.ancestors = ancestors
        self.descendants = descendants
    }

    /// Total number of posts in the thread context
    var totalContextPosts: Int {
        return ancestors.count + descendants.count
    }

    /// Whether this thread has any context (parents or replies)
    var hasContext: Bool {
        return !ancestors.isEmpty || !descendants.isEmpty
    }
}

// Extension to support video player functionality
extension Post.Attachment.AttachmentType {
    var needsVideoPlayer: Bool {
        switch self {
        case .video, .gifv:
            return true
        case .image, .audio, .animatedGIF:
            return false
        }
    }

    var isAnimated: Bool {
        switch self {
        case .gifv, .animatedGIF:
            return true
        case .video, .image, .audio:
            return false
        }
    }
}

// MARK: - Concurrency Support
// Post already conforms to @unchecked Sendable in its class declaration (line 120)

public struct NotificationAccount: Sendable, Codable {
    public let id: String
    public let username: String
    public let displayName: String?
    public let avatarURL: String?

    public init(id: String, username: String, displayName: String? = nil, avatarURL: String? = nil)
    {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
    }
}

public struct DirectMessage: Identifiable, Codable, Sendable {
    public let id: String
    public let sender: NotificationAccount
    public let recipient: NotificationAccount
    public let content: String
    public let createdAt: Date
    public let platform: SocialPlatform

    public init(
        id: String, sender: NotificationAccount, recipient: NotificationAccount, content: String,
        createdAt: Date, platform: SocialPlatform
    ) {
        self.id = id
        self.sender = sender
        self.recipient = recipient
        self.content = content
        self.createdAt = createdAt
        self.platform = platform
    }
}

public struct DMConversation: Identifiable, Codable, Sendable {
    public let id: String
    public let participant: NotificationAccount
    public let lastMessage: DirectMessage
    public let unreadCount: Int
    public let platform: SocialPlatform

    public init(
        id: String, participant: NotificationAccount, lastMessage: DirectMessage, unreadCount: Int,
        platform: SocialPlatform
    ) {
        self.id = id
        self.participant = participant
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
        self.platform = platform
    }
}

public enum UnifiedChatMessage: Identifiable, Sendable {
    case bluesky(BlueskyChatMessage)
    case mastodon(Post)

    public var id: String {
        switch self {
        case .bluesky(let msg): return msg.id
        case .mastodon(let post): return post.id
        }
    }

    public var text: String {
        switch self {
        case .bluesky(let msg):
            switch msg {
            case .message(let view): return view.text
            case .deleted: return "(Deleted Message)"
            }
        case .mastodon(let post):
            // Mastodon content is HTML - convert to plain text for display
            if post.content.isEmpty {
                return "(Empty message)"
            }
            let htmlString = HTMLString(raw: post.content)
            return htmlString.plainText
        }
    }

    public var sentAt: Date {
        switch self {
        case .bluesky(let msg):
            switch msg {
            case .message(let view): return ISO8601DateFormatter().date(from: view.sentAt) ?? Date()
            case .deleted: return Date()
            }
        case .mastodon(let post): return post.createdAt
        }
    }

    public var authorId: String {
        switch self {
        case .bluesky(let msg):
            switch msg {
            case .message(let view): return view.sender.did
            case .deleted: return ""
            }
        case .mastodon(let post): return post.authorId
        }
    }
}

import Combine
import Foundation
import SwiftUI
// MARK: - AttributedTextOverlay for per-segment tap support
import UIKit

// MARK: - Post Actions
public enum PostAction {
    case reply
    case repost
    case like
    case share
    case quote
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
public class Post: Identifiable, Codable, Equatable, ObservableObject {
    public let id: String
    public let content: String
    public let authorName: String
    public let authorUsername: String
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
            if let original = originalPost, Post.detectCycle(start: self, next: original) {
                print(
                    "[Post] Cycle detected in originalPost chain for post id: \(id). Breaking cycle."
                )
                originalPost = nil
            }
        }
    }
    @Published public var isReposted: Bool = false
    @Published public var isLiked: Bool = false
    @Published public var isReplied: Bool = false
    @Published public var likeCount: Int = 0
    @Published public var repostCount: Int = 0
    @Published public var replyCount: Int = 0

    // Properties for reply and boost functionality - these should NOT be @Published
    // to prevent cycles when Posts contain other Posts
    public var boostedBy: String?
    public var parent: Post? {
        didSet {
            if let parentPost = parent, Post.detectCycle(start: self, next: parentPost) {
                print("[Post] Cycle detected in parent chain for post id: \(id). Breaking cycle.")
                parent = nil
            }
        }
    }
    public var inReplyToID: String?
    public var inReplyToUsername: String?

    // Quoted post support - NOT @Published to prevent cycles
    public var quotedPost: Post? = nil

    // Computed properties for convenience
    public var authorHandle: String {
        return authorUsername
    }

    // Platform-specific IDs for API operations
    public let platformSpecificId: String

    let quotedPostUri: String?
    let quotedPostAuthorHandle: String?

    public var cid: String?  // Bluesky only, optional for backward compatibility

    // Bluesky AT Protocol record URIs for unlike/unrepost functionality
    public var blueskyLikeRecordURI: String?  // URI of the like record created by this user
    public var blueskyRepostRecordURI: String?  // URI of the repost record created by this user

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
        case platformSpecificId
        case boostedBy
        case parent
        case inReplyToID
        case inReplyToUsername
        case quotedPostUri
        case quotedPostAuthorHandle
        case cid
        case quotedPost
        case blueskyLikeRecordURI
        case blueskyRepostRecordURI
    }

    public required convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let content = try container.decode(String.self, forKey: .content)
        let authorName = try container.decode(String.self, forKey: .authorName)
        let authorUsername = try container.decode(String.self, forKey: .authorUsername)
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
        let quotedPost = try container.decodeIfPresent(Post.self, forKey: .quotedPost)
        let blueskyLikeRecordURI = try container.decodeIfPresent(
            String.self, forKey: .blueskyLikeRecordURI)
        let blueskyRepostRecordURI = try container.decodeIfPresent(
            String.self, forKey: .blueskyRepostRecordURI)
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
            platformSpecificId: platformSpecificId,
            boostedBy: boostedBy,
            parent: parent,
            inReplyToID: inReplyToID,
            inReplyToUsername: inReplyToUsername,
            quotedPostUri: quotedPostUri,
            quotedPostAuthorHandle: quotedPostAuthorHandle,
            quotedPost: quotedPost,
            cid: cid,
            blueskyLikeRecordURI: blueskyLikeRecordURI,
            blueskyRepostRecordURI: blueskyRepostRecordURI
        )
        self.cid = cid
        self.quotedPost = quotedPost
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(authorName, forKey: .authorName)
        try container.encode(authorUsername, forKey: .authorUsername)
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
        try container.encode(platformSpecificId, forKey: .platformSpecificId)
        try container.encodeIfPresent(boostedBy, forKey: .boostedBy)
        try container.encodeIfPresent(parent, forKey: .parent)
        try container.encodeIfPresent(inReplyToID, forKey: .inReplyToID)
        try container.encodeIfPresent(inReplyToUsername, forKey: .inReplyToUsername)
        try container.encodeIfPresent(quotedPostUri, forKey: .quotedPostUri)
        try container.encodeIfPresent(quotedPostAuthorHandle, forKey: .quotedPostAuthorHandle)
        try container.encodeIfPresent(cid, forKey: .cid)
        try container.encodeIfPresent(quotedPost, forKey: .quotedPost)
        try container.encodeIfPresent(blueskyLikeRecordURI, forKey: .blueskyLikeRecordURI)
        try container.encodeIfPresent(blueskyRepostRecordURI, forKey: .blueskyRepostRecordURI)
    }

    public init(
        id: String,
        content: String,
        authorName: String,
        authorUsername: String,
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
        platformSpecificId: String = "",
        boostedBy: String? = nil,
        parent: Post? = nil,
        inReplyToID: String? = nil,
        inReplyToUsername: String? = nil,
        quotedPostUri: String? = nil,
        quotedPostAuthorHandle: String? = nil,
        quotedPost: Post? = nil,
        cid: String? = nil,
        blueskyLikeRecordURI: String? = nil,
        blueskyRepostRecordURI: String? = nil
    ) {
        self.id = id
        self.content = content
        self.authorName = authorName
        self.authorUsername = authorUsername
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
        self.platformSpecificId = platformSpecificId.isEmpty ? id : platformSpecificId
        self.boostedBy = boostedBy
        self.inReplyToID = inReplyToID
        self.inReplyToUsername = inReplyToUsername
        self.quotedPostUri = quotedPostUri
        self.quotedPostAuthorHandle = quotedPostAuthorHandle
        self.quotedPost = quotedPost
        self.cid = cid
        self.blueskyLikeRecordURI = blueskyLikeRecordURI
        self.blueskyRepostRecordURI = blueskyRepostRecordURI
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
            platformSpecificId: "",
            quotedPostUri: nil,
            quotedPostAuthorHandle: nil
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
                    url: "https://httpbin.org/image/jpeg",
                    type: .image,
                    altText: "A sample image"
                )
            ],
            mentions: [],
            tags: [],
            likeCount: 3,
            repostCount: 1,
            platformSpecificId: "",
            quotedPostUri: nil,
            quotedPostAuthorHandle: nil
        ),
        // Sample post with quote post (Bluesky)
        Post(
            id: "quote-test",
            content: "This is a great point! Quoting this for visibility.",
            authorName: "Quote User",
            authorUsername: "quoteuser.bsky.social",
            authorProfilePictureURL: "https://picsum.photos/204",
            createdAt: Date().addingTimeInterval(-1200),
            platform: .bluesky,
            originalURL: "https://bsky.app/profile/quoteuser.bsky.social/post/quoteid",
            attachments: [],
            mentions: [],
            tags: [],
            likeCount: 8,
            repostCount: 3,
            platformSpecificId: "at://did:plc:example/app.bsky.feed.post/quoteid",
            quotedPostUri: "at://did:plc:example/app.bsky.feed.post/originalid",
            quotedPostAuthorHandle: "original.bsky.social",
            quotedPost: Post(
                id: "quoted-original",
                content:
                    "Quote posts are a powerful way to add context and commentary to existing posts. They help facilitate meaningful discussions!",
                authorName: "Original Author",
                authorUsername: "original.bsky.social",
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
                platformSpecificId: "at://did:plc:example/app.bsky.feed.post/originalid"
            )
        ),
        // Sample boosted post (Mastodon)
        Post(
            id: "3",
            content: "",
            authorName: "User Three",
            authorUsername: "user3@mastodon.social",
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
                platformSpecificId: "",
                quotedPostUri: nil,
                quotedPostAuthorHandle: nil
            ),
            isReposted: true,
            repostCount: 5,
            platformSpecificId: "",
            quotedPostUri: nil,
            quotedPostAuthorHandle: nil
        ),
        // Sample boosted post (Bluesky)
        Post(
            id: "5",
            content: "",
            authorName: "User Four",
            authorUsername: "user4.bsky.social",
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
                platformSpecificId: "",
                quotedPostUri: nil,
                quotedPostAuthorHandle: nil
            ),
            isReposted: true,
            repostCount: 8,
            platformSpecificId: "",
            quotedPostUri: nil,
            quotedPostAuthorHandle: nil
        ),
    ]

    /// Create a copy of the post with a new ID
    func copy(with newId: String) -> Post {
        return Post(
            id: newId,
            content: self.content,
            authorName: self.authorName,
            authorUsername: self.authorUsername,
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
            platformSpecificId: newId,  // Update the platform-specific ID too
            boostedBy: self.boostedBy,
            parent: self.parent,
            inReplyToID: self.inReplyToID,
            inReplyToUsername: self.inReplyToUsername,
            quotedPostUri: self.quotedPostUri,
            quotedPostAuthorHandle: self.quotedPostAuthorHandle,
            quotedPost: self.quotedPost,
            cid: self.cid
        )
    }

    /// Create a deep copy of this post to prevent reference sharing issues
    func deepCopy() -> Post {
        return Post(
            id: self.id,
            content: self.content,
            authorName: self.authorName,
            authorUsername: self.authorUsername,
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
            platformSpecificId: self.platformSpecificId,
            boostedBy: self.boostedBy,
            parent: self.parent?.deepCopy(),  // Deep copy parent too
            inReplyToID: self.inReplyToID,
            inReplyToUsername: self.inReplyToUsername,
            quotedPostUri: self.quotedPostUri,
            quotedPostAuthorHandle: self.quotedPostAuthorHandle,
            quotedPost: self.quotedPost?.deepCopy(),  // Deep copy quoted posts too
            cid: self.cid,
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
                    } else {
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

class PostViewModel: ObservableObject, Identifiable {
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
    /// Posts that come before this post in the thread (ancestors/parents)
    let ancestors: [Post]

    /// Posts that come after this post in the thread (replies/descendants)
    let descendants: [Post]

    /// Initialize a thread context
    /// - Parameters:
    ///   - ancestors: Parent posts in chronological order (oldest first)
    ///   - descendants: Reply posts in chronological order (newest first)
    init(ancestors: [Post] = [], descendants: [Post] = []) {
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

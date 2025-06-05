import Foundation

/// Represents the type of content in a timeline entry
public enum TimelineEntryKind {
    case normal
    case boost(boostedBy: String)
    case reply(parentId: String)
}

/// A unified timeline entry that wraps a Post with additional metadata for timeline display
public struct TimelineEntry: Identifiable, Hashable {
    public let id: String
    public let kind: TimelineEntryKind
    public let post: Post
    public let createdAt: Date

    public init(id: String, kind: TimelineEntryKind, post: Post, createdAt: Date) {
        self.id = post.stableId  // Use the post's stable ID
        self.kind = kind
        self.post = post
        self.createdAt = createdAt
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: TimelineEntry, rhs: TimelineEntry) -> Bool {
        lhs.id == rhs.id
    }
}

/// Pagination information for tracking timeline pagination state
public struct PaginationInfo {
    public let hasNextPage: Bool
    public let nextPageToken: String?

    public init(hasNextPage: Bool, nextPageToken: String? = nil) {
        self.hasNextPage = hasNextPage
        self.nextPageToken = nextPageToken
    }

    public static let empty = PaginationInfo(hasNextPage: false, nextPageToken: nil)
}

/// Result of a timeline fetch with pagination information
public struct TimelineResult {
    public let posts: [Post]
    public let pagination: PaginationInfo

    public init(posts: [Post], pagination: PaginationInfo) {
        self.posts = posts
        self.pagination = pagination
    }
}

import Foundation

/// Represents a single, display-ready entry in the timeline (normal, boost, reply, etc.)
struct TimelineEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case normal
        case boost(boostedBy: String)
        case reply(parentId: String?)
    }

    let id: String
    let kind: Kind
    let post: Post
    let createdAt: Date
    // Add more display info as needed (e.g., reply context, pinned, etc.)

    // Convenience for boosts
    var boostedBy: String? {
        if case let .boost(boostedBy) = kind { return boostedBy } else { return nil }
    }
    // Convenience for replies
    var parentId: String? {
        if case let .reply(parentId) = kind { return parentId } else { return nil }
    }
}

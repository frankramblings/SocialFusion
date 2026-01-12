import Foundation
import SwiftUI

// MARK: - Render Models

/// Represents a post that can be rendered in a share image
public struct PostRenderable: Identifiable {
    public let id: String
    public let title: String?  // Context line like "in ..."
    public let contextLabel: String?  // "Boosted by ..." or "Replying to ..."
    public let authorDisplayName: String
    public let authorHandle: String
    public let authorId: String
    public let authorAvatarURL: URL?  // Profile picture URL
    public let networkLabel: String  // "Mastodon" or "Bluesky"
    public let timestampString: String
    public let detailedTimestampString: String?  // Full date/time for "Just this" mode
    public let statsString: String  // "12 replies • 5 reposts • 23 likes"
    public let boostBannerData: BoostBannerData?
    public let quotePostData: QuotePostData?
    public let mediaThumbnails: [MediaThumbnail]
    public let linkPreviewData: LinkPreviewData?
    public let content: AttributedString
    public let platform: SocialPlatform
    
    public struct BoostBannerData {
        public let boosterHandle: String
        public let boosterDisplayName: String?
    }
    
    public struct QuotePostData {
        public let authorDisplayName: String
        public let authorHandle: String
        public let content: AttributedString
        public let mediaThumbnails: [MediaThumbnail]
    }
    
    public struct MediaThumbnail {
        public let url: URL?
        public let type: MediaType
        public let placeholder: String
        
        public enum MediaType {
            case image
            case video
            case gif
        }
    }
    
    public struct LinkPreviewData {
        public let url: URL
        public let title: String
        public let description: String?
        public let thumbnailURL: URL?
    }
}

/// Represents a comment/reply that can be rendered in a share image
public struct CommentRenderable: Identifiable {
    public let id: String
    public let parentID: String?
    public let authorID: String
    public let authorDisplayName: String
    public let authorHandle: String
    public let authorAvatarURL: URL?  // Profile picture URL
    public let timestampString: String
    public let score: Int?  // For sorting (likes/reposts)
    public let content: AttributedString
    public let depth: Int  // Visual depth for indentation
    public let isSelected: Bool  // Whether this is the selected comment
    public let platform: SocialPlatform
    public let parentAuthorDisplayName: String?  // For "Replying to..." label
}

/// Represents a complete document to be rendered as a share image
public struct ShareImageDocument {
    public let selectedPost: PostRenderable
    public let selectedCommentID: String?  // If sharing a specific comment
    public let ancestorChain: [CommentRenderable]  // Parent comments up to root
    public let replySubtree: [CommentRenderable]  // Replies under selected, in preorder
    public let includePostDetails: Bool
    public let hideUsernames: Bool
    public let showWatermark: Bool
    public let includeReplies: Bool
    
    /// All comments in render order (ancestors + selected + replies)
    public var allComments: [CommentRenderable] {
        var result: [CommentRenderable] = []
        result.append(contentsOf: ancestorChain)
        if let selected = replySubtree.first(where: { $0.isSelected }) {
            result.append(selected)
            // Add remaining replies (excluding selected which is already added)
            result.append(contentsOf: replySubtree.filter { !$0.isSelected })
        } else {
            result.append(contentsOf: replySubtree)
        }
        return result
    }
}

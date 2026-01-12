import Foundation
import SwiftUI

/// Stable layout snapshot for a post row that prevents reflow
/// All layout-affecting properties are captured BEFORE rendering
/// Once a row is on-screen, its snapshot should remain stable
struct PostLayoutSnapshot: Identifiable, Equatable {
  let id: String
  
  // Banner visibility (affects height)
  let isBoostBannerVisible: Bool
  let isReplyBannerVisible: Bool
  
  // Text content key (hash of rendered text + content warning state)
  // Used to detect if text content changed in a way that affects layout
  let textKey: String
  
  // Media blocks with stable aspect ratios
  let mediaBlocks: [MediaBlockSnapshot]
  
  // Quote attachment (if present)
  let quoteSnapshot: QuoteSnapshot?
  
  // Link preview (if present)
  let linkPreviewSnapshot: LinkPreviewSnapshot?
  
  // Poll (if present) - has fixed height
  let hasPoll: Bool
  
  // Content warning state (affects text rendering)
  let hasContentWarning: Bool
  
  /// Computes a stable hash for text content
  static func computeTextKey(
    content: String,
    hasContentWarning: Bool,
    isExpanded: Bool
  ) -> String {
    let combined = "\(content)|\(hasContentWarning)|\(isExpanded)"
    return String(combined.hashValue)
  }
}

/// Snapshot for a single media block with stable dimensions
struct MediaBlockSnapshot: Identifiable, Equatable {
  let id: String
  let url: String
  let type: Post.Attachment.AttachmentType
  let aspectRatio: CGFloat?  // nil means defer rendering
  let width: Int?
  let height: Int?
  let altText: String?
  
  /// Whether this media should be shown immediately
  /// If false, a placeholder with fixed height should be shown
  var shouldShow: Bool {
    aspectRatio != nil
  }
  
  /// Default aspect ratio to use if unknown
  /// Prevents layout jumps by using a reasonable default
  static let defaultAspectRatio: CGFloat = 16.0 / 9.0
  
  /// Placeholder height for unknown aspect ratios
  static let placeholderHeight: CGFloat = 200
}

/// Snapshot for quote attachment
struct QuoteSnapshot: Equatable {
  let postId: String
  let authorName: String
  let authorUsername: String
  let content: String
  let hasMedia: Bool
  let mediaAspectRatio: CGFloat?  // For quote's embedded media
  
  // Fixed height for quote cards (prevents reflow)
  static let fixedHeight: CGFloat = 120
}

/// Snapshot for link preview
struct LinkPreviewSnapshot: Equatable {
  let url: String
  let title: String?
  let description: String?
  let thumbnailURL: String?
  let thumbnailAspectRatio: CGFloat?
  
  // Fixed height for link previews (prevents reflow)
  static let fixedHeight: CGFloat = 100
}

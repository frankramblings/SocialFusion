import Foundation

/// Builds stable PostLayoutSnapshot from a Post
/// Uses cache and payload dimensions to ensure stable layout
@MainActor
class PostLayoutSnapshotBuilder {
  private let dimensionCache: MediaDimensionCache
  private let prefetcher: MediaPrefetcher
  
  init(
    dimensionCache: MediaDimensionCache = .shared,
    prefetcher: MediaPrefetcher = .shared
  ) {
    self.dimensionCache = dimensionCache
    self.prefetcher = prefetcher
  }
  
  /// Build snapshot for a post
  /// This should be called BEFORE the post appears on screen
  func buildSnapshot(for post: Post) async -> PostLayoutSnapshot {
    // Determine which post to display (original for boosts)
    let displayPost = post.originalPost ?? post
    
    // Determine banner visibility (stable - based on post state, not async)
    let isBoostBannerVisible = determineBoostBannerVisibility(for: post)
    let isReplyBannerVisible = displayPost.inReplyToID != nil
    
    // Build text key
    let textKey = PostLayoutSnapshot.computeTextKey(
      content: displayPost.content,
      hasContentWarning: false,  // TODO: Add content warning support if needed
      isExpanded: false
    )
    
    // Build media blocks (with dimensions from cache or payload)
    let mediaBlocks = await buildMediaBlocks(for: displayPost)
    
    // Build quote snapshot (if present)
    let quoteSnapshot = buildQuoteSnapshot(for: displayPost)
    
    // Build link preview snapshot (if present)
    let linkPreviewSnapshot = buildLinkPreviewSnapshot(for: displayPost)
    
    // Check for poll
    let hasPoll = displayPost.poll != nil
    
    return PostLayoutSnapshot(
      id: post.id,
      isBoostBannerVisible: isBoostBannerVisible,
      isReplyBannerVisible: isReplyBannerVisible,
      textKey: textKey,
      mediaBlocks: mediaBlocks,
      quoteSnapshot: quoteSnapshot,
      linkPreviewSnapshot: linkPreviewSnapshot,
      hasPoll: hasPoll,
      hasContentWarning: false
    )
  }
  
  /// Build snapshot synchronously (uses cached dimensions only)
  /// Use this when you need a snapshot immediately but can accept missing dimensions
  func buildSnapshotSync(for post: Post) -> PostLayoutSnapshot {
    let displayPost = post.originalPost ?? post
    
    let isBoostBannerVisible = determineBoostBannerVisibility(for: post)
    let isReplyBannerVisible = displayPost.inReplyToID != nil
    
    let textKey = PostLayoutSnapshot.computeTextKey(
      content: displayPost.content,
      hasContentWarning: false,
      isExpanded: false
    )
    
    // Build media blocks using only cached/payload dimensions
    let mediaBlocks = buildMediaBlocksSync(for: displayPost)
    
    let quoteSnapshot = buildQuoteSnapshot(for: displayPost)
    let linkPreviewSnapshot = buildLinkPreviewSnapshot(for: displayPost)
    let hasPoll = displayPost.poll != nil
    
    return PostLayoutSnapshot(
      id: post.id,
      isBoostBannerVisible: isBoostBannerVisible,
      isReplyBannerVisible: isReplyBannerVisible,
      textKey: textKey,
      mediaBlocks: mediaBlocks,
      quoteSnapshot: quoteSnapshot,
      linkPreviewSnapshot: linkPreviewSnapshot,
      hasPoll: hasPoll,
      hasContentWarning: false
    )
  }
  
  // MARK: - Private Helpers
  
  private func determineBoostBannerVisibility(for post: Post) -> Bool {
    // Check if this is a boost
    if post.originalPost != nil {
      return true
    }
    
    // Check boostedBy metadata
    if post.boostedBy != nil && !post.boostedBy!.isEmpty {
      return true
    }
    
    // Check boosters
    if !post.boostersPreview.isEmpty || post.boosters != nil {
      return true
    }
    
    return false
  }
  
  private func buildMediaBlocks(for post: Post) async -> [MediaBlockSnapshot] {
    let attachments = post.attachments
    
    return await withTaskGroup(of: MediaBlockSnapshot?.self, returning: [MediaBlockSnapshot].self) { group in
      for attachment in attachments {
        group.addTask {
          await self.buildMediaBlock(for: attachment)
        }
      }
      
      var blocks: [MediaBlockSnapshot] = []
      for await block in group {
        if let block = block {
          blocks.append(block)
        }
      }
      
      // Preserve original order
      return attachments.compactMap { attachment in
        blocks.first { $0.url == attachment.url }
      }
    }
  }
  
  private func buildMediaBlock(for attachment: Post.Attachment) async -> MediaBlockSnapshot? {
    // First, try payload dimensions
    if let width = attachment.width, let height = attachment.height, width > 0 && height > 0 {
      let aspectRatio = CGFloat(width) / CGFloat(height)
      return MediaBlockSnapshot(
        id: attachment.id,
        url: attachment.url,
        type: attachment.type,
        aspectRatio: aspectRatio,
        width: width,
        height: height,
        altText: attachment.altText
      )
    }
    
    // Try cache
    if let cachedRatio = dimensionCache.getAspectRatio(for: attachment.url) {
      return MediaBlockSnapshot(
        id: attachment.id,
        url: attachment.url,
        type: attachment.type,
        aspectRatio: cachedRatio,
        width: attachment.width,
        height: attachment.height,
        altText: attachment.altText
      )
    }
    
    // Try to fetch (but don't block - return nil if not available)
    if let url = URL(string: attachment.url),
       let size = await ImageSizeFetcher.fetchImageSize(url: url) {
      let aspectRatio = size.width / size.height
      return MediaBlockSnapshot(
        id: attachment.id,
        url: attachment.url,
        type: attachment.type,
        aspectRatio: aspectRatio,
        width: Int(size.width),
        height: Int(size.height),
        altText: attachment.altText
      )
    }
    
    // No dimension available - return block with nil aspectRatio (will show placeholder)
    return MediaBlockSnapshot(
      id: attachment.id,
      url: attachment.url,
      type: attachment.type,
      aspectRatio: nil,
      width: attachment.width,
      height: attachment.height,
      altText: attachment.altText
    )
  }
  
  private func buildMediaBlocksSync(for post: Post) -> [MediaBlockSnapshot] {
    return post.attachments.map { attachment in
      // Try payload dimensions first
      if let width = attachment.width, let height = attachment.height, width > 0 && height > 0 {
        let aspectRatio = CGFloat(width) / CGFloat(height)
        return MediaBlockSnapshot(
          id: attachment.id,
          url: attachment.url,
          type: attachment.type,
          aspectRatio: aspectRatio,
          width: width,
          height: height,
          altText: attachment.altText
        )
      }
      
      // Try cache
      if let cachedRatio = dimensionCache.getAspectRatio(for: attachment.url) {
        return MediaBlockSnapshot(
          id: attachment.id,
          url: attachment.url,
          type: attachment.type,
          aspectRatio: cachedRatio,
          width: attachment.width,
          height: attachment.height,
          altText: attachment.altText
        )
      }
      
      // No dimension available
      return MediaBlockSnapshot(
        id: attachment.id,
        url: attachment.url,
        type: attachment.type,
        aspectRatio: nil,
        width: attachment.width,
        height: attachment.height,
        altText: attachment.altText
      )
    }
  }
  
  private func buildQuoteSnapshot(for post: Post) -> QuoteSnapshot? {
    guard let quotedPost = post.quotedPost else {
      return nil
    }
    
    let hasMedia = !quotedPost.attachments.isEmpty
    var mediaAspectRatio: CGFloat? = nil
    
    if hasMedia, let firstAttachment = quotedPost.attachments.first {
      // Try to get aspect ratio from payload or cache
      if let width = firstAttachment.width, let height = firstAttachment.height, height > 0 {
        mediaAspectRatio = CGFloat(width) / CGFloat(height)
      } else if let cachedRatio = dimensionCache.getAspectRatio(for: firstAttachment.url) {
        mediaAspectRatio = cachedRatio
      }
    }
    
    return QuoteSnapshot(
      postId: quotedPost.id,
      authorName: quotedPost.authorName,
      authorUsername: quotedPost.authorUsername,
      content: quotedPost.content,
      hasMedia: hasMedia,
      mediaAspectRatio: mediaAspectRatio
    )
  }
  
  private func buildLinkPreviewSnapshot(for post: Post) -> LinkPreviewSnapshot? {
    guard let linkURL = post.primaryLinkURL else {
      return nil
    }
    
    var thumbnailAspectRatio: CGFloat? = nil
    
    if let thumbnailURL = post.primaryLinkThumbnailURL {
      // Try to get aspect ratio from cache
      thumbnailAspectRatio = dimensionCache.getAspectRatio(for: thumbnailURL.absoluteString)
    }
    
    return LinkPreviewSnapshot(
      url: linkURL.absoluteString,
      title: post.primaryLinkTitle,
      description: post.primaryLinkDescription,
      thumbnailURL: post.primaryLinkThumbnailURL?.absoluteString,
      thumbnailAspectRatio: thumbnailAspectRatio
    )
  }
}

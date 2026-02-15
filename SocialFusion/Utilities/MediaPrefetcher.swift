import Foundation

/// Prefetches media dimensions before posts appear on screen
@MainActor
class MediaPrefetcher {
  static let shared = MediaPrefetcher()
  
  private var prefetchTasks: [String: Task<Void, Never>] = [:]
  private var prefetchGeneration: [String: UUID] = [:]
  
  private init() {}
  
  /// Prefetch dimensions for a post's attachments.
  /// When `force` is false, existing in-flight work for unchanged posts is preserved.
  func prefetchDimensions(for post: Post, force: Bool = false) {
    let postId = post.id

    if force {
      prefetchTasks[postId]?.cancel()
      prefetchTasks.removeValue(forKey: postId)
      prefetchGeneration.removeValue(forKey: postId)
    } else if prefetchTasks[postId] != nil {
      return
    }
    let generation = UUID()
    prefetchGeneration[postId] = generation
    
    // Get attachments to prefetch
    let attachments = post.originalPost?.attachments ?? post.attachments
    let uncachedAttachments = attachments.filter {
      MediaDimensionCache.shared.getAspectRatio(for: $0.url) == nil
    }
    guard !uncachedAttachments.isEmpty else {
      prefetchGeneration.removeValue(forKey: postId)
      return
    }
    
    // Start prefetch task
    prefetchTasks[postId] = Task { [weak self] in
      guard let self = self else { return }
      await prefetchAttachments(uncachedAttachments)
      if prefetchGeneration[postId] == generation {
        prefetchTasks.removeValue(forKey: postId)
        prefetchGeneration.removeValue(forKey: postId)
      }
    }
  }
  
  /// Prefetch dimensions for multiple posts (batch)
  func prefetchDimensions(for posts: [Post], force: Bool = false) {
    for post in posts {
      prefetchDimensions(for: post, force: force)
    }
  }
  
  /// Prefetch dimensions for attachments that are about to appear
  func prefetchUpcoming(visiblePostIds: [String], upcomingPosts: [Post], lookahead: Int = 10) {
    let visibleSet = Set(visiblePostIds)
    
    // Prefetch next N posts that aren't visible yet
    let toPrefetch = upcomingPosts
      .filter { !visibleSet.contains($0.id) }
      .prefix(lookahead)
    
    for post in toPrefetch {
      prefetchDimensions(for: post)
    }
  }

  func prefetchLookahead(posts: [Post], from startIndex: Int, lookahead: Int = 12) {
    guard !posts.isEmpty else { return }
    let safeStart = max(0, min(startIndex, posts.count - 1))
    let safeEnd = min(posts.count, safeStart + max(0, lookahead))
    guard safeStart < safeEnd else { return }

    for index in safeStart..<safeEnd {
      prefetchDimensions(for: posts[index])
    }
  }
  
  /// Cancel prefetch for a post
  func cancelPrefetch(for postId: String) {
    prefetchTasks[postId]?.cancel()
    prefetchTasks.removeValue(forKey: postId)
    prefetchGeneration.removeValue(forKey: postId)
  }
  
  /// Cancel all prefetches
  func cancelAll() {
    for task in prefetchTasks.values {
      task.cancel()
    }
    prefetchTasks.removeAll()
    prefetchGeneration.removeAll()
  }
  
  // MARK: - Private Helpers
  
  private func prefetchAttachments(_ attachments: [Post.Attachment]) async {
    await withTaskGroup(of: Void.self) { group in
      for attachment in attachments {
        // Skip if already cached
        if MediaDimensionCache.shared.getAspectRatio(for: attachment.url) != nil {
          continue
        }
        
        // Prefetch dimension
        group.addTask {
          if let url = URL(string: attachment.url) {
            _ = await ImageSizeFetcher.fetchImageSize(url: url)
          }
        }
      }
    }
  }
}

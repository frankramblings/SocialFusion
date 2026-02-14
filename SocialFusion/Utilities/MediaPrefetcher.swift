import Foundation

/// Prefetches media dimensions before posts appear on screen
@MainActor
class MediaPrefetcher {
  static let shared = MediaPrefetcher()
  
  private var prefetchTasks: [String: Task<Void, Never>] = [:]
  private var prefetchGeneration: [String: UUID] = [:]
  
  private init() {}
  
  /// Prefetch dimensions for a post's attachments
  func prefetchDimensions(for post: Post) {
    let postId = post.id
    
    // Cancel existing prefetch for this post
    prefetchTasks[postId]?.cancel()
    let generation = UUID()
    prefetchGeneration[postId] = generation
    
    // Get attachments to prefetch
    let attachments = post.originalPost?.attachments ?? post.attachments
    
    // Start prefetch task
    prefetchTasks[postId] = Task { [weak self] in
      guard let self = self else { return }
      await prefetchAttachments(attachments)
      if prefetchGeneration[postId] == generation {
        prefetchTasks.removeValue(forKey: postId)
        prefetchGeneration.removeValue(forKey: postId)
      }
    }
  }
  
  /// Prefetch dimensions for multiple posts (batch)
  func prefetchDimensions(for posts: [Post]) {
    for post in posts {
      prefetchDimensions(for: post)
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

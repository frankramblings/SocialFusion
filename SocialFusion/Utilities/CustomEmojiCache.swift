import Foundation
import UIKit

/// An actor-based cache for custom emoji images with async loading
/// Uses modern Swift concurrency for thread-safe, non-blocking emoji rendering
public actor CustomEmojiCache {
  /// Shared singleton instance
  public static let shared = CustomEmojiCache()

  /// In-memory image cache
  private var imageCache: [URL: UIImage] = [:]

  /// Track in-flight loading tasks to coalesce duplicate requests
  private var loadingTasks: [URL: Task<UIImage?, Never>] = [:]

  /// Maximum number of emoji images to cache
  private let maxCacheSize = 500

  /// LRU tracking for cache eviction
  private var accessOrder: [URL] = []

  /// URLSession configured for emoji loading
  private let session: URLSession

  private init() {
    // Configure URLSession with caching
    let config = URLSessionConfiguration.default
    config.urlCache = URLCache(
      memoryCapacity: 10 * 1024 * 1024,  // 10 MB memory cache
      diskCapacity: 50 * 1024 * 1024,    // 50 MB disk cache
      diskPath: "custom_emoji_cache"
    )
    config.requestCachePolicy = .returnCacheDataElseLoad
    config.timeoutIntervalForRequest = 10
    session = URLSession(configuration: config)
  }

  // MARK: - Public API

  /// Loads an emoji image from URL, returning cached version if available
  /// - Parameter url: The URL of the emoji image
  /// - Returns: The loaded and scaled UIImage, or nil if loading failed
  public func loadEmoji(from url: URL) async -> UIImage? {
    // Check cache first (fast path)
    if let cachedImage = imageCache[url] {
      updateAccessOrder(url)
      return cachedImage
    }

    // Check if there's already a loading task for this URL (coalesce requests)
    if let existingTask = loadingTasks[url] {
      return await existingTask.value
    }

    // Start new loading task
    let task = Task<UIImage?, Never> {
      await downloadAndScaleEmoji(from: url)
    }
    loadingTasks[url] = task

    let image = await task.value
    loadingTasks[url] = nil

    // Cache successful downloads
    if let image = image {
      cacheImage(image, for: url)
    }

    return image
  }

  /// Returns a cached image if available (does not trigger loading)
  /// - Parameter url: The URL to check
  /// - Returns: Cached image or nil
  public func getCachedImage(for url: URL) -> UIImage? {
    if let image = imageCache[url] {
      updateAccessOrder(url)
      return image
    }
    return nil
  }

  /// Preloads emoji images in the background
  /// Call this when posts are loaded to warm the cache
  /// - Parameter emojiMap: Dictionary mapping shortcodes to URLs
  public func preloadEmoji(_ emojiMap: [String: URL]) async {
    await withTaskGroup(of: Void.self) { group in
      for (_, url) in emojiMap where imageCache[url] == nil {
        group.addTask {
          _ = await self.loadEmoji(from: url)
        }
      }
    }
  }

  /// Preloads emoji from a Post's custom emoji map
  /// - Parameter post: The post containing custom emoji
  public func preloadEmoji(from post: Post) async {
    guard let emojiMap = post.customEmoji, !emojiMap.isEmpty else { return }
    await preloadEmoji(emojiMap)
  }

  /// Preloads emoji from multiple posts
  /// Call this when timeline loads new posts
  /// - Parameter posts: Array of posts to preload emoji for
  public func preloadEmoji(from posts: [Post]) async {
    var allURLs: Set<URL> = []

    for post in posts {
      if let emojiMap = post.customEmoji {
        allURLs.formUnion(emojiMap.values)
      }
      // Also check original post for boosts
      if let originalPost = post.originalPost, let originalEmoji = originalPost.customEmoji {
        allURLs.formUnion(originalEmoji.values)
      }
    }

    if !allURLs.isEmpty {
      print("🎨 [EmojiCache] Pre-warming \(allURLs.count) emoji images")
      await withTaskGroup(of: Void.self) { group in
        for url in allURLs where imageCache[url] == nil {
          group.addTask {
            _ = await self.loadEmoji(from: url)
          }
        }
      }
    }
  }

  /// Clears the cache (call on memory warning)
  public func clearCache() {
    imageCache.removeAll()
    loadingTasks.removeAll()
    accessOrder.removeAll()
  }

  // MARK: - Private Methods

  /// Downloads and scales an emoji image
  private func downloadAndScaleEmoji(from url: URL) async -> UIImage? {
    do {
      let (data, response) = try await session.data(from: url)

      // Validate response
      guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode) else {
        return nil
      }

      guard let image = UIImage(data: data) else {
        return nil
      }

      // Scale to emoji size (40pt for 2x retina)
      return scaleImage(image, to: CGSize(width: 40, height: 40))
    } catch {
      print("⚠️ [EmojiCache] Failed to load emoji from \(url): \(error.localizedDescription)")
      return nil
    }
  }

  /// Scales an image to the target size, maintaining aspect ratio
  private func scaleImage(_ image: UIImage, to size: CGSize) -> UIImage {
    let aspectRatio = image.size.width / image.size.height
    var targetSize = size

    if aspectRatio > 1 {
      targetSize.height = size.width / aspectRatio
    } else {
      targetSize.width = size.height * aspectRatio
    }

    let renderer = UIGraphicsImageRenderer(size: targetSize)
    return renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
  }

  /// Caches an image with LRU eviction
  private func cacheImage(_ image: UIImage, for url: URL) {
    // Evict if at capacity (LRU)
    if imageCache.count >= maxCacheSize {
      evictLRU()
    }

    imageCache[url] = image
    updateAccessOrder(url)
  }

  /// Updates access order for LRU tracking
  private func updateAccessOrder(_ url: URL) {
    if let index = accessOrder.firstIndex(of: url) {
      accessOrder.remove(at: index)
    }
    accessOrder.append(url)
  }

  /// Evicts the least recently used item
  private func evictLRU() {
    guard let oldestURL = accessOrder.first else { return }
    accessOrder.removeFirst()
    imageCache[oldestURL] = nil
  }
}

// MARK: - Convenience Methods for Timeline Pre-warming

extension CustomEmojiCache {
  /// Convenience method to prewarm from array of posts on main actor
  /// Call this when timeline loads new posts
  @MainActor
  public static func prewarmTimeline(_ posts: [Post]) {
    Task.detached(priority: .utility) {
      await shared.preloadEmoji(from: posts)
    }
  }
}

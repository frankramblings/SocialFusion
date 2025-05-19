import Foundation
import LinkPresentation
import SwiftUI

/// A cache for link previews to avoid repeated fetching of the same URLs.
/// This reduces network load and improves performance.
final class LinkPreviewCache {
    static let shared = LinkPreviewCache()

    // Cache expiration time (24 hours)
    private let cacheExpirationTime: TimeInterval = 86400

    // Main cache dictionary storing metadata and the timestamp when it was cached
    private var cache: [URL: (metadata: LPLinkMetadata, timestamp: Date)] = [:]

    // Additional cache for image URLs
    private var imageCache: [URL: URL] = [:]

    private init() {}

    // MARK: - Public API

    /// Store metadata in the cache
    func cache(metadata: LPLinkMetadata, for url: URL) {
        cache[url] = (metadata, Date())
    }

    /// Store image URL in the cache
    func cacheImage(url: URL, for metadataURL: URL) {
        imageCache[metadataURL] = url
    }

    /// Retrieve metadata from the cache
    func getMetadata(for url: URL) -> LPLinkMetadata? {
        guard let cached = cache[url] else { return nil }

        // Check if the cached item has expired
        let now = Date()
        if now.timeIntervalSince(cached.timestamp) > cacheExpirationTime {
            // Remove expired cache item
            cache.removeValue(forKey: url)
            return nil
        }

        return cached.metadata
    }

    /// Retrieve image URL from the cache
    func getImageURL(for url: URL) -> URL? {
        return imageCache[url]
    }

    /// Check if a URL exists in the cache
    func containsMetadata(for url: URL) -> Bool {
        guard let cached = cache[url] else { return false }

        // Check if the cached item has expired
        let now = Date()
        if now.timeIntervalSince(cached.timestamp) > cacheExpirationTime {
            // Remove expired cache item
            cache.removeValue(forKey: url)
            return false
        }

        return true
    }

    /// Clear the entire cache
    func clearCache() {
        cache.removeAll()
        imageCache.removeAll()
    }

    /// Remove a specific URL from the cache
    func removeFromCache(url: URL) {
        cache.removeValue(forKey: url)
        imageCache.removeValue(forKey: url)
    }
}

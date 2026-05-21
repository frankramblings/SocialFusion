import Foundation
import LinkPresentation
import SwiftUI

/// A cache for link previews to avoid repeated fetching of the same URLs.
/// This reduces network load and improves performance.
///
/// Thread-safety: LPMetadataProvider completion handlers fire on
/// arbitrary background queues, so cache writes can race with reads
/// kicked off from the main thread (e.g. SwiftUI view bodies). All
/// access goes through `queue` — concurrent for reads, barrier for
/// writes — which is the standard reader/writer pattern for shared
/// Swift dictionaries.
final class LinkPreviewCache {
    static let shared = LinkPreviewCache()

    // Cache expiration time (24 hours)
    private let cacheExpirationTime: TimeInterval = 86400

    // Main cache dictionary storing metadata and the timestamp when it was cached
    private var cache: [URL: (metadata: LPLinkMetadata, timestamp: Date)] = [:]

    // Additional cache for image URLs
    private var imageCache: [URL: URL] = [:]

    // Reader/writer queue. Reads use the default concurrent access;
    // writes use barriers so they serialize against in-flight reads.
    private let queue = DispatchQueue(
        label: "com.socialfusionapp.linkpreview-cache",
        attributes: .concurrent
    )

    private init() {}

    // MARK: - Public API

    /// Store metadata in the cache
    func cache(metadata: LPLinkMetadata, for url: URL) {
        queue.async(flags: .barrier) {
            self.cache[url] = (metadata, Date())
        }
    }

    /// Store image URL in the cache
    func cacheImage(url: URL, for metadataURL: URL) {
        queue.async(flags: .barrier) {
            self.imageCache[metadataURL] = url
        }
    }

    /// Retrieve metadata from the cache
    func getMetadata(for url: URL) -> LPLinkMetadata? {
        var result: LPLinkMetadata?
        var isExpired = false
        queue.sync {
            guard let cached = self.cache[url] else { return }
            if Date().timeIntervalSince(cached.timestamp) > self.cacheExpirationTime {
                isExpired = true
            } else {
                result = cached.metadata
            }
        }
        if isExpired {
            queue.async(flags: .barrier) {
                self.cache.removeValue(forKey: url)
            }
        }
        return result
    }

    /// Retrieve image URL from the cache
    func getImageURL(for url: URL) -> URL? {
        queue.sync { imageCache[url] }
    }

    /// Check if a URL exists in the cache
    func containsMetadata(for url: URL) -> Bool {
        return getMetadata(for: url) != nil
    }

    /// Clear the entire cache
    func clearCache() {
        queue.async(flags: .barrier) {
            self.cache.removeAll()
            self.imageCache.removeAll()
        }
    }

    /// Remove a specific URL from the cache
    func removeFromCache(url: URL) {
        queue.async(flags: .barrier) {
            self.cache.removeValue(forKey: url)
            self.imageCache.removeValue(forKey: url)
        }
    }
}

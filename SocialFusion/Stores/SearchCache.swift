import Foundation

/// LRU cache for search results
public class SearchCache {
  public static let shared = SearchCache()
  
  private struct CacheEntry {
    let results: [SearchResultItem]
    let nextPageTokens: [String: SearchPageToken]
    let timestamp: Date
    
    init(results: [SearchResultItem], nextPageTokens: [String: SearchPageToken], timestamp: Date = Date()) {
      self.results = results
      self.nextPageTokens = nextPageTokens
      self.timestamp = timestamp
    }
  }
  
  private var cache: [String: CacheEntry] = [:]
  private let maxSize = 50
  private let maxAge: TimeInterval = 3600 // 1 hour
  
  private init() {}
  
  /// Get cached results for a query
  public func get(key: String) -> (results: [SearchResultItem], nextPageTokens: [String: SearchPageToken])? {
    guard let entry = cache[key] else {
      return nil
    }
    
    // Check if cache is expired
    if Date().timeIntervalSince(entry.timestamp) > maxAge {
      cache.removeValue(forKey: key)
      return nil
    }
    
    return (entry.results, entry.nextPageTokens)
  }
  
  /// Store results in cache
  public func set(key: String, results: [SearchResultItem], nextPageTokens: [String: SearchPageToken]) {
    // Remove oldest entries if cache is full
    if cache.count >= maxSize {
      let sortedEntries = cache.sorted { $0.value.timestamp < $1.value.timestamp }
      let entriesToRemove = sortedEntries.prefix(cache.count - maxSize + 1)
      for (key, _) in entriesToRemove {
        cache.removeValue(forKey: key)
      }
    }
    
    cache[key] = CacheEntry(results: results, nextPageTokens: nextPageTokens)
  }
  
  /// Clear all cached results
  public func clear() {
    cache.removeAll()
  }
  
  /// Remove a specific cache entry
  public func remove(key: String) {
    cache.removeValue(forKey: key)
  }
}

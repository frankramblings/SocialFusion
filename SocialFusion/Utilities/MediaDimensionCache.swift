import Foundation
import UIKit

/// Cache for media dimensions (memory + disk) with TTL and LRU eviction
@MainActor
class MediaDimensionCache {
  static let shared = MediaDimensionCache()
  
  // Memory cache (fast access)
  private var memoryCache: [String: CachedDimension] = [:]
  private let memoryCacheQueue = DispatchQueue(label: "com.socialfusion.mediaDimensionCache.memory", attributes: .concurrent)
  
  // Disk cache directory
  private let cacheDirectory: URL
  private let diskCacheQueue = DispatchQueue(label: "com.socialfusion.mediaDimensionCache.disk")
  
  // Cache configuration
  private let maxMemoryEntries = 500
  private let maxDiskSize: Int64 = 10 * 1024 * 1024  // 10MB
  private let ttl: TimeInterval = 7 * 24 * 60 * 60  // 7 days
  
  private struct CachedDimension: Codable {
    let width: Int
    let height: Int
    let aspectRatio: CGFloat
    let cachedAt: Date
    
    var isExpired: Bool {
      Date().timeIntervalSince(cachedAt) > 7 * 24 * 60 * 60  // 7 days TTL
    }
  }
  
  private init() {
    // Create cache directory
    let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    cacheDirectory = cachesDir.appendingPathComponent("MediaDimensions", isDirectory: true)
    
    // Create directory if needed
    try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    
    // Load from disk on init
    loadFromDisk()
  }
  
  /// Get cached dimension for a URL
  func getDimension(for url: String) -> CGSize? {
    let key = cacheKey(for: url)
    
    // Check memory cache first
    return memoryCacheQueue.sync {
      if let cached = memoryCache[key], !cached.isExpired {
        return CGSize(width: cached.width, height: cached.height)
      }
      return nil
    }
  }
  
  /// Get cached aspect ratio for a URL
  func getAspectRatio(for url: String) -> CGFloat? {
    let key = cacheKey(for: url)
    
    return memoryCacheQueue.sync {
      if let cached = memoryCache[key], !cached.isExpired {
        return cached.aspectRatio
      }
      return nil
    }
  }
  
  /// Store dimension in cache
  func setDimension(_ size: CGSize, for url: String) {
    let key = cacheKey(for: url)
    let cached = CachedDimension(
      width: Int(size.width),
      height: Int(size.height),
      aspectRatio: size.width / size.height,
      cachedAt: Date()
    )
    
    // Store in memory
    memoryCacheQueue.async(flags: .barrier) { [weak self] in
      guard let self = self else { return }
      
      // LRU eviction: remove oldest if at capacity
      if self.memoryCache.count >= self.maxMemoryEntries {
        let sorted = self.memoryCache.sorted { $0.value.cachedAt < $1.value.cachedAt }
        if let oldest = sorted.first {
          self.memoryCache.removeValue(forKey: oldest.key)
        }
      }
      
      self.memoryCache[key] = cached
    }
    
    // Store on disk (async)
    diskCacheQueue.async { [weak self] in
      guard let self = self else { return }
      self.saveToDisk(key: key, dimension: cached)
    }
  }
  
  /// Clear expired entries
  func clearExpired() {
    memoryCacheQueue.async(flags: .barrier) { [weak self] in
      guard let self = self else { return }
      self.memoryCache = self.memoryCache.filter { !$0.value.isExpired }
    }
    
    diskCacheQueue.async { [weak self] in
      guard let self = self else { return }
      self.clearExpiredFromDisk()
    }
  }
  
  /// Clear all cache
  func clearAll() {
    memoryCacheQueue.async(flags: .barrier) { [weak self] in
      guard let self = self else { return }
      self.memoryCache.removeAll()
    }
    
    diskCacheQueue.async { [weak self] in
      guard let self = self else { return }
      try? FileManager.default.removeItem(at: self.cacheDirectory)
      try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }
  }
  
  // MARK: - Private Helpers
  
  private func cacheKey(for url: String) -> String {
    // Use URL as-is for key (normalize if needed)
    return url
  }
  
  private func fileURL(for key: String) -> URL {
    // Sanitize key for filesystem
    let sanitized = key
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: ":", with: "_")
      .replacingOccurrences(of: "?", with: "_")
      .replacingOccurrences(of: "&", with: "_")
    return cacheDirectory.appendingPathComponent("\(sanitized).json")
  }
  
  private func loadFromDisk() {
    diskCacheQueue.async { [weak self] in
      guard let self = self else { return }
      
      guard let files = try? FileManager.default.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: nil) else {
        return
      }
      
      var loaded: [String: CachedDimension] = [:]
      
      for file in files where file.pathExtension == "json" {
        if let data = try? Data(contentsOf: file),
           let cached = try? JSONDecoder().decode(CachedDimension.self, from: data),
           !cached.isExpired {
          // Extract key from filename
          let key = file.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: "/")
          loaded[key] = cached
        }
      }
      
      // Merge into memory cache
      self.memoryCacheQueue.async(flags: .barrier) { [weak self] in
        guard let self = self else { return }
        self.memoryCache.merge(loaded) { _, new in new }
      }
    }
  }
  
  private func saveToDisk(key: String, dimension: CachedDimension) {
    let fileURL = fileURL(for: key)
    
    if let data = try? JSONEncoder().encode(dimension) {
      try? data.write(to: fileURL)
    }
  }
  
  private func clearExpiredFromDisk() {
    guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
      return
    }
    
    for file in files where file.pathExtension == "json" {
      if let data = try? Data(contentsOf: file),
         let cached = try? JSONDecoder().decode(CachedDimension.self, from: data),
         cached.isExpired {
        try? FileManager.default.removeItem(at: file)
      }
    }
  }
}

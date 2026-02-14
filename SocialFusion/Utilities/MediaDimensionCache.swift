import Foundation
import UIKit

/// Cache for media dimensions (memory + disk) with TTL and LRU eviction
@MainActor
class MediaDimensionCache {
  static let shared = MediaDimensionCache()
  
  // Memory cache (fast access) - actor-isolated, no need for DispatchQueue
  private var memoryCache: [String: CachedDimension] = [:]
  
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
    
    // Check memory cache - actor-isolated, safe to access directly
    if let cached = memoryCache[key], !cached.isExpired {
      return CGSize(width: cached.width, height: cached.height)
    }
    return nil
  }
  
  /// Get cached aspect ratio for a URL
  func getAspectRatio(for url: String) -> CGFloat? {
    let key = cacheKey(for: url)
    
    // Check memory cache - actor-isolated, safe to access directly
    if let cached = memoryCache[key], !cached.isExpired {
      return cached.aspectRatio
    }
    return nil
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
    
    // Store in memory - actor-isolated, safe to mutate directly
    // LRU eviction: remove oldest if at capacity
    if memoryCache.count >= maxMemoryEntries {
      let sorted = memoryCache.sorted { $0.value.cachedAt < $1.value.cachedAt }
      if let oldest = sorted.first {
        memoryCache.removeValue(forKey: oldest.key)
      }
    }
    
    memoryCache[key] = cached
    
    // Store on disk (async, nonisolated - filesystem access doesn't need MainActor)
    let directory = cacheDirectory
    diskCacheQueue.async { [weak self] in
      guard let self = self else { return }
      self.saveToDisk(key: key, dimension: cached, cacheDirectory: directory)
    }
  }
  
  /// Clear expired entries
  func clearExpired() {
    // Clear memory cache - actor-isolated, safe to mutate directly
    memoryCache = memoryCache.filter { !$0.value.isExpired }
    
    // Clear disk cache (async, nonisolated - filesystem access doesn't need MainActor)
    let directory = cacheDirectory
    diskCacheQueue.async { [weak self] in
      guard let self = self else { return }
      self.clearExpiredFromDisk(cacheDirectory: directory)
    }
  }
  
  /// Clear all cache
  func clearAll() {
    // Clear memory cache - actor-isolated, safe to mutate directly
    memoryCache.removeAll()
    
    // Clear disk cache (async, nonisolated)
    let directory = cacheDirectory
    diskCacheQueue.async {
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
  }
  
  // MARK: - Private Helpers

  nonisolated static func _test_diskFilename(for key: String) -> String {
    encodeKeyForFilename(key)
  }

  nonisolated static func _test_decodeFilename(_ filename: String) -> String? {
    decodeFilenameToKey(filename)
  }
  
  private func cacheKey(for url: String) -> String {
    // Use URL as-is for key (normalize if needed)
    return url
  }
  
  private func fileURL(for key: String) -> URL {
    let encoded = Self.encodeKeyForFilename(key)
    return cacheDirectory.appendingPathComponent("\(encoded).json")
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
          let filename = file.deletingPathExtension().lastPathComponent
          if let key = Self.decodeFilenameToKey(filename) {
            loaded[key] = cached
          } else {
            // Backward compatibility for legacy sanitized filenames
            loaded[filename.replacingOccurrences(of: "_", with: "/")] = cached
          }
        }
      }
      
      // Merge into memory cache - must be on MainActor
      Task { @MainActor [weak self] in
        guard let self = self else { return }
        self.memoryCache.merge(loaded) { _, new in new }
      }
    }
  }
  
  nonisolated private func saveToDisk(key: String, dimension: CachedDimension, cacheDirectory: URL) {
    let fileURL = fileURL(for: key, cacheDirectory: cacheDirectory)
    
    if let data = try? JSONEncoder().encode(dimension) {
      try? data.write(to: fileURL)
    }
  }
  
  nonisolated private func fileURL(for key: String, cacheDirectory: URL) -> URL {
    let encoded = Self.encodeKeyForFilename(key)
    return cacheDirectory.appendingPathComponent("\(encoded).json")
  }
  
  nonisolated private func clearExpiredFromDisk(cacheDirectory: URL) {
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

  nonisolated private static func encodeKeyForFilename(_ key: String) -> String {
    let data = Data(key.utf8)
    return data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  nonisolated private static func decodeFilenameToKey(_ filename: String) -> String? {
    var base64 = filename
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let paddingLength = (4 - (base64.count % 4)) % 4
    if paddingLength > 0 {
      base64 += String(repeating: "=", count: paddingLength)
    }
    guard let data = Data(base64Encoded: base64) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}

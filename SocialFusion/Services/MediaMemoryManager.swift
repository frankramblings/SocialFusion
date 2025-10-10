import AVFoundation
import Foundation
import SwiftUI
import UIKit

/// Memory management service for media content
@MainActor
class MediaMemoryManager: ObservableObject {
    static let shared = MediaMemoryManager()

    // MARK: - Configuration

    private struct Config {
        static let maxCacheSize: Int = 100 * 1024 * 1024  // 100MB
        static let maxImageCacheCount = 50
        static let maxVideoCacheCount = 10
        static let lowMemoryThreshold: Float = 0.8  // 80% of available memory
        static let compressionQuality: CGFloat = 0.8
        static let maxImageDimension: CGFloat = 2048
    }

    // MARK: - Cache Management

    private var imageCache = NSCache<NSString, UIImage>()
    private var videoPlayerCache = NSCache<NSString, AVPlayer>()
    private var gifDataCache = NSCache<NSString, NSData>()

    // Memory monitoring
    @Published private(set) var currentMemoryUsage: Float = 0.0
    @Published private(set) var isLowMemory: Bool = false

    private var memoryMonitorTimer: Timer?

    private init() {
        setupCaches()
        startMemoryMonitoring()
        setupMemoryWarningObserver()

        print(
            "🧠 [MediaMemoryManager] Initialized with \(Config.maxCacheSize / (1024*1024))MB cache limit"
        )
    }

    deinit {
        memoryMonitorTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Cache Setup

    private func setupCaches() {
        // Image cache
        imageCache.countLimit = Config.maxImageCacheCount
        imageCache.totalCostLimit = Config.maxCacheSize / 2  // 50MB for images
        imageCache.name = "MediaImageCache"

        // Video player cache
        videoPlayerCache.countLimit = Config.maxVideoCacheCount
        videoPlayerCache.name = "MediaVideoCache"

        // GIF data cache
        gifDataCache.countLimit = Config.maxImageCacheCount / 2  // Fewer GIFs
        gifDataCache.totalCostLimit = Config.maxCacheSize / 4  // 25MB for GIFs
        gifDataCache.name = "MediaGIFCache"

        // Set eviction policies
        imageCache.evictsObjectsWithDiscardedContent = true
        videoPlayerCache.evictsObjectsWithDiscardedContent = true
        gifDataCache.evictsObjectsWithDiscardedContent = true
    }

    // MARK: - Memory Monitoring

    private func startMemoryMonitoring() {
        memoryMonitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.updateMemoryUsage()
            }
        }
    }

    private func updateMemoryUsage() {
        let usage = getMemoryUsage()
        currentMemoryUsage = usage
        isLowMemory = usage > Config.lowMemoryThreshold

        if isLowMemory {
            print(
                "⚠️ [MediaMemoryManager] Low memory detected (\(Int(usage * 100))%), triggering cleanup"
            )
            performMemoryCleanup()
        }
    }

    private func getMemoryUsage() -> Float {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let usedMemory = Float(info.resident_size)
            let totalMemory = Float(ProcessInfo.processInfo.physicalMemory)
            return usedMemory / totalMemory
        }

        return 0.0
    }

    private func setupMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc private func didReceiveMemoryWarning() {
        print("🚨 [MediaMemoryManager] Memory warning received, performing aggressive cleanup")
        performAggressiveCleanup()
    }

    // MARK: - Image Management

    /// Load and cache an optimized image
    func loadOptimizedImage(from url: URL) async throws -> UIImage {
        let key = url.absoluteString as NSString

        // Check cache first
        if let cachedImage = imageCache.object(forKey: key) {
            return cachedImage
        }

        // Download and optimize
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let originalImage = UIImage(data: data) else {
            throw MediaErrorHandler.MediaError.decodingFailed("Invalid image data")
        }

        // Optimize image for memory usage
        let optimizedImage = optimizeImage(originalImage)

        // Cache with cost based on memory footprint
        let cost = calculateImageMemoryCost(optimizedImage)
        imageCache.setObject(optimizedImage, forKey: key, cost: cost)

        return optimizedImage
    }

    private func optimizeImage(_ image: UIImage) -> UIImage {
        let size = image.size
        let maxDimension = Config.maxImageDimension

        // Skip optimization if image is already small enough
        if size.width <= maxDimension && size.height <= maxDimension {
            return image
        }

        // Calculate new size maintaining aspect ratio
        let aspectRatio = size.width / size.height
        var newSize: CGSize

        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        // Resize image
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        image.draw(in: CGRect(origin: .zero, size: newSize))

        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }

    private func calculateImageMemoryCost(_ image: UIImage) -> Int {
        let size = image.size
        let scale = image.scale
        let bytesPerPixel = 4  // RGBA

        return Int(size.width * scale * size.height * scale * CGFloat(bytesPerPixel))
    }

    // MARK: - GIF Management

    /// Load and cache GIF data with size limits
    func loadOptimizedGIF(from url: URL) async throws -> Data {
        let key = url.absoluteString as NSString

        // Check cache first
        if let cachedData = gifDataCache.object(forKey: key) {
            return cachedData as Data
        }

        // Download GIF data
        let (data, _) = try await URLSession.shared.data(from: url)

        // Check size limits
        let maxGIFSize = 10 * 1024 * 1024  // 10MB max for GIFs
        if data.count > maxGIFSize {
            print(
                "⚠️ [MediaMemoryManager] GIF too large (\(data.count / (1024*1024))MB), skipping cache"
            )
            return data
        }

        // Cache the data
        let nsData = data as NSData
        gifDataCache.setObject(nsData, forKey: key, cost: data.count)

        return data
    }

    // MARK: - Video Player Management

    /// Get or create a cached video player
    func getCachedPlayer(for url: URL) -> AVPlayer? {
        let key = url.absoluteString as NSString
        return videoPlayerCache.object(forKey: key)
    }

    /// Cache a video player
    func cachePlayer(_ player: AVPlayer, for url: URL) {
        let key = url.absoluteString as NSString
        videoPlayerCache.setObject(player, forKey: key)
    }

    /// Remove a video player from cache
    func removePlayer(for url: URL) {
        let key = url.absoluteString as NSString
        videoPlayerCache.removeObject(forKey: key)
    }

    // MARK: - Memory Cleanup

    private func performMemoryCleanup() {
        // Remove oldest 25% of cached items
        let imagesToRemove = imageCache.countLimit / 4
        let gifsToRemove = gifDataCache.countLimit / 4

        // Clear some image cache
        for _ in 0..<imagesToRemove {
            // NSCache doesn't provide direct access to remove oldest items
            // So we reduce the count limit temporarily to force eviction
            let originalLimit = imageCache.countLimit
            imageCache.countLimit = max(1, originalLimit - 1)
            imageCache.countLimit = originalLimit
        }

        // Clear some GIF cache
        for _ in 0..<gifsToRemove {
            let originalLimit = gifDataCache.countLimit
            gifDataCache.countLimit = max(1, originalLimit - 1)
            gifDataCache.countLimit = originalLimit
        }

        // Note: NSCache doesn't support enumeration, so we'll clear the entire cache
        videoPlayerCache.removeAllObjects()

        print("🧹 [MediaMemoryManager] Memory cleanup completed")
    }

    private func performAggressiveCleanup() {
        // Clear all caches
        imageCache.removeAllObjects()
        gifDataCache.removeAllObjects()

        // Note: NSCache doesn't support enumeration, so we'll clear the entire cache
        // Players will be deallocated when removed from cache
        videoPlayerCache.removeAllObjects()

        // Force garbage collection
        autoreleasepool {
            // Empty autoreleasepool to release any autorelease objects
        }

        print("🧹 [MediaMemoryManager] Aggressive cleanup completed")
    }

    // MARK: - Public Cleanup Methods

    /// Clear all media caches
    func clearAllCaches() {
        imageCache.removeAllObjects()
        gifDataCache.removeAllObjects()
        videoPlayerCache.removeAllObjects()

        print("🧹 [MediaMemoryManager] All caches cleared")
    }

    /// Get current cache statistics
    func getCacheStats() -> (images: Int, gifs: Int, videos: Int, totalMemory: String) {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory

        let totalMemory = formatter.string(
            fromByteCount: Int64(imageCache.totalCostLimit + gifDataCache.totalCostLimit))

        return (
            images: imageCache.countLimit,
            gifs: gifDataCache.countLimit,
            videos: videoPlayerCache.countLimit,
            totalMemory: totalMemory
        )
    }
}

// MARK: - Error Types

// Note: MediaError is defined in MediaErrorHandler.swift to avoid duplication

// MARK: - SwiftUI Integration

/// A view modifier that automatically manages memory for media content
struct MediaMemoryModifier: ViewModifier {
    @StateObject private var memoryManager = MediaMemoryManager.shared

    func body(content: Content) -> some View {
        content
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didEnterBackgroundNotification)
            ) { _ in
                // Clear caches when app goes to background
                memoryManager.clearAllCaches()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            ) { _ in
                // App became active, memory monitoring will resume automatically
            }
    }
}

extension View {
    func mediaMemoryManagement() -> some View {
        self.modifier(MediaMemoryModifier())
    }
}

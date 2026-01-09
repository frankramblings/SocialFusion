import AVFoundation
import Foundation
import ImageIO
import SwiftUI
import UIKit

/// Memory management service for media content
@MainActor
class MediaMemoryManager: ObservableObject {
    static let shared = MediaMemoryManager()

    // MARK: - Configuration

    private struct Config {
        static let maxCacheSize: Int = 500 * 1024 * 1024  // 500MB (increased for videos)
        static let maxImageCacheCount = 50
        static let maxVideoCacheCount = 20  // Increased for better video caching
        static let lowMemoryThreshold: Float = 0.8  // 80% of available memory
        static let compressionQuality: CGFloat = 0.8
        static let maxImageDimension: CGFloat = 2048
    }

    // MARK: - Cache Management

    private var imageCache = NSCache<NSString, UIImage>()
    private var videoPlayerCache = NSCache<NSString, AVPlayer>()
    private var gifDataCache = NSCache<NSString, NSData>()
    private var animatedGIFCache = NSCache<NSString, UIImage>()

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
        imageCache.totalCostLimit = Config.maxCacheSize / 5  // 100MB for images (reduced from 50%)
        imageCache.name = "MediaImageCache"

        // Video player cache - videos need more memory
        videoPlayerCache.countLimit = Config.maxVideoCacheCount
        videoPlayerCache.totalCostLimit = Config.maxCacheSize / 2  // 250MB for videos
        videoPlayerCache.name = "MediaVideoCache"

        // GIF data cache
        gifDataCache.countLimit = Config.maxImageCacheCount / 2  // Fewer GIFs
        gifDataCache.totalCostLimit = Config.maxCacheSize / 4  // 25MB for GIFs
        gifDataCache.name = "MediaGIFCache"
        
        // Animated GIF UIImage cache
        animatedGIFCache.countLimit = Config.maxImageCacheCount / 2  // Fewer GIFs
        animatedGIFCache.totalCostLimit = Config.maxCacheSize / 4  // 25MB for animated GIFs
        animatedGIFCache.name = "AnimatedGIFCache"

        // Set eviction policies
        imageCache.evictsObjectsWithDiscardedContent = true
        videoPlayerCache.evictsObjectsWithDiscardedContent = true
        gifDataCache.evictsObjectsWithDiscardedContent = true
        animatedGIFCache.evictsObjectsWithDiscardedContent = true
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

    /// Load and cache an optimized image with optional target size
    func loadOptimizedImage(from url: URL, targetSize: CGSize? = nil) async throws -> UIImage {
        let key =
            (url.absoluteString + (targetSize.map { "_\($0.width)x\($0.height)" } ?? ""))
            as NSString

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
        let optimizedImage = optimizeImage(originalImage, targetSize: targetSize)

        // Cache with cost based on memory footprint
        let cost = calculateImageMemoryCost(optimizedImage)
        imageCache.setObject(optimizedImage, forKey: key, cost: cost)

        return optimizedImage
    }

    private func optimizeImage(_ image: UIImage, targetSize: CGSize? = nil) -> UIImage {
        let size = image.size
        let maxDimension = targetSize?.width ?? Config.maxImageDimension

        // If a target size is provided, we use it as the maximum dimension
        // while maintaining aspect ratio

        // Skip optimization if image is already small enough and no target size
        if targetSize == nil && size.width <= maxDimension && size.height <= maxDimension {
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

        // Ensure we don't scale UP
        if newSize.width >= size.width && newSize.height >= size.height && targetSize == nil {
            return image
        }

        // Resize image using modern renderer
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // Use exact pixels for better memory control
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
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
            print("✅ [MediaMemoryManager] Using cached GIF data for: \(url.absoluteString)")
            return cachedData as Data
        }

        print("🔄 [MediaMemoryManager] Loading GIF from: \(url.absoluteString)")
        
        // Create a URLSession configuration with timeout
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)
        
        do {
            // Download GIF data with better error handling
            let (data, response) = try await session.data(from: url)
            
            // Check HTTP response status
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 [MediaMemoryManager] HTTP Status: \(httpResponse.statusCode) for \(url.absoluteString)")
                
                if httpResponse.statusCode != 200 {
                    let errorMsg = "HTTP \(httpResponse.statusCode) for \(url.absoluteString)"
                    print("❌ [MediaMemoryManager] \(errorMsg)")
                    throw NSError(domain: "MediaMemoryManager", code: httpResponse.statusCode, 
                                 userInfo: [NSLocalizedDescriptionKey: errorMsg])
                }
            }
            
            // Validate we got data
            guard !data.isEmpty else {
                let errorMsg = "Empty response for \(url.absoluteString)"
                print("❌ [MediaMemoryManager] \(errorMsg)")
                throw NSError(domain: "MediaMemoryManager", code: -1, 
                             userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }
            
            print("✅ [MediaMemoryManager] Loaded \(data.count) bytes from \(url.absoluteString)")

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
        } catch {
            print("❌ [MediaMemoryManager] Failed to load GIF from \(url.absoluteString): \(error.localizedDescription)")
            print("❌ [MediaMemoryManager] Error details: \(error)")
            throw error
        }
    }
    
    /// Get cached animated GIF UIImage if available
    func getCachedAnimatedGIF(for url: URL) -> UIImage? {
        let key = url.absoluteString as NSString
        return animatedGIFCache.object(forKey: key)
    }
    
    /// Cache an animated GIF UIImage
    func cacheAnimatedGIF(_ image: UIImage, for url: URL) {
        let key = url.absoluteString as NSString
        let cost = calculateImageMemoryCost(image)
        animatedGIFCache.setObject(image, forKey: key, cost: cost)
    }
    
    /// Load or get cached animated GIF UIImage
    func loadAnimatedGIF(from url: URL) async throws -> UIImage {
        // Check cache first
        if let cachedImage = getCachedAnimatedGIF(for: url) {
            print("✅ [MediaMemoryManager] Using cached animated GIF for: \(url.absoluteString)")
            return cachedImage
        }
        
        print("🔄 [MediaMemoryManager] Loading animated GIF from: \(url.absoluteString)")
        
        // Load data (this will use the data cache)
        let data: Data
        do {
            data = try await loadOptimizedGIF(from: url)
        } catch {
            print("❌ [MediaMemoryManager] Failed to load GIF data: \(error.localizedDescription)")
            throw error
        }
        
        // Validate data is not empty
        guard !data.isEmpty else {
            let errorMsg = "Empty GIF data for \(url.absoluteString)"
            print("❌ [MediaMemoryManager] \(errorMsg)")
            throw NSError(domain: "MediaMemoryManager", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        // Create animated UIImage
        guard let image = createAnimatedImage(from: data) else {
            let errorMsg = "Failed to create animated image from data (\(data.count) bytes) for \(url.absoluteString)"
            print("❌ [MediaMemoryManager] \(errorMsg)")
            // Log first few bytes to help diagnose
            let preview = data.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " ")
            print("❌ [MediaMemoryManager] Data preview (first 20 bytes): \(preview)")
            throw NSError(domain: "MediaMemoryManager", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        // Verify it's actually animated
        if let images = image.images, images.count > 1 {
            print("✅ [MediaMemoryManager] Created animated GIF with \(images.count) frames, duration: \(image.duration)s from \(url.absoluteString)")
            print("✅ [MediaMemoryManager] First frame size: \(images.first?.size ?? .zero), animationDuration: \(image.duration)")
        } else {
            print("⚠️ [MediaMemoryManager] Created GIF but it may not be animated (frames: \(image.images?.count ?? 0), duration: \(image.duration))")
            print("⚠️ [MediaMemoryManager] Image properties - images array: \(image.images != nil ? "exists" : "nil"), count: \(image.images?.count ?? 0)")
        }
        
        // Cache the UIImage
        cacheAnimatedGIF(image, for: url)
        
        return image
    }
    
    private func createAnimatedImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        var frames: [UIImage] = []
        var duration: Double = 0
        
        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            let frameDuration = getFrameDuration(from: source, at: i)
            duration += frameDuration
            frames.append(UIImage(cgImage: cgImage))
        }
        
        guard !frames.isEmpty else { return nil }
        return UIImage.animatedImage(with: frames, duration: duration)
    }
    
    private func getFrameDuration(from source: CGImageSource, at index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil),
              let gifProps = (properties as NSDictionary)[kCGImagePropertyGIFDictionary as String] as? NSDictionary,
              let delay = gifProps[kCGImagePropertyGIFDelayTime as String] as? NSNumber
        else { return 0.1 }
        return delay.doubleValue > 0 ? delay.doubleValue : 0.1
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
            
            let originalGIFLimit = animatedGIFCache.countLimit
            animatedGIFCache.countLimit = max(1, originalGIFLimit - 1)
            animatedGIFCache.countLimit = originalGIFLimit
        }

        // Note: NSCache doesn't support enumeration, so we'll clear the entire cache
        videoPlayerCache.removeAllObjects()

        print("🧹 [MediaMemoryManager] Memory cleanup completed")
    }

    private func performAggressiveCleanup() {
        // Clear all caches
        imageCache.removeAllObjects()
        gifDataCache.removeAllObjects()
        animatedGIFCache.removeAllObjects()

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
        animatedGIFCache.removeAllObjects()
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

    #if DEBUG
    // Testing shims to expose private members for unit tests
    @usableFromInline
    internal func _test_optimizeImage(_ image: UIImage) -> UIImage {
        return optimizeImage(image)
    }

    @usableFromInline
    internal var _test_imageCache: NSCache<NSString, UIImage> {
        return imageCache
    }
    #endif
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

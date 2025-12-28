import Combine
import SwiftUI

/// Priority levels for image loading requests
public enum ImageLoadPriority: Int, CaseIterable {
    case high = 3  // Currently visible
    case normal = 2  // About to be visible
    case low = 1  // Off-screen but cached
    case background = 0  // Pre-loading
}

/// A high-performance image cache that provides reliable image loading with smart prioritization
public class ImageCache: ObservableObject {
    public static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private var inFlightRequests = [URL: AnyPublisher<UIImage?, Never>]()
    private let requestQueue = DispatchQueue(label: "ImageCache.requests", qos: .userInitiated)

    // Add a memory-only cache for frequently accessed profile images
    private let hotCache = NSCache<NSString, UIImage>()

    // Priority-based request management
    private var requestPriorities = [URL: ImageLoadPriority]()
    private let priorityLock = NSLock()

    private init() {
        // Configure URLSession with optimized settings for image loading
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 200 * 1024 * 1024,  // Increased to 200MB memory
            diskCapacity: 500 * 1024 * 1024,  // Increased to 500MB disk
            diskPath: "profile_images"
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 30  // Reduced for faster failures during scrolling
        config.timeoutIntervalForResource = 90
        config.httpMaximumConnectionsPerHost = 12  // Increased for better concurrency
        config.waitsForConnectivity = true

        self.session = URLSession(configuration: config)

        // Increase cache limits
        cache.countLimit = 500  // Increased from 200
        cache.totalCostLimit = 100 * 1024 * 1024  // Increased to 100MB

        // Hot cache for frequently accessed images (profile pics that appear multiple times)
        hotCache.countLimit = 150  // Increased
        hotCache.totalCostLimit = 30 * 1024 * 1024  // 30MB for hot cache

        // Enable debug logging for cache hits/misses
        print(
            "🔧 [ImageCache] Initialized with scroll-optimized settings - Memory: 200MB, Disk: 500MB, Count: 500"
        )
    }

    /// Load image with priority-aware handling for scroll performance
    func loadImage(from url: URL, priority: ImageLoadPriority = .normal) -> AnyPublisher<
        UIImage?, Never
    > {
        let key = NSString(string: url.absoluteString)

        // Check hot cache first (most frequently accessed)
        if let hotImage = hotCache.object(forKey: key) {
            return Just(hotImage).eraseToAnyPublisher()
        }

        // Check regular memory cache
        if let cachedImage = cache.object(forKey: key) {
            // Promote to hot cache if accessed again
            hotCache.setObject(cachedImage, forKey: key)
            return Just(cachedImage).eraseToAnyPublisher()
        }

        // Update priority for this request
        priorityLock.lock()
        let currentPriority = requestPriorities[url] ?? .background
        if priority.rawValue > currentPriority.rawValue {
            requestPriorities[url] = priority
        }
        priorityLock.unlock()

        // Check if we already have an in-flight request for this URL
        if let existingPublisher = inFlightRequests[url] {
            return existingPublisher
        }

        // Create new request with priority-based timeouts and retry logic
        let timeoutInterval: TimeInterval = priority == .high ? 15 : 30
        let retryCount = priority == .high ? 3 : 2

        // Smart jitter based on priority - high priority gets less delay
        let jitter = priority == .high ? Double.random(in: 0.0...0.1) : Double.random(in: 0.1...0.3)

        let publisher = session.dataTaskPublisher(for: url)
            .timeout(
                .seconds(timeoutInterval),
                scheduler: DispatchQueue.global(qos: qosForPriority(priority))
            )
            .delay(for: .seconds(jitter), scheduler: DispatchQueue.global(qos: .background))
            .retry(retryCount)
            .subscribe(on: DispatchQueue.global(qos: qosForPriority(priority)))
            .map { [weak self] data, response -> UIImage? in
                guard let httpResponse = response as? HTTPURLResponse else {
                    return nil
                }

                guard httpResponse.statusCode == 200 else {
                    return nil
                }

                guard let image = UIImage(data: data) else {
                    return nil
                }

                // Optimize image if it's large
                let optimizedImage = self?.optimizeImageIfNeeded(image) ?? image

                // Cache with priority-based cost
                self?.cacheImage(optimizedImage, forKey: key, priority: priority)

                return optimizedImage
            }
            .replaceError(with: nil)
            .handleEvents(
                receiveCompletion: { [weak self] _ in
                    // Clean up tracking
                    self?.requestQueue.async {
                        self?.inFlightRequests.removeValue(forKey: url)
                        self?.priorityLock.lock()
                        self?.requestPriorities.removeValue(forKey: url)
                        self?.priorityLock.unlock()
                    }
                }
            )
            .share()
            .eraseToAnyPublisher()

        // Store in-flight request
        inFlightRequests[url] = publisher

        return publisher
    }

    private func optimizeImageIfNeeded(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 1024
        let size = image.size
        
        if size.width <= maxDimension && size.height <= maxDimension {
            return image
        }
        
        let aspectRatio = size.width / size.height
        var newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Cache image with priority-based placement
    private func cacheImage(_ image: UIImage, forKey key: NSString, priority: ImageLoadPriority) {
        // High priority images go to both caches immediately
        if priority == .high {
            cache.setObject(image, forKey: key)
            hotCache.setObject(image, forKey: key)
            print("💾 [ImageCache] Cached high-priority image: \(key.lastPathComponent)")
        } else {
            // Normal priority images go to regular cache
            cache.setObject(image, forKey: key)
            print("💾 [ImageCache] Cached image: \(key.lastPathComponent)")
        }
    }

    /// Convert ImageLoadPriority to QoS for better system integration
    private func qosForPriority(_ priority: ImageLoadPriority) -> DispatchQoS.QoSClass {
        switch priority {
        case .high:
            return .userInteractive
        case .normal:
            return .userInitiated
        case .low:
            return .utility
        case .background:
            return .background
        }
    }

    /// Cancel low-priority requests when scrolling fast
    public func cancelLowPriorityRequests() {
        priorityLock.lock()
        let lowPriorityURLs = requestPriorities.compactMap { url, priority in
            priority.rawValue <= ImageLoadPriority.low.rawValue ? url : nil
        }
        priorityLock.unlock()

        for url in lowPriorityURLs {
            inFlightRequests.removeValue(forKey: url)
            print("🚫 [ImageCache] Cancelled low-priority request: \(url.lastPathComponent)")
        }
    }

    public func clearCache() {
        cache.removeAllObjects()
        hotCache.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
        inFlightRequests.removeAll()
        requestPriorities.removeAll()
        print("🗑️ [ImageCache] Cache cleared")
    }

    public func getCacheInfo() -> (memoryCount: Int, diskSize: Int) {
        let diskSize = session.configuration.urlCache?.currentDiskUsage ?? 0
        let memoryCount = cache.countLimit
        return (memoryCount, diskSize)
    }
}

/// A reliable cached async image view with scroll-aware priority management
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    private let priority: ImageLoadPriority
    private let onImageLoad: ((UIImage) -> Void)?

    // Stable identifier to prevent view recycling issues
    private let stableID: String

    @StateObject private var imageCache = ImageCache.shared
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var hasError = false
    @State private var retryCount = 0
    @State private var cancellables = Set<AnyCancellable>()
    @State private var isVisible = false

    private let maxRetries = 2

    init(
        url: URL?,
        priority: ImageLoadPriority = .normal,
        onImageLoad: ((UIImage) -> Void)? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.priority = priority
        self.onImageLoad = onImageLoad
        self.content = content
        self.placeholder = placeholder
        self.stableID = url?.absoluteString ?? UUID().uuidString
    }

    var body: some View {
        Group {
            if let image = image {
                content(Image(uiImage: image))
            } else {
                placeholder()
                    .overlay(errorOverlay)
            }
        }
        .id(stableID)
        .onAppear {
            isVisible = true
            if image == nil && !isLoading {
                loadImage()
            }
        }
        .onDisappear {
            isVisible = false
        }
        .onChange(of: url) { _ in
            image = nil
            hasError = false
            retryCount = 0
            loadImage()
        }
    }

    @ViewBuilder
    private var errorOverlay: some View {
        if hasError && retryCount >= maxRetries {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundColor(.orange)
                .background(Circle().fill(Color.white).frame(width: 16, height: 16))
                .offset(x: 6, y: 6)
        }
    }

    private func loadImage() {
        guard let url = url, !isLoading else { return }
        
        isLoading = true
        hasError = false
        
        imageCache.loadImage(from: url, priority: isVisible ? .high : priority)
            .receive(on: DispatchQueue.main)
            .sink { [stableID] loadedImage in
                self.isLoading = false
                if let loadedImage = loadedImage {
                    self.image = loadedImage
                    self.onImageLoad?(loadedImage)
                } else {
                    self.hasError = true
                    self.handleRetry()
                }
            }
            .store(in: &cancellables)
    }

    private func handleRetry() {
        guard retryCount < maxRetries && isVisible else { return }
        
        retryCount += 1
        let delay = Double(retryCount) * 1.0
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if self.isVisible {
                self.loadImage()
            }
        }
    }
}

/// Convenience initializers
extension CachedAsyncImage where Content == Image, Placeholder == AnyView {
    init(url: URL?, priority: ImageLoadPriority = .normal, onImageLoad: ((UIImage) -> Void)? = nil)
    {
        self.init(
            url: url,
            priority: priority,
            onImageLoad: onImageLoad,
            content: { image in image },
            placeholder: {
                AnyView(
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.7)
                        )
                )
            }
        )
    }
}

extension CachedAsyncImage where Content == Image {
    init(
        url: URL?, priority: ImageLoadPriority = .normal,
        onImageLoad: ((UIImage) -> Void)? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.init(
            url: url,
            priority: priority,
            onImageLoad: onImageLoad,
            content: { image in image },
            placeholder: placeholder
        )
    }
}

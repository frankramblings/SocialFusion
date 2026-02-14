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

    }

    /// Load image with progressive loading support (thumbnail first, then full image)
    func loadImageProgressive(from url: URL, thumbnailURL: URL?, priority: ImageLoadPriority = .normal) -> AnyPublisher<UIImage?, Never> {
        // If thumbnail URL is provided, load thumbnail first
        if let thumbURL = thumbnailURL {
            let thumbnailPublisher = loadImage(from: thumbURL, priority: priority)
            let fullImagePublisher = loadImage(from: url, priority: priority)
            
            // Return thumbnail immediately, then full image when ready
            return thumbnailPublisher
                .flatMap { thumbnail -> AnyPublisher<UIImage?, Never> in
                    if let thumb = thumbnail {
                        // Show thumbnail first, then load full image
                        return fullImagePublisher
                            .prepend(thumb) // Prepend thumbnail so it shows first
                            .eraseToAnyPublisher()
                    } else {
                        // No thumbnail, just load full image
                        return fullImagePublisher
                    }
                }
                .eraseToAnyPublisher()
        }
        
        // No thumbnail, use regular loading
        return loadImage(from: url, priority: priority)
    }
    
    /// Synchronously check if image is already cached (for immediate display)
    /// Checks memory cache first, then URLCache disk cache
    func getCachedImage(for url: URL) -> UIImage? {
        let key = NSString(string: url.absoluteString)
        
        // Check hot cache first (most frequently accessed)
        if let hotImage = hotCache.object(forKey: key) {
            return hotImage
        }
        
        // Check regular memory cache
        if let cachedImage = cache.object(forKey: key) {
            // Promote to hot cache if accessed again
            hotCache.setObject(cachedImage, forKey: key)
            return cachedImage
        }
        
        // Check URLCache (disk cache) synchronously
        if let cachedResponse = session.configuration.urlCache?.cachedResponse(for: URLRequest(url: url)),
           let image = UIImage(data: cachedResponse.data) {
            // Found in disk cache - promote to memory cache for faster future access
            let optimizedImage = optimizeImageIfNeeded(image)
            cache.setObject(optimizedImage, forKey: key)
            hotCache.setObject(optimizedImage, forKey: key)
            return optimizedImage
        }
        
        return nil
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

        let publisher = session.dataTaskPublisher(for: url)
            .timeout(
                .seconds(timeoutInterval),
                scheduler: DispatchQueue.global(qos: qosForPriority(priority))
            )
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
        } else {
            // Normal priority images go to regular cache
            cache.setObject(image, forKey: key)
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
    @State private var loadStartTime: Date?
    @State private var timeoutTask: Task<Void, Never>?

    private let maxRetries = 2
    private let loadTimeout: TimeInterval = 5.0  // Retry if not loaded within 5 seconds

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
            self.isVisible = true
            guard let url = self.url else { return }
            
            // CRITICAL FIX: Check cache synchronously BEFORE showing placeholder
            // This prevents spinner from showing when image is already cached
            if let cachedImage = self.imageCache.getCachedImage(for: url) {
                // Image is cached - set it immediately before view renders
                self.image = cachedImage
                self.onImageLoad?(cachedImage)
                self.hasError = false
                self.retryCount = 0
                self.isLoading = false
                self.cancelTimeoutTask()
            } else if self.image == nil && !self.isLoading {
                // Not cached - start loading
                self.loadImage()
            }
        }
        .task {
            // CRITICAL FIX: Also check cache in task to catch cases where onAppear
            // might not fire immediately or view is recreated
            guard let url = self.url, self.image == nil else { return }
            
            if let cachedImage = self.imageCache.getCachedImage(for: url) {
                await MainActor.run {
                    self.image = cachedImage
                    self.onImageLoad?(cachedImage)
                    self.hasError = false
                    self.retryCount = 0
                    self.isLoading = false
                    self.cancelTimeoutTask()
                }
            }
        }
        .onDisappear {
            self.isVisible = false
            // CRITICAL FIX: Don't clear image state when view disappears
            // This prevents images from turning into spinners when closing fullscreen
            // The image should remain in state so it can be shown immediately if view reappears
            // Only cancel timeout to prevent retries
            self.cancelTimeoutTask()
        }
        .onChange(of: url) { newURL in
            // Cancel any existing operations when URL changes
            self.cancellables.removeAll()
            self.cancelTimeoutTask()
            
            // Check cache synchronously when URL changes
            if let newURL = newURL {
                if let cachedImage = imageCache.getCachedImage(for: newURL) {
                    // Image is cached - show it immediately
                    DispatchQueue.main.async {
                        self.image = cachedImage
                        self.onImageLoad?(cachedImage)
                        self.hasError = false
                        self.retryCount = 0
                        self.isLoading = false
                    }
                    return
                }
            }
            
            // Not cached - reset and load
            DispatchQueue.main.async {
                self.image = nil
                self.hasError = false
                self.retryCount = 0
                self.isLoading = false
                self.loadImage()
            }
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
        guard let url = url else { return }
        
        // Prevent duplicate loads
        if isLoading {
            return
        }
        
        // Cancel any existing operations
        cancellables.removeAll()
        cancelTimeoutTask()
        
        // Reset error state
        hasError = false
        isLoading = true
        loadStartTime = Date()
        
        // Start timeout task - retry if image doesn't load within timeout period
        timeoutTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(loadTimeout * 1_000_000_000))
                
                // Check if task was cancelled
                guard !Task.isCancelled else { return }
                
                // Check if we're still loading and haven't received the image
                if self.isLoading && self.image == nil && self.isVisible {
                    // Timeout reached - trigger retry
                    self.hasError = true
                    self.handleRetry()
                }
            } catch {
                // Task was cancelled or failed - ignore
                return
            }
        }
        
        // Load image from cache
        imageCache.loadImage(from: url, priority: isVisible ? .high : priority)
            .receive(on: DispatchQueue.main)
            .sink { loadedImage in
                // Check visibility and ensure we're still loading the same URL
                guard self.isVisible, self.url == url else { return }
                
                self.isLoading = false
                self.cancelTimeoutTask()
                
                if let loadedImage = loadedImage {
                    // Only update if we don't already have this image (prevent race conditions)
                    if self.image != loadedImage {
                        self.image = loadedImage
                        self.onImageLoad?(loadedImage)
                    }
                    self.hasError = false
                    self.retryCount = 0  // Reset retry count on success
                } else {
                    // Nil image means load failed
                    self.hasError = true
                    self.handleRetry()
                }
            }
            .store(in: &cancellables)
    }
    
    private func cancelTimeoutTask() {
        timeoutTask?.cancel()
        timeoutTask = nil
        loadStartTime = nil
    }

    private func handleRetry() {
        guard retryCount < maxRetries && isVisible else { return }
        
        retryCount += 1
        let delay = Double(retryCount) * 1.0
        
        // Cancel current loading and timeout before retrying
        cancellables.removeAll()
        cancelTimeoutTask()
        isLoading = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if self.isVisible && self.image == nil {
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

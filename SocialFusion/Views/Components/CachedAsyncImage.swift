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
                    print("❌ [ImageCache] Invalid response type for: \(url.lastPathComponent)")
                    return nil
                }

                guard httpResponse.statusCode == 200 else {
                    print(
                        "❌ [ImageCache] HTTP \(httpResponse.statusCode) for: \(url.lastPathComponent)"
                    )
                    return nil
                }

                guard let image = UIImage(data: data) else {
                    print(
                        "❌ [ImageCache] Failed to decode image data for: \(url.lastPathComponent)")
                    return nil
                }

                print(
                    "✅ [ImageCache] Successfully loaded: \(url.lastPathComponent) (priority: \(priority))"
                )

                // Cache with priority-based cost
                self?.cacheImage(image, forKey: key, priority: priority)

                return image
            }
            .replaceError(with: nil)
            .handleEvents(
                receiveOutput: { [weak self] image in
                    if image == nil {
                        print("⚠️ [ImageCache] No image to cache for: \(url.lastPathComponent)")
                    }
                },
                receiveCompletion: { [weak self] completion in
                    // Clean up tracking
                    self?.requestQueue.async {
                        self?.inFlightRequests.removeValue(forKey: url)
                        self?.priorityLock.lock()
                        self?.requestPriorities.removeValue(forKey: url)
                        self?.priorityLock.unlock()
                    }

                    switch completion {
                    case .finished:
                        print("🏁 [ImageCache] Request completed for: \(url.lastPathComponent)")
                    case .failure(let error):
                        print(
                            "❌ [ImageCache] Request failed for \(url.lastPathComponent): \(error)")
                    }
                }
            )
            .share()
            .eraseToAnyPublisher()

        // Store in-flight request
        inFlightRequests[url] = publisher

        return publisher
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
    @State private var viewAppearCount = 0
    @State private var isVisible = false

    private let maxRetries = 3

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
            } else if isLoading {
                placeholder()
            } else if hasError && retryCount >= maxRetries {
                // Show error state after max retries
                placeholder()
                    .overlay(
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .background(Circle().fill(Color.white).frame(width: 16, height: 16))
                            .offset(x: 6, y: 6),
                        alignment: .bottomTrailing
                    )
            } else {
                placeholder()
                    .onAppear {
                        if !isLoading {
                            // Use Task to defer state updates outside view rendering cycle
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                                loadImageWithPriority()
                            }
                        }
                    }
            }
        }
        .id(stableID)
        .onAppear {
            // Use Task to defer state updates outside view rendering cycle
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                isVisible = true
                viewAppearCount += 1

                // Load with high priority when visible
                if image == nil && !isLoading {
                    let loadPriority: ImageLoadPriority = isVisible ? .high : priority
                    let delay = viewAppearCount > 1 ? 0.05 : 0.0  // Reduced delay for responsiveness

                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    loadImageWithPriority(loadPriority)
                }
            }
        }
        .onDisappear {
            // Use Task to defer state updates outside view rendering cycle
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                isVisible = false
                // Don't cancel immediately - keep some requests for smooth scrolling back
            }
        }
        .onChange(of: url) { newURL in
            // Use Task to defer state updates outside view rendering cycle
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                // Reset state when URL changes
                image = nil
                hasError = false
                retryCount = 0
                isLoading = false
                viewAppearCount = 0

                if newURL != nil {
                    loadImageWithPriority()
                }
            }
        }
    }

    private func loadImageWithPriority(_ overridePriority: ImageLoadPriority? = nil) {
        guard let url = url else {
            return
        }

        guard !isLoading else {
            return
        }

        let loadPriority = overridePriority ?? (isVisible ? .high : priority)
        isLoading = true
        hasError = false
        let startTime = Date()

        // Clear previous cancellables for this load
        cancellables.removeAll()

        imageCache.loadImage(from: url, priority: loadPriority)
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [url, loadPriority, startTime] loadedImage in

                // Update loading state
                self.isLoading = false
                let loadTime = Date().timeIntervalSince(startTime)

                if let loadedImage = loadedImage {
                    self.image = loadedImage
                    self.onImageLoad?(loadedImage)
                    self.hasError = false
                    self.retryCount = 0

                    // Post success notification for live monitoring
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ProfileImageLoadAttempt"),
                        object: nil,
                        userInfo: [
                            "url": url.absoluteString,
                            "success": true,
                            "loadTime": loadTime,
                            "priority": loadPriority.rawValue,
                        ]
                    )
                } else {
                    // Network request completed but returned nil (could be 404, invalid data, etc.)
                    self.hasError = true

                    // Post failure notification for live monitoring
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ProfileImageLoadAttempt"),
                        object: nil,
                        userInfo: [
                            "url": url.absoluteString,
                            "success": false,
                            "loadTime": loadTime,
                            "priority": loadPriority.rawValue,
                        ]
                    )

                    // Smart retry logic based on priority and visibility
                    if self.retryCount < self.maxRetries && self.isVisible {
                        self.retryCount += 1
                        let baseDelay = Double(self.retryCount * self.retryCount) * 0.3  // Faster retries
                        let jitter = Double.random(in: 0.05...0.15)
                        let delay = baseDelay + jitter

                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                            if self.isVisible {  // Only retry if still visible
                                self.loadImageWithPriority(loadPriority)
                            }
                        }
                    }
                }
            })
            .store(in: &cancellables)
    }
}

/// Convenience initializers
extension CachedAsyncImage where Content == Image, Placeholder == AnyView {
    init(url: URL?, priority: ImageLoadPriority = .normal, onImageLoad: ((UIImage) -> Void)? = nil) {
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

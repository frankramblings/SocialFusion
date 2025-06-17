import Combine
import SwiftUI

/// A cached async image loader that provides reliable image loading with proper caching
public class ImageCache: ObservableObject {
    public static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private var inFlightRequests = [URL: AnyPublisher<UIImage?, Never>]()

    private init() {
        // Configure URLSession with optimized settings for image loading
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 100 * 1024 * 1024,  // 100MB memory
            diskCapacity: 200 * 1024 * 1024,  // 200MB disk
            diskPath: "profile_images"
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60

        self.session = URLSession(configuration: config)

        // Set cache limits
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024  // 50MB
    }

    func loadImage(from url: URL) -> AnyPublisher<UIImage?, Never> {
        let key = NSString(string: url.absoluteString)

        // Check memory cache first
        if let cachedImage = cache.object(forKey: key) {
            return Just(cachedImage).eraseToAnyPublisher()
        }

        // Check if we already have an in-flight request for this URL
        if let existingPublisher = inFlightRequests[url] {
            return existingPublisher
        }

        // Create new request
        let publisher = session.dataTaskPublisher(for: url)
            .map { data, response -> UIImage? in
                guard let httpResponse = response as? HTTPURLResponse,
                    httpResponse.statusCode == 200,
                    let image = UIImage(data: data)
                else {
                    return nil
                }
                return image
            }
            .replaceError(with: nil)
            .handleEvents(
                receiveOutput: { [weak self] image in
                    if let image = image {
                        // Cache the successful result
                        self?.cache.setObject(image, forKey: key)
                    }
                },
                receiveCompletion: { [weak self] _ in
                    // Remove from in-flight requests
                    self?.inFlightRequests.removeValue(forKey: url)
                }
            )
            .share()
            .eraseToAnyPublisher()

        // Store in-flight request
        inFlightRequests[url] = publisher

        return publisher
    }

    public func clearCache() {
        cache.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }
}

/// A reliable cached async image view with retry logic
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    @StateObject private var imageCache = ImageCache.shared
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var hasError = false
    @State private var retryCount = 0
    @State private var cancellables = Set<AnyCancellable>()

    private let maxRetries = 2

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = image {
                content(Image(uiImage: image))
            } else if isLoading {
                placeholder()
            } else if hasError && retryCount >= maxRetries {
                placeholder()
            } else {
                placeholder()
                    .onAppear {
                        loadImage()
                    }
            }
        }
        .onAppear {
            if image == nil && !isLoading {
                loadImage()
            }
        }
    }

    private func loadImage() {
        guard let url = url else { return }

        isLoading = true
        hasError = false

        imageCache.loadImage(from: url)
            .receive(on: DispatchQueue.main)
            .sink { loadedImage in
                isLoading = false

                if let loadedImage = loadedImage {
                    image = loadedImage
                    hasError = false
                    retryCount = 0
                } else {
                    hasError = true

                    // Retry logic with exponential backoff
                    if retryCount < maxRetries {
                        retryCount += 1
                        let delay = Double(retryCount) * 1.0  // 1s, 2s delays

                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            loadImage()
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
}

/// Convenience initializer for simple cases
extension CachedAsyncImage where Content == Image, Placeholder == AnyView {
    init(url: URL?) {
        self.init(
            url: url,
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

/// Convenience initializer with custom placeholder
extension CachedAsyncImage where Content == Image {
    init(url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.init(
            url: url,
            content: { image in image },
            placeholder: placeholder
        )
    }
}

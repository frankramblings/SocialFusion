import Foundation
import LinkPresentation
import SwiftUI

// Simple caching for link metadata and images
final class LinkPreviewCache {
    static let shared = LinkPreviewCache()

    private var metadataCache = [URL: LPLinkMetadata]()
    private var imageURLCache = [URL: URL]()
    private let cacheQueue = DispatchQueue(label: "linkPreviewCache", attributes: .concurrent)

    private init() {}

    func getMetadata(for url: URL) -> LPLinkMetadata? {
        return cacheQueue.sync {
            return metadataCache[url]
        }
    }

    func cache(metadata: LPLinkMetadata, for url: URL) {
        cacheQueue.async(flags: .barrier) {
            self.metadataCache[url] = metadata
        }
    }

    func getImageURL(for url: URL) -> URL? {
        return cacheQueue.sync {
            return imageURLCache[url]
        }
    }

    func cacheImage(url imageURL: URL, for linkURL: URL) {
        cacheQueue.async(flags: .barrier) {
            self.imageURLCache[linkURL] = imageURL
        }
    }

    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.metadataCache.removeAll()
            self.imageURLCache.removeAll()
        }
    }
}

// Simplified and more stable metadata provider manager
final class MetadataProviderManager {
    static let shared = MetadataProviderManager()
    private var activeProviders = [URL: LPMetadataProvider]()
    private let queue = DispatchQueue(label: "metadataProvider", qos: .utility)

    private init() {}

    func startFetchingMetadata(
        for url: URL,
        completion: @escaping (LPLinkMetadata?, Error?) -> Void
    ) {
        // Check cache first
        if let cachedMetadata = LinkPreviewCache.shared.getMetadata(for: url) {
            DispatchQueue.main.async {
                completion(cachedMetadata, nil)
            }
            return
        }

        // Cancel any existing provider for this URL
        cancelProvider(for: url)

        // Create a new provider
        let provider = LPMetadataProvider()
        activeProviders[url] = provider

        // Set timeout
        provider.timeout = 10.0

        // Start fetching on background queue
        queue.async { [weak self] in
            provider.startFetchingMetadata(for: url) { metadata, error in
                DispatchQueue.main.async {
                    self?.removeProvider(for: url)

                    // Cache successful results
                    if let metadata = metadata, error == nil {
                        LinkPreviewCache.shared.cache(metadata: metadata, for: url)
                    }

                    completion(metadata, error)
                }
            }
        }
    }

    func cancelProvider(for url: URL) {
        activeProviders[url]?.cancel()
        removeProvider(for: url)
    }

    private func removeProvider(for url: URL) {
        activeProviders.removeValue(forKey: url)
    }

    // Cancel all active providers
    func cancelAll() {
        for (url, provider) in activeProviders {
            provider.cancel()
            removeProvider(for: url)
        }
    }
}

struct LinkPreview: View {
    let url: URL
    @State private var metadata: LPLinkMetadata?
    @State private var isLoading = true
    @State private var loadingFailed = false
    @State private var retryCount = 0

    private let maxRetries = 2

    var body: some View {
        Group {
            if isLoading && retryCount == 0 {
                LinkPreviewPlaceholder()
            } else if loadingFailed || metadata == nil {
                LinkPreviewFallback(url: url)
            } else if let metadata = metadata {
                LinkPreviewContent(metadata: metadata, url: url)
            } else {
                LinkPreviewFallback(url: url)
            }
        }
        .onAppear {
            loadMetadata()
        }
        .onDisappear {
            MetadataProviderManager.shared.cancelProvider(for: url)
        }
    }

    private func loadMetadata() {
        guard retryCount <= maxRetries else {
            isLoading = false
            loadingFailed = true
            return
        }

        isLoading = true

        MetadataProviderManager.shared.startFetchingMetadata(for: url) { metadata, error in
            if let error = error {
                print("Error fetching link metadata for \(url): \(error)")

                // Retry logic for transient errors
                if retryCount < maxRetries && isTransientError(error) {
                    retryCount += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        loadMetadata()
                    }
                    return
                }

                isLoading = false
                loadingFailed = true
                return
            }

            self.metadata = metadata
            self.isLoading = false
            self.loadingFailed = metadata == nil
        }
    }

    private func isTransientError(_ error: Error) -> Bool {
        let nsError = error as NSError
        // Network errors that might be worth retrying
        return nsError.domain == NSURLErrorDomain
            && (nsError.code == NSURLErrorTimedOut
                || nsError.code == NSURLErrorNetworkConnectionLost
                || nsError.code == NSURLErrorNotConnectedToInternet)
    }
}

// Extracted content view for better organization
struct LinkPreviewContent: View {
    let metadata: LPLinkMetadata
    let url: URL
    @State private var imageURL: URL?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image section
            if let imageURL = imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: 200)
                            .cornerRadius(12)
                            .clipped()
                    case .failure(_):
                        EmptyView()
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.15))
                            .frame(maxWidth: .infinity, maxHeight: 200)
                            .cornerRadius(12)
                            .overlay(ProgressView())
                    @unknown default:
                        EmptyView()
                    }
                }
            }

            // Text content
            VStack(alignment: .leading, spacing: 6) {
                if let title = metadata.title, !title.isEmpty {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                }

                // Use domain as description if no other description available
                Text(url.host?.replacingOccurrences(of: "www.", with: "") ?? "Link")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
        )
        .onTapGesture {
            UIApplication.shared.open(url)
        }
        .onAppear {
            loadImage()
        }
    }

    private func loadImage() {
        guard let imageProvider = metadata.imageProvider ?? metadata.iconProvider else { return }

        // Check cache first
        if let cachedImageURL = LinkPreviewCache.shared.getImageURL(for: url) {
            self.imageURL = cachedImageURL
            return
        }

        imageProvider.loadObject(ofClass: UIImage.self) { image, error in
            guard let image = image as? UIImage, error == nil else { return }

            // Create temporary file for image
            let tempDir = FileManager.default.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("png")

            do {
                if let data = image.pngData() {
                    try data.write(to: tempURL)
                    DispatchQueue.main.async {
                        self.imageURL = tempURL
                        LinkPreviewCache.shared.cacheImage(url: tempURL, for: self.url)
                    }
                }
            } catch {
                print("Failed to save image: \(error)")
            }
        }
    }
}

// Improved placeholder with better styling
struct LinkPreviewPlaceholder: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image placeholder
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 120)
                .cornerRadius(12)
                .overlay(
                    ProgressView()
                        .scaleEffect(0.8)
                )

            // Text placeholders
            VStack(alignment: .leading, spacing: 6) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(4)

                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 12)
                    .frame(maxWidth: 120)
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
        )
        .redacted(reason: .placeholder)
    }
}

// Improved fallback with better styling
struct LinkPreviewFallback: View {
    let url: URL
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Link icon
            Image(systemName: "link")
                .font(.title2)
                .foregroundColor(.secondary)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color.gray.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(url.host?.replacingOccurrences(of: "www.", with: "") ?? "Link")
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("External Link")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
        )
        .onTapGesture {
            UIApplication.shared.open(url)
        }
    }
}

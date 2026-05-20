import Foundation
import LinkPresentation
import SwiftUI

// Simplified and more stable metadata provider manager
final class MetadataProviderManager {
    static let shared = MetadataProviderManager()

    private var activeProviders = [URL: LPMetadataProvider]()
    private let providerQueue = DispatchQueue(label: "metadataProvider", attributes: .concurrent)
    private let maxConcurrentRequests = 5  // Increased from 3 to reduce queuing delays
    private var requestCount = 0

    private init() {}

    func startFetchingMetadata(
        for url: URL, completion: @escaping (LPLinkMetadata?, Error?) -> Void
    ) {
        // Check cache first
        if let cachedMetadata = LinkPreviewCache.shared.getMetadata(for: url) {
            DispatchQueue.main.async {
                completion(cachedMetadata, nil)
            }
            return
        }

        // Limit concurrent requests to prevent too many web processes
        providerQueue.async(flags: .barrier) {
            guard self.requestCount < self.maxConcurrentRequests else {
                // Queue is full, delay this request with shorter delay to reduce timeout issues
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {  // Reduced from 0.5s
                    self.startFetchingMetadata(for: url, completion: completion)
                }
                return
            }

            self.requestCount += 1

            let provider = LPMetadataProvider()
            self.activeProviders[url] = provider

            provider.startFetchingMetadata(for: url) { metadata, error in
                self.providerQueue.async(flags: .barrier) {
                    self.activeProviders.removeValue(forKey: url)
                    self.requestCount -= 1
                }

                if let metadata = metadata {
                    LinkPreviewCache.shared.cache(metadata: metadata, for: url)
                }

                DispatchQueue.main.async {
                    completion(metadata, error)
                }
            }
        }
    }

    func cancelProvider(for url: URL) {
        providerQueue.async(flags: .barrier) {
            if let provider = self.activeProviders.removeValue(forKey: url) {
                provider.cancel()
                self.requestCount -= 1
            }
        }
    }

    func cancelAllProviders() {
        providerQueue.async(flags: .barrier) {
            self.activeProviders.values.forEach { $0.cancel() }
            self.activeProviders.removeAll()
            self.requestCount = 0
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
            // Use Task to defer state updates outside view rendering cycle
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                loadMetadata()
            }
        }
        .onDisappear {
            // Use Task to defer state updates outside view rendering cycle
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                MetadataProviderManager.shared.cancelProvider(for: url)
            }
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
                #if DEBUG
                print("Error fetching link metadata for \(url): \(error)")
                #endif

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
        Button {
            HapticEngine.tap.trigger()
            UIApplication.shared.open(url)
        } label: {
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
                                .clipShape(RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous))
                                .clipped()
                        case .failure(_):
                            EmptyView()
                        case .empty:
                            RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous)
                                .fill(Color(.systemGray5))
                                .frame(maxWidth: .infinity, maxHeight: 200)
                                .overlay(ProgressView())
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .id(imageURL.absoluteString)
                }

                // Text content
                VStack(alignment: .leading, spacing: 6) {
                    if let title = metadata.title, !title.isEmpty {
                        Text(title)
                            .font(.headline.weight(.semibold))
                            .lineLimit(2)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                    }

                    // Use domain as description if no other description available
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 10))
                        Text(url.host?.replacingOccurrences(of: "www.", with: "") ?? "Link")
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous)
                    .fill(Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous))
        }
        .buttonStyle(LinkPreviewCardPressStyle())
        .accessibilityLabel(metadata.title ?? url.host ?? "Link")
        .accessibilityValue(url.host ?? "")
        .accessibilityHint("Opens this link in your browser")
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
                #if DEBUG
                print("Failed to save image: \(error)")
                #endif
            }
        }
    }
}

// Improved placeholder with better styling
struct LinkPreviewPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image placeholder
            RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous)
                .fill(Color(.systemGray5))
                .frame(height: 120)
                .overlay(
                    ProgressView()
                        .scaleEffect(0.8)
                )

            // Text placeholders — system-named grays adapt to dark mode
            // (Color.gray.opacity reads as brown-tinted in dark mode).
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(.systemGray5).opacity(0.7))
                    .frame(height: 12)
                    .frame(maxWidth: 120)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous)
                .fill(Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous))
        .redacted(reason: .placeholder)
    }
}

// Improved fallback with better styling
struct LinkPreviewFallback: View {
    let url: URL
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            HapticEngine.tap.trigger()
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: 12) {
                // Link icon — tinted accent so the affordance feels intentional
                Image(systemName: "link")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Color.accentColor.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(url.host?.replacingOccurrences(of: "www.", with: "") ?? "Link")
                        .font(.callout.weight(.medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)

                    Text("External Link")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous)
                    .fill(Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous))
        }
        .buttonStyle(LinkPreviewCardPressStyle())
        .accessibilityLabel(url.host ?? "External link")
        .accessibilityHint("Opens this link in your browser")
    }
}

/// Subtle press feedback for link previews — small scale + dim. Shared between
/// the rich content and fallback variants so taps feel consistent.
private struct LinkPreviewCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.86 : 1.0)
            .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

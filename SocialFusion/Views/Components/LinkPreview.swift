import Foundation
import LinkPresentation
import SwiftUI

// Singleton metadata provider manager to prevent deallocation issues
final class MetadataProviderManager {
    static let shared = MetadataProviderManager()
    private var activeProviders = [URL: LPMetadataProvider]()

    private init() {}

    func startFetchingMetadata(
        for url: URL, completion: @escaping (LPLinkMetadata?, Error?) -> Void
    ) {
        // Check cache first - temporarily disabled until we fix import issues
        // TODO: Re-enable caching once dependencies are fixed
        /*
        if let cachedMetadata = LinkPreviewCache.shared.getMetadata(for: url) {
            completion(cachedMetadata, nil)
            return
        }
        */

        // Cancel any existing provider for this URL
        cancelProvider(for: url)

        // Create a new provider (must be a new instance each time)
        let provider = LPMetadataProvider()
        activeProviders[url] = provider

        // Start fetching
        provider.startFetchingMetadata(for: url) { [weak self] metadata, error in
            // Remove the provider from active providers when done
            DispatchQueue.main.async {
                self?.removeProvider(for: url)

                // Cache the successful result - temporarily disabled
                // TODO: Re-enable caching once dependencies are fixed
                /*
                if let metadata = metadata, error == nil {
                    LinkPreviewCache.shared.cache(metadata: metadata, for: url)
                }
                */

                completion(metadata, error)
            }
        }
    }

    func cancelProvider(for url: URL) {
        activeProviders[url]?.cancel()
        removeProvider(for: url)
    }

    func removeProvider(for url: URL) {
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
    @State private var title: String?
    @State private var desc: String?
    @State private var imageURL: URL?
    @State private var isLoading = true
    @State private var loadingFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                LinkPreviewPlaceholder()
            } else if loadingFailed {
                LinkPreviewFallback(url: url)
            } else {
                // Link preview content
                VStack(alignment: .leading, spacing: 8) {
                    if let imageURL = imageURL {
                        AsyncImage(url: imageURL) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(maxWidth: .infinity, maxHeight: 220)
                                    .cornerRadius(14)
                                    .clipped()
                                    .accessibilityAddTraits(.isImage)
                            } else if phase.error != nil {
                                EmptyView() // Hide on error
                            } else {
                                Color.gray.opacity(0.15)
                                    .frame(maxWidth: .infinity, maxHeight: 220)
                                    .cornerRadius(14)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if let title = title {
                            Text(title)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .lineLimit(2)
                        }

                        if let desc = desc {
                            Text(desc)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }

                        Text(url.host ?? "")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            }
        }
        .onTapGesture {
            // Open URL when tapped
            UIApplication.shared.open(url)
        }
        .onAppear {
            // Check for cached image URL first - temporarily disabled
            // TODO: Re-enable caching once dependencies are fixed
            /*
            if let cachedImageURL = LinkPreviewCache.shared.getImageURL(for: url) {
                self.imageURL = cachedImageURL
            }
            */

            loadMetadata()
        }
        .onDisappear {
            // Clean up provider when view disappears
            MetadataProviderManager.shared.cancelProvider(for: url)
        }
    }

    private func loadMetadata() {
        isLoading = true

        // First, check if we're allowed to fetch from this URL based on robots.txt - temporarily disabled
        // TODO: Re-enable robots.txt checking once dependencies are fixed
        /*
        RobotsTxtChecker.shared.isAllowedToFetch(url: url) { isAllowed in
            if !isAllowed {
                DispatchQueue.main.async {
                    print("Fetching metadata for \(self.url) is not allowed by robots.txt")
                    self.isLoading = false
                    self.loadingFailed = true
                }
                return
            }
        */

        // */ // Close the comment block

        // Use the manager to handle the fetch
        MetadataProviderManager.shared.startFetchingMetadata(for: self.url) { metadata, error in
            DispatchQueue.main.async {
                self.isLoading = false

                if let error = error {
                    print("Error fetching link metadata: \(error)")
                    self.loadingFailed = true
                    return
                }

                guard let metadata = metadata else {
                    self.loadingFailed = true
                    return
                }

                // Extract metadata
                self.title = metadata.title

                // For description, use the URL domain
                if let host = self.url.host {
                    self.desc = host.replacingOccurrences(of: "www.", with: "")
                }

                // Extract image if available
                if let imageProvider = metadata.imageProvider ?? metadata.iconProvider {
                    imageProvider.loadObject(ofClass: UIImage.self) { image, error in
                        if let error = error {
                            print("Error loading image: \(error)")
                            return
                        }

                        if let image = image as? UIImage, let data = image.pngData() {
                            // Create a temporary URL for the image
                            let tempDir = FileManager.default.temporaryDirectory
                            let tempUrl = tempDir.appendingPathComponent(UUID().uuidString)
                                .appendingPathExtension("png")

                            do {
                                try data.write(to: tempUrl)
                                DispatchQueue.main.async {
                                    self.imageURL = tempUrl
                                    // Cache the image URL - temporarily disabled
                                    // TODO: Re-enable caching once dependencies are fixed
                                    // LinkPreviewCache.shared.cacheImage(url: tempUrl, for: self.url)
                                }
                            } catch {
                                print("Failed to save image: \(error)")
                            }
                        }
                    }
                }
            }
        }
    }
}

// Link preview placeholder while loading
struct LinkPreviewPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image placeholder
            Rectangle()
                .foregroundColor(Color.gray.opacity(0.2))
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    ProgressView()
                        .frame(width: 30, height: 30)
                )

            // Title placeholder
            Rectangle()
                .foregroundColor(Color.gray.opacity(0.2))
                .frame(height: 16)
                .frame(width: 200)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            // Description placeholder
            Rectangle()
                .foregroundColor(Color.gray.opacity(0.15))
                .frame(height: 12)
                .frame(width: 240)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            // URL placeholder
            Rectangle()
                .foregroundColor(Color.gray.opacity(0.15))
                .frame(height: 10)
                .frame(width: 160)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// Fallback link preview for when loading fails
struct LinkPreviewFallback: View {
    let url: URL

    var body: some View {
        HStack(spacing: 12) {
            // Link icon
            Image(systemName: "link")
                .font(.title2)
                .foregroundColor(.secondary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.gray.opacity(0.1))
                )
                .padding(.leading, 8)

            VStack(alignment: .leading, spacing: 4) {
                // Show the host if available, otherwise the URL string
                Text(url.host ?? url.absoluteString)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("Link")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // External link icon
            Image(systemName: "arrow.up.right")
                .font(.callout)
                .foregroundColor(.secondary)
                .padding(.trailing, 12)
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            // Open URL when tapped
            UIApplication.shared.open(url)
        }
    }
}

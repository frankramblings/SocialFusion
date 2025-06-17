import LinkPresentation
import SwiftUI

/// A link preview component that maintains stable dimensions to prevent layout shifts
struct StabilizedLinkPreview: View {
    let url: URL
    let idealHeight: CGFloat

    @State private var metadata: LPLinkMetadata?
    @State private var isLoading = true
    @State private var loadingFailed = false
    @State private var retryCount = 0
    @Environment(\.colorScheme) private var colorScheme

    private let maxRetries = 2

    init(url: URL, idealHeight: CGFloat = 200) {
        self.url = url
        self.idealHeight = idealHeight
        print(
            "🎯 [StabilizedLinkPreview] Created for URL: \(url.absoluteString) with height: \(idealHeight)"
        )
    }

    var body: some View {
        contentView
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: isLoading)
            .onAppear {
                print("🎯 [StabilizedLinkPreview] onAppear for URL: \(url.absoluteString)")
                loadMetadata()
            }
            .onDisappear {
                print("🎯 [StabilizedLinkPreview] onDisappear for URL: \(url.absoluteString)")
                MetadataProviderManager.shared.cancelProvider(for: url)
            }
    }

    @ViewBuilder
    private var contentView: some View {
        if isLoading && retryCount == 0 {
            StabilizedLinkLoadingView(height: idealHeight)
        } else if let metadata = metadata {
            StabilizedLinkContentView(
                metadata: metadata,
                url: url,
                height: idealHeight
            )
        } else {
            StabilizedLinkFallbackView(url: url, height: idealHeight)
        }
    }

    private func loadMetadata() {
        guard retryCount <= maxRetries else {
            print("🎯 [StabilizedLinkPreview] Max retries exceeded for URL: \(url.absoluteString)")
            isLoading = false
            loadingFailed = true
            return
        }

        print(
            "🎯 [StabilizedLinkPreview] Starting metadata load for URL: \(url.absoluteString) (attempt \(retryCount + 1))"
        )
        isLoading = true

        MetadataProviderManager.shared.startFetchingMetadata(for: url) { metadata, error in
            DispatchQueue.main.async {
                if let error = error {
                    print(
                        "🎯 [StabilizedLinkPreview] Error fetching metadata for \(self.url): \(error)"
                    )

                    if self.retryCount < self.maxRetries && self.isTransientError(error) {
                        self.retryCount += 1
                        print(
                            "🎯 [StabilizedLinkPreview] Will retry after delay for URL: \(self.url.absoluteString)"
                        )
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.loadMetadata()
                        }
                        return
                    }

                    print(
                        "🎯 [StabilizedLinkPreview] Failed to load metadata for URL: \(self.url.absoluteString)"
                    )
                    self.isLoading = false
                    self.loadingFailed = true
                    return
                }

                print(
                    "🎯 [StabilizedLinkPreview] Successfully loaded metadata for URL: \(self.url.absoluteString)"
                )
                if let metadata = metadata {
                    print("🎯 [StabilizedLinkPreview] Metadata title: \(metadata.title ?? "nil")")
                    print(
                        "🎯 [StabilizedLinkPreview] Metadata URL: \(metadata.url?.absoluteString ?? "nil")"
                    )
                }

                self.metadata = metadata
                self.isLoading = false
                self.loadingFailed = metadata == nil
            }
        }
    }

    private func isTransientError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
            && (nsError.code == NSURLErrorTimedOut
                || nsError.code == NSURLErrorNetworkConnectionLost
                || nsError.code == NSURLErrorNotConnectedToInternet)
    }
}

/// Loading state with shimmer effect and consistent height
private struct StabilizedLinkLoadingView: View {
    let height: CGFloat
    @State private var phase: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image placeholder on top (Ivory style)
            Rectangle()
                .fill(shimmerGradient)
                .frame(maxWidth: .infinity)
                .frame(height: 130)
                .clipShape(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: 16,
                            bottomLeading: 0,
                            bottomTrailing: 0,
                            topTrailing: 16
                        )
                    )
                )

            // Text placeholders below image
            VStack(alignment: .leading, spacing: 6) {
                // Title placeholder
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(4)

                // Description placeholder
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 14)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(4)

                // URL placeholder
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 12)
                    .frame(maxWidth: 120)
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .clipped()
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1.3
            }
        }
    }

    private var shimmerGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.gray.opacity(0.1), location: phase - 0.3),
                .init(color: Color.gray.opacity(0.3), location: phase),
                .init(color: Color.gray.opacity(0.1), location: phase + 0.3),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// Content view with Ivory-style vertical layout (image above, text below)
private struct StabilizedLinkContentView: View {
    let metadata: LPLinkMetadata
    let url: URL
    let height: CGFloat

    @State private var imageURL: URL?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: {
            UIApplication.shared.open(url)
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Image on top (Ivory style) - full width, edge to edge
                imageSection
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 100, maxHeight: 160)

                // Text content below image (Ivory style)
                textSection
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
            .clipped()
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadImageURL()
        }
    }

    @ViewBuilder
    private var imageSection: some View {
        if let imageURL = imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 160)
                        .clipped()
                        .clipShape(
                            UnevenRoundedRectangle(
                                cornerRadii: .init(
                                    topLeading: 16,
                                    bottomLeading: 0,
                                    bottomTrailing: 0,
                                    topTrailing: 16
                                )
                            )
                        )
                case .failure(_):
                    failureImageView
                case .empty:
                    loadingImageView
                @unknown default:
                    EmptyView()
                }
            }
        } else {
            placeholderImageView
        }
    }

    private var failureImageView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.15))
            .clipShape(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 16,
                        bottomLeading: 0,
                        bottomTrailing: 0,
                        topTrailing: 16
                    )
                )
            )
            .overlay(
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundColor(.secondary)
            )
    }

    private var loadingImageView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.1))
            .clipShape(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 16,
                        bottomLeading: 0,
                        bottomTrailing: 0,
                        topTrailing: 16
                    )
                )
            )
            .overlay(
                ProgressView()
                    .scaleEffect(0.8)
            )
    }

    private var placeholderImageView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.15))
            .clipShape(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 16,
                        bottomLeading: 0,
                        bottomTrailing: 0,
                        topTrailing: 16
                    )
                )
            )
            .overlay(
                Image(systemName: "link")
                    .font(.title2)
                    .foregroundColor(.secondary)
            )
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = metadata.title, !title.isEmpty {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let description = metadata.value(forKey: "_summary") as? String,
                !description.isEmpty
            {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(url.host?.replacingOccurrences(of: "www.", with: "") ?? "Link")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadImageURL() {
        print("🔍 [StabilizedLinkPreview] Loading image for URL: \(url)")

        guard let imageProvider = metadata.imageProvider ?? metadata.iconProvider else {
            print("❌ [StabilizedLinkPreview] No image provider found for \(url)")
            return
        }

        if let cachedURL = LinkPreviewCache.shared.getImageURL(for: url) {
            print("✅ [StabilizedLinkPreview] Using cached image for \(url)")
            self.imageURL = cachedURL
            return
        }

        print("📥 [StabilizedLinkPreview] Loading image from provider for \(url)")
        imageProvider.loadObject(ofClass: UIImage.self) { image, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ [StabilizedLinkPreview] Error loading image for \(self.url): \(error)")
                    return
                }

                guard let image = image as? UIImage else {
                    print("❌ [StabilizedLinkPreview] Invalid image type for \(self.url)")
                    return
                }

                print("✅ [StabilizedLinkPreview] Successfully loaded image for \(self.url)")

                let tempDir = FileManager.default.temporaryDirectory
                let tempURL = tempDir.appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("png")

                do {
                    if let data = image.pngData() {
                        try data.write(to: tempURL)
                        self.imageURL = tempURL
                        LinkPreviewCache.shared.cacheImage(url: tempURL, for: self.url)
                        print("💾 [StabilizedLinkPreview] Cached image for \(self.url)")
                    }
                } catch {
                    print(
                        "❌ [StabilizedLinkPreview] Failed to save image for \(self.url): \(error)")
                }
            }
        }
    }
}

/// Fallback view with Ivory-style vertical layout
private struct StabilizedLinkFallbackView: View {
    let url: URL
    let height: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: {
            UIApplication.shared.open(url)
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Icon placeholder on top
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .clipShape(
                        UnevenRoundedRectangle(
                            cornerRadii: .init(
                                topLeading: 16,
                                bottomLeading: 0,
                                bottomTrailing: 0,
                                topTrailing: 16
                            )
                        )
                    )
                    .overlay(
                        Image(systemName: "link")
                            .font(.title)
                            .foregroundColor(.secondary)
                    )

                // Text content below
                VStack(alignment: .leading, spacing: 6) {
                    Text(url.host?.replacingOccurrences(of: "www.", with: "") ?? "Link")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Show more of the URL path for better context
                    Text(url.path.isEmpty ? "External Link" : url.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
            .clipped()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VStack(spacing: 16) {
        StabilizedLinkPreview(
            url: URL(string: "https://apple.com")!,
            idealHeight: 180
        )

        StabilizedLinkPreview(
            url: URL(string: "https://github.com")!,
            idealHeight: 180
        )

        StabilizedLinkPreview(
            url: URL(string: "https://invalid-url.com")!,
            idealHeight: 180
        )
    }
    .padding()
}

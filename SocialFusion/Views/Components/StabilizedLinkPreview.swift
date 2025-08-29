import LinkPresentation
import SwiftUI
import UIKit

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
        #if targetEnvironment(simulator)
            print("🎯 [StabilizedLinkPreview] Running on iOS Simulator")
        #else
            print("🎯 [StabilizedLinkPreview] Running on device")
        #endif
    }

    var body: some View {
        contentView
            .frame(maxWidth: .infinity, idealHeight: idealHeight, maxHeight: idealHeight)
            .fixedSize(horizontal: false, vertical: true)
            .animation(.easeInOut(duration: 0.2), value: isLoading)
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

    @ViewBuilder
    private var contentView: some View {
        if isLoading && retryCount == 0 {
            StabilizedLinkLoadingView(height: idealHeight)
        } else if let metadata = metadata,
            metadata.title != nil || metadata.iconProvider != nil || metadata.imageProvider != nil
        {
            // Show rich content if we have meaningful metadata
            StabilizedLinkContentView(
                metadata: metadata,
                url: url,
                height: idealHeight
            )
        } else {
            // Always show fallback - better than nothing!
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

        // Add a timeout for metadata loading
        let timeoutTask = DispatchWorkItem {
            DispatchQueue.main.async {
                print(
                    "⏰ [StabilizedLinkPreview] Timeout reached for URL: \(self.url.absoluteString)")
                self.isLoading = false
                self.loadingFailed = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0, execute: timeoutTask)

        MetadataProviderManager.shared.startFetchingMetadata(for: url) { metadata, error in
            timeoutTask.cancel()  // Cancel timeout if we get a response
            DispatchQueue.main.async {
                if let error = error {
                    print(
                        "❌ [StabilizedLinkPreview] Error fetching metadata for \(self.url): \(error)"
                    )
                    print(
                        "❌ [StabilizedLinkPreview] Error domain: \((error as NSError).domain), code: \((error as NSError).code)"
                    )
                    print(
                        "❌ [StabilizedLinkPreview] Error localizedDescription: \(error.localizedDescription)"
                    )

                    if self.retryCount < self.maxRetries && self.isTransientError(error) {
                        self.retryCount += 1
                        print(
                            "🔄 [StabilizedLinkPreview] Will retry (\(self.retryCount)/\(self.maxRetries)) after delay for URL: \(self.url.absoluteString)"
                        )
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.loadMetadata()
                        }
                        return
                    }

                    print(
                        "❌ [StabilizedLinkPreview] Failed to load metadata for URL: \(self.url.absoluteString) after \(self.retryCount) retries"
                    )
                    self.isLoading = false
                    self.loadingFailed = true
                    return
                }

                print(
                    "✅ [StabilizedLinkPreview] Successfully loaded metadata for URL: \(self.url.absoluteString)"
                )
                if let metadata = metadata {
                    print("🎯 [StabilizedLinkPreview] Metadata title: \(metadata.title ?? "nil")")
                    print(
                        "🎯 [StabilizedLinkPreview] Metadata URL: \(metadata.url?.absoluteString ?? "nil")"
                    )
                    print("🎯 [StabilizedLinkPreview] Has icon: \(metadata.iconProvider != nil)")
                    print("🎯 [StabilizedLinkPreview] Has image: \(metadata.imageProvider != nil)")
                } else {
                    print(
                        "⚠️ [StabilizedLinkPreview] Metadata is nil but no error - treating as success with fallback"
                    )
                }

                self.metadata = metadata
                self.isLoading = false
                // Even if metadata is nil, don't mark as failed - use fallback view instead
                self.loadingFailed = false
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
                .frame(height: 120)
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
        .frame(maxWidth: .infinity, idealHeight: height, maxHeight: height + 50)
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
            // Use Task to defer state updates outside view rendering cycle
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
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
                // Image on top - full width, edge to edge, matching Bluesky style
                imageSection
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)  // Slightly reduced height to prevent squishing
                    .clipped()

                // Text content below image - Bluesky style
                textSection
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)  // Increased vertical padding for more breathing room
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        colorScheme == .dark
                            ? Color(.systemGray6) : Color(.systemGray6).opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
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
                        .frame(maxHeight: 140)
                        .clipped()
                        .clipShape(
                            UnevenRoundedRectangle(
                                cornerRadii: .init(
                                    topLeading: 12,
                                    bottomLeading: 0,
                                    bottomTrailing: 0,
                                    topTrailing: 12
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
                        topLeading: 12,
                        bottomLeading: 0,
                        bottomTrailing: 0,
                        topTrailing: 12
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
                        topLeading: 12,
                        bottomLeading: 0,
                        bottomTrailing: 0,
                        topTrailing: 12
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
                        topLeading: 12,
                        bottomLeading: 0,
                        bottomTrailing: 0,
                        topTrailing: 12
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
        VStack(alignment: .leading, spacing: 6) {  // Increased spacing for breathing room
            // Title - Bluesky style with proper line height
            if let title = metadata.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineSpacing(2)  // Add proper line spacing
                    .lineLimit(2)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Description - Bluesky style
            if let description = metadata.value(forKey: "_summary") as? String,
                !description.isEmpty
            {
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Domain - Bluesky style with subtle styling
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text(url.host?.replacingOccurrences(of: "www.", with: "") ?? "Link")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
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

                // Create a temporary file URL for the image
                let tempDir = FileManager.default.temporaryDirectory
                let tempURL = tempDir.appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("jpg")

                if let imageData = image.jpegData(compressionQuality: 0.8) {
                    do {
                        try imageData.write(to: tempURL)
                        LinkPreviewCache.shared.cacheImage(url: tempURL, for: self.url)
                        self.imageURL = tempURL
                        print("💾 [StabilizedLinkPreview] Cached image at: \(tempURL)")
                    } catch {
                        print("❌ [StabilizedLinkPreview] Failed to write image data: \(error)")
                    }
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
                // Icon placeholder on top - Bluesky style
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .clipShape(
                        UnevenRoundedRectangle(
                            cornerRadii: .init(
                                topLeading: 12,
                                bottomLeading: 0,
                                bottomTrailing: 0,
                                topTrailing: 12
                            )
                        )
                    )
                    .overlay(
                        Image(systemName: "link")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    )

                // Text content below - Bluesky style
                VStack(alignment: .leading, spacing: 6) {
                    Text(url.host?.replacingOccurrences(of: "www.", with: "") ?? "Link")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Show more of the URL path for better context
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Text(url.path.isEmpty ? "External Link" : url.path)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        colorScheme == .dark
                            ? Color(.systemGray6) : Color(.systemGray6).opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
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

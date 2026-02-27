import LinkPresentation
import SwiftUI
import UIKit

/// A link preview component that maintains stable dimensions to prevent layout shifts
/// Mirrors the nuanced behaviors of Ivory and Bluesky.
///
/// **Server-First Hybrid Architecture:**
/// - Server card fields (title/description/thumbnailURL) are treated as sufficient for rich rendering
/// - LPLinkMetadata may enhance (e.g., add icon/image) but never downgrades the view
/// - LP timeouts/errors do not force fallback when server fields exist
struct StabilizedLinkPreview: View {
    let url: URL
    let title: String?
    let description: String?
    let thumbnailURL: URL?
    let idealHeight: CGFloat

    @State private var metadata: LPLinkMetadata?
    @State private var isLoading = true
    @State private var loadingFailed = false
    @State private var retryCount = 0
    @Environment(\.colorScheme) private var colorScheme

    private let maxRetries = 2

    /// Whether server-provided card fields are sufficient for rich rendering
    /// True if we have a title, description, OR thumbnail from the server card
    private var hasServerCardFields: Bool {
        (title != nil && !(title?.isEmpty ?? true)) ||
        (description != nil && !(description?.isEmpty ?? true)) ||
        thumbnailURL != nil
    }

    init(
        url: URL, title: String? = nil, description: String? = nil, thumbnailURL: URL? = nil,
        idealHeight: CGFloat = 200
    ) {
        self.url = url
        self.title = title
        self.description = description
        self.thumbnailURL = thumbnailURL
        self.idealHeight = idealHeight
    }

    var body: some View {
        contentView
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: isLoading)
            // DEBUG: Track layout shifts for link previews
            .trackLayoutShifts(id: "linkpreview-\(url.absoluteString.hashValue)", componentType: "LinkPreview")
            .onAppear {
                // Defer state updates to prevent AttributeGraph cycles
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                    // Prevent AttributeGraph cycles by checking if already loading
                    guard !isLoading || metadata == nil else { return }
                    loadMetadata()
                }
            }
            .onDisappear {
                // Defer cleanup to prevent AttributeGraph cycles
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                    MetadataProviderManager.shared.cancelProvider(for: url)
                }
            }
    }

    @ViewBuilder
    private var contentView: some View {
        // Server-First Hybrid Logic:
        // 1. If server card fields exist, use rich view immediately (no loading state)
        // 2. LP metadata enhances but never downgrades the view
        // 3. Only show loading/fallback when no server fields exist

        if hasServerCardFields {
            // Server card fields are sufficient - render rich content immediately
            // LP metadata may enhance (add icon/image) but view won't downgrade
            StabilizedLinkRichContentView(
                metadata: metadata,  // May be nil initially, enhances when loaded
                url: url,
                passedTitle: title,
                passedDescription: description,
                passedThumbnailURL: thumbnailURL
            )
        } else if isLoading && retryCount == 0 {
            // No server fields - show loading state while fetching LP metadata
            StabilizedLinkLoadingView(height: idealHeight)
        } else if let metadata = metadata {
            // No server fields, but LP metadata available
            if metadata.imageProvider != nil || metadata.iconProvider != nil
                || metadata.title != nil
            {
                StabilizedLinkRichContentView(
                    metadata: metadata,
                    url: url,
                    passedTitle: title,
                    passedDescription: description,
                    passedThumbnailURL: thumbnailURL
                )
            } else {
                // LP metadata exists but has no rich content - show fallback
                StabilizedLinkFallbackView(url: url)
            }
        } else {
            // No server fields, no LP metadata - show generic fallback
            StabilizedLinkFallbackView(url: url)
        }
    }

    private func loadMetadata() {
        guard retryCount <= maxRetries else {
            isLoading = false
            loadingFailed = true
            // DEBUG: Log when retries exhausted (only on actual fallback/slow scenarios)
            #if DEBUG
            if !hasServerCardFields {
                print("[LinkPreview] FALLBACK: Retries exhausted for \(url.host ?? "unknown"), serverCardFields=\(hasServerCardFields)")
            }
            #endif
            return
        }

        isLoading = true
        let serverFieldsExist = hasServerCardFields

        // Reduced timeout to 5 seconds - LPMetadataProvider typically completes faster
        // This prevents showing generic fallback too quickly while still being responsive
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds (reduced from 8)
            if self.isLoading {
                // Only show fallback if we're still loading after timeout
                // This means the metadata fetch is taking too long
                self.isLoading = false
                self.loadingFailed = true

                // DEBUG: Log timeout with decision outcome
                #if DEBUG
                if !serverFieldsExist {
                    print("[LinkPreview] TIMEOUT: LP fetch timed out for \(self.url.host ?? "unknown"), serverCardFields=\(serverFieldsExist), decision=fallback")
                }
                #endif
            }
        }

        let startTime = Date()
        MetadataProviderManager.shared.startFetchingMetadata(for: url) { metadata, error in
            timeoutTask.cancel()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds

                let elapsed = Date().timeIntervalSince(startTime)

                if let error = error {
                    if self.retryCount < self.maxRetries && self.isTransientError(error) {
                        self.retryCount += 1
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
                            self.loadMetadata()
                        }
                        return
                    }
                    self.isLoading = false
                    self.loadingFailed = true

                    // DEBUG: Log errors with decision outcome (throttled to slow/fallback only)
                    #if DEBUG
                    if !serverFieldsExist {
                        print("[LinkPreview] ERROR: LP fetch failed for \(self.url.host ?? "unknown") in \(String(format: "%.2f", elapsed))s, serverCardFields=\(serverFieldsExist), decision=fallback, error=\(error.localizedDescription)")
                    }
                    #endif
                    return
                }

                // Always update metadata if we got it, even if timeout already fired
                // This ensures we show rich previews when metadata arrives late
                if let metadata = metadata {
                    self.metadata = metadata
                    self.isLoading = false
                    self.loadingFailed = false

                    // DEBUG: Log slow fetches only (> 3s threshold)
                    #if DEBUG
                    if elapsed > 3.0 && !serverFieldsExist {
                        print("[LinkPreview] SLOW: LP fetch took \(String(format: "%.2f", elapsed))s for \(self.url.host ?? "unknown"), serverCardFields=\(serverFieldsExist), decision=rich_from_lp")
                    }
                    #endif
                } else {
                    // No metadata and no error - show fallback
                    self.isLoading = false
                    self.loadingFailed = true

                    // DEBUG: Log empty response with decision outcome
                    #if DEBUG
                    let decision = serverFieldsExist ? "rich_from_server" : "fallback"
                    print("[LinkPreview] EMPTY: LP returned nil for \(self.url.host ?? "unknown"), serverCardFields=\(serverFieldsExist), decision=\(decision)")
                    #endif
                }
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

// MARK: - Supporting Views

/// Fixed height constant for link preview image area - used by both loading and loaded states
/// ZERO LAYOUT SHIFT: Both states must use the same height to prevent reflow
private let linkPreviewImageHeight: CGFloat = 180

/// Loading state with shimmer effect - MUST match loaded state geometry exactly
private struct StabilizedLinkLoadingView: View {
    let height: CGFloat  // Kept for backward compatibility, but we use linkPreviewImageHeight
    @State private var phase: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ZERO LAYOUT SHIFT: Image area uses same height as loaded state (180pt)
            Rectangle()
                .fill(shimmerGradient)
                .frame(maxWidth: .infinity)
                .frame(height: linkPreviewImageHeight)
                .clipShape(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: MediaConstants.CornerRadius.feed,
                            bottomLeading: 0,
                            bottomTrailing: 0,
                            topTrailing: MediaConstants.CornerRadius.feed
                        )
                    )
                )

            // Text placeholder area - matches loaded state structure
            VStack(alignment: .leading, spacing: 4) {
                // Title placeholder
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 15)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(4)

                // Description placeholder
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 13)
                    .frame(maxWidth: 200)
                    .cornerRadius(4)

                // URL/domain placeholder
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 10, height: 10)
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 80, height: 12)
                        .cornerRadius(4)
                }
                .padding(.top, 2)
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed)
                .fill(Color(.systemGray6).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed).stroke(
                Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous)
        )
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1.3
            }
        }
    }

    private var shimmerGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.gray.opacity(0.05), location: phase - 0.3),
                .init(color: Color.gray.opacity(0.15), location: phase),
                .init(color: Color.gray.opacity(0.05), location: phase + 0.3),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// Rich Large Content View (Image on top)
/// Supports server-first hybrid rendering where metadata may be nil initially
private struct StabilizedLinkRichContentView: View {
    let metadata: LPLinkMetadata?  // Optional: may be nil when rendering from server card fields only
    let url: URL
    let passedTitle: String?
    let passedDescription: String?
    let passedThumbnailURL: URL?
    @State private var imageURL: URL?
    @State private var iconURL: URL?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            UIApplication.shared.open(url)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Image Section - ZERO LAYOUT SHIFT: Always use fixed height
                ZStack {
                    if let imageURL = imageURL ?? passedThumbnailURL {
                        GeometryReader { geo in
                            AsyncImage(url: imageURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: geo.size.width, height: linkPreviewImageHeight)
                                        .clipped()
                                default:
                                    imagePlaceholder
                                }
                            }
                        }
                        .frame(height: linkPreviewImageHeight)
                    } else if let iconURL = iconURL {
                        // Use icon in large slot if no featured image (Bluesky/Ivory style)
                        ZStack {
                            Color.gray.opacity(0.05)

                            AsyncImage(url: iconURL) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 80, height: 80)
                                        .cornerRadius(12)
                                        .shadow(color: .black.opacity(0.1), radius: 10)
                                } else {
                                    imagePlaceholder
                                }
                            }
                        }
                        .frame(height: linkPreviewImageHeight)
                    } else {
                        imagePlaceholder
                    }
                }
                .clipShape(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: MediaConstants.CornerRadius.feed,
                            bottomLeading: 0,
                            bottomTrailing: 0,
                            topTrailing: MediaConstants.CornerRadius.feed
                        )
                    )
                )

                // Text Section
                VStack(alignment: .leading, spacing: 4) {
                    // Prefer passed title (from server card), fall back to LP metadata title
                    let title = passedTitle ?? metadata?.title
                    if let title = title, !title.isEmpty, title != url.host {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(2)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                    }

                    // Prefer passed description (from server card), fall back to LP metadata description
                    let description = passedDescription ?? metadata.flatMap { extractDescription(from: $0) }
                    if let description = description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 13))
                            .lineLimit(2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 10))
                        Text(url.host?.replacingOccurrences(of: "www.", with: "") ?? "Link")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed)
                    .fill(Color(.systemGray6).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed).stroke(
                    Color(.separator).opacity(0.3), lineWidth: 1))
            .clipShape(
                RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            if imageURL == nil && iconURL == nil {
                loadMedia()
            }
        }
    }

    private var imagePlaceholder: some View {
        // ZERO LAYOUT SHIFT: Placeholder uses same height as loaded images
        Rectangle()
            .fill(Color.gray.opacity(0.1))
            .frame(height: linkPreviewImageHeight)
            .overlay(
                Image(systemName: "link")
                    .font(.title)
                    .foregroundColor(.secondary.opacity(0.3))
            )
    }

    private func loadMedia() {
        // Try to load image from LP metadata first (enhances server card)
        if let imageProvider = metadata?.imageProvider {
            if let cached = LinkPreviewCache.shared.getImageURL(for: url) {
                self.imageURL = cached
            } else {
                imageProvider.loadObject(ofClass: UIImage.self) { image, _ in
                    guard let image = image as? UIImage else { return }
                    Task { @MainActor in
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
                            UUID().uuidString + ".jpg")
                        if let data = image.jpegData(compressionQuality: 0.8) {
                            try? data.write(to: tempURL)
                            LinkPreviewCache.shared.cacheImage(url: tempURL, for: self.url)
                            self.imageURL = tempURL
                        }
                    }
                }
            }
        }

        // Also try to load icon as fallback from LP metadata
        if let iconProvider = metadata?.iconProvider {
            iconProvider.loadObject(ofClass: UIImage.self) { image, _ in
                guard let image = image as? UIImage else { return }
                Task { @MainActor in
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
                        UUID().uuidString + ".png")
                    if let data = image.pngData() {
                        try? data.write(to: tempURL)
                        self.iconURL = tempURL
                    }
                }
            }
        }
    }
}

/// Compact Content View (Horizontal)
private struct StabilizedLinkCompactContentView: View {
    let metadata: LPLinkMetadata
    let url: URL
    let passedTitle: String?
    @State private var iconURL: URL?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: 12) {
                // Icon Section
                if let iconURL = iconURL {
                    AsyncImage(url: iconURL) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: "link").foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1))
                        Image(systemName: "link").foregroundColor(.secondary)
                    }
                    .frame(width: 44, height: 44)
                }

                VStack(alignment: .leading, spacing: 2) {
                    let title = passedTitle ?? metadata.title ?? url.host ?? "Link"
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(.primary)

                    Text(url.host?.replacingOccurrences(of: "www.", with: "") ?? "External Link")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed)
                    .fill(Color(.systemGray6).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed).stroke(
                    Color(.separator).opacity(0.3), lineWidth: 0.5))
            .clipShape(
                RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            if iconURL == nil { loadIcon() }
        }
    }

    private func loadIcon() {
        guard let provider = metadata.iconProvider else { return }
        provider.loadObject(ofClass: UIImage.self) { image, _ in
            guard let image = image as? UIImage else { return }
            Task { @MainActor in
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
                    UUID().uuidString + ".png")
                if let data = image.pngData() {
                    try? data.write(to: tempURL)
                    self.iconURL = tempURL
                }
            }
        }
    }
}

/// Fallback Content View
private struct StabilizedLinkFallbackView: View {
    let url: URL
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "link.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(url.host?.replacingOccurrences(of: "www.", with: "") ?? "Link")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)

                    Text("External Link")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed)
                    .fill(Color(.systemGray6).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed).stroke(
                    Color(.separator).opacity(0.3), lineWidth: 0.5))
            .clipShape(
                RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Utilities

private func extractDescription(from metadata: LPLinkMetadata) -> String? {
    // Try some common internal keys since LPMetadataProvider's public API is limited
    if let summary = metadata.value(forKey: "_summary") as? String { return summary }
    if let selectedText = metadata.value(forKey: "selectedText") as? String { return selectedText }
    return nil
}

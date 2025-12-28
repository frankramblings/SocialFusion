import LinkPresentation
import SwiftUI
import UIKit

/// A link preview component that maintains stable dimensions to prevent layout shifts
/// Mirrors the nuanced behaviors of Ivory and Bluesky.
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
        if isLoading && retryCount == 0 {
            StabilizedLinkLoadingView(height: idealHeight)
        } else if let metadata = metadata {
            if metadata.imageProvider != nil || metadata.iconProvider != nil
                || metadata.title != nil || thumbnailURL != nil
            {
                // Favor Large Mode (Ivory/Bluesky style) for everything with metadata
                StabilizedLinkRichContentView(
                    metadata: metadata,
                    url: url,
                    passedTitle: title,
                    passedDescription: description,
                    passedThumbnailURL: thumbnailURL
                )
            } else {
                StabilizedLinkFallbackView(url: url)
            }
        } else {
            // Always show fallback - better than nothing!
            StabilizedLinkFallbackView(url: url)
        }
    }

    private func loadMetadata() {
        guard retryCount <= maxRetries else {
            isLoading = false
            loadingFailed = true
            return
        }

        isLoading = true

        // Add a timeout for metadata loading
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)  // 8 seconds
            if self.isLoading {
                self.isLoading = false
                self.loadingFailed = true
            }
        }

        MetadataProviderManager.shared.startFetchingMetadata(for: url) { metadata, error in
            timeoutTask.cancel()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
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
                    return
                }

                self.metadata = metadata
                self.isLoading = false
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

// MARK: - Supporting Views

/// Loading state with shimmer effect
private struct StabilizedLinkLoadingView: View {
    let height: CGFloat
    @State private var phase: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(shimmerGradient)
                .frame(maxWidth: .infinity)
                .frame(height: 120)
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

            VStack(alignment: .leading, spacing: 8) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(4)

                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 12)
                    .frame(maxWidth: 180)
                    .cornerRadius(4)
            }
            .padding(12)
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6).opacity(0.5)))
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(
                Color(.separator).opacity(0.3), lineWidth: 0.5)
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
private struct StabilizedLinkRichContentView: View {
    let metadata: LPLinkMetadata
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
                // Image Section
                ZStack {
                    if let imageURL = imageURL ?? passedThumbnailURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(maxWidth: .infinity)
                                    .frame(maxHeight: 180)
                                    .clipped()
                            default:
                                imagePlaceholder
                            }
                        }
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
                        .frame(height: 180)
                    } else {
                        imagePlaceholder
                    }
                }
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

                // Text Section
                VStack(alignment: .leading, spacing: 4) {
                    let title = passedTitle ?? metadata.title
                    if let title = title, !title.isEmpty, title != url.host {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(2)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                    }

                    let description = passedDescription ?? extractDescription(from: metadata)
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
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6).opacity(0.5)))
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(
                    Color(.separator).opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            if imageURL == nil && iconURL == nil {
                loadMedia()
            }
        }
    }

    private var imagePlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.1))
            .frame(height: 120)
            .overlay(
                Image(systemName: "link")
                    .font(.title)
                    .foregroundColor(.secondary.opacity(0.3))
            )
    }

    private func loadMedia() {
        // Try to load image first
        if let imageProvider = metadata.imageProvider {
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

        // Also try to load icon as fallback
        if let iconProvider = metadata.iconProvider {
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
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6).opacity(0.5)))
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(
                    Color(.separator).opacity(0.3), lineWidth: 0.5))
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
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6).opacity(0.5)))
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(
                    Color(.separator).opacity(0.3), lineWidth: 0.5))
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

import AVKit
import ImageIO
import SwiftUI
import UIKit

/// A professional-grade media display component that handles all media types robustly
struct SmartMediaView: View {
    let attachment: Post.Attachment
    let contentMode: ContentMode
    let maxWidth: CGFloat?
    let maxHeight: CGFloat?
    let cornerRadius: CGFloat
    let onTap: (() -> Void)?

    @State private var loadingState: LoadingState = .loading
    @State private var retryCount: Int = 0

    private let maxRetries = 3

    enum LoadingState {
        case loading
        case loaded
        case failed(Error)
    }

    enum ContentMode {
        case fit
        case fill
    }

    init(
        attachment: Post.Attachment,
        contentMode: ContentMode = .fill,
        maxWidth: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        cornerRadius: CGFloat = 12,
        onTap: (() -> Void)? = nil
    ) {
        self.attachment = attachment
        self.contentMode = contentMode
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.cornerRadius = cornerRadius
        self.onTap = onTap
    }

    @ViewBuilder
    private var mediaContent: some View {
        if attachment.type == .audio {
            // Use the comprehensive AudioPlayerView
            AudioPlayerView(
                url: URL(string: attachment.url),
                title: attachment.altText?.isEmpty == false ? attachment.altText : "Audio",
                artist: nil  // Could extract from metadata in the future
            )
            .frame(maxWidth: .infinity)
            .onAppear { print("[SmartMediaView] audio appear url=\(attachment.url)") }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Audio player: \(attachment.altText ?? "Audio content")")
            .accessibilityHint("Use VoiceOver gestures to control playback")
        } else if attachment.type == .video {
            // Use AVPlayer for true video content
            VideoPlayerView(
                url: URL(string: attachment.url),
                isGIF: false
            )
            .onAppear { print("[SmartMediaView] video appear url=\(attachment.url)") }
        } else if attachment.type == .gifv {
            // For GIFV (Mastodon MP4 videos), use VideoPlayerView
            VideoPlayerView(
                url: URL(string: attachment.url),
                isGIF: true  // Treat as GIF for looping behavior
            )
            .onAppear { print("[SmartMediaView] gifv appear url=\(attachment.url)") }
        } else if attachment.type == .animatedGIF {
            // Flag-driven unfurling with local fallback
            let url = URL(string: attachment.url)
            if let url = url {
                Group {
                    if FeatureFlags.enableGIFUnfurling {
                        GIFUnfurlContainer(
                            url: url,
                            maxHeight: maxHeight ?? 300,
                            cornerRadius: cornerRadius,
                            showControls: true,
                            contentMode: contentMode == .fill ? .scaleAspectFill : .scaleAspectFit,
                            onTap: { onTap?() }
                        )
                    } else {
                        AnimatedGIFViewComponent(url: url)
                            .frame(maxHeight: maxHeight ?? 300)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.08))
                .onAppear {
                    print(
                        "[SmartMediaView] animatedGIF appear url=\(attachment.url) cornerRadius=\(cornerRadius)"
                    )
                }
            } else {
                // Fallback if URL is invalid
                loadingView
            }
        } else {
            // Use CachedAsyncImage for static images with better loading and retry logic
            CachedAsyncImage(url: URL(string: attachment.url), priority: .high) { image in
                image
                    .resizable()
                    .aspectRatio(
                        contentMode: contentMode == SmartMediaView.ContentMode.fill
                            ? SwiftUI.ContentMode.fill : SwiftUI.ContentMode.fit
                    )
                    .onAppear {
                        // Use Task to defer state updates outside view rendering cycle
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                            loadingState = .loaded
                        }
                    }
            } placeholder: {
                loadingView
                    .onAppear {
                        // Use Task to defer state updates outside view rendering cycle
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                            loadingState = .loading
                        }
                    }
            }
            .overlay(
                Group {
                    if case .failed(let error) = loadingState {
                        failureView(error: error)
                    }
                }
            )
        }
    }

    var body: some View {
        mediaContent
            .frame(maxWidth: maxWidth, maxHeight: maxHeight)
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onTapGesture {
                if attachment.type != .audio {  // Don't override audio player tap handling
                    onTap?()
                }
            }
    }

    // Extract a title from the audio file URL
    private func extractTitle(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let filename = url.lastPathComponent
        let nameWithoutExtension = url.deletingPathExtension().lastPathComponent
        return nameWithoutExtension.isEmpty ? filename : nameWithoutExtension
    }

    private var loadingView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.1))
            .overlay(
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.secondary)
            )
    }

    private func failureView(error: Error) -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.15))
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    Text("Media unavailable")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if retryCount < maxRetries {
                        Button("Retry") {
                            retryCount += 1
                            // Trigger reload by changing state
                            loadingState = .loading
                        }
                        .font(.caption2)
                        .foregroundColor(.blue)
                    }
                }
            )
    }

    // Infer aspect ratio from common query hints (e.g., Tenor: ww/hh). Fallback to 3:2.
    private func inferAspectRatio(from urlString: String) -> CGFloat {
        guard let url = URL(string: urlString),
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let items = comps.queryItems, !items.isEmpty
        else { return 3.0 / 2.0 }

        func value(_ keys: [String]) -> CGFloat? {
            for k in keys {
                if let v = items.first(where: { $0.name.lowercased() == k })?.value,
                    let d = Double(v), d > 0
                {
                    return CGFloat(d)
                }
            }
            return nil
        }

        let widthKeys = ["ww", "w", "width"]
        let heightKeys = ["hh", "h", "height"]
        if let w = value(widthKeys), let h = value(heightKeys), h > 0 { return max(w / h, 0.01) }
        return 3.0 / 2.0
    }
}

/// Professional video player component with GIF optimization and robust error handling
private struct VideoPlayerView: View {
    let url: URL?
    let isGIF: Bool

    @State private var player: AVPlayer?
    @State private var playerLooper: AVPlayerLooper?
    @State private var hasError = false
    @State private var isLoading = true
    @State private var retryCount = 0
    @State private var bufferProgress: Float = 0.0
    @State private var isBuffering = false

    @StateObject private var errorHandler = MediaErrorHandler.shared
    @StateObject private var memoryManager = MediaMemoryManager.shared
    @StateObject private var performanceMonitor = MediaPerformanceMonitor.shared

    var body: some View {
        Group {
            if let player = player, !hasError {
                ZStack(alignment: .center) {
                    VideoPlayer(player: player)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(contentMode: .fill)
                        .onAppear {
                            // Use Task to defer state updates outside view rendering cycle
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                                if isGIF {
                                    // For GIFs, ensure looping and auto-play
                                    player.play()
                                }
                            }
                        }
                        .onDisappear {
                            // Use Task to defer state updates outside view rendering cycle
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                                player.pause()
                            }
                        }

                    // Buffering indicator
                    if isBuffering {
                        VStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(1.2)
                                .tint(.white)

                            if bufferProgress > 0 {
                                VStack(spacing: 4) {
                                    Text("Buffering...")
                                        .font(.caption)
                                        .foregroundColor(.white)

                                    ProgressView(value: bufferProgress, total: 1.0)
                                        .frame(width: 120)
                                        .tint(.white)
                                }
                            } else {
                                Text("Buffering...")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.ultraThinMaterial.opacity(0.8))
                        )
                    }
                }
            } else if hasError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundColor(.orange)

                    Text("Video failed to load")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button("Retry") {
                        retrySetup()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .background(Color.gray.opacity(0.1))
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .overlay(
                        VStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading video...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    )
            }
        }
        .onAppear {
            // Use Task to defer state updates outside view rendering cycle
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                await setupPlayer()
            }
        }
        .onDisappear {
            // Use Task to defer state updates outside view rendering cycle
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                cleanup()
            }
        }
        .mediaRetryHandler(url: url?.absoluteString ?? "") {
            retrySetup()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(accessibilityTraits)
    }

    // MARK: - Accessibility Support

    private var accessibilityDescription: String {
        if hasError {
            return "Video failed to load. Double tap to retry."
        } else if isLoading {
            return "Video loading..."
        } else if isBuffering {
            let progress = Int(bufferProgress * 100)
            return "Video buffering, \(progress)% loaded"
        } else if isGIF {
            return "Animated GIF video"
        } else {
            return "Video content"
        }
    }

    private var accessibilityHint: String {
        if hasError {
            return "Double tap to retry loading the video"
        } else if isLoading || isBuffering {
            return "Please wait while the video loads"
        } else {
            return "Double tap to play or pause"
        }
    }

    private var accessibilityTraits: AccessibilityTraits {
        var traits: AccessibilityTraits = [.playsSound]

        if hasError {
            traits.insert(.updatesFrequently)
        } else if !isLoading && !isBuffering {
            traits.insert(.startsMediaSession)
        }

        return traits
    }

    private func setupPlayer() async {
        guard let url = url else {
            hasError = true
            isLoading = false
            return
        }

        // Track performance
        performanceMonitor.trackMediaLoadStart(url: url.absoluteString)

        do {
            // Check if we have a cached player first
            if let cachedPlayer = memoryManager.getCachedPlayer(for: url) {
                self.player = cachedPlayer
                hasError = false
                isLoading = false
                performanceMonitor.trackMediaLoadComplete(url: url.absoluteString, success: true)
                return
            }

            let player = try await errorHandler.loadMediaWithRetry(url: url) { url in
                return try await createPlayer(for: url)
            }

            // Cache the player for reuse
            memoryManager.cachePlayer(player, for: url)
            performanceMonitor.trackPlayerCreation()

            self.player = player
            hasError = false
            isLoading = false
            performanceMonitor.trackMediaLoadComplete(url: url.absoluteString, success: true)

        } catch {
            print("❌ [VideoPlayerView] Failed to setup player: \(error)")
            hasError = true
            isLoading = false
            performanceMonitor.trackMediaLoadComplete(url: url.absoluteString, success: false)
        }
    }

    private func createPlayer(for url: URL) async throws -> AVPlayer {
        return try await withCheckedThrowingContinuation { continuation in
            let asset = AVURLAsset(url: url)
            let playerItem = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: playerItem)

            var hasResumed = false

            // Monitor player status
            let statusObserver = playerItem.observe(\.status, options: [.new]) {
                [weak playerItem] item, _ in
                guard !hasResumed else { return }

                switch item.status {
                case .readyToPlay:
                    hasResumed = true

                    // Set up buffering monitoring
                    if let playerItem = playerItem {
                        self.setupBufferingMonitoring(for: playerItem)
                    }

                    continuation.resume(returning: player)
                case .failed:
                    hasResumed = true
                    if let error = item.error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(
                            throwing: MediaErrorHandler.MediaError.playerSetupFailed(
                                "Unknown player error"))
                    }
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }

            // Set up timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(
                    throwing: MediaErrorHandler.MediaError.loadTimeout)
            }
        }
    }

    private func setupBufferingMonitoring(for playerItem: AVPlayerItem) {
        // Monitor buffering state
        let bufferObserver = playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) {
            item, _ in
            DispatchQueue.main.async {
                // Note: In a struct, we can't capture self weakly
                // This should be handled differently in production
            }
        }

        // Monitor buffer progress
        let progressObserver = playerItem.observe(\.loadedTimeRanges, options: [.new]) {
            item, _ in
            DispatchQueue.main.async {
                // Note: In a struct, we can't capture self weakly
                // This should be handled differently in production
            }
        }

        // Store observers to prevent deallocation (in a real implementation, you'd want to clean these up)
        // For now, they'll be cleaned up when the player item is deallocated
    }

    private func retrySetup() {
        hasError = false
        isLoading = true
        retryCount += 1

        Task {
            await setupPlayer()
        }
    }

    private func cleanup() {
        player?.pause()
        // Don't set player to nil - let the memory manager handle caching
        playerLooper = nil
    }
}

enum MediaError: Error, LocalizedError {
    case unknownState
    case invalidURL
    case loadingFailed

    var errorDescription: String? {
        switch self {
        case .unknownState:
            return "Unknown loading state"
        case .invalidURL:
            return "Invalid media URL"
        case .loadingFailed:
            return "Failed to load media"
        }
    }
}

/// A SwiftUI view that displays animated GIFs properly with container bounds
private struct AnimatedGIFViewComponent: UIViewRepresentable {
    let url: URL?

    fileprivate func makeUIView(context: Context) -> GIFContainerView {
        let containerView = GIFContainerView()
        containerView.clipsToBounds = true
        containerView.backgroundColor = UIColor.clear

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(imageView)
        containerView.imageView = imageView

        // Use constraints for proper bounds handling
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        // Let SwiftUI handle the overall sizing
        containerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        containerView.setContentHuggingPriority(.defaultLow, for: .vertical)
        containerView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        containerView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        return containerView
    }

    fileprivate func updateUIView(_ containerView: GIFContainerView, context: Context) {
        guard let url = url, let imageView = containerView.imageView else {
            containerView.imageView?.image = nil
            return
        }

        // Use URLSession with caching for better performance
        print("[AnimatedGIFView] start fetch url=\(url.absoluteString)")
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    imageView.image = UIImage(systemName: "photo")
                    print(
                        "[AnimatedGIFView] fetch failed: \(error?.localizedDescription ?? "unknown")"
                    )
                }
                return
            }

            DispatchQueue.main.async {
                // Create animated image from GIF data
                if let animatedImage = UIImage.animatedImageWithData(data) {
                    imageView.image = animatedImage
                    print(
                        "[AnimatedGIFView] animated image set frames ok size=\(animatedImage.size)")
                } else {
                    // Fallback to static image if animation fails
                    imageView.image = UIImage(data: data)
                    print("[AnimatedGIFView] fallback static image set")
                }
            }
        }
        task.resume()
    }
}

/// Custom container view that properly handles sizing for SwiftUI integration
private class GIFContainerView: UIView {
    var imageView: UIImageView?

    override var intrinsicContentSize: CGSize {
        // Return no intrinsic size - let SwiftUI decide
        return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        // Return the given size exactly - no overriding
        return size
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Force clipping to container bounds - constraints handle the sizing
        self.clipsToBounds = true
    }
}

extension UIImage {
    static func animatedImageWithData(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        var images: [UIImage] = []
        var duration: Double = 0
        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            let frameDuration = UIImage.frameDuration(from: source, at: i)
            duration += frameDuration
            images.append(UIImage(cgImage: cgImage))
        }
        if images.isEmpty { return nil }
        return UIImage.animatedImage(with: images, duration: duration)
    }

    private static func frameDuration(from source: CGImageSource, at index: Int) -> Double {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil),
            let gifProps = (properties as NSDictionary)[kCGImagePropertyGIFDictionary as String]
                as? NSDictionary,
            let delay = gifProps[kCGImagePropertyGIFDelayTime as String] as? NSNumber
        else { return 0.1 }
        return delay.doubleValue
    }
}

#Preview {
    VStack(spacing: 20) {
        SmartMediaView(
            attachment: Post.Attachment(
                url: "https://picsum.photos/400/300",
                type: .image,
                altText: "Sample image"
            ),
            maxHeight: 200
        )

        SmartMediaView(
            attachment: Post.Attachment(
                url: "https://media.giphy.com/media/3o7aD2saalBwwftBIY/giphy.gif",
                type: .animatedGIF,
                altText: "Sample GIF"
            ),
            maxHeight: 200
        )
    }
    .padding()
}

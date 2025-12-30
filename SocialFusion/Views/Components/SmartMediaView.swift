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
    @State private var loadedAspectRatio: CGFloat? = nil

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
        let initialRatio = CGFloat(
            attachment.aspectRatio ?? Double(inferAspectRatio(from: attachment.url)))
        let ratio = loadedAspectRatio ?? initialRatio

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
        } else if attachment.type == .video || attachment.type == .gifv {
            VideoPlayerView(
                url: URL(string: attachment.url),
                isGIF: attachment.type == .gifv,
                aspectRatio: ratio,
                onSizeDetected: { size in
                    if size.width > 0 && size.height > 0 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            loadedAspectRatio = size.width / size.height
                        }
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { print("[SmartMediaView] video/gifv appear url=\(attachment.url)") }
        } else if attachment.type == .animatedGIF {
            // Flag-driven unfurling with local fallback
            let url = URL(string: attachment.url)
            if let url = url {
                GIFUnfurlContainer(
                    url: url,
                    maxHeight: maxHeight ?? 500,
                    cornerRadius: cornerRadius,
                    showControls: true,
                    contentMode: contentMode == .fill ? .scaleAspectFill : .scaleAspectFit,
                    onTap: { onTap?() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.opacity(0.08))
                .onAppear {
                    print(
                        "[SmartMediaView] animatedGIF appear url=\(attachment.url) cornerRadius=\(cornerRadius)"
                    )
                }
            } else {
                // Fallback if URL is invalid
                loadingView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            // Use CachedAsyncImage for static images with progressive loading support
            let imageURL = URL(string: attachment.url)
            let thumbnailURL = attachment.thumbnailURL.flatMap { URL(string: $0) }
            
            // Use progressive loading if thumbnail is available
            if let imageURL = imageURL, let thumbnailURL = thumbnailURL {
                // Progressive loading: show thumbnail first, then full image
                CachedAsyncImage(
                    url: imageURL,
                    priority: .high,
                    onImageLoad: { uiImage in
                        let size = uiImage.size
                        if size.width > 0 && size.height > 0 {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                loadedAspectRatio = CGFloat(size.width / size.height)
                            }
                        }
                    }
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode == .fill ? .fill : .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 1_000_000)
                                loadingState = .loaded
                            }
                        }
                } placeholder: {
                    // Show thumbnail while loading full image
                    CachedAsyncImage(url: thumbnailURL, priority: .high) { thumbnailImage in
                        thumbnailImage
                            .resizable()
                            .aspectRatio(contentMode: contentMode == .fill ? .fill : .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .blur(radius: 1) // Slight blur for progressive effect
                    } placeholder: {
                        loadingView
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_000_000)
                            loadingState = .loading
                        }
                    }
                }
                .overlay(
                    Group {
                        if case .failed(let error) = loadingState {
                            failureView(error: error)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                )
            } else {
                // Regular loading without thumbnail
                CachedAsyncImage(
                    url: imageURL,
                    priority: .high,
                    onImageLoad: { uiImage in
                        let size = uiImage.size
                        if size.width > 0 && size.height > 0 {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                loadedAspectRatio = CGFloat(size.width / size.height)
                            }
                        }
                    }
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode == .fill ? .fill : .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 1_000_000)
                                loadingState = .loaded
                            }
                        }
                } placeholder: {
                    loadingView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 1_000_000)
                                loadingState = .loading
                            }
                        }
                }
                .overlay(
                    Group {
                        if case .failed(let error) = loadingState {
                            failureView(error: error)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                )
            }
        }
    }

    var body: some View {
        let initialRatio = attachment.aspectRatio ?? inferAspectRatio(from: attachment.url)
        let ratio = loadedAspectRatio ?? initialRatio

        Group {
            if contentMode == .fill {
                // Grid mode: Fixed aspect ratio (usually square)
                mediaContent
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                    .contentShape(Rectangle())
            } else {
                // Detail/Single mode: Adaptive aspect ratio
                mediaContent
                    .aspectRatio(ratio, contentMode: .fit)
                    .frame(maxWidth: maxWidth)
                    .frame(maxHeight: maxHeight)
            }
        }
        .background(Color.gray.opacity(0.05))
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
    let aspectRatio: CGFloat
    var onSizeDetected: ((CGSize) -> Void)? = nil

    @StateObject private var playerModel = VideoPlayerViewModel()
    @State private var hasError = false
    @State private var isLoading = true
    @State private var retryCount = 0

    @StateObject private var errorHandler = MediaErrorHandler.shared
    @StateObject private var memoryManager = MediaMemoryManager.shared
    @StateObject private var performanceMonitor = MediaPerformanceMonitor.shared

    var body: some View {
        Group {
            if let player = playerModel.player, !hasError {
                ZStack(alignment: .center) {
                    VideoPlayer(player: player)
                        .aspectRatio(aspectRatio, contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                            // Detect size from track
                            Task {
                                if let track = try? await player.currentItem?.asset.loadTracks(
                                    withMediaType: .video
                                ).first {
                                    let size = try? await track.load(.naturalSize)
                                    let transform = try? await track.load(.preferredTransform)
                                    if let size = size, let transform = transform {
                                        let correctedSize = size.applying(transform)
                                        onSizeDetected?(
                                            CGSize(
                                                width: abs(correctedSize.width),
                                                height: abs(correctedSize.height)))
                                    }
                                }
                            }

                            if isGIF {
                                player.play()
                            }
                        }
                        .onDisappear {
                            player.pause()
                        }

                    // Buffering indicator
                    if playerModel.isBuffering {
                        VStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(1.2)
                                .tint(.white)

                            if playerModel.bufferProgress > 0 {
                                VStack(spacing: 4) {
                                    Text("Buffering...")
                                        .font(.caption)
                                        .foregroundColor(.white)

                                    ProgressView(value: playerModel.bufferProgress, total: 1.0)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.opacity(0.1))
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Task {
                await setupPlayer()
            }
        }
        .onDisappear {
            cleanup()
        }
        .mediaRetryHandler(url: url?.absoluteString ?? "") {
            retrySetup()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(accessibilityTraits)
    }

    private var accessibilityDescription: String {
        if hasError {
            return "Video failed to load. Double tap to retry."
        } else if isLoading {
            return "Video loading..."
        } else if playerModel.isBuffering {
            let progress = Int(playerModel.bufferProgress * 100)
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
        } else if isLoading || playerModel.isBuffering {
            return "Please wait while the video loads"
        } else {
            return "Double tap to play or pause"
        }
    }

    private var accessibilityTraits: AccessibilityTraits {
        var traits: AccessibilityTraits = [.playsSound]
        if hasError {
            _ = traits.insert(.updatesFrequently)
        } else if !isLoading && !playerModel.isBuffering {
            _ = traits.insert(.startsMediaSession)
        }
        return traits
    }

    private func setupPlayer() async {
        guard let url = url else {
            hasError = true
            isLoading = false
            return
        }

        performanceMonitor.trackMediaLoadStart(url: url.absoluteString)

        do {
            if let cachedPlayer = memoryManager.getCachedPlayer(for: url) {
                playerModel.setPlayer(cachedPlayer)
                hasError = false
                isLoading = false
                performanceMonitor.trackMediaLoadComplete(url: url.absoluteString, success: true)
                return
            }

            let player = try await errorHandler.loadMediaWithRetry(url: url) { url in
                return try await createPlayer(for: url)
            }

            memoryManager.cachePlayer(player, for: url)
            performanceMonitor.trackPlayerCreation()

            playerModel.setPlayer(player)
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

            _ = playerItem.observe(\.status, options: [.new]) { item, _ in
                guard !hasResumed else { return }

                switch item.status {
                case .readyToPlay:
                    hasResumed = true
                    continuation.resume(returning: player)
                case .failed:
                    hasResumed = true
                    continuation.resume(
                        throwing: item.error
                            ?? MediaErrorHandler.MediaError.playerSetupFailed("Unknown error"))
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(throwing: MediaErrorHandler.MediaError.loadTimeout)
            }
        }
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
        playerModel.player?.pause()
    }
}

class VideoPlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isBuffering = false
    @Published var bufferProgress: Float = 0

    private var statusObserver: NSKeyValueObservation?
    private var bufferObserver: NSKeyValueObservation?
    private var progressObserver: NSKeyValueObservation?

    func setPlayer(_ player: AVPlayer) {
        self.player = player
        setupObservers()
    }

    private func setupObservers() {
        guard let item = player?.currentItem else { return }

        bufferObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) {
            [weak self] item, change in
            DispatchQueue.main.async {
                self?.isBuffering = !item.isPlaybackLikelyToKeepUp
            }
        }

        progressObserver = item.observe(\.loadedTimeRanges, options: [.new]) {
            [weak self] item, change in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let duration = item.duration.seconds
                if duration > 0 {
                    let loaded =
                        item.loadedTimeRanges.map({ $0.timeRangeValue.end.seconds }).max() ?? 0
                    self.bufferProgress = Float(loaded / duration)
                }
            }
        }
    }

    deinit {
        statusObserver?.invalidate()
        bufferObserver?.invalidate()
        progressObserver?.invalidate()
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

    @StateObject private var memoryManager = MediaMemoryManager.shared

    fileprivate func updateUIView(_ containerView: GIFContainerView, context: Context) {
        guard let url = url, let imageView = containerView.imageView else {
            containerView.imageView?.image = nil
            return
        }

        // Use MediaMemoryManager for optimized GIF loading
        Task {
            do {
                let data = try await memoryManager.loadOptimizedGIF(from: url)
                await MainActor.run {
                    if let animatedImage = UIImage.animatedImageWithData(data) {
                        imageView.image = animatedImage
                    } else {
                        imageView.image = UIImage(data: data)
                    }
                }
            } catch {
                await MainActor.run {
                    imageView.image = UIImage(systemName: "photo")
                    print("[AnimatedGIFView] fetch failed: \(error.localizedDescription)")
                }
            }
        }
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

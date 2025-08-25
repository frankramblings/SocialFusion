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
            // TODO: Implement audio player once AudioPlayerView is properly integrated
            VStack {
                Image(systemName: "waveform")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("Audio playback coming soon")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
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

/// Professional video player component with GIF optimization
private struct VideoPlayerView: View {
    let url: URL?
    let isGIF: Bool

    @State private var player: AVPlayer?
    @State private var playerLooper: AVPlayerLooper?

    var body: some View {
        Group {
            if let player = player {
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
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .overlay(
                        ProgressView()
                            .scaleEffect(1.2)
                    )
            }
        }
        .onAppear {
            // Use Task to defer state updates outside view rendering cycle
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                setupPlayer()
            }
        }
        .onDisappear {
            // Use Task to defer state updates outside view rendering cycle
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                cleanup()
            }
        }
    }

    private func setupPlayer() {
        guard let url = url else { return }

        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)

        if isGIF {
            // Set up looping for GIFs
            let queuePlayer = AVQueuePlayer()
            playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
            player = queuePlayer

            // Mute GIFs by default (they're usually silent anyway)
            newPlayer.isMuted = true
        } else {
            player = newPlayer
        }
    }

    private func cleanup() {
        player?.pause()
        player = nil
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

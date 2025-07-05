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

    var body: some View {
        Group {
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
            } else if attachment.type.needsVideoPlayer {
                // Use AVPlayer for video-like content (including .gifv)
                VideoPlayerView(
                    url: URL(string: attachment.url),
                    isGIF: attachment.type.isAnimated
                )
            } else if attachment.type == .animatedGIF {
                // Use specialized GIF handler for true GIFs
                AnimatedGIFView(url: URL(string: attachment.url))
            } else {
                // Use CachedAsyncImage for static images with better loading and retry logic
                CachedAsyncImage(url: URL(string: attachment.url), priority: .high) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode == .fill ? .fill : .fit)
                        .onAppear {
                            loadingState = .loaded
                        }
                } placeholder: {
                    loadingView
                        .onAppear {
                            loadingState = .loading
                        }
                } onFailure: { error in
                    loadingState = .failed(error)
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
        .frame(maxWidth: maxWidth, maxHeight: maxHeight)
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
                    .onAppear {
                        if isGIF {
                            // For GIFs, ensure looping and auto-play
                            player.play()
                        }
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .overlay(
                        ProgressView()
                            .scaleEffect(1.2)
                    )
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanup()
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

/// Enhanced animated GIF view with better performance
struct AnimatedGIFView: UIViewRepresentable {
    let url: URL?

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.systemGray6
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        guard let url = url else {
            uiView.image = nil
            return
        }

        // Use URLSession with caching for better performance
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    uiView.image = UIImage(systemName: "photo")
                }
                return
            }

            DispatchQueue.main.async {
                if let animatedImage = UIImage.animatedGIF(data: data) {
                    uiView.image = animatedImage
                } else {
                    // Fallback to static image
                    uiView.image = UIImage(data: data)
                }
            }
        }
        task.resume()
    }
}

extension UIImage {
    static func animatedGIF(data: Data) -> UIImage? {
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
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [CFString: Any],
            let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else {
            return 0.1  // Default frame duration
        }
        if let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber {
            return unclamped.doubleValue > 0.011 ? unclamped.doubleValue : 0.1
        }
        if let clamped = gifProperties[kCGImagePropertyGIFDelayTime] as? NSNumber {
            return clamped.doubleValue > 0.011 ? clamped.doubleValue : 0.1
        }
        return 0.1
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

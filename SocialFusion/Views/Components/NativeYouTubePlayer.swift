import AVFoundation
import AVKit
import SwiftUI
import WebKit

/// Native YouTube Player using AVPlayer for better performance and native controls
struct NativeYouTubePlayer: View {
    let videoID: String
    let url: URL
    @Binding var isPlaying: Bool

    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var hasError = false
    @State private var errorMessage = ""
    @State private var streamURL: URL?

    var body: some View {
        ZStack {
            if let player = player, !hasError {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                        isPlaying = true
                    }
                    .onDisappear {
                        player.pause()
                        isPlaying = false
                    }
            } else if hasError {
                // Fallback to WebView if native fails
                YouTubeWebViewFallback(videoID: videoID, isPlaying: $isPlaying)
            } else if isLoading {
                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.8))

                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)

                        Text("Loading native player...")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .onAppear {
            loadNativeVideo()
        }
        .onDisappear {
            player?.pause()
            isPlaying = false
        }
    }

    private func loadNativeVideo() {
        Task {
            do {
                let extractedURL = try await extractYouTubeVideoURL(videoID: videoID)

                await MainActor.run {
                    self.streamURL = extractedURL
                    self.player = AVPlayer(url: extractedURL)
                    self.isLoading = false

                    // Configure player for better experience
                    if let player = self.player {
                        player.automaticallyWaitsToMinimizeStalling = false

                        // Add observer for when player is ready
                        NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: player.currentItem,
                            queue: .main
                        ) { _ in
                            self.isPlaying = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.hasError = true
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

/// Fallback WebView component for when native extraction fails
struct YouTubeWebViewFallback: UIViewRepresentable {
    let videoID: String
    @Binding var isPlaying: Bool

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url == nil else { return }

        let embedHTML = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
                <style>
                    body { 
                        margin: 0; 
                        padding: 0; 
                        background: #000; 
                        overflow: hidden;
                    }
                    .video-container { 
                        position: relative; 
                        width: 100%; 
                        height: 100vh; 
                        display: flex;
                        align-items: center;
                        justify-content: center;
                    }
                    iframe { 
                        width: 100%; 
                        height: 100%; 
                        border: none; 
                        border-radius: 12px;
                    }
                </style>
            </head>
            <body>
                <div class="video-container">
                    <iframe 
                        src="https://www.youtube.com/embed/\(videoID)?autoplay=1&playsinline=1&rel=0&modestbranding=1&controls=1&showinfo=0&fs=1"
                        frameborder="0" 
                        allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                        allowfullscreen>
                    </iframe>
                </div>
            </body>
            </html>
            """

        webView.loadHTMLString(embedHTML, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: YouTubeWebViewFallback

        init(_ parent: YouTubeWebViewFallback) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isPlaying = true
        }
    }
}

/// YouTube URL extraction function using our custom extractor
func extractYouTubeVideoURL(videoID: String) async throws -> URL {
    return try await YouTubeExtractor.shared.extractVideoURL(videoID: videoID)
}

#Preview {
    NativeYouTubePlayer(
        videoID: "dQw4w9WgXcQ",
        url: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!,
        isPlaying: .constant(false)
    )
    .frame(height: 200)
    .cornerRadius(12)
}

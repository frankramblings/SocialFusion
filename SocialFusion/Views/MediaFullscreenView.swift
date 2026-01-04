import AVKit
import Combine
import ImageIO
import SwiftUI

/// View for displaying media attachments in fullscreen mode (Legacy - use FullscreenMediaView in Components instead)
struct LegacyFullscreenMediaView: View {
    // For single attachment view
    var attachment: Post.Attachment? = nil
    // For gallery view with multiple attachments
    var attachments: [Post.Attachment] = []
    var initialIndex: Int = 0

    @State private var currentIndex: Int = 0
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showControls = true
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var videoPlayers: [URL: AVPlayer] = [:]
    @State private var currentPlayer: AVPlayer? = nil
    @State private var isVideoBuffering = false
    @State private var observers: [Any] = []
    @State private var activeTask: URLSessionDataTask? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    // Replace the task queues with a single serial queue
    private let serialQueue = DispatchQueue(label: "com.socialfusion.media", qos: .userInitiated)

    // Note: updateState method removed as it's not compatible with SwiftUI's immutable view pattern
    // Use @State variables instead for mutable state
    // private func updateState<T>(_ keyPath: WritableKeyPath<FullscreenMediaView, T>, value: T) {
    //     DispatchQueue.main.async {
    //         self[keyPath: keyPath] = value
    //     }
    // }

    // Computed property to work with either single attachment or collection
    private var currentAttachments: [Post.Attachment] {
        if let attachment = attachment {
            return [attachment]
        } else {
            return attachments
        }
    }

    private var currentAttachment: Post.Attachment? {
        guard currentAttachments.indices.contains(currentIndex) else {
            return nil
        }
        return currentAttachments[currentIndex]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background color
                Color.black.edgesIgnoringSafeArea(.all)

                if currentAttachments.isEmpty {
                    // No media available
                    VStack(spacing: 16) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("No media available")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                } else if let currentAttachment = currentAttachment {
                    // Use a custom TabView implementation to avoid state reset
                    HStack(spacing: 0) {
                        ForEach(currentAttachments.indices, id: \.self) { index in
                            mediaView(for: currentAttachments[index], in: geometry)
                                .frame(width: geometry.size.width)
                                .offset(x: -CGFloat(currentIndex) * geometry.size.width)
                        }
                    }
                    .frame(
                        width: geometry.size.width, height: geometry.size.height,
                        alignment: .leading
                    )
                    .offset(x: CGFloat(currentIndex) * geometry.size.width)
                    .animation(.easeInOut, value: currentIndex)
                    .gesture(
                        DragGesture()
                            .onEnded { gesture in
                                let threshold = geometry.size.width * 0.3
                                if gesture.translation.width > threshold {
                                    withAnimation {
                                        currentIndex = max(0, currentIndex - 1)
                                    }
                                } else if gesture.translation.width < -threshold {
                                    withAnimation {
                                        currentIndex = min(
                                            currentAttachments.count - 1, currentIndex + 1)
                                    }
                                }
                            }
                    )
                    .onAppear {
                        currentIndex = initialIndex
                        setupMedia()
                    }
                    .onChange(of: currentIndex) { _ in
                        withAnimation {
                            scale = 1.0
                            offset = .zero
                        }
                        lastOffset = .zero
                        setupMedia()
                    }
                    .onChange(of: scenePhase) { newPhase in
                        switch newPhase {
                        case .active:
                            resumeVideoPlayback()
                        case .inactive, .background:
                            pauseAllPlayersExcept(nil)
                        @unknown default:
                            break
                        }
                    }
                }

                // Loading indicator
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(2)
                            .foregroundColor(.white)
                        Text("Loading...")
                            .foregroundColor(.white)
                            .font(.subheadline)
                    }
                    .padding(20)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
                }

                // Error overlay
                if let errorMessage = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.yellow)
                        Text(errorMessage)
                            .font(.headline)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button(action: retryLoading) {
                            Text("Try Again")
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .cornerRadius(8)
                        }
                    }
                    .padding(20)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(12)
                }

                // Video buffering indicator
                if isVideoBuffering,
                    let currentAttachment = currentAttachment,
                    currentAttachment.type == .video || currentAttachment.type == .gifv
                {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(2)
                            .foregroundColor(.white)
                        Text("Buffering video...")
                            .foregroundColor(.white)
                            .font(.subheadline)
                    }
                    .padding(20)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
                }

                // Controls overlay
                if showControls {
                    VStack {
                        HStack {
                            Button(action: { dismiss() }) {
                                Image(systemName: "xmark")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                            .padding(.leading)
                            .accessibilityLabel("Close")

                            Spacer()

                            if let currentAttachment = currentAttachment,
                                currentAttachment.type == .image,
                                !currentAttachment.url.isEmpty,
                                let imageURL = URL(string: currentAttachment.url)
                            {
                                Button(action: {
                                    shareImage(url: imageURL)
                                }) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding(12)
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
                                }
                                .padding(.trailing)
                                .accessibilityLabel("Share")
                            }
                        }
                        .padding(.top, 44)

                        Spacer()

                        if let currentAttachment = currentAttachment,
                            let altText = currentAttachment.altText,
                            !altText.isEmpty
                        {
                            Text(altText)
                                .font(.caption)
                                .padding()
                                .background(Color.black.opacity(0.6))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .padding()
                        }

                        if currentAttachments.count > 1 {
                            HStack(spacing: 8) {
                                ForEach(0..<currentAttachments.count, id: \.self) { index in
                                    Circle()
                                        .fill(
                                            currentIndex == index
                                                ? Color.white : Color.white.opacity(0.5)
                                        )
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .padding(.bottom)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .contentShape(Rectangle())  // Make entire view tappable
            .onTapGesture {
                withAnimation {
                    showControls.toggle()
                }
            }
        }
        .background(Color.black)
        .edgesIgnoringSafeArea(.all)
        .statusBar(hidden: true)
        .gesture(
            DragGesture()
                .onEnded { gesture in
                    if gesture.translation.height > 100
                        || gesture.predictedEndTranslation.height > 200
                    {
                        withAnimation {
                            dismiss()
                        }
                    }
                }
        )
        .onTapGesture(count: 2) {
            withAnimation {
                scale = 1.0
                offset = .zero
            }
        }
        .onDisappear {
            cleanup()
        }
    }

    @ViewBuilder
    private func mediaView(for attachment: Post.Attachment, in geometry: GeometryProxy) -> some View
    {
        switch attachment.type {
        case .image:
            if !attachment.url.isEmpty, let url = URL(string: attachment.url) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        // Show loading state immediately
                        ZStack {
                            Color.black
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(2)
                                    .foregroundColor(.white)
                                Text("Loading...")
                                    .foregroundColor(.white)
                                    .font(.subheadline)
                            }
                        }
                        .onAppear {
                            DispatchQueue.main.async {
                                self.isLoading = true
                                self.errorMessage = nil
                            }
                        }
                    case .success(let image):
                        // Success state with proper scaling and gesture handling
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                // Combine magnification and drag gestures
                                SimultaneousGesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            let delta = value / lastScale
                                            lastScale = value
                                            scale = min(max(scale * delta, 1.0), 4.0)
                                        }
                                        .onEnded { _ in
                                            lastScale = 1.0
                                            if scale < 1.2 {
                                                withAnimation {
                                                    scale = 1.0
                                                    offset = .zero
                                                }
                                            }
                                        },
                                    DragGesture()
                                        .onChanged { value in
                                            if scale > 1.0 {
                                                offset = CGSize(
                                                    width: lastOffset.width
                                                        + value.translation.width,
                                                    height: lastOffset.height
                                                        + value.translation.height
                                                )
                                            }
                                        }
                                        .onEnded { value in
                                            lastOffset = offset
                                            if scale < 1.2 {
                                                withAnimation {
                                                    offset = .zero
                                                }
                                            }
                                        }
                                )
                            )
                            .highPriorityGesture(
                                // High priority gesture for dismissing
                                DragGesture()
                                    .onEnded { value in
                                        if scale <= 1.0 {
                                            if value.translation.height > 100
                                                || value.predictedEndTranslation.height > 200
                                            {
                                                withAnimation {
                                                    dismiss()
                                                }
                                            }
                                        }
                                    }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation {
                                    if scale > 1.0 {
                                        scale = 1.0
                                        offset = .zero
                                    } else {
                                        scale = 2.0
                                    }
                                }
                            }
                            .onTapGesture {
                                withAnimation {
                                    showControls.toggle()
                                }
                            }
                            .onAppear {
                                DispatchQueue.main.async {
                                    self.isLoading = false
                                    self.errorMessage = nil
                                }
                            }
                    case .failure(let error):
                        // Error state with retry option
                        ZStack {
                            Color.black
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundColor(.yellow)
                                Text("Failed to load image")
                                    .foregroundColor(.white)
                                if let error = error as NSError? {
                                    Text(error.localizedDescription)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                                Button(action: {
                                    // Clear URL cache for this URL
                                    URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
                                    // Retry loading by triggering a view update
                                    DispatchQueue.main.async {
                                        self.currentIndex = self.currentIndex
                                    }
                                }) {
                                    Text("Retry")
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .background(Color.blue)
                                        .cornerRadius(8)
                                }
                            }
                        }
                        .onAppear {
                            DispatchQueue.main.async {
                                self.isLoading = false
                                self.errorMessage = error.localizedDescription
                            }
                        }
                    @unknown default:
                        // Handle unknown states
                        ZStack {
                            Color.black
                            Text("Unknown state")
                                .foregroundColor(.white)
                        }
                        .onAppear {
                            DispatchQueue.main.async {
                                self.isLoading = false
                                self.errorMessage = "Unknown loading state"
                            }
                        }
                    }
                }
                .transition(.opacity)
            } else {
                // Invalid URL state
                ZStack {
                    Color.black
                    Text("Invalid image URL")
                        .foregroundColor(.white)
                }
                .onAppear {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.errorMessage = "Invalid image URL"
                    }
                }
            }
        case .video:
            if !attachment.url.isEmpty, let url = URL(string: attachment.url) {
                // Use our managed player
                let player = videoPlayers[url] ?? createPlayer(for: url)
                VideoPlayer(player: player)
                    .edgesIgnoringSafeArea(.all)
                    .onAppear {
                        currentPlayer = player
                        player.play()
                    }
            } else {
                Text("Invalid video URL")
                    .foregroundColor(.white)
            }
        case .gifv:
            if !attachment.url.isEmpty, let url = URL(string: attachment.url) {
                // Use our managed player
                let player = videoPlayers[url] ?? createPlayer(for: url)
                VideoPlayer(player: player)
                    .edgesIgnoringSafeArea(.all)
                    .onAppear {
                        // CRITICAL: Configure looping for GIF videos
                        configureGIFLooping(for: player)
                        currentPlayer = player
                        // Ensure playback rate is 1.0 before playing
                        player.rate = 1.0
                        player.play()
                    }
            } else {
                Text("Invalid GIF URL")
                    .foregroundColor(.white)
            }
        case .animatedGIF:
            if !attachment.url.isEmpty, let url = URL(string: attachment.url) {
                FullscreenAnimatedGIFView(url: url)
                    .edgesIgnoringSafeArea(.all)
            } else {
                Text("Invalid GIF URL")
                    .foregroundColor(.white)
            }
        case .audio:
            if !attachment.url.isEmpty, let url = URL(string: attachment.url) {
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)

                    AudioPlayerView(
                        url: url,
                        title: attachment.altText?.isEmpty == false ? attachment.altText : "Audio",
                        artist: nil
                    )
                    .padding(20)
                }
            } else {
                Text("Invalid audio URL")
                    .foregroundColor(.white)
            }
        default:
            Text("Unsupported media type")
                .foregroundColor(.white)
        }
    }

    private func setupMedia() {
        guard let currentAttachment = currentAttachment,
            !currentAttachment.url.isEmpty,
            let url = URL(string: currentAttachment.url)
        else {
            return
        }

        // Cancel any existing task
        activeTask?.cancel()
        activeTask = nil

        if currentAttachment.type == .video || currentAttachment.type == .gifv {
            setupVideoPlayer(for: url)
        } else if currentAttachment.type == .image || currentAttachment.type == .animatedGIF {
            setupImageLoading(for: url)
        }
    }

    private func setupVideoPlayer(for url: URL) {
        if videoPlayers[url] == nil {
            isVideoBuffering = true
            let player = createPlayer(for: url)
            // CRITICAL: Configure looping for GIF videos (gifv)
            if currentAttachment?.type == .gifv {
                configureGIFLooping(for: player)
            }
            videoPlayers[url] = player
            currentPlayer = player
        } else {
            currentPlayer = videoPlayers[url]
            // CRITICAL: Configure looping for GIF videos (gifv) even if cached
            if currentAttachment?.type == .gifv {
                configureGIFLooping(for: currentPlayer!)
            }
            currentPlayer?.seek(to: .zero)
            currentPlayer?.play()
        }
    }

    private func setupImageLoading(for url: URL) {
        // Ensure we're on the main thread for state updates
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }

        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30

        let session = URLSession(configuration: config)
        let task = session.dataTask(with: url) { data, response, error in

            self.serialQueue.async {
                if let error = error {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.errorMessage = error.localizedDescription
                    }
                    return
                }

                guard let data = data, UIImage(data: data) != nil else {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.errorMessage = "Invalid image data"
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }

        activeTask = task
        task.resume()
    }

    private func resumeVideoPlayback() {
        guard let currentAttachment = currentAttachment,
            !currentAttachment.url.isEmpty,
            let url = URL(string: currentAttachment.url),
            let player = videoPlayers[url]
        else {
            return
        }

        if player.currentItem?.status == .readyToPlay {
            isVideoBuffering = false
            player.play()
        } else {
            isVideoBuffering = true
            let newPlayer = createPlayer(for: url)
            videoPlayers[url] = newPlayer
            currentPlayer = newPlayer
        }
    }

    private func retryLoading() {
        guard let currentAttachment = currentAttachment,
            !currentAttachment.url.isEmpty,
            let url = URL(string: currentAttachment.url)
        else {
            return
        }

        // Clear all caches for this URL
        URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
        if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
            cookies.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        }

        // Reset state
        isLoading = true
        errorMessage = nil

        if currentAttachment.type == .video || currentAttachment.type == .gifv {
            setupVideoPlayer(for: url)
        } else {
            setupImageLoading(for: url)
        }
    }

    private func shareImage(url: URL) {
        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        UIApplication.shared.windows.first?.rootViewController?
            .present(activityVC, animated: true)
    }

    private func cleanup() {
        // Ensure cleanup happens on the main thread
        DispatchQueue.main.async {
            // Cancel active task
            self.activeTask?.cancel()
            self.activeTask = nil

            // Clean up video players
            self.pauseAllPlayersExcept(nil)
            self.cleanupObservers()
            self.videoPlayers.removeAll()

            // Reset state
            self.isLoading = false
            self.errorMessage = nil
            self.isVideoBuffering = false
        }

        // Clean up network tasks and caches on background thread
        serialQueue.async {
            // Clean up network tasks
            URLSession.shared.getAllTasks { tasks in
                tasks.forEach { task in
                    if let url = task.originalRequest?.url,
                        self.currentAttachments.contains(where: { $0.url == url.absoluteString })
                    {
                        task.cancel()
                    }
                }
            }

            // Clear caches
            self.currentAttachments.forEach { attachment in
                if !attachment.url.isEmpty,
                    let url = URL(string: attachment.url)
                {
                    URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
                    if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
                        cookies.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
                    }
                }
            }
        }
    }

    /// Configure AVPlayer to loop infinitely for GIF videos (gifv)
    private func configureGIFLooping(for player: AVPlayer) {
        guard let playerItem = player.currentItem else { return }

        // CRITICAL: Set playback rate to 1.0 to prevent fast playback
        // Some videos might have incorrect rate metadata
        player.rate = 1.0

        // Set actionAtItemEnd to .none to prevent pausing at end
        player.actionAtItemEnd = .none

        // Add observer to loop when video ends
        let loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak player] _ in
            // Seek back to beginning and play again for infinite loop
            player?.seek(to: .zero)
            player?.rate = 1.0  // Ensure rate stays at 1.0
            player?.play()
        }

        // Store observer for cleanup
        observers.append(loopObserver)
    }

    // Create and configure a player with proper buffering setup
    private func createPlayer(for url: URL) -> AVPlayer {
        let player = AVPlayer(url: url)

        // Configure player for improved buffering
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        // Set a reasonable buffer size for better playback
        playerItem.preferredForwardBufferDuration = 10.0

        // Monitor buffering state
        let accessLogObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: playerItem,
            queue: .main
        ) { _ in
            if let accessLog = playerItem.accessLog(),
                let lastEvent = accessLog.events.last
            {
                // When enough is buffered, remove loading indicator
                if lastEvent.indicatedBitrate > 0 && playerItem.isPlaybackLikelyToKeepUp {
                    self.isVideoBuffering = false
                }
            }
        }
        observers.append(accessLogObserver)

        // Monitor playback readiness
        let stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: playerItem,
            queue: .main
        ) { _ in
            self.isVideoBuffering = true
        }
        observers.append(stalledObserver)

        // Monitor player status
        let statusObserver = player.observe(\.status, options: [.new]) { player, _ in
            DispatchQueue.main.async {
                if player.status == .readyToPlay {
                    self.isVideoBuffering = false
                    player.play()
                } else if player.status == .failed {
                    self.isVideoBuffering = false
                    self.isLoading = false
                    self.errorMessage = "Video failed to load"
                }
            }
        }
        observers.append(statusObserver)

        // Replace with configured player item
        player.replaceCurrentItem(with: playerItem)

        return player
    }

    // Pause all video players except for the specified one
    private func pauseAllPlayersExcept(_ exceptPlayer: AVPlayer?) {
        for (_, player) in videoPlayers {
            if player != exceptPlayer {
                player.pause()
            }
        }
    }

    // Clean up all observers
    private func cleanupObservers() {
        for observer in observers {
            if let observer = observer as? NSObjectProtocol {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        observers.removeAll()
    }
}

// Convenience extension to safely access array elements
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// Legacy MediaFullscreenView for backward compatibility
struct MediaFullscreenView: View {
    let attachment: Post.Attachment
    var attachments: [Post.Attachment] = []
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        // Redirect to the new FullscreenMediaView for better functionality
        LegacyFullscreenMediaView(
            attachment: attachment, attachments: attachments.isEmpty ? [] : attachments)
    }
}

/// Fullscreen view for animated GIFs
struct FullscreenAnimatedGIFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .black
        // CRITICAL: Set infinite loop for animated GIFs (0 = infinite)
        imageView.animationRepeatCount = 0
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        // Load the GIF data
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)

                await MainActor.run {
                    // Create animated image from GIF data
                    if let animatedImage = createAnimatedImage(from: data) {
                        uiView.image = animatedImage
                        // Ensure looping is enabled for animated GIFs
                        uiView.animationRepeatCount = 0
                    } else {
                        // Fallback to static image if animation fails
                        uiView.image = UIImage(data: data)
                    }
                }
            } catch {
                print("❌ [FullscreenAnimatedGIFView] Failed to load GIF from \(url): \(error)")
                await MainActor.run {
                    uiView.image = nil
                }
            }
        }
    }

    private func createAnimatedImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        var frames: [UIImage] = []
        var duration: Double = 0

        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            let frameDuration = getFrameDuration(from: source, at: i)
            duration += frameDuration
            frames.append(UIImage(cgImage: cgImage))
        }

        guard !frames.isEmpty else { return nil }
        return UIImage.animatedImage(with: frames, duration: duration)
    }

    private func getFrameDuration(from source: CGImageSource, at index: Int) -> Double {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as NSDictionary?,
            let gifProps = properties[kCGImagePropertyGIFDictionary as String] as? NSDictionary,
            let delay = gifProps[kCGImagePropertyGIFDelayTime as String] as? NSNumber
        else { return 0.1 }
        return delay.doubleValue
    }
}

#Preview {
    MediaFullscreenView(
        attachment: Post.Attachment(
            url: "https://picsum.photos/800/600",
            type: .image,
            altText: "Sample image description"
        )
    )
}

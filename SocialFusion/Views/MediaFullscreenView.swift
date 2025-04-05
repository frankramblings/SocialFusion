import AVKit
import Combine
import SwiftUI

/// View for displaying media attachments in fullscreen mode
struct FullscreenMediaView: View {
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
    @State private var isLoading = true
    @State private var loadError = false
    @State private var errorMessage = "Failed to load media"
    // State for video players
    @State private var videoPlayers: [URL: AVPlayer] = [:]
    @State private var currentPlayer: AVPlayer? = nil
    @State private var isVideoBuffering = true
    @State private var observers: [Any] = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.scenePhase) private var scenePhase

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
                    TabView(selection: $currentIndex) {
                        ForEach(currentAttachments.indices, id: \.self) { index in
                            ZStack {
                                mediaView(for: currentAttachments[index], in: geometry)
                                    .gesture(
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
                                            }
                                    )
                                    .simultaneousGesture(
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
                                            .onEnded { _ in
                                                lastOffset = offset
                                                if scale < 1.2 {
                                                    withAnimation {
                                                        offset = .zero
                                                    }
                                                }
                                            }
                                    )
                                    .simultaneousGesture(
                                        TapGesture(count: 2)
                                            .onEnded { _ in
                                                withAnimation {
                                                    if scale > 1.0 {
                                                        scale = 1.0
                                                        offset = .zero
                                                    } else {
                                                        scale = 2.0
                                                    }
                                                }
                                                lastOffset = offset
                                            }
                                    )
                                    .simultaneousGesture(
                                        TapGesture()
                                            .onEnded { _ in
                                                withAnimation {
                                                    showControls.toggle()
                                                }
                                            }
                                    )
                            }
                            .tag(index)
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .onAppear {
                        currentIndex = initialIndex
                        // Preload media for smoother experience
                        preloadMedia()

                        // Set a timeout for loading
                        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                            if isLoading {
                                // Still loading after 8 seconds, trigger error state
                                isLoading = false
                                loadError = true
                                errorMessage = "Media loading timed out"
                            }
                        }
                    }
                    .onChange(of: currentIndex) { _ in
                        withAnimation {
                            scale = 1.0
                            offset = .zero
                        }
                        lastOffset = .zero
                        // Reset loading state for new index
                        isLoading = true
                        loadError = false
                        // Preload media for the new index
                        preloadMedia()

                        // Pause any existing video players
                        pauseAllPlayersExcept(nil)

                        // Set a timeout for loading the new media
                        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                            if isLoading {
                                // Still loading after 8 seconds, trigger error state
                                isLoading = false
                                loadError = true
                                errorMessage = "Media loading timed out"
                            }
                        }
                    }
                    .onChange(of: scenePhase) { newPhase in
                        switch newPhase {
                        case .active:
                            // App came back to foreground - restart video if needed
                            if let currentAttachment = currentAttachment,
                                currentAttachment.type == .video || currentAttachment.type == .gifv,
                                let urlString = currentAttachment.url,
                                let url = URL(string: urlString),
                                let player = videoPlayers[url]
                            {
                                // Ensure video buffer is ready before playing
                                if player.currentItem?.status == .readyToPlay {
                                    isVideoBuffering = false
                                    player.play()
                                } else {
                                    // Recreate player if it wasn't ready
                                    isVideoBuffering = true
                                    let newPlayer = createPlayer(for: url)
                                    videoPlayers[url] = newPlayer
                                    currentPlayer = newPlayer
                                }
                            }
                        case .inactive, .background:
                            // App went to background - pause video
                            pauseAllPlayersExcept(nil)
                        @unknown default:
                            break
                        }
                    }
                } else {
                    Text("No media to display")
                        .foregroundColor(.white)
                }

                // Loading error overlay
                if loadError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.yellow)

                        Text(errorMessage)
                            .font(.headline)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button(action: {
                            // Try again
                            isLoading = true
                            loadError = false
                            preloadMedia()

                            // Set a timeout for retry loading
                            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                                if isLoading {
                                    isLoading = false
                                    loadError = true
                                    errorMessage = "Media loading failed again"
                                }
                            }
                        }) {
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
                            Button(action: {
                                // Close the fullscreen view
                                dismiss()
                            }) {
                                Image(systemName: "xmark")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                            .padding(.leading)
                            .accessibilityLabel("Close")
                            .accessibilityHint("Dismisses the fullscreen media view")

                            Spacer()

                            if let currentAttachment = currentAttachment,
                                currentAttachment.type == .image,
                                let imageURLString = currentAttachment.url,
                                let imageURL = URL(string: imageURLString)
                            {
                                Button(action: {
                                    saveImageToPhotos(from: imageURL)
                                }) {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding(12)
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
                                }
                                .padding(.trailing)
                                .accessibilityLabel("Save Image")
                                .accessibilityHint("Saves the image to your photo library")
                            }
                        }
                        .padding(.top)

                        Spacer()

                        // Alt text display if available
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

                        // Page indicator dots
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
        }
        .background(Color.black)
        .edgesIgnoringSafeArea(.all)
        .statusBar(hidden: true)
        .gesture(
            // Add swipe down to dismiss gesture
            DragGesture()
                .onEnded { gesture in
                    // If the user swipes down with enough velocity, dismiss the view
                    if gesture.translation.height > 100
                        || gesture.predictedEndTranslation.height > 200
                    {
                        dismiss()
                    }
                }
        )
        .onTapGesture(count: 2) {
            // Double tap to reset scale
            withAnimation {
                scale = 1.0
                offset = .zero
            }
        }
        .onDisappear {
            // Cleanup when view disappears
            pauseAllPlayersExcept(nil)
            cleanupObservers()
            videoPlayers.removeAll()

            URLSession.shared.getAllTasks { tasks in
                tasks.forEach { task in
                    if task.originalRequest?.url?.absoluteString.contains(
                        currentAttachment?.url ?? "") ?? false
                    {
                        task.cancel()
                    }
                }
            }
        }
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
                    self.loadError = true
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

    // Helper function to preload media for smoother gallery experience
    private func preloadMedia() {
        // Ensure current media is loaded
        if let currentAttachment = currentAttachment,
            let urlString = currentAttachment.url,
            let url = URL(string: urlString)
        {

            if currentAttachment.type == .video || currentAttachment.type == .gifv {
                // Configure video player if not already created
                if videoPlayers[url] == nil {
                    isVideoBuffering = true
                    let player = createPlayer(for: url)
                    videoPlayers[url] = player
                    currentPlayer = player
                } else {
                    // Reuse existing player
                    currentPlayer = videoPlayers[url]
                    currentPlayer?.seek(to: .zero)
                    currentPlayer?.play()
                }
            }
        }

        // Preload adjacent media
        for index in max(0, currentIndex - 1)...min(currentAttachments.count - 1, currentIndex + 1)
        {
            if index != currentIndex,
                let attachment = currentAttachments[safe: index],
                let urlString = attachment.url,
                let url = URL(string: urlString)
            {

                if attachment.type == .image {
                    // Preload images
                    URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
                    let task = URLSession.shared.dataTask(with: url)
                    task.resume()
                } else if (attachment.type == .video || attachment.type == .gifv)
                    && videoPlayers[url] == nil
                {
                    // Prepare video player without playing
                    let player = createPlayer(for: url)
                    videoPlayers[url] = player
                    player.pause()
                }
            }
        }
    }

    // Save image to photo library
    private func saveImageToPhotos(from url: URL) {
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else {
                print("Error downloading image: \(error?.localizedDescription ?? "Unknown error")")
                return
            }

            if let image = UIImage(data: data) {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
        }
        task.resume()
    }

    @ViewBuilder
    private func mediaView(for attachment: Post.Attachment, in geometry: GeometryProxy) -> some View
    {
        switch attachment.type {
        case .image:
            if let urlString = attachment.url, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .foregroundColor(.white)
                            .scaleEffect(2)
                            .onAppear {
                                isLoading = true
                                loadError = false
                            }
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(scale)
                            .offset(offset)
                            .onAppear {
                                isLoading = false
                                loadError = false
                            }
                    case .failure(let error):
                        VStack {
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
                        }
                        .onAppear {
                            isLoading = false
                            loadError = true
                            errorMessage = "Failed to load image: \(error.localizedDescription)"
                        }
                    @unknown default:
                        EmptyView()
                            .onAppear {
                                isLoading = false
                                loadError = true
                            }
                    }
                }
                .transition(.opacity)
            } else {
                Text("Invalid image URL")
                    .foregroundColor(.white)
                    .onAppear {
                        isLoading = false
                        loadError = true
                        errorMessage = "Invalid image URL"
                    }
            }
        case .video:
            if let urlString = attachment.url, let url = URL(string: urlString) {
                // Use our managed player
                let player = videoPlayers[url] ?? createPlayer(for: url)

                ZStack {
                    VideoPlayer(player: player)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .onAppear {
                            videoPlayers[url] = player
                            currentPlayer = player

                            // Set up notification for looping videos
                            NotificationCenter.default.addObserver(
                                forName: .AVPlayerItemDidPlayToEndTime,
                                object: player.currentItem,
                                queue: .main
                            ) { _ in
                                player.seek(to: .zero)
                                player.play()
                            }
                        }
                        .onDisappear {
                            player.pause()
                            NotificationCenter.default.removeObserver(
                                self,
                                name: .AVPlayerItemDidPlayToEndTime,
                                object: player.currentItem)
                        }
                }
            } else {
                Text("Invalid video URL")
                    .foregroundColor(.white)
                    .onAppear {
                        isLoading = false
                        loadError = true
                        errorMessage = "Invalid video URL"
                    }
            }
        case .gifv:
            if let urlString = attachment.url, let url = URL(string: urlString) {
                // Use our managed player for GIFs too
                let player = videoPlayers[url] ?? createPlayer(for: url)

                ZStack {
                    VideoPlayer(player: player)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .onAppear {
                            videoPlayers[url] = player
                            currentPlayer = player

                            // Auto-play and loop GIFs
                            player.play()
                            player.actionAtItemEnd = .none

                            NotificationCenter.default.addObserver(
                                forName: .AVPlayerItemDidPlayToEndTime,
                                object: player.currentItem,
                                queue: .main
                            ) { _ in
                                player.seek(to: .zero)
                                player.play()
                            }
                        }
                        .onDisappear {
                            player.pause()
                            NotificationCenter.default.removeObserver(
                                self,
                                name: .AVPlayerItemDidPlayToEndTime,
                                object: player.currentItem)
                        }
                }
            } else {
                Text("Invalid GIF URL")
                    .foregroundColor(.white)
                    .onAppear {
                        isLoading = false
                        loadError = true
                        errorMessage = "Invalid GIF URL"
                    }
            }
        default:
            Text("Unsupported media type")
                .foregroundColor(.white)
                .onAppear {
                    isLoading = false
                    loadError = true
                    errorMessage = "Unsupported media type"
                }
        }
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
        FullscreenMediaView(
            attachment: attachment, attachments: attachments.isEmpty ? [] : attachments)
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

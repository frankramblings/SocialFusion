import AVKit
import SwiftUI
import Photos
import UniformTypeIdentifiers
import UIKit

/// A view that displays media in fullscreen with zoom and swipe capabilities
struct FullscreenMediaView: View {
    let media: Post.Attachment
    let allMedia: [Post.Attachment]
    let showAltTextInitially: Bool
    let onDismiss: () -> Void

    @State private var currentScale: CGFloat = 1.0
    @State private var previousScale: CGFloat = 1.0
    @State private var currentOffset: CGSize = .zero
    @State private var previousOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var currentIndex: Int
    @State private var overlaysVisible: Bool = true
    @State private var showAltText: Bool = false
    @State private var isSharing: Bool = false
    @State private var videoPlayers: [URL: AVPlayer] = [:]
    @State private var currentPlayer: AVPlayer? = nil

    init(
        media: Post.Attachment, allMedia: [Post.Attachment], showAltTextInitially: Bool = false,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.media = media
        self.allMedia = allMedia
        self.showAltTextInitially = showAltTextInitially
        self.onDismiss = onDismiss

        // Find the index of the current media in the array
        if let index = allMedia.firstIndex(where: { $0.id == media.id }) {
            _currentIndex = State(initialValue: index)
        } else {
            _currentIndex = State(initialValue: 0)
        }

        // Initialize showAltText based on parameter
        _showAltText = State(initialValue: showAltTextInitially)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dark vertical gradient background
                LinearGradient(
                    gradient: Gradient(colors: [Color.black, Color(white: 0.12)]),
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                TabView(selection: $currentIndex) {
                    ForEach(Array(allMedia.enumerated()), id: \.element.id) { index, attachment in
                        ZStack {
                            mediaView(for: attachment)
                                .scaleEffect(
                                    attachment.id == allMedia[currentIndex].id ? currentScale : 1.0
                                )
                                .offset(
                                    x: attachment.id == allMedia[currentIndex].id
                                        ? currentOffset.width + dragOffset.width
                                        : 0,
                                    y: attachment.id == allMedia[currentIndex].id
                                        ? currentOffset.height + dragOffset.height
                                        : 0
                                )
                                .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 8)
                                .accessibilityLabel(attachment.altText ?? "Image")
                                .gesture(
                                    SimultaneousGesture(
                                        MagnificationGesture()
                                            .onChanged { value in
                                                let delta = value / previousScale
                                                previousScale = value
                                                currentScale *= delta
                                                // Reset drag offset when zooming
                                                if currentScale > 1.0 {
                                                    dragOffset = .zero
                                                }
                                            }
                                            .onEnded { _ in
                                                previousScale = 1.0
                                                if currentScale < 1.0 {
                                                    withAnimation {
                                                        currentScale = 1.0
                                                        currentOffset = .zero
                                                        previousOffset = .zero
                                                        dragOffset = .zero
                                                    }
                                                }
                                            },
                                        // Higher minimumDistance (25) reduces interference with TabView's horizontal swipe gesture
                                        // TabView can recognize horizontal swipes before this gesture activates
                                        DragGesture(minimumDistance: 25)
                                            .onChanged { value in
                                                if currentScale > 1.0 {
                                                    // When zoomed: pan the image with immediate visual feedback
                                                    dragOffset = value.translation
                                                } else {
                                                    // When not zoomed: check if this is a horizontal swipe
                                                    let absWidth = abs(value.translation.width)
                                                    let absHeight = abs(value.translation.height)
                                                    let isPrimarilyHorizontal = absWidth > absHeight * 1.5
                                                    let hasMultipleImages = allMedia.count > 1
                                                    
                                                    // CRITICAL: For horizontal swipes with multiple images, don't update dragOffset
                                                    // This prevents the gesture from interfering with TabView's swipe
                                                    if !isPrimarilyHorizontal || !hasMultipleImages {
                                                        dragOffset = value.translation
                                                    }
                                                }
                                            }
                                            .onEnded { value in
                                                if currentScale > 1.0 {
                                                    // When zoomed: update pan offset
                                                    currentOffset = CGSize(
                                                        width: previousOffset.width
                                                            + value.translation.width,
                                                        height: previousOffset.height
                                                            + value.translation.height
                                                    )
                                                    previousOffset = currentOffset
                                                    dragOffset = .zero
                                                } else {
                                                    // When not zoomed: check for swipe-to-dismiss
                                                    let absWidth = abs(value.translation.width)
                                                    let absHeight = abs(value.translation.height)
                                                    let distance = sqrt(
                                                        pow(value.translation.width, 2)
                                                            + pow(value.translation.height, 2))
                                                    let velocity = sqrt(
                                                        pow(value.predictedEndTranslation.width, 2)
                                                            + pow(
                                                                value.predictedEndTranslation
                                                                    .height, 2))

                                                    // Adjust thresholds based on number of images
                                                    let hasMultipleImages = allMedia.count > 1
                                                    
                                                    // Check if swipe is primarily horizontal
                                                    let isPrimarilyHorizontal = absWidth > absHeight * 1.5
                                                    
                                                    // CRITICAL: When there are multiple images, completely ignore horizontal swipes
                                                    // Let TabView handle horizontal navigation - only dismiss on vertical/diagonal swipes
                                                    if hasMultipleImages && isPrimarilyHorizontal {
                                                        // Reset drag offset and let TabView handle the horizontal swipe
                                                        withAnimation(
                                                            .spring(
                                                                response: 0.3, dampingFraction: 0.8)
                                                        ) {
                                                            dragOffset = .zero
                                                        }
                                                        return // Don't process horizontal swipes when multiple images
                                                    }
                                                    
                                                    // For vertical/diagonal swipes (or single image), allow dismissal
                                                    let verticalThreshold: CGFloat = hasMultipleImages ? 200 : 100
                                                    let diagonalThreshold: CGFloat = hasMultipleImages ? 200 : 100
                                                    let velocityThreshold: CGFloat = hasMultipleImages ? 1500 : 500
                                                    
                                                    // Only allow dismissal for vertical/diagonal swipes when multiple images
                                                    // For single image, allow all directions
                                                    let shouldDismiss: Bool
                                                    if hasMultipleImages {
                                                        // Multiple images: only dismiss on vertical/diagonal swipes
                                                        shouldDismiss =
                                                            distance > diagonalThreshold
                                                            || absHeight > verticalThreshold
                                                            || velocity > velocityThreshold
                                                    } else {
                                                        // Single image: allow dismissal in any direction (original behavior)
                                                        let horizontalThreshold: CGFloat = 150
                                                        shouldDismiss =
                                                            distance > diagonalThreshold
                                                            || absHeight > verticalThreshold
                                                            || absWidth > horizontalThreshold
                                                            || velocity > velocityThreshold
                                                    }

                                                    if shouldDismiss {
                                                        // Swipe to dismiss
                                                        withAnimation(.easeOut(duration: 0.3)) {
                                                            onDismiss()
                                                        }
                                                    } else {
                                                        // Reset if swipe wasn't strong enough
                                                        withAnimation(
                                                            .spring(
                                                                response: 0.3, dampingFraction: 0.8)
                                                        ) {
                                                            dragOffset = .zero
                                                        }
                                                    }
                                                }
                                            }
                                    )
                                )
                                .onTapGesture(count: 2) {
                                    // Double tap to zoom in/out
                                    withAnimation {
                                        if currentScale > 1.0 {
                                            currentScale = 1.0
                                            currentOffset = .zero
                                            previousOffset = .zero
                                            dragOffset = .zero
                                        } else {
                                            currentScale = min(3.0, UIScreen.main.scale)
                                        }
                                    }
                                }
                                .onTapGesture(count: 1) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        overlaysVisible.toggle()
                                        if !overlaysVisible { showAltText = false }
                                    }
                                }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .onChange(of: currentIndex) { _ in
                    // Reset zoom and drag when switching images
                    withAnimation {
                        currentScale = 1.0
                        currentOffset = .zero
                        previousOffset = .zero
                        dragOffset = .zero
                    }
                }

                // Overlays (X, alt text, sharrow)
                if overlaysVisible {
                    VStack {
                        // Top overlay: Close button and ALT/info button
                        HStack {
                            Spacer()
                            Button(action: {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    onDismiss()
                                }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(10)
                            }
                            .buttonStyle(GlassyButtonStyle())
                            .accessibilityLabel("Close fullscreen viewer")
                            .padding(.trailing, 8)
                        }
                        .padding(.top, 12)
                        .padding(.trailing, 8)
                        Spacer()
                        // Bottom overlay: Alt text, info button (left), share button (right), and page dots
                        VStack(spacing: 16) {
                            // Alt text if toggled
                            if showAltText, let altText = allMedia[currentIndex].altText,
                                !altText.isEmpty
                            {
                                HStack {
                                    Text(altText)
                                        .font(.callout)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(Color.black.opacity(0.92))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 16)
                                                        .stroke(
                                                            Color.white.opacity(0.15), lineWidth: 1)
                                                )
                                        )
                                        .shadow(
                                            color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4
                                        )
                                        .accessibilityLabel("Image description: \(altText)")
                                    Spacer()
                                }
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            // Button row
                            HStack(alignment: .bottom) {
                                // Info button (lower left) - only show if alt text exists
                                if let altText = allMedia[currentIndex].altText, !altText.isEmpty {
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showAltText.toggle()
                                        }
                                        HapticEngine.tap.trigger()
                                    }) {
                                        Text("ALT")
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .foregroundColor(showAltText ? .black : .white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(
                                                showAltText
                                                    ? Color.yellow : Color.white.opacity(0.2),
                                                in: Capsule()
                                            )
                                            .padding(10)
                                    }
                                    .buttonStyle(GlassyButtonStyle())
                                    .accessibilityLabel("Show image description")
                                    .accessibilityHint("Toggles the alt text overlay")
                                }

                                Spacer()

                                // Share button (lower right)
                                Button(action: {
                                    shareMedia(at: currentIndex)
                                }) {
                                    Image(systemName: isSharing ? "checkmark" : "square.and.arrow.up")
                                        .font(.title2)
                                        .foregroundColor(isSharing ? .green : .white)
                                        .padding(12)
                                }
                                .buttonStyle(GlassyButtonStyle())
                                .disabled(isSharing)
                                .accessibilityLabel(isSharing ? "Sharing..." : "Share image")
                            }

                            // Page indicator dots (only if multiple images)
                            if allMedia.count > 1 {
                                HStack(spacing: 8) {
                                    ForEach(0..<allMedia.count, id: \.self) { idx in
                                        Circle()
                                            .fill(
                                                idx == currentIndex
                                                    ? Color.white : Color.white.opacity(0.3)
                                            )
                                            .frame(width: 7, height: 7)
                                    }
                                }
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 1)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .animation(.easeInOut(duration: 0.2), value: overlaysVisible)
                }

            }
        }
        .ignoresSafeArea()
        .statusBar(hidden: true)
        .onAppear {
            // Reset zoom and drag state when view appears to ensure fresh state
            currentScale = 1.0
            currentOffset = .zero
            previousOffset = .zero
            dragOffset = .zero
        }
        .onDisappear {
            cleanupPlaybackResources()
        }

    }

    private func mediaView(for attachment: Post.Attachment) -> some View {
        guard let url = URL(string: attachment.url), !attachment.url.isEmpty else {
            return AnyView(
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text("Invalid image URL")
                }
                .foregroundColor(.white)
            )
        }

        // CRITICAL FIX: Check cache synchronously before creating view
        // This prevents spinner from showing when image is already cached
        let imageCache = ImageCache.shared
        if let cachedImage = imageCache.getCachedImage(for: url) {
            // Image is cached - show it immediately without placeholder
            return AnyView(
                Image(uiImage: cachedImage)
                    .resizable()
                    .scaledToFit()
            )
        }

        // Handle animated GIFs separately to ensure they animate properly
        if attachment.type == .animatedGIF {
            return AnyView(
                GeometryReader { geometry in
                    GIFUnfurlContainer(
                        url: url,
                        maxHeight: geometry.size.height,
                        cornerRadius: 0,
                        showControls: false,
                        contentMode: .scaleAspectFit,
                        onTap: nil
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            )
        }
        
        // Handle videos and GIFV (video-based GIFs)
        if attachment.type == .video || attachment.type == .gifv {
            return AnyView(
                FullscreenVideoPlayerView(
                    url: url,
                    isGIF: attachment.type == .gifv,
                    videoPlayers: $videoPlayers,
                    currentPlayer: $currentPlayer
                )
            )
        }

        // Use CachedAsyncImage for loading uncached images
        // The cache will handle the image, and each view instance has its own state
        return AnyView(
            CachedAsyncImage(
                url: url,
                priority: .high
            ) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(2)
                    Text("Loading...")
                        .foregroundColor(.white)
                        .font(.subheadline)
                }
            }
            // Use a stable ID based on URL only (not attachment.id) to allow cache reuse
            .id("fullscreen-\(url.absoluteString)")
        )
    }

    private func shareMedia(at index: Int) {
        guard index < allMedia.count else { return }
        let attachment = allMedia[index]
        
        HapticEngine.tap.trigger()
        isSharing = true
        
        Task {
            do {
                var activityItems: [Any] = []
                var tempFileURL: URL?
                
                guard let url = URL(string: attachment.url) else {
                    await MainActor.run { isSharing = false }
                    return
                }
                
                // Handle different media types with proper activity item sources
                switch attachment.type {
                case .image:
                    // Static images - use ImageActivityItemSource for better Photos integration
                    let imageCache = ImageCache.shared
                    if let cachedImage = imageCache.getCachedImage(for: url) {
                        // Use ImageActivityItemSource to ensure "Save to Photos" is available
                        activityItems.append(ImageActivityItemSource(image: cachedImage))
                    } else {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        if let image = UIImage(data: data) {
                            // Use ImageActivityItemSource to ensure "Save to Photos" is available
                            activityItems.append(ImageActivityItemSource(image: image))
                        } else {
                            // Fallback to URL with item source
                            activityItems.append(MediaActivityItemSource(mediaURL: url, mediaType: .image))
                        }
                    }
                    
                case .animatedGIF:
                    // GIFs - download and save to temp file, then use file URL
                    // File URLs with .gif extension enable "Save to Photos" for GIFs
                    let (data, _) = try await URLSession.shared.data(from: url)
                    
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileName = "shared_gif_\(UUID().uuidString).gif"
                    tempFileURL = tempDir.appendingPathComponent(fileName)
                    
                    if let tempURL = tempFileURL {
                        try data.write(to: tempURL)
                        // Pass file URL directly - iOS will recognize .gif extension and enable "Save to Photos"
                        activityItems.append(tempURL)
                    } else {
                        // Fallback to URL with item source
                        activityItems.append(MediaActivityItemSource(mediaURL: url, mediaType: .animatedGIF))
                    }
                    
                case .video, .gifv:
                    // Videos and GIFV - download and save to temp file with proper content type
                    // File URLs with video extensions enable "Save to Photos" for videos
                    let (data, _) = try await URLSession.shared.data(from: url)
                    
                    // Determine file extension from URL or content type
                    let fileExtension = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileName = attachment.type == .gifv 
                        ? "shared_gifv_\(UUID().uuidString).\(fileExtension)"
                        : "shared_video_\(UUID().uuidString).\(fileExtension)"
                    tempFileURL = tempDir.appendingPathComponent(fileName)
                    
                    if let tempURL = tempFileURL {
                        try data.write(to: tempURL)
                        // Pass file URL directly - iOS will recognize video extensions and enable "Save to Photos"
                        // Also enables sharing to Messages, Mail, AirDrop, etc.
                        activityItems.append(tempURL)
                    } else {
                        // Fallback to URL with item source
                        activityItems.append(MediaActivityItemSource(mediaURL: url, mediaType: attachment.type))
                    }
                    
                case .audio:
                    // Audio - download and save to temp file
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let fileExtension = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileName = "shared_audio_\(UUID().uuidString).\(fileExtension)"
                    tempFileURL = tempDir.appendingPathComponent(fileName)
                    
                    if let tempURL = tempFileURL {
                        try data.write(to: tempURL)
                        activityItems.append(MediaActivityItemSource(mediaURL: tempURL, mediaType: .audio))
                    } else {
                        activityItems.append(MediaActivityItemSource(mediaURL: url, mediaType: .audio))
                    }
                }
                
                // Present share sheet with actual media
                await MainActor.run {
                    let av = UIActivityViewController(
                        activityItems: activityItems,
                        applicationActivities: nil
                    )
                    
                    // Don't exclude activity types - let iOS show all available options
                    // This enables Save to Photos, Messages, Mail, AirDrop, etc.
                    // Only exclude activity types that truly don't make sense for media
                    av.excludedActivityTypes = [
                        .assignToContact,  // Don't assign media to contacts
                        .addToReadingList   // Reading list doesn't make sense for media
                    ]
                    
                    // iOS will automatically show media-specific options:
                    // - "Save to Photos" for images, GIFs, and videos (when using UIImage or file URLs)
                    // - "Messages" for all media types
                    // - "Mail" for all media types
                    // - "AirDrop" for all media types
                    // - Other apps that support the media type (e.g., photo editing apps)
                    // ImageActivityItemSource ensures UIImage is properly recognized for Photos integration
                    // File URLs with proper extensions (.gif, .mp4, etc.) enable video/GIF saving to Photos
                    
                    // Clean up temp file after sharing completes
                    if let tempURL = tempFileURL {
                        av.completionWithItemsHandler = { activityType, completed, returnedItems, error in
                            // Clean up temp file after a delay to ensure sharing completed
                            Task {
                                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                                try? FileManager.default.removeItem(at: tempURL)
                            }
                        }
                    }
                    
                    // Find the topmost view controller to present from
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first(where: { $0.isKeyWindow }),
                       let rootVC = window.rootViewController
                    {
                        // Find the topmost presented view controller
                        var topVC = rootVC
                        while let presented = topVC.presentedViewController {
                            topVC = presented
                        }
                        
                        // For iPad support
                        if let popover = av.popoverPresentationController {
                            popover.sourceView = topVC.view
                            popover.sourceRect = CGRect(
                                x: topVC.view.bounds.midX, 
                                y: topVC.view.bounds.midY, 
                                width: 0, 
                                height: 0
                            )
                            popover.permittedArrowDirections = []
                        }
                        
                        topVC.present(av, animated: true) {
                            // Reset sharing state after a delay
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                await MainActor.run {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        isSharing = false
                                    }
                                }
                            }
                        }
                    } else {
                        // Fallback: reset sharing state if presentation fails
                        isSharing = false
                    }
                }
            } catch {
                // On error, fallback to sharing URL
                await MainActor.run {
                    if let url = URL(string: attachment.url) {
                        let av = UIActivityViewController(
                            activityItems: [url],
                            applicationActivities: nil
                        )
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let window = windowScene.windows.first,
                           let rootVC = window.rootViewController
                        {
                            if let popover = av.popoverPresentationController {
                                popover.sourceView = window
                                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                                popover.permittedArrowDirections = []
                            }
                            
                            rootVC.present(av, animated: true) {
                                Task {
                                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                                    await MainActor.run {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            isSharing = false
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        isSharing = false
                    }
                }
            }
        }
    }
    
    private func cleanupPlaybackResources() {
        for player in videoPlayers.values {
            player.pause()
        }
        videoPlayers.removeAll()
        currentPlayer = nil
    }
}

/// Helper view for video playback in fullscreen
private struct FullscreenVideoPlayerView: View {
    let url: URL
    let isGIF: Bool
    @Binding var videoPlayers: [URL: AVPlayer]
    @Binding var currentPlayer: AVPlayer?
    
    @State private var player: AVPlayer?
    @State private var gifLoopObserverToken: NSObjectProtocol?

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    var body: some View {
        Group {
            if isSimulator {
                simulatorPlaceholder
            } else if let player = player {
                VideoPlayer(player: player)
                    .edgesIgnoringSafeArea(.all)
                    .onAppear {
                        currentPlayer = player
                        player.isMuted = false  // Unmuted in fullscreen
                        if isGIF {
                            player.rate = 1.0
                            configureGIFLooping(for: player)
                        }
                        player.play()
                    }
                    .onDisappear {
                        if let token = gifLoopObserverToken {
                            NotificationCenter.default.removeObserver(token)
                            gifLoopObserverToken = nil
                        }
                        if currentPlayer == player {
                            player.pause()
                            currentPlayer = nil
                        }
                        videoPlayers.removeValue(forKey: url)
                    }
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(2)
                    Text("Loading video...")
                        .foregroundColor(.white)
                        .font(.subheadline)
                }
            }
        }
        .onAppear {
            guard !isSimulator else { return }
            if let existingPlayer = videoPlayers[url] {
                player = existingPlayer
            } else {
                let newPlayer = AVPlayer(url: url)
                videoPlayers[url] = newPlayer
                player = newPlayer
            }
        }
    }

    private var simulatorPlaceholder: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            VStack(spacing: 12) {
                Image(systemName: "video.slash")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.8))
                Text("Video unavailable in Simulator")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.subheadline)
            }
        }
    }
    
    /// Configure AVPlayer to loop infinitely for GIF videos (gifv)
    private func configureGIFLooping(for player: AVPlayer) {
        guard let playerItem = player.currentItem else { return }
        if let token = gifLoopObserverToken {
            NotificationCenter.default.removeObserver(token)
            gifLoopObserverToken = nil
        }
        
        // CRITICAL: Set playback rate to 1.0 to prevent fast playback
        player.rate = 1.0
        
        // Set actionAtItemEnd to .none to prevent pausing at end
        player.actionAtItemEnd = .none
        
        // Add observer to loop when video ends
        gifLoopObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak player] _ in
            guard let player = player else { return }
            // Seek to beginning and play again
            player.seek(to: .zero)
            player.rate = 1.0
            player.play()
        }
    }
}

// Enhanced GlassyButtonStyle with Liquid Glass materials
struct GlassyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .overlay(
                Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(
                .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct FullscreenMediaView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleMedia = [
            Post.Attachment(
                url: "https://picsum.photos/800/600",
                type: .image,
                altText: "A sample image with alt text"
            ),
            Post.Attachment(
                url: "https://picsum.photos/800/601",
                type: .image,
                altText: "Second sample image"
            ),
        ]

        FullscreenMediaView(
            media: sampleMedia[0], allMedia: sampleMedia, showAltTextInitially: false, onDismiss: {}
        )
    }
}

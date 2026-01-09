import AVFoundation
import AVKit
import ImageIO
import ObjectiveC
import SwiftUI
import UIKit
import os.log

/// PreferenceKey to track video visibility in scroll views
private struct VideoVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue: [String: Bool] = [:]
    
    static func reduce(value: inout [String: Bool], nextValue: () -> [String: Bool]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// A professional-grade media display component that handles all media types robustly
struct SmartMediaView: View {
    let attachment: Post.Attachment
    let contentMode: ContentMode
    let maxWidth: CGFloat?
    let maxHeight: CGFloat?
    let cornerRadius: CGFloat
    let onTap: (() -> Void)?
    
    // For fullscreen support - optional to maintain backward compatibility
    let allMedia: [Post.Attachment]?

    // Hero transition support
    let heroID: String?
    let mediaNamespace: Namespace.ID?

    @State private var loadingState: LoadingState = .loading
    @State private var retryCount: Int = 0
    @State private var loadedAspectRatio: CGFloat? = nil
    @State private var isVideoVisible = false  // Track visibility for video playback
    
    // Optional coordinator for fullscreen - only used if available
    @EnvironmentObject private var mediaCoordinator: FullscreenMediaCoordinator

    private let maxRetries = 3
    
    /// Determines if a video view is visible based on its frame
    /// Uses a threshold: video is considered visible if >= 30% is on screen
    private func isVideoViewVisible(geometry: GeometryProxy) -> Bool {
        let frame = geometry.frame(in: .global)
        let screenBounds = UIScreen.main.bounds
        
        // Check if view intersects with screen bounds
        let intersection = screenBounds.intersection(frame)
        
        // Consider visible if at least 30% of the view is on screen
        // Reduced from 50% to match industry standards (IceCubesApp, Bluesky use 20-30%)
        // This allows videos to start playing earlier, improving perceived performance
        let visibleArea = intersection.width * intersection.height
        let totalArea = frame.width * frame.height
        
        guard totalArea > 0 else { return false }
        
        let visibilityRatio = visibleArea / totalArea
        return visibilityRatio >= 0.3
    }

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
        heroID: String? = nil,
        mediaNamespace: Namespace.ID? = nil,
        allMedia: [Post.Attachment]? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.attachment = attachment
        self.contentMode = contentMode
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.cornerRadius = cornerRadius
        self.heroID = heroID
        self.mediaNamespace = mediaNamespace
        self.allMedia = allMedia
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
                    // Defer state update to prevent AttributeGraph cycles
                    // Use a longer delay to ensure we're completely outside the view update cycle
                    Task { @MainActor in
                        guard size.width > 0 && size.height > 0 else { return }
                        // Longer delay to ensure we're not in the middle of a view update
                        // This prevents AttributeGraph cycles and "Modifying state during view update" warnings
                        try? await Task.sleep(nanoseconds: 33_000_000)  // ~2 frames at 60fps
                        guard !Task.isCancelled else { return }
                        // Double-check we're on main actor and defer the actual state update
                        await MainActor.run {
                            // Use DispatchQueue to ensure we're outside the current update cycle
                            DispatchQueue.main.async {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    loadedAspectRatio = size.width / size.height
                                }
                            }
                        }
                    }
                },
                isVisible: isVideoVisible,
                shouldMute: true,  // Mute by default for feed videos
                onFullscreenTap: {
                    // Trigger fullscreen if coordinator is available
                    let mediaToShow = allMedia ?? [attachment]
                    mediaCoordinator.present(
                        media: attachment,
                        allMedia: mediaToShow,
                        showAltTextInitially: false,
                        mediaNamespace: mediaNamespace,
                        thumbnailFrames: [:]
                    )
                }
            )
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: VideoVisibilityPreferenceKey.self,
                            value: [attachment.url: isVideoViewVisible(geometry: geometry)]
                        )
                }
            )
            .onPreferenceChange(VideoVisibilityPreferenceKey.self) { visibilityMap in
                if let visible = visibilityMap[attachment.url] {
                    isVideoVisible = visible
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cornerRadius(cornerRadius)
            .clipped()
            .onAppear { print("[SmartMediaView] video/gifv appear url=\(attachment.url)") }
        } else if attachment.type == .animatedGIF {
            // Flag-driven unfurling with local fallback
            let url = URL(string: attachment.url)
            let initialRatio = attachment.aspectRatio.map { CGFloat($0) }
            // Use adaptive max height: allow taller GIFs to display fully
            // Only apply maxHeight if explicitly provided, otherwise let GIF display at natural height
            let adaptiveMaxHeight = maxHeight ?? UIScreen.main.bounds.height * 0.8
            if let url = url {
                GIFUnfurlContainer(
                    url: url,
                    maxHeight: adaptiveMaxHeight,
                    cornerRadius: cornerRadius,
                    showControls: true,
                    contentMode: contentMode == .fill ? .scaleAspectFill : .scaleAspectFit,
                    onTap: { onTap?() }
                )
                // Don't apply frame constraints here - GIFUnfurlContainer handles its own sizing
                // Only constrain maxWidth to prevent overflow
                .frame(maxWidth: maxWidth ?? .infinity)
                .onAppear {
                    print(
                        "[SmartMediaView] 🎬 animatedGIF appear url=\(attachment.url) cornerRadius=\(cornerRadius) type=\(attachment.type)"
                    )
                }
            } else {
                // Fallback if URL is invalid
                loadingView
                    .frame(maxWidth: maxWidth ?? .infinity, maxHeight: maxHeight ?? .infinity)
                    .onAppear {
                        print("[SmartMediaView] ❌ Invalid URL for animatedGIF: \(attachment.url)")
                    }
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
                        // Defer state update to prevent AttributeGraph cycles
                        Task { @MainActor in
                            // Small delay to ensure we're not in the middle of a view update
                            try? await Task.sleep(nanoseconds: 16_000_000)  // ~1 frame at 60fps
                            let size = uiImage.size
                            if size.width > 0 && size.height > 0 {
                                await MainActor.run {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        loadedAspectRatio = CGFloat(size.width / size.height)
                                    }
                                }
                            }
                        }
                    }
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode == .fill ? .fill : .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
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
                            .clipped()
                            .blur(radius: 1)  // Slight blur for progressive effect
                    } placeholder: {
                        loadingView
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
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
                        // Defer state update to prevent AttributeGraph cycles
                        Task { @MainActor in
                            // Small delay to ensure we're not in the middle of a view update
                            try? await Task.sleep(nanoseconds: 16_000_000)  // ~1 frame at 60fps
                            let size = uiImage.size
                            if size.width > 0 && size.height > 0 {
                                await MainActor.run {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        loadedAspectRatio = CGFloat(size.width / size.height)
                                    }
                                }
                            }
                        }
                    }
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode == .fill ? .fill : .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .onAppear {
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 1_000_000)
                                loadingState = .loaded
                            }
                        }
                } placeholder: {
                    loadingView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
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
                // Grid mode: Fill the container (aspect ratio constraint applied at container level)
                mediaContent
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                    .contentShape(Rectangle())
                    .clipped()
            } else {
                // Detail/Single mode: Container size matches image exactly
                // Background only visible during loading state
                // Note: animatedGIF uses GIFUnfurlContainer which handles its own sizing via GeometryReader
                if attachment.type == .animatedGIF {
                    // GIFUnfurlContainer manages its own aspect ratio and sizing via GeometryReader
                    // Don't apply additional frame constraints - let it size itself naturally
                    mediaContent
                        .background(
                            // Only show gray background during loading - completely removed when loaded
                            Group {
                                if case .loading = loadingState {
                                    Color.gray.opacity(0.05)
                                }
                                // No background when loaded - container wraps tightly around image
                            }
                        )
                } else {
                    // For other media types, apply aspect ratio constraint
                    mediaContent
                        .aspectRatio(ratio, contentMode: .fit)
                        .frame(maxWidth: maxWidth)
                        .frame(maxHeight: maxHeight)
                        .background(
                            // Only show gray background during loading - completely removed when loaded
                            Group {
                                if case .loading = loadingState {
                                    Color.gray.opacity(0.05)
                                }
                                // No background when loaded - container wraps tightly around image
                            }
                        )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .applyHeroTransition(heroID: heroID, namespace: mediaNamespace, isSource: true)
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
    
    // Visibility and mute control
    var isVisible: Bool = true  // Default to true for backward compatibility
    var shouldMute: Bool = true  // Mute by default for feed videos (best practice)
    
    // Fullscreen support
    var onFullscreenTap: (() -> Void)? = nil

    @StateObject private var playerModel = VideoPlayerViewModel()
    @State private var hasError = false
    @State private var isLoading = true
    @State private var retryCount = 0
    @State private var wasPlayingBeforeDisappear = false

    @StateObject private var errorHandler = MediaErrorHandler.shared
    @StateObject private var memoryManager = MediaMemoryManager.shared
    @StateObject private var performanceMonitor = MediaPerformanceMonitor.shared

    private let logger = Logger(subsystem: "com.socialfusion.app", category: "VideoPlayerView")

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
            } else if let player = playerModel.player, !hasError {
                ZStack(alignment: .center) {
                    VideoPlayer(player: player)
                        .aspectRatio(aspectRatio, contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onChange(of: player.isMuted) { newValue in
                            // Sync mute state when VideoPlayer controls change it
                            // This ensures the mute button works properly
                            playerModel.isMuted = newValue
                        }
                        .onAppear {
                            // Detect size from track - defer callback to avoid AttributeGraph cycles
                            detectVideoSize(from: player)
                            
                            // Set mute state based on shouldMute parameter
                            player.isMuted = shouldMute
                            playerModel.isMuted = shouldMute
                            
                            // Only play if visible and it's a GIF (GIFs should autoplay)
                            // Regular videos wait for visibility change
                            if isGIF && isVisible {
                                // Ensure playback rate is 1.0 for GIF videos
                                player.rate = 1.0
                                player.play()
                            } else if !isGIF && isVisible {
                                // For regular videos, start playing when visible
                                player.play()
                            }
                        }
                        .onDisappear {
                            // Store playback state before pausing
                            wasPlayingBeforeDisappear = player.rate > 0
                            player.pause()
                        }
                        .onChange(of: isVisible) { newValue in
                            // Smart playback control based on visibility
                            guard let player = playerModel.player else { return }
                            
                            if newValue {
                                // Video became visible - resume playback
                                if isGIF {
                                    player.rate = 1.0
                                    player.play()
                                } else {
                                    // For regular videos, play if it was playing before or if it's a new video
                                    if wasPlayingBeforeDisappear || player.rate == 0 {
                                        player.play()
                                    }
                                }
                            } else {
                                // Video became invisible - pause playback
                                wasPlayingBeforeDisappear = player.rate > 0
                                player.pause()
                            }
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
                    
                    // Control buttons overlay
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 8) {
                                // Fullscreen button (always visible when onFullscreenTap is provided)
                                if let onFullscreenTap = onFullscreenTap {
                                    Button(action: {
                                        onFullscreenTap()
                                    }) {
                                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                            .font(.title3)
                                            .foregroundColor(.white)
                                            .padding(8)
                                            .background(
                                                Circle()
                                                    .fill(.ultraThinMaterial.opacity(0.8))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                // Mute/unmute button (only show when muted and not a GIF)
                                if !isGIF && playerModel.isMuted && !isLoading && !hasError {
                                    Button(action: {
                                        playerModel.toggleMute()
                                    }) {
                                        Image(systemName: "speaker.slash.fill")
                                            .font(.title3)
                                            .foregroundColor(.white)
                                            .padding(8)
                                            .background(
                                                Circle()
                                                    .fill(.ultraThinMaterial.opacity(0.8))
                                            )
                                    }
                                }
                            }
                            .padding(12)
                        }
                        Spacer()
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
            guard !isSimulator else { return }
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
        if isSimulator {
            return "Video unavailable in Simulator"
        }
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
        if isSimulator {
            return "Video playback is disabled in Simulator"
        }
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
        if isSimulator {
            hasError = false
            isLoading = false
            return
        }
        guard let url = url else {
            hasError = true
            isLoading = false
            return
        }

        performanceMonitor.trackMediaLoadStart(url: url.absoluteString)

        // CRITICAL: Simulator-specific handling - add warning for video playback issues
        #if targetEnvironment(simulator)
        logger.info("⚠️ [SIMULATOR] Setting up video player - videos may not play correctly in simulator")
        #endif

        do {
            if let cachedPlayer = memoryManager.getCachedPlayer(for: url) {
                // CRITICAL: Ensure player allows muting and is properly configured
                cachedPlayer.allowsExternalPlayback = false  // Disable AirPlay to ensure mute works properly
                
                // Set mute state based on shouldMute parameter
                cachedPlayer.isMuted = shouldMute
                
                // CRITICAL: Configure audio session to allow mixing with other audio for muted videos
                if shouldMute {
                    configureAudioSessionForMutedPlayback()
                }

                // CRITICAL: Configure looping for GIFs (gifv videos from Mastodon)
                if isGIF {
                    configureGIFLooping(for: cachedPlayer)
                }
                playerModel.setPlayer(cachedPlayer)
                hasError = false
                isLoading = false
                performanceMonitor.trackMediaLoadComplete(url: url.absoluteString, success: true)
                return
            }

            let player = try await errorHandler.loadMediaWithRetry(url: url) { url in
                return try await createPlayer(for: url)
            }

            // CRITICAL: Ensure player allows muting and is properly configured
            // VideoPlayer's built-in mute button should work, but we ensure the player is ready
            player.allowsExternalPlayback = false  // Disable AirPlay to ensure mute works properly
            
            // Set mute state based on shouldMute parameter
            player.isMuted = shouldMute
            
            // CRITICAL: Configure audio session to allow mixing with other audio for muted videos
            if shouldMute {
                configureAudioSessionForMutedPlayback()
            }

            // CRITICAL: Configure looping for GIFs (gifv videos from Mastodon)
            if isGIF {
                configureGIFLooping(for: player)
            }

            memoryManager.cachePlayer(player, for: url)
            performanceMonitor.trackPlayerCreation()

            playerModel.setPlayer(player)
            hasError = false
            isLoading = false
            performanceMonitor.trackMediaLoadComplete(url: url.absoluteString, success: true)

        } catch {
            #if targetEnvironment(simulator)
            logger.error(
                "❌ [SIMULATOR] Failed to setup player: \(error.localizedDescription, privacy: .public)")
            logger.info("⚠️ [SIMULATOR] Video playback errors are common in simulator - test on a real device for accurate behavior")
            #else
            logger.error(
                "❌ Failed to setup player: \(error.localizedDescription, privacy: .public)")
            #endif
            hasError = true
            isLoading = false
            performanceMonitor.trackMediaLoadComplete(url: url.absoluteString, success: false)
        }
    }

    private var simulatorPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.15))
            VStack(spacing: 8) {
                Image(systemName: "video.slash")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("Video unavailable in Simulator")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
        }
        .aspectRatio(aspectRatio, contentMode: .fill)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func createPlayer(for url: URL) async throws -> AVPlayer {
        // #region agent log
        let logData: [String: Any] = [
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "location": "SmartMediaView.swift:583",
            "message": "createPlayer called",
            "data": [
                "url": url.absoluteString,
                "isFileURL": url.isFileURL,
                "thread": Thread.isMainThread ? "main" : "background",
            ],
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "A",
        ]
        if let logJSON = try? JSONSerialization.data(withJSONObject: logData),
            let logString = String(data: logJSON, encoding: .utf8)
        {
            if let fileHandle = FileHandle(
                forWritingAtPath:
                    "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log")
            {
                fileHandle.seekToEndOfFile()
                fileHandle.write(("\n" + logString).data(using: .utf8) ?? Data())
                fileHandle.closeFile()
            } else {
                try? logString.write(
                    toFile: "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log",
                    atomically: false, encoding: .utf8)
            }
        }
        // #endregion

        // Check if this URL needs authentication
        let (needsAuth, platform) = AuthenticatedVideoAssetLoader.needsAuthentication(url: url)

        // Check if this is an HLS playlist (.m3u8) - these should be played directly, not downloaded
        let isHLSPlaylist = url.absoluteString.contains(".m3u8") || url.pathExtension == "m3u8"

        if needsAuth, let platform = platform {
            if let account = await AuthenticatedVideoAssetLoader.getAccountForPlatform(platform) {
                // Get access token (try to get valid token)
                do {
                    let token = try await account.getValidAccessToken()
                    logger.info(
                        "✅ Using authenticated video loading for \(platform.rawValue, privacy: .public)"
                    )

                    // For HLS playlists (.m3u8), try using standard HTTPS scheme first
                    // CRITICAL: Custom schemes can cause issues with AVFoundation's HLS parser
                    // AVFoundation can call resource loader with standard HTTPS URLs if we set up the delegate properly
                    if isHLSPlaylist {
                        logger.info(
                            "📺 Detected HLS playlist (.m3u8) - using standard HTTPS scheme with resource loader delegate"
                        )

                        // Use standard HTTPS URL but set up resource loader to intercept requests
                        // This allows AVFoundation's HLS parser to work normally while we handle authentication
                        let asset = AVURLAsset(url: url)
                        let loader = AuthenticatedVideoAssetLoader(
                            authToken: token, originalURL: url, platform: platform)
                        asset.resourceLoader.setDelegate(loader, queue: DispatchQueue.main)

                        // Retain the loader to prevent deallocation
                        objc_setAssociatedObject(
                            asset, "loader", loader, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

                        return try await createPlayerWithAsset(asset: asset)
                    }

                    // For authenticated videos (non-HLS), download to temp file immediately
                    // The resource loader approach is unreliable with AVFoundation for non-HLS videos
                    logger.info(
                        "📥 Downloading authenticated video to temp file for reliable playback")
                    let tempFileURL = try await AuthenticatedVideoAssetLoader.downloadToTempFile(
                        url: url, authToken: token, platform: platform)

                    // Small delay to ensure file system has synced
                    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds

                    // Verify file is readable before creating asset
                    let fileManager = FileManager.default
                    guard fileManager.fileExists(atPath: tempFileURL.path) else {
                        throw NSError(
                            domain: "VideoPlayerView", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Downloaded file does not exist"])
                    }

                    let fileAsset = AVURLAsset(url: tempFileURL)

                    // #region agent log
                    let logData2: [String: Any] = [
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                        "location": "SmartMediaView.swift:644",
                        "message": "asset_created_from_temp_file",
                        "data": [
                            "tempFileURL": tempFileURL.absoluteString,
                            "fileExists": FileManager.default.fileExists(atPath: tempFileURL.path),
                            "thread": Thread.isMainThread ? "main" : "background",
                        ],
                        "sessionId": "debug-session",
                        "runId": "run1",
                        "hypothesisId": "C",
                    ]
                    if let logJSON2 = try? JSONSerialization.data(withJSONObject: logData2),
                        let logString2 = String(data: logJSON2, encoding: .utf8)
                    {
                        if let fileHandle = FileHandle(
                            forWritingAtPath:
                                "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log"
                        ) {
                            fileHandle.seekToEndOfFile()
                            fileHandle.write(("\n" + logString2).data(using: .utf8) ?? Data())
                            fileHandle.closeFile()
                        } else {
                            try? logString2.write(
                                toFile:
                                    "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log",
                                atomically: false, encoding: .utf8)
                        }
                    }
                    // #endregion

                    // Load asset tracks and playable property to help AVFoundation recognize the file format
                    logger.info(
                        "🔍 Loading asset properties for file: \(tempFileURL.lastPathComponent, privacy: .public)"
                    )
                    async let tracksTask = fileAsset.loadTracks(withMediaType: .video)
                    async let playableTask = fileAsset.load(.isPlayable)

                    // Wait for both to complete
                    let tracks = try await tracksTask
                    let isPlayable = try await playableTask

                    logger.info("✅ Asset loaded - tracks: \(tracks.count), playable: \(isPlayable)")

                    if !isPlayable {
                        throw NSError(
                            domain: "VideoPlayerView", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Video file is not playable"])
                    }

                    logger.info(
                        "✅ Playing from temporary file: \(tempFileURL.lastPathComponent, privacy: .public)"
                    )
                    return try await createPlayerWithAsset(asset: fileAsset)
                } catch {
                    // If token refresh fails, try with current token
                    if let token = account.getAccessToken() {
                        logger.warning(
                            "⚠️ Using existing token (refresh failed): \(error.localizedDescription, privacy: .public)"
                        )

                        // For HLS playlists, use custom scheme to ensure resource loader is called
                        if isHLSPlaylist {
                            logger.info(
                                "📺 Retry: Using custom scheme for HLS playlist to ensure resource loader is called"
                            )
                            // Use custom scheme to ensure resource loader handles all requests from the start
                            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                            components?.scheme = "authenticated-video"
                            guard let customSchemeURL = components?.url else {
                                throw NSError(
                                    domain: "VideoPlayerView", code: -1,
                                    userInfo: [
                                        NSLocalizedDescriptionKey: "Failed to create custom scheme URL"
                                    ])
                            }
                            
                            let asset = AVURLAsset(url: customSchemeURL)
                            let loader = AuthenticatedVideoAssetLoader(
                                authToken: token, originalURL: url, platform: platform)
                            asset.resourceLoader.setDelegate(loader, queue: DispatchQueue.main)
                            
                            objc_setAssociatedObject(
                                asset, "loader", loader, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                            return try await createPlayerWithAsset(asset: asset)
                        }

                        logger.info("📥 Downloading authenticated video to temp file")
                        let tempFileURL =
                            try await AuthenticatedVideoAssetLoader.downloadToTempFile(
                                url: url, authToken: token, platform: platform)
                        let fileAsset = AVURLAsset(url: tempFileURL)
                        
                        return try await createPlayerWithAsset(asset: fileAsset)
                    } else {
                        logger.warning(
                            "⚠️ No token available for \(platform.rawValue, privacy: .public), trying unauthenticated asset"
                        )
                        let asset = AVURLAsset(url: url)
                        return try await createPlayerWithAsset(asset: asset)
                    }
                }
            } else {
                // No account available, but URL needs auth - try unauthenticated first
                // Some Mastodon instances allow public media access
                logger.warning(
                    "⚠️ URL needs auth for \(platform.rawValue, privacy: .public) but no account available, trying unauthenticated"
                )
                let asset = AVURLAsset(url: url)
                
                return try await createPlayerWithAsset(asset: asset)
            }
        } else {
            // No authentication needed, use regular asset
            let asset = AVURLAsset(url: url)
            
            return try await createPlayerWithAsset(asset: asset)
        }
    }

    private func createPlayerWithAsset(asset: AVURLAsset) async throws -> AVPlayer {
        let logger = Logger(subsystem: "com.socialfusion.app", category: "VideoPlayerView")
        logger.info(
            "🎬 Creating AVPlayerItem for asset: \(asset.url.absoluteString, privacy: .public)")

        // #region agent log
        let logData3: [String: Any] = [
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "location": "SmartMediaView.swift:728",
            "message": "createPlayerWithAsset_start",
            "data": [
                "assetURL": asset.url.absoluteString,
                "isFileURL": asset.url.isFileURL,
                "thread": Thread.isMainThread ? "main" : "background",
            ],
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "A",
        ]
        if let logJSON3 = try? JSONSerialization.data(withJSONObject: logData3),
            let logString3 = String(data: logJSON3, encoding: .utf8)
        {
            if let fileHandle = FileHandle(
                forWritingAtPath:
                    "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log")
            {
                fileHandle.seekToEndOfFile()
                fileHandle.write(("\n" + logString3).data(using: .utf8) ?? Data())
                fileHandle.closeFile()
            } else {
                try? logString3.write(
                    toFile: "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log",
                    atomically: false, encoding: .utf8)
            }
        }
        // #endregion

        // CRITICAL: Load asset properties BEFORE creating player item
        // This ensures format description is available, preventing -12881 errors
        // For HLS, tracks won't be available until playlist is parsed, so we only load .isPlayable
        let isHLSPlaylist = asset.url.absoluteString.contains(".m3u8") || asset.url.pathExtension == "m3u8"
        logger.info("🔍 Loading asset properties before creating player item (HLS: \(isHLSPlaylist))")
        do {
            if isHLSPlaylist {
                // For HLS, only load .isPlayable - tracks won't be available until playlist is parsed
                // Loading tracks too early can cause timebase errors
                // CRITICAL: Load .isPlayable which triggers the resource loader to fetch the playlist
                let isPlayable = try await asset.load(.isPlayable)
                logger.info("✅ HLS asset properties loaded - playable: \(isPlayable)")
                
                guard isPlayable else {
                    throw NSError(
                        domain: "VideoPlayerView", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "HLS asset is not playable"])
                }

                // With standard HTTPS URLs, AVFoundation handles playlist parsing naturally
                // The isPlayable check above ensures the asset is ready
                logger.info("✅ HLS asset ready for player item creation")
            } else {
                // For non-HLS videos, load both playable and tracks
                async let playableTask = asset.load(.isPlayable)
                async let tracksTask = asset.loadTracks(withMediaType: .video)
                
                let isPlayable = try await playableTask
                let tracks = try await tracksTask
                
                logger.info("✅ Asset properties loaded - playable: \(isPlayable), tracks: \(tracks.count)")
                
                guard isPlayable else {
                    throw NSError(
                        domain: "VideoPlayerView", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Video asset is not playable"])
                }
            }
        } catch {
            logger.warning("⚠️ Failed to load asset properties: \(error.localizedDescription, privacy: .public)")
            // Continue anyway - some assets might work without explicit loading
        }
        
        // CRITICAL: Ensure we're on the main thread for AVFoundation operations
        // AVFoundation requires main thread for player item creation to avoid timebase errors
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                // CRITICAL: Simulator-specific handling - simulators often crash on video playback
                // Add logging for simulator to help diagnose issues
                #if targetEnvironment(simulator)
                logger.info("⚠️ [SIMULATOR] Creating AVPlayerItem - videos may not play correctly in simulator")
                #endif
                
                // CRITICAL: Configure player item AFTER asset properties are loaded
                // This ensures format description is available, preventing -12881 errors
                // Note: AVPlayerItem(asset:) doesn't throw, so we don't need do-catch here
                let playerItem = AVPlayerItem(asset: asset)
                
                // Configure buffering for smooth playback (like IceCubesApp and Bluesky)
                // For feed videos, use 5-8 seconds buffer (balance between smooth playback and memory)
                // Fullscreen videos use 10 seconds, but feed needs less to save memory
                playerItem.preferredForwardBufferDuration = 6.0
                
                // Create player with configured item
                let player = AVPlayer(playerItem: playerItem)
                
                // CRITICAL: Don't wait to minimize stalling for feed videos
                // This makes videos start playing immediately (like YouTube, IceCubesApp, Bluesky)
                // Users expect immediate playback in feeds, not waiting for perfect buffering
                player.automaticallyWaitsToMinimizeStalling = false
                
                // Disable external playback (AirPlay) for feed videos to ensure mute works properly
                player.allowsExternalPlayback = false
                
                // CRITICAL: Mute videos by default in feed to prevent interrupting audio from other apps
                // This ensures videos don't take over system audio (e.g., podcasts)
                player.isMuted = true
                
                // CRITICAL: Configure audio session to allow mixing with other audio
                // This prevents videos from hijacking system audio even when muted
                configureAudioSessionForMutedPlayback()

                var hasResumed = false

                // #region agent log
                let logData4: [String: Any] = [
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "location": "SmartMediaView.swift:734",
                "message": "playerItem_created",
                "data": [
                    "assetURL": asset.url.absoluteString,
                    "initialStatus": playerItem.status.rawValue,
                    "thread": Thread.isMainThread ? "main" : "background",
                ],
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "A",
            ]
            if let logJSON4 = try? JSONSerialization.data(withJSONObject: logData4),
                let logString4 = String(data: logJSON4, encoding: .utf8)
            {
                if let fileHandle = FileHandle(
                    forWritingAtPath:
                        "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log")
                {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(("\n" + logString4).data(using: .utf8) ?? Data())
                    fileHandle.closeFile()
                } else {
                    try? logString4.write(
                        toFile:
                            "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log",
                        atomically: false, encoding: .utf8)
                }
            }
            // #endregion

            logger.info("🎬 AVPlayerItem created, initial status: \(playerItem.status.rawValue)")

            // Check initial status
            if playerItem.status == .readyToPlay {
                hasResumed = true
                logger.info("✅ Player item already ready to play")
                continuation.resume(returning: player)
                return
            }

            if playerItem.status == .failed {
                hasResumed = true
                let error =
                    playerItem.error
                    ?? MediaErrorHandler.MediaError.playerSetupFailed(
                        "Player item failed immediately")
                logger.error(
                    "❌ Player item failed immediately: \(error.localizedDescription, privacy: .public)"
                )
                continuation.resume(throwing: error)
                return
            }

            // Store observer for cleanup - CRITICAL: Prevents memory leaks
            let statusObserver = playerItem.observe(\.status, options: [.new, .initial]) { [weak playerItem] item, _ in
                guard !hasResumed else {
                    // #region agent log
                    let logData5: [String: Any] = [
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                        "location": "SmartMediaView.swift:762",
                        "message": "status_observer_skipped_already_resumed",
                        "data": [
                            "status": item.status.rawValue,
                            "thread": Thread.isMainThread ? "main" : "background",
                        ],
                        "sessionId": "debug-session",
                        "runId": "run1",
                        "hypothesisId": "E",
                    ]
                    if let logJSON5 = try? JSONSerialization.data(withJSONObject: logData5),
                        let logString5 = String(data: logJSON5, encoding: .utf8)
                    {
                        if let fileHandle = FileHandle(
                            forWritingAtPath:
                                "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log"
                        ) {
                            fileHandle.seekToEndOfFile()
                            fileHandle.write(("\n" + logString5).data(using: .utf8) ?? Data())
                            fileHandle.closeFile()
                        } else {
                            try? logString5.write(
                                toFile:
                                    "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log",
                                atomically: false, encoding: .utf8)
                        }
                    }
                    // #endregion
                    return
                }

                let statusDescription: String
                switch item.status {
                case .unknown:
                    statusDescription = "unknown"
                case .readyToPlay:
                    statusDescription = "readyToPlay"
                case .failed:
                    statusDescription = "failed"
                @unknown default:
                    statusDescription = "unknown(\(item.status.rawValue))"
                }

                logger.info(
                    "🎬 Player item status changed to: \(statusDescription, privacy: .public)")

                // #region agent log
                let logData6: [String: Any] = [
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                    "location": "SmartMediaView.swift:777",
                    "message": "status_changed",
                    "data": [
                        "status": statusDescription,
                        "statusRaw": item.status.rawValue,
                        "hasError": item.error != nil,
                        "errorCode": (item.error as NSError?)?.code ?? -1,
                        "thread": Thread.isMainThread ? "main" : "background",
                    ],
                    "sessionId": "debug-session",
                    "runId": "run1",
                    "hypothesisId": "D",
                ]
                if let logJSON6 = try? JSONSerialization.data(withJSONObject: logData6),
                    let logString6 = String(data: logJSON6, encoding: .utf8)
                {
                    if let fileHandle = FileHandle(
                        forWritingAtPath:
                            "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log")
                    {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(("\n" + logString6).data(using: .utf8) ?? Data())
                        fileHandle.closeFile()
                    } else {
                        try? logString6.write(
                            toFile:
                                "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log",
                            atomically: false, encoding: .utf8)
                    }
                }
                // #endregion

                switch item.status {
                case .readyToPlay:
                    hasResumed = true
                    logger.info("✅ Player item ready to play")
                    // #region agent log
                    let logData7: [String: Any] = [
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                        "location": "SmartMediaView.swift:784",
                        "message": "continuation_resume_success",
                        "data": [
                            "thread": Thread.isMainThread ? "main" : "background"
                        ],
                        "sessionId": "debug-session",
                        "runId": "run1",
                        "hypothesisId": "E",
                    ]
                    if let logJSON7 = try? JSONSerialization.data(withJSONObject: logData7),
                        let logString7 = String(data: logJSON7, encoding: .utf8)
                    {
                        if let fileHandle = FileHandle(
                            forWritingAtPath:
                                "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log"
                        ) {
                            fileHandle.seekToEndOfFile()
                            fileHandle.write(("\n" + logString7).data(using: .utf8) ?? Data())
                            fileHandle.closeFile()
                        } else {
                            try? logString7.write(
                                toFile:
                                    "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log",
                                atomically: false, encoding: .utf8)
                        }
                    }
                    // #endregion
                    continuation.resume(returning: player)
                case .failed:
                    hasResumed = true
                    let error =
                        item.error
                        ?? MediaErrorHandler.MediaError.playerSetupFailed("Unknown error")
                    if let nsError = item.error as NSError? {
                        logger.error(
                            "❌ Player item failed: \(error.localizedDescription, privacy: .public) - Domain: \(nsError.domain, privacy: .public), Code: \(nsError.code)"
                        )
                        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
                        {
                            logger.error(
                                "❌ Underlying error: \(underlyingError.localizedDescription, privacy: .public) - Domain: \(underlyingError.domain, privacy: .public), Code: \(underlyingError.code)"
                            )
                        }
                    } else {
                        logger.error(
                            "❌ Player item failed: \(error.localizedDescription, privacy: .public)")
                    }
                    // #region agent log
                    let logData8: [String: Any] = [
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                        "location": "SmartMediaView.swift:804",
                        "message": "continuation_resume_error",
                        "data": [
                            "errorDomain": (item.error as NSError?)?.domain ?? "unknown",
                            "errorCode": (item.error as NSError?)?.code ?? -1,
                            "thread": Thread.isMainThread ? "main" : "background",
                        ],
                        "sessionId": "debug-session",
                        "runId": "run1",
                        "hypothesisId": "E",
                    ]
                    if let logJSON8 = try? JSONSerialization.data(withJSONObject: logData8),
                        let logString8 = String(data: logJSON8, encoding: .utf8)
                    {
                        if let fileHandle = FileHandle(
                            forWritingAtPath:
                                "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log"
                        ) {
                            fileHandle.seekToEndOfFile()
                            fileHandle.write(("\n" + logString8).data(using: .utf8) ?? Data())
                            fileHandle.closeFile()
                        } else {
                            try? logString8.write(
                                toFile:
                                    "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log",
                                atomically: false, encoding: .utf8)
                        }
                    }
                    // #endregion
                    continuation.resume(throwing: error)
                case .unknown:
                    logger.debug("🎬 Player item status: unknown (waiting...)")
                    break
                @unknown default:
                    break
                }
            }

            // Also check for errors periodically, even if status hasn't changed
            // CRITICAL: Use weak references to prevent retain cycles
            var errorCheckCount = 0
            weak var weakPlayerItem = playerItem
            weak var weakPlayer = player
            let loggerRef = logger // Capture logger since self is a struct
            let errorCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                guard let playerItem = weakPlayerItem, let player = weakPlayer else {
                    timer.invalidate()
                    return
                }
                errorCheckCount += 1
                if hasResumed {
                    timer.invalidate()
                    return
                }

                // For local files, give more time - AVFoundation may need to scan the file
                let isLocalFile = asset.url.isFileURL
                if isLocalFile && errorCheckCount > 20 {
                    // Local files might need more time to scan - if still unknown after 10 seconds, something's wrong
                    hasResumed = true
                    timer.invalidate()
                    let error =
                        playerItem.error
                        ?? MediaErrorHandler.MediaError.playerSetupFailed(
                            "Local file failed to load after 10 seconds")
                    loggerRef.error(
                        "❌ Local file failed to load: \(error.localizedDescription, privacy: .public)"
                    )
                    if let nsError = playerItem.error as NSError? {
                        loggerRef.error(
                            "❌ AVPlayerItem error domain: \(nsError.domain, privacy: .public), code: \(nsError.code), userInfo: \(nsError.userInfo)"
                        )
                    }
                    continuation.resume(throwing: error)
                    return
                }

                if let error = playerItem.error {
                    hasResumed = true
                    timer.invalidate()
                    loggerRef.error(
                        "❌ Player item error detected: \(error.localizedDescription, privacy: .public)"
                    )
                    if let nsError = error as NSError? {
                        loggerRef.error(
                            "❌ Error domain: \(nsError.domain, privacy: .public), code: \(nsError.code)"
                        )
                        loggerRef.error("❌ Error userInfo: \(nsError.userInfo)")
                    }
                    continuation.resume(throwing: error)
                    return
                }

                // Check status even if observer hasn't fired
                if playerItem.status == .readyToPlay {
                    hasResumed = true
                    timer.invalidate()
                    loggerRef.info("✅ Player item ready (detected via timer check)")
                    continuation.resume(returning: player)
                    return
                }

                if errorCheckCount >= 30 {
                    timer.invalidate()
                }
            }
            RunLoop.main.add(errorCheckTimer, forMode: .common)

            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak playerItem] in
                guard let playerItem = playerItem else { return }
                guard !hasResumed else { return }
                errorCheckTimer.invalidate()
                statusObserver.invalidate() // CRITICAL: Clean up observer
                hasResumed = true
                loggerRef.error(
                    "❌ Player item timed out after 30 seconds - status: \(playerItem.status.rawValue)"
                )
                if let error = playerItem.error {
                    loggerRef.error(
                        "❌ Player item error: \(error.localizedDescription, privacy: .public)")
                    if let nsError = error as NSError? {
                        loggerRef.error(
                            "❌ Error domain: \(nsError.domain, privacy: .public), code: \(nsError.code)"
                        )
                    }
                }
                continuation.resume(throwing: MediaErrorHandler.MediaError.loadTimeout)
            }
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
    
    /// Detect video size from tracks - CRITICAL: Don't load tracks for HLS
    /// This prevents timebase errors similar to the player item creation issue
    private func detectVideoSize(from player: AVPlayer) {
        Task { @MainActor in
            // Longer delay to ensure we're not in the middle of a view update
            try? await Task.sleep(nanoseconds: 33_000_000)  // ~2 frames at 60fps
            guard !Task.isCancelled else { return }

            // CRITICAL: Don't load tracks for HLS - tracks aren't available until playlist is parsed
            // This prevents timebase errors similar to the player item creation issue
            guard let currentItem = player.currentItem else { return }
            // Only AVURLAsset has url property - check and cast
            guard let urlAsset = currentItem.asset as? AVURLAsset else { return }
            let assetURL = urlAsset.url.absoluteString
            let isHLS = assetURL.contains(".m3u8") || assetURL.contains("playlist.m3u8")
            
            guard !isHLS else { return }
            
            guard let tracks = try? await currentItem.asset.loadTracks(withMediaType: .video),
                  let track = tracks.first else { return }
            
            let size = try? await track.load(.naturalSize)
            let transform = try? await track.load(.preferredTransform)
            
            guard let size = size, let transform = transform else { return }
            
            let correctedSize = size.applying(transform)
            // Defer state update to next run loop to prevent cycles
            // Use DispatchQueue to ensure we're outside the current update cycle
            // Defer state update to prevent AttributeGraph cycles
            // Use Task to ensure we're outside the current update cycle
            Task { @MainActor in
                // Additional delay to ensure we're completely outside view update cycle
                try? await Task.sleep(nanoseconds: 16_000_000)  // ~1 frame at 60fps
                guard !Task.isCancelled else { return }
                onSizeDetected?(
                    CGSize(
                        width: abs(correctedSize.width),
                        height: abs(correctedSize.height)))
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

        // Remove any existing observer first to avoid duplicates
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        // Add observer to loop when video ends
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak player] _ in
            // Seek back to beginning and play again for infinite loop
            player?.seek(to: .zero)
            player?.rate = 1.0  // Ensure rate stays at 1.0
            player?.play()
        }

        logger.info("🔄 Configured GIF looping for player with rate=1.0")
    }
    
    /// Configure AVAudioSession for muted video playback to prevent hijacking system audio
    /// Uses .ambient category which allows mixing with other audio and respects silent switch
    fileprivate func configureAudioSessionForMutedPlayback() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Use .ambient category which:
            // - Allows mixing with other audio (doesn't interrupt podcasts/music)
            // - Respects the silent switch
            // - Doesn't take over system audio
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            // Note: We don't activate the session here - let it activate naturally when needed
            // This ensures we don't interrupt other audio sessions unnecessarily
            logger.debug("✅ Configured audio session for muted playback (.ambient category)")
        } catch {
            logger.warning("⚠️ Failed to configure audio session for muted playback: \(error.localizedDescription, privacy: .public)")
        }
    }
}

class VideoPlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isBuffering = false
    @Published var bufferProgress: Float = 0
    @Published var isMuted = false

    private var statusObserver: NSKeyValueObservation?
    private var bufferObserver: NSKeyValueObservation?
    private var progressObserver: NSKeyValueObservation?
    private var loopObserver: NSObjectProtocol?
    private var muteObserver: NSKeyValueObservation?

    func setPlayer(_ player: AVPlayer) {
        self.player = player
        // Initialize mute state
        self.isMuted = player.isMuted
        setupObservers()
    }

    func toggleMute() {
        guard let player = player else { return }
        player.isMuted.toggle()
        isMuted = player.isMuted
    }

    private func setupObservers() {
        guard let item = player?.currentItem, let player = player else { return }

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

        // Observe mute state changes to keep UI in sync
        muteObserver = player.observe(\.isMuted, options: [.new, .initial]) {
            [weak self] player, _ in
            DispatchQueue.main.async {
                self?.isMuted = player.isMuted
            }
        }
    }

    deinit {
        statusObserver?.invalidate()
        bufferObserver?.invalidate()
        progressObserver?.invalidate()
        muteObserver?.invalidate()
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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
        // CRITICAL: Set infinite loop for animated GIFs (0 = infinite)
        imageView.animationRepeatCount = 0

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
                        // Ensure looping is enabled for animated GIFs
                        imageView.animationRepeatCount = 0
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

// MARK: - Hero Transition Extension

extension View {
    /// Applies matchedGeometryEffect for hero transitions when heroID and namespace are provided
    @ViewBuilder
    func applyHeroTransition(heroID: String?, namespace: Namespace.ID?, isSource: Bool) -> some View
    {
        if let heroID = heroID, let namespace = namespace {
            self.matchedGeometryEffect(id: heroID, in: namespace, isSource: isSource)
        } else {
            self
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

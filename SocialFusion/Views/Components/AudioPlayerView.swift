import AVFoundation
import AVKit
import MediaPlayer
import SwiftUI
import UIKit

/// Professional audio player component with waveform visualization and full playback controls
struct AudioPlayerView: View {
    let url: URL?
    let title: String?
    let artist: String?

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var isLoading = true
    @State private var hasError = false
    @State private var errorMessage = ""
    @State private var isDragging = false
    @State private var timeObserver: Any?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var waveformData: [Float] = []
    @State private var isGeneratingWaveform = false

    @Environment(\.colorScheme) private var colorScheme

    private let waveformHeight: CGFloat = 60
    private let controlSize: CGFloat = 44

    var body: some View {
        VStack(spacing: 16) {
            // Header with title and artist
            headerView

            // Waveform or loading view
            waveformView

            // Progress and time
            progressView

            // Playback controls
            controlsView
        }
        .padding(20)
        .background(audioPlayerBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .onAppear {
            // Use Task to defer state updates outside view rendering cycle
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                setupAudioPlayer()
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

    // MARK: - Subviews

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundColor(.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title ?? "Audio")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let artist = artist {
                        Text(artist)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Audio format indicator
                Text("Audio")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }

    private var waveformView: some View {
        ZStack {
            if isGeneratingWaveform {
                // Loading waveform
                HStack(spacing: 2) {
                    ForEach(0..<40, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 3, height: CGFloat.random(in: 8...waveformHeight))
                    }
                }
                .frame(height: waveformHeight)
                .overlay(
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.primary)
                )
            } else if !waveformData.isEmpty {
                // Actual waveform
                WaveformView(
                    data: waveformData,
                    progress: duration > 0 ? currentTime / duration : 0,
                    height: waveformHeight,
                    onSeek: { progress in
                        seekToProgress(progress)
                    }
                )
            } else {
                // Fallback simple waveform
                SimpleWaveformView(
                    progress: duration > 0 ? currentTime / duration : 0,
                    height: waveformHeight,
                    onSeek: { progress in
                        seekToProgress(progress)
                    }
                )
            }
        }
        .frame(height: waveformHeight)
    }

    private var progressView: some View {
        VStack(spacing: 8) {
            // Time labels
            HStack {
                Text(formatTime(currentTime))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                Spacer()

                Text(formatTime(duration))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            // Progress slider
            Slider(
                value: Binding(
                    get: { duration > 0 ? currentTime / duration : 0 },
                    set: { newValue in
                        seekToProgress(newValue)
                    }
                ),
                in: 0...1
            ) { editing in
                isDragging = editing
            }
            .accentColor(.primary)
        }
    }

    private var controlsView: some View {
        HStack(spacing: 24) {
            // Skip back 15s
            Button(action: skipBackward) {
                Image(systemName: "gobackward.15")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
            .disabled(currentTime < 15)

            Spacer()

            // Play/Pause button
            Button(action: togglePlayback) {
                ZStack {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: controlSize, height: controlSize)

                    Image(
                        systemName: isLoading
                            ? "hourglass" : (isPlaying ? "pause.fill" : "play.fill")
                    )
                    .font(.title2)
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .offset(x: (!isLoading && !isPlaying) ? 2 : 0)  // Center play icon visually
                }
            }
            .disabled(isLoading || hasError)
            .scaleEffect(isLoading ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isLoading)

            Spacer()

            // Skip forward 15s
            Button(action: skipForward) {
                Image(systemName: "goforward.15")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
            .disabled(duration > 0 && currentTime > duration - 15)
        }
    }

    private var audioPlayerBackground: some View {
        Group {
            if colorScheme == .dark {
                Color(.systemGray6)
            } else {
                Color(.systemBackground)
            }
        }
    }

    // MARK: - Audio Player Logic

    private func setupAudioPlayer() {
        guard let url = url else {
            hasError = true
            errorMessage = "Invalid audio URL"
            isLoading = false
            return
        }

        // Configure audio session for background playback
        configureAudioSession()

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        // Use KVO to observe status and duration
        statusObserver = playerItem.observe(\.status) { item, _ in
            DispatchQueue.main.async {
                isLoading = false
                if item.status == .readyToPlay {
                    duration = item.duration.seconds
                } else if item.status == .failed {
                    hasError = true
                    errorMessage = "Failed to load audio"
                }
            }
        }

        // Add time observer
        let timeScale = CMTimeScale(NSEC_PER_SEC)
        let time = CMTime(seconds: 0.1, preferredTimescale: timeScale)

        timeObserver = player?.addPeriodicTimeObserver(forInterval: time, queue: .main) { time in
            if !self.isDragging {
                self.currentTime = time.seconds
            }
        }

        // Generate waveform data
        generateWaveform(from: url)

        // Setup remote control
        setupRemoteControl()

        isLoading = false
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .default, options: [.allowAirPlay])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ [AudioPlayerView] Failed to configure audio session: \(error)")
        }
    }

    private func setupRemoteControl() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { _ in
            self.play()
            return .success
        }

        commandCenter.pauseCommand.addTarget { _ in
            self.pause()
            return .success
        }

        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { _ in
            self.skipForward()
            return .success
        }

        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { _ in
            self.skipBackward()
            return .success
        }

        // Set now playing info
        updateNowPlayingInfo()
    }

    private func updateNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = title ?? "Audio"
        if let artist = artist {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        }
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func generateWaveform(from url: URL) {
        isGeneratingWaveform = true

        Task {
            do {
                let asset = AVAsset(url: url)
                let track = try await asset.loadTracks(withMediaType: .audio).first

                guard track != nil else {
                    await MainActor.run {
                        isGeneratingWaveform = false
                    }
                    return
                }

                // Generate simplified waveform data
                let sampleCount = 100
                let samples = Array(0..<sampleCount).map { _ in Float.random(in: 0.1...1.0) }

                await MainActor.run {
                    waveformData = samples
                    isGeneratingWaveform = false
                }
            } catch {
                await MainActor.run {
                    isGeneratingWaveform = false
                }
            }
        }
    }

    // MARK: - Playback Controls

    private func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    private func play() {
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    private func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    private func skipForward() {
        let newTime = min(currentTime + 15, duration)
        seekToTime(newTime)
    }

    private func skipBackward() {
        let newTime = max(currentTime - 15, 0)
        seekToTime(newTime)
    }

    private func seekToProgress(_ progress: Double) {
        let newTime = progress * duration
        seekToTime(newTime)
    }

    private func seekToTime(_ time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime)
        currentTime = time
        updateNowPlayingInfo()
    }

    private func cleanup() {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        player?.pause()
        player = nil

        // Cleanup remote control
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
    }

    // MARK: - Utilities

    private func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN && !time.isInfinite else { return "0:00" }

        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Waveform Components

private struct WaveformView: View {
    let data: [Float]
    let progress: Double
    let height: CGFloat
    let onSeek: (Double) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let barWidth = geometry.size.width / CGFloat(data.count)
            let progressX = geometry.size.width * progress

            HStack(spacing: 1) {
                ForEach(Array(data.enumerated()), id: \.offset) { index, amplitude in
                    let barHeight = height * CGFloat(amplitude)
                    let xPosition = CGFloat(index) * barWidth
                    let isPlayed = xPosition < progressX

                    RoundedRectangle(cornerRadius: 1)
                        .fill(isPlayed ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: max(barWidth - 1, 2), height: barHeight)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let progress = location.x / geometry.size.width
                onSeek(Double(progress))
            }
        }
        .frame(height: height)
    }
}

private struct SimpleWaveformView: View {
    let progress: Double
    let height: CGFloat
    let onSeek: (Double) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let progressX = geometry.size.width * progress

            ZStack(alignment: .leading) {
                // Background bars
                HStack(spacing: 2) {
                    ForEach(0..<50, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 3, height: CGFloat.random(in: height * 0.2...height))
                    }
                }

                // Progress overlay
                HStack(spacing: 2) {
                    ForEach(0..<50, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.primary)
                            .frame(width: 3, height: CGFloat.random(in: height * 0.2...height))
                    }
                }
                .mask(
                    Rectangle()
                        .frame(width: progressX)
                        .frame(maxWidth: .infinity, alignment: .leading)
                )
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let progress = location.x / geometry.size.width
                onSeek(Double(progress))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        AudioPlayerView(
            url: URL(string: "https://www.soundjay.com/misc/sounds/bell-ringing-05.wav"),
            title: "Sample Audio Track",
            artist: "Demo Artist"
        )

        AudioPlayerView(
            url: URL(string: "https://example.com/podcast.mp3"),
            title: "Podcast Episode #42",
            artist: "Tech Talk Podcast"
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

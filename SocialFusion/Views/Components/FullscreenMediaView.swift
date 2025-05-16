import SwiftUI

/// A view that displays media in fullscreen with zoom and swipe capabilities
struct FullscreenMediaView: View {
    let media: MediaAttachment
    let allMedia: [MediaAttachment]

    @State private var currentScale: CGFloat = 1.0
    @State private var previousScale: CGFloat = 1.0
    @State private var currentOffset: CGSize = .zero
    @State private var previousOffset: CGSize = .zero
    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(media: MediaAttachment, allMedia: [MediaAttachment]) {
        self.media = media
        self.allMedia = allMedia

        // Find the index of the current media in the array
        if let index = allMedia.firstIndex(where: { $0.id == media.id }) {
            _currentIndex = State(initialValue: index)
        } else {
            _currentIndex = State(initialValue: 0)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                TabView(selection: $currentIndex) {
                    ForEach(Array(allMedia.enumerated()), id: \.element.id) { index, attachment in
                        ZStack {
                            mediaView(for: attachment)
                                .scaleEffect(attachment.id == media.id ? currentScale : 1.0)
                                .offset(attachment.id == media.id ? currentOffset : .zero)
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            if attachment.id == media.id {
                                                let delta = value / previousScale
                                                previousScale = value
                                                // Limit zoom to avoid extreme scaling
                                                currentScale = min(
                                                    max(currentScale * delta, 1.0), 5.0)
                                            }
                                        }
                                        .onEnded { _ in
                                            previousScale = 1.0
                                            // If zoomed out too much, reset scale
                                            if currentScale < 1.0 {
                                                withAnimation {
                                                    currentScale = 1.0
                                                    currentOffset = .zero
                                                }
                                            }
                                            // If zoomed out enough, reset
                                            if currentScale < 1.2 {
                                                withAnimation {
                                                    currentScale = 1.0
                                                    currentOffset = .zero
                                                }
                                            }
                                        }
                                )
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            if attachment.id == media.id && currentScale > 1.0 {
                                                // Only allow panning when zoomed in
                                                currentOffset = CGSize(
                                                    width: previousOffset.width
                                                        + value.translation.width,
                                                    height: previousOffset.height
                                                        + value.translation.height
                                                )
                                            }
                                        }
                                        .onEnded { _ in
                                            previousOffset = currentOffset
                                        }
                                )
                                .onTapGesture(count: 2) {
                                    // Double tap to zoom in/out
                                    withAnimation {
                                        if currentScale > 1.0 {
                                            currentScale = 1.0
                                            currentOffset = .zero
                                            previousOffset = .zero
                                        } else {
                                            currentScale = min(3.0, UIScreen.main.scale)
                                        }
                                    }
                                }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))

                // Alt text if available
                if let altText = allMedia[currentIndex].altText, !altText.isEmpty {
                    VStack {
                        Spacer()
                        Text(altText)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .padding(.bottom)
                    }
                }

                // Close button
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                        }
                        .padding()
                    }
                    Spacer()
                }
            }
            .onTapGesture {
                // Single tap on background dismisses
                if currentScale == 1.0 {
                    dismiss()
                }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func mediaView(for attachment: MediaAttachment) -> some View {
        switch attachment.type {
        case .video, .animatedGIF:
            // For video content, we would use AVKit components
            // This is a placeholder - you would implement actual video playback
            ZStack {
                Color.black
                Image(systemName: "play.circle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .foregroundColor(.white)
            }

        case .image, .unknown:
            // For images, use AsyncImage
            AsyncImage(url: attachment.url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
                } else if phase.error != nil {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                        Text("Failed to load image")
                    }
                    .foregroundColor(.white)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(2)
                }
            }

        case .audio:
            // For audio content
            VStack {
                Image(systemName: "waveform")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                Text("Audio")
                    .font(.headline)
            }
            .foregroundColor(.white)
        }
    }
}

struct FullscreenMediaView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleMedia = [
            MediaAttachment(
                id: "1",
                url: URL(string: "https://picsum.photos/800/600")!,
                altText: "A sample image with alt text"
            ),
            MediaAttachment(
                id: "2",
                url: URL(string: "https://picsum.photos/800/601")!,
                type: .image
            ),
        ]

        FullscreenMediaView(media: sampleMedia[0], allMedia: sampleMedia)
    }
}

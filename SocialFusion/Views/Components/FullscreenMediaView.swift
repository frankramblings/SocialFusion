import SwiftUI

/// A view that displays media in fullscreen with zoom and swipe capabilities
struct FullscreenMediaView: View {
    let media: Post.Attachment
    let allMedia: [Post.Attachment]

    @State private var currentScale: CGFloat = 1.0
    @State private var previousScale: CGFloat = 1.0
    @State private var currentOffset: CGSize = .zero
    @State private var previousOffset: CGSize = .zero
    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(media: Post.Attachment, allMedia: [Post.Attachment]) {
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
                                            previousScale = 1.0  // Reset for next gesture
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

                // Close button in the top-right corner
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .padding()
                                .shadow(color: .black.opacity(0.5), radius: 2)
                        }
                    }
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .statusBar(hidden: true)
    }

    private func mediaView(for attachment: Post.Attachment) -> some View {
        // For images
        AsyncImage(url: URL(string: attachment.url)) { phase in
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

        FullscreenMediaView(media: sampleMedia[0], allMedia: sampleMedia)
    }
}

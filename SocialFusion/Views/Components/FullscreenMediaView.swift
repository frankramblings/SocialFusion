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
    @State private var overlaysVisible: Bool = true
    @State private var showAltText: Bool = false
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
                                    attachment.id == allMedia[currentIndex].id
                                        ? currentOffset : .zero
                                )
                                .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 8)
                                .accessibilityLabel(attachment.altText ?? "Image")
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            if attachment.id == allMedia[currentIndex].id {
                                                let delta = value / previousScale
                                                previousScale = value
                                                currentScale = min(
                                                    max(currentScale * delta, 1.0), 5.0)
                                            }
                                        }
                                        .onEnded { _ in
                                            previousScale = 1.0
                                        }
                                )
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            if attachment.id == allMedia[currentIndex].id
                                                && currentScale > 1.0
                                            {
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
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))

                // Overlays (X, alt text, sharrow)
                if overlaysVisible {
                    VStack {
                        // Top overlay: Close button and ALT/info button
                        HStack {
                            Spacer()
                            // ALT/info button (shows if alt text exists)
                            if let altText = allMedia[currentIndex].altText, !altText.isEmpty {
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showAltText.toggle()
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(showAltText ? .yellow : .white)
                                        .padding(10)
                                }
                                .buttonStyle(GlassyButtonStyle())
                                .accessibilityLabel("Show image description")
                                .accessibilityHint("Toggles the alt text overlay")
                                .padding(.trailing, 4)
                            }
                            Button(action: { dismiss() }) {
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
                        // Bottom overlay: Alt text (if toggled) and share button
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 0) {
                                if showAltText, let altText = allMedia[currentIndex].altText,
                                    !altText.isEmpty
                                {
                                    Text(altText)
                                        .font(.body)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color.black.opacity(0.85),
                                                    Color.black.opacity(0.0),
                                                ]),
                                                startPoint: .bottom, endPoint: .top
                                            )
                                        )
                                        .cornerRadius(16)
                                        .padding(.bottom, 12)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                        .accessibilityLabel("Image description: \(altText)")
                                }
                            }
                            Spacer()
                            VStack {
                                Button(action: {
                                    // Share the image URL
                                    if let url = URL(string: allMedia[currentIndex].url) {
                                        let av = UIActivityViewController(
                                            activityItems: [url], applicationActivities: nil)
                                        if let windowScene = UIApplication.shared.connectedScenes
                                            .first as? UIWindowScene,
                                            let window = windowScene.windows.first,
                                            let rootVC = window.rootViewController
                                        {
                                            rootVC.present(av, animated: true, completion: nil)
                                        }
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .padding(12)
                                }
                                .buttonStyle(GlassyButtonStyle())
                                .accessibilityLabel("Share image")
                                .padding(.bottom, 8)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .animation(.easeInOut(duration: 0.2), value: overlaysVisible)
                }

                // Page indicator dots (only if multiple images)
                if allMedia.count > 1 {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(0..<allMedia.count, id: \.self) { idx in
                                Circle()
                                    .fill(
                                        idx == currentIndex ? Color.white : Color.white.opacity(0.3)
                                    )
                                    .frame(width: 7, height: 7)
                            }
                        }
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 1)
                        .padding(.bottom, 18)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .statusBar(hidden: true)
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height > 100 || value.predictedEndTranslation.height > 200
                    {
                        withAnimation { dismiss() }
                    }
                }
        )
    }

    private func mediaView(for attachment: Post.Attachment) -> some View {
        print("FullscreenMediaView loading URL: \(attachment.url) type: \(attachment.type)")
        guard attachment.type == .image else {
            return AnyView(
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text("Unsupported media type")
                }
                .foregroundColor(.white)
            )
        }
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
        return AnyView(
            AsyncImage(url: url) { phase in
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
        )
    }
}

// GlassyButtonStyle for overlay buttons
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

        FullscreenMediaView(media: sampleMedia[0], allMedia: sampleMedia)
    }
}

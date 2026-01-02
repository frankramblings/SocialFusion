import SwiftUI

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
                                        DragGesture(minimumDistance: 10)
                                            .onChanged { value in
                                                if currentScale > 1.0 {
                                                    // When zoomed: pan the image with immediate visual feedback
                                                    dragOffset = value.translation
                                                } else {
                                                    // When not zoomed: show visual feedback for swipe-to-dismiss in any direction
                                                    dragOffset = value.translation
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
                                                    // When not zoomed: check for swipe-to-dismiss in ANY direction
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

                                                    // Thresholds: horizontal swipes need to be stronger to avoid conflicts with TabView
                                                    let verticalThreshold: CGFloat = 100
                                                    let horizontalThreshold: CGFloat = 150  // Higher threshold for horizontal
                                                    let diagonalThreshold: CGFloat = 100
                                                    let velocityThreshold: CGFloat = 500

                                                    // Check if swipe is primarily horizontal
                                                    let isPrimarilyHorizontal =
                                                        absWidth > absHeight * 1.5

                                                    // Dismiss if:
                                                    // - Strong vertical swipe (>100px)
                                                    // - Strong diagonal swipe (both >100px)
                                                    // - Strong horizontal swipe (>150px) - higher threshold to avoid TabView conflict
                                                    // - High velocity swipe (500+)
                                                    let shouldDismiss: Bool
                                                    if isPrimarilyHorizontal {
                                                        // Horizontal swipes need to be stronger
                                                        shouldDismiss =
                                                            absWidth > horizontalThreshold
                                                            || velocity > velocityThreshold
                                                    } else {
                                                        // Vertical/diagonal swipes use normal threshold
                                                        shouldDismiss =
                                                            distance > diagonalThreshold
                                                            || absHeight > verticalThreshold
                                                            || absWidth > diagonalThreshold
                                                            || velocity > velocityThreshold
                                                    }

                                                    if shouldDismiss {
                                                        // Swipe to dismiss in any direction
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
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

    }

    private func mediaView(for attachment: Post.Attachment) -> some View {
        print("FullscreenMediaView loading URL: \(attachment.url) type: \(attachment.type)")

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

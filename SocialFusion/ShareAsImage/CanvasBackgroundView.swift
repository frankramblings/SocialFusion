import SwiftUI

/// Wraps share image content in a styled canvas background
struct CanvasBackgroundView<Content: View>: View {
    let preset: ShareCanvasPreset
    let shortSide: CGFloat
    let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(
        preset: ShareCanvasPreset,
        shortSide: CGFloat = 1080,
        @ViewBuilder content: () -> Content
    ) {
        self.preset = preset
        self.shortSide = shortSide
        self.content = content()
    }

    private var canvasSize: CGSize {
        preset.canvasSize(shortSide: shortSide)
    }

    private var safeInsets: SafeInsetCalculator.SafeInsets {
        SafeInsetCalculator.computeSafeInsets(for: preset, shortSide: shortSide)
    }

    var body: some View {
        ZStack {
            // Background gradient
            backgroundGradient

            // Content centered in safe zone
            content
                .frame(
                    maxWidth: canvasSize.width - safeInsets.totalHorizontal,
                    maxHeight: canvasSize.height - safeInsets.totalVertical
                )
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    // MARK: - Background Styles

    private var backgroundGradient: some View {
        Group {
            if colorScheme == .dark {
                darkModeGradient
            } else {
                lightModeGradient
            }
        }
    }

    private var lightModeGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.95, blue: 0.97),  // Light gray-blue
                Color(red: 0.92, green: 0.92, blue: 0.95),  // Slightly darker
                Color(red: 0.90, green: 0.90, blue: 0.93),  // Even darker at bottom
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var darkModeGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.12, green: 0.12, blue: 0.14),  // Dark gray
                Color(red: 0.10, green: 0.10, blue: 0.12),  // Slightly darker
                Color(red: 0.08, green: 0.08, blue: 0.10),  // Even darker at bottom
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// A canvas view that applies preset dimensions and safe zones to content
struct ShareCanvasView: View {
    let document: ShareImageDocument
    let preset: ShareCanvasPreset
    let shortSide: CGFloat

    init(
        document: ShareImageDocument,
        preset: ShareCanvasPreset,
        shortSide: CGFloat = 1080
    ) {
        self.document = document
        self.preset = preset
        self.shortSide = shortSide
    }

    private var cardWidth: CGFloat {
        SafeInsetCalculator.maxCardWidth(for: preset, shortSide: shortSide)
    }

    var body: some View {
        CanvasBackgroundView(preset: preset, shortSide: shortSide) {
            ShareImageRootView(
                document: document,
                targetPixelWidth: cardWidth
            )
        }
    }
}

// MARK: - Previews

#if DEBUG
struct CanvasBackgroundView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // 4:3 preview
            CanvasBackgroundView(preset: .ratio4x3, shortSide: 300) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(radius: 4)
            }
            .previewDisplayName("4:3")

            // 1:1 preview
            CanvasBackgroundView(preset: .ratio1x1, shortSide: 300) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(radius: 4)
            }
            .previewDisplayName("1:1")

            // 4:5 preview
            CanvasBackgroundView(preset: .ratio4x5, shortSide: 300) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(radius: 4)
            }
            .previewDisplayName("4:5")

            // 9:16 preview (scaled down)
            CanvasBackgroundView(preset: .ratio9x16, shortSide: 200) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(radius: 4)
            }
            .previewDisplayName("9:16")
        }
    }
}
#endif

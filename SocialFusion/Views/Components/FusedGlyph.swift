import SwiftUI

/// The Fused motif: a miniature of the SocialFusion logo. Two overlapping
/// circles (Mastodon purple + Bluesky blue) with a cyan lens at their
/// intersection. Optionally plays a bloom on first appearance.
public struct FusedGlyph: View {
    /// Visual size of the bounding box in pt.
    public let size: CGFloat

    /// If true, the glyph plays the D-bloom on first appearance, then settles to A.
    /// If false, it renders A statically.
    public let bloomOnAppear: Bool

    @State private var bloomScale: CGFloat = 1.0
    @State private var bloomOpacity: Double = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Colors from LaunchAnimationView for exact brand alignment.
    private let purple = Color(red: 0.54, green: 0.39, blue: 1.00)
    private let blue = Color(red: 0.00, green: 0.59, blue: 1.00)
    private let cyan = Color(red: 0.11, green: 0.91, blue: 1.00)

    public init(size: CGFloat = 18, bloomOnAppear: Bool = false) {
        self.size = size
        self.bloomOnAppear = bloomOnAppear
    }

    public var body: some View {
        let circleSize = size * 0.68
        ZStack {
            // Purple circle (Mastodon side).
            Circle()
                .fill(purple.opacity(0.88))
                .frame(width: circleSize, height: circleSize)
                .offset(x: -circleSize * 0.20)

            // Blue circle (Bluesky side).
            Circle()
                .fill(blue.opacity(0.88))
                .frame(width: circleSize, height: circleSize)
                .offset(x: circleSize * 0.20)

            // Cyan lens at the intersection.
            Ellipse()
                .fill(cyan.opacity(0.95))
                .frame(width: circleSize * 0.22, height: circleSize * 0.78)

            // Bloom (D state) — radial glow centered on the lens.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.85), cyan.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: circleSize * 0.55
                    )
                )
                .frame(width: circleSize * 1.2, height: circleSize * 1.2)
                .blendMode(.plusLighter)
                .scaleEffect(bloomScale)
                .opacity(bloomOpacity)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true) // Decorative; semantics live on the badge text.
        .onAppear {
            guard bloomOnAppear else { return }
            // Reduce-motion respect: use the SwiftUI environment value
            // rather than the static UIAccessibility flag so any
            // mid-session change to the user's preference takes effect
            // immediately — also keeps this view independent of UIKit
            // for testability and previewability.
            if reduceMotion { return }
            withAnimation(.easeOut(duration: 0.18)) {
                bloomScale = 1.4
                bloomOpacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                withAnimation(.easeIn(duration: 0.32)) {
                    bloomScale = 1.0
                    bloomOpacity = 0.0
                }
            }
        }
    }
}

#if DEBUG
struct FusedGlyph_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 20) {
            FusedGlyph(size: 14)
            FusedGlyph(size: 18)
            FusedGlyph(size: 24)
            FusedGlyph(size: 40, bloomOnAppear: true)
        }
        .padding()
    }
}
#endif

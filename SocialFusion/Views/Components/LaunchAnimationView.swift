import SwiftUI
import UIKit

struct LaunchAnimationView: View {
    var onFinished: () -> Void = {}

    // MARK: – State
    @State private var fused = false
    @State private var bloomScale: CGFloat = 0.3
    @State private var bloomOpacity: Double = 0
    @State private var textSpacing: CGFloat = 80
    @State private var rootScale: CGFloat = 0.96
    @State private var rootOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Honors the system reduce-motion accessibility flag. Spec acceptance
    // criterion: "Reduce-motion respected on launch animation, Fused
    // bloom, profile parallax." When enabled, snap to the final state
    // instead of animating circles together.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: – Geometry
    private let circleSize: CGFloat = 180
    private let startGap: CGFloat = 80
    private var halfWidth: CGFloat { circleSize / 2 }

    // MARK: – Colours
    private let purple = Color(red: 0.54, green: 0.39, blue: 1.00)  // #8A63FF
    private let blue = Color(red: 0.00, green: 0.59, blue: 1.00)  // #0096FF
    private let lensCyan = Color(red: 0.11, green: 0.91, blue: 1.00)  // #1EE7FF
    private let lensOutlineWidth: CGFloat = 2

    // MARK: – Timing
    private let anim = Animation.spring(response: 0.62, dampingFraction: 0.78)

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Two circles + fusion lens
                ZStack {
                    Circle()
                        .fill(purple.opacity(0.85))
                        .frame(width: circleSize, height: circleSize)
                        .overlay(
                            Circle()
                                .stroke(purple, lineWidth: 1)
                                .opacity(0.9)
                        )
                        .offset(x: fused ? -halfWidth / 2 : -(halfWidth + startGap))

                    Circle()
                        .fill(blue.opacity(0.85))
                        .frame(width: circleSize, height: circleSize)
                        .overlay(
                            Circle()
                                .stroke(blue, lineWidth: 1)
                                .opacity(0.9)
                        )
                        .offset(x: fused ? halfWidth / 2 : (halfWidth + startGap))

                    // Lens: solid core, radial glow, and outline
                    ZStack {
                        Circle()
                            .fill(lensCyan.opacity(0.6))

                        Circle()
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.8), lensCyan.opacity(0.0),
                                    ]),
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: circleSize * 0.35
                                )
                            )
                            .blendMode(.plusLighter)

                        Circle()
                            .stroke(lensCyan.opacity(0.9), lineWidth: lensOutlineWidth)
                    }
                    .frame(width: circleSize * 0.7)
                    .opacity(bloomOpacity)
                    .blur(radius: fused ? 12 : 2)
                    .scaleEffect(bloomScale)
                }

                // Animated app name with subtle tracking-in effect
                HStack(spacing: textSpacing) {
                    Text("Social")
                    Text("Fusion")
                }
                .font(.system(size: 36, weight: .bold, design: .default))
                .opacity(fused ? 1 : 0)
                .scaleEffect(fused ? 1.0 : 0.98)
            }
            .scaleEffect(rootScale)
            .opacity(rootOpacity)
        }
        .onAppear {
            runSequence()
        }
        .accessibilityHidden(true)
    }

    @MainActor
    private func runSequence() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000)

            // Reduce Motion: skip the converging-circles + bloom +
            // haptic-impact sequence entirely. Show the rested,
            // fused state with a gentle opacity fade and hand off
            // quickly. Same brand beat, no motion — matches Apple's
            // own behavior on launch animations under Reduce Motion.
            if reduceMotion {
                fused = true
                textSpacing = 0
                bloomScale = 1.0
                bloomOpacity = 0.88
                rootScale = 1.0
                withAnimation(.easeOut(duration: 0.32)) {
                    rootOpacity = 1.0
                }
                try? await Task.sleep(nanoseconds: 700_000_000)
                onFinished()
                return
            }

            // Pre-warm the fusion-impact generator. Held as a
            // singleton instance so the prepare() actually takes
            // effect — a per-trigger generator gets deallocated
            // before its prepared state is consumed.
            Self.fusionImpactGenerator.prepare()

            // Stage 0: gentle entrance — root fades in and settles to scale 1
            withAnimation(.easeOut(duration: 0.28)) {
                rootScale = 1.0
                rootOpacity = 1.0
            }

            // Stage 1: circles converge using spring physics (feels weighted, alive)
            withAnimation(anim) {
                fused = true
                textSpacing = 0
            }

            // Wait until circles overlap ~50%, then trigger the fusion bloom
            try? await Task.sleep(nanoseconds: 280_000_000)

            // The fusion moment — haptic impact synced with the bloom
            Self.fusionImpactGenerator.impactOccurred(intensity: 0.8)

            withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
                bloomScale = 1.45
                bloomOpacity = 1
            }

            // Settle into the resting state
            try? await Task.sleep(nanoseconds: 160_000_000)
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                bloomScale = 1.0
                bloomOpacity = 0.88
            }

            // Hold a beat so the user can take it in, then hand off
            try? await Task.sleep(nanoseconds: 760_000_000)
            onFinished()
        }
    }

    /// Held singleton so prepare() actually warms a generator the
    /// trigger can use. Allocating per-call (the prior pattern) made
    /// the warm-up a no-op because the prepared instance was
    /// released before impactOccurred fired.
    private static let fusionImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
}

#if DEBUG
    struct LaunchAnimationView_Previews: PreviewProvider {
        static var previews: some View {
            LaunchAnimationView()
                .environment(\.colorScheme, .light)
            LaunchAnimationView()
                .environment(\.colorScheme, .dark)
        }
    }
#endif

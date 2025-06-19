import SwiftUI

struct LaunchAnimationView: View {
    var onFinished: () -> Void = {}

    // MARK: – State
    @State private var fused = false
    @State private var bloomScale: CGFloat = 0.3
    @State private var bloomOpacity: Double = 0
    @State private var textSpacing: CGFloat = 80

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
    private let anim = Animation.easeOut(duration: 0.6)

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

                // Animated app name
                HStack(spacing: textSpacing) {
                    Text("Social")
                    Text("Fusion")
                }
                .font(.system(size: 36, weight: .bold, design: .default))
                .opacity(fused ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(anim) {
                fused = true  // circles and text converge over 0.6 s
                textSpacing = 0
            }
            // Wait until the circles are ~50 % overlapped, then trigger the reaction
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.12)) {
                    bloomScale = 1.4
                    bloomOpacity = 1
                }
                // settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.easeIn(duration: 0.28)) {
                        bloomScale = 1.0
                        bloomOpacity = 0.85
                    }
                }
            }
            // Allow more time for the complete animation sequence including the settle phase
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                onFinished()
            }
        }
        .accessibilityHidden(true)
    }
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

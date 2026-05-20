import SwiftUI

/// A delightful "You're caught up" moment shown when the user reaches the end of their timeline.
/// Features a satisfying checkmark stroke draw, gentle scale-in, and a quiet pride in the design.
struct CaughtUpMarker: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hasAppeared = false
  @State private var checkmarkProgress: CGFloat = 0
  @State private var ringScale: CGFloat = 0.6
  @State private var ringOpacity: Double = 0

  var body: some View {
    HStack(spacing: 12) {
      // Left tapered divider
      taperedDivider(reversed: false)
        .opacity(hasAppeared ? 1 : 0)

      // Checkmark badge — the moment of pride
      ZStack {
        // Soft tinted halo (decorative; gives the badge presence without weight)
        Circle()
          .fill(
            RadialGradient(
              colors: [
                Color.accentColor.opacity(0.22),
                Color.accentColor.opacity(0.0),
              ],
              center: .center,
              startRadius: 2,
              endRadius: 22
            )
          )
          .frame(width: 44, height: 44)
          .opacity(ringOpacity)
          .scaleEffect(ringScale)

        // Filled inner disc
        Circle()
          .fill(Color.accentColor.opacity(0.12))
          .overlay(
            Circle()
              .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
          )
          .frame(width: 26, height: 26)
          .scaleEffect(ringScale)
          .opacity(ringOpacity)

        // Checkmark — drawn via trim animation
        CheckmarkShape()
          .trim(from: 0, to: checkmarkProgress)
          .stroke(
            Color.accentColor,
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
          )
          .frame(width: 13, height: 9)
      }
      .accessibilityHidden(true)

      // Label
      Text("You're caught up")
        .font(.footnote.weight(.semibold))
        .foregroundColor(.primary.opacity(0.78))
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 2)
        .fixedSize()

      // Right tapered divider
      taperedDivider(reversed: true)
        .opacity(hasAppeared ? 1 : 0)
    }
    .padding(.vertical, 18)
    .padding(.horizontal, 20)
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("You are caught up with your timeline")
    .onAppear {
      runEntrance()
    }
  }

  /// A divider line that fades toward the badge — gives the marker a "horizon" feel.
  private func taperedDivider(reversed: Bool) -> some View {
    LinearGradient(
      colors: [
        Color.secondary.opacity(0.0),
        Color.secondary.opacity(0.35),
      ],
      startPoint: reversed ? .trailing : .leading,
      endPoint: reversed ? .leading : .trailing
    )
    .frame(height: 0.5)
    .frame(maxWidth: .infinity)
  }

  private func runEntrance() {
    if reduceMotion {
      checkmarkProgress = 1
      ringScale = 1
      ringOpacity = 1
      hasAppeared = true
      return
    }

    // Stage 1: ring expands in
    withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
      ringScale = 1
      ringOpacity = 1
    }

    // Stage 2: checkmark draws — slightly delayed for choreography.
    // No haptic here: the marker is rendered inside a LazyVStack and
    // SwiftUI rebuilds it every time it scrolls back into view, so
    // firing a haptic on .onAppear would fire on every scroll-past,
    // not just the first encounter. The checkmark stroke is the
    // visual delight; the haptic was originally 'quiet pride' but
    // became scroll noise.
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 180_000_000)
      withAnimation(.easeOut(duration: 0.38)) {
        checkmarkProgress = 1
      }
      try? await Task.sleep(nanoseconds: 140_000_000)
      withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
        hasAppeared = true
      }
    }
  }
}

/// Classic checkmark glyph drawn as a Shape so we can animate its stroke.
private struct CheckmarkShape: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    let w = rect.width
    let h = rect.height
    p.move(to: CGPoint(x: 0, y: h * 0.55))
    p.addLine(to: CGPoint(x: w * 0.38, y: h * 0.95))
    p.addLine(to: CGPoint(x: w, y: h * 0.1))
    return p
  }
}

#Preview("Caught Up") {
  CaughtUpMarker()
    .background(Color(.systemBackground))
}

#Preview("Caught Up — Dark") {
  CaughtUpMarker()
    .background(Color(.systemBackground))
    .preferredColorScheme(.dark)
}

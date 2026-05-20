import SwiftUI

/// A typing indicator that matches iMessage's signature dot-pulse rhythm.
/// Each dot brightens and slightly scales in sequence, then settles — feels
/// considered and alive without being attention-grabbing.
struct TypingIndicatorBubble: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hasAppeared = false

  private let dotSize: CGFloat = 7
  private let period: Double = 1.2  // total cycle time

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      Color.clear.frame(width: 28, height: 28)

      Group {
        if reduceMotion {
          // Static dots if user prefers reduced motion
          HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { _ in
              Circle()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: dotSize, height: dotSize)
            }
          }
        } else {
          TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
              .truncatingRemainder(dividingBy: period) / period
            HStack(spacing: 5) {
              ForEach(0..<3, id: \.self) { index in
                AnimatedDot(
                  size: dotSize,
                  phase: t,
                  delay: Double(index) * 0.18
                )
              }
            }
          }
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 11)
      .background(
        LinearGradient(
          colors: [
            Color(.systemGray5),
            Color(.systemGray5).opacity(0.92),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .clipShape(BubbleShape(isFromMe: false, hasTail: true))
      .scaleEffect(hasAppeared ? 1.0 : 0.88, anchor: .bottomLeading)
      .opacity(hasAppeared ? 1.0 : 0.0)

      Spacer(minLength: 60)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .accessibilityLabel("Typing")
    .onAppear {
      if reduceMotion {
        hasAppeared = true
      } else {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
          hasAppeared = true
        }
      }
    }
  }
}

/// A single dot that brightens and gently rises in sync with a shared phase clock.
private struct AnimatedDot: View {
  let size: CGFloat
  let phase: Double  // 0..1, shared across all dots
  let delay: Double  // offset in phase units

  var body: some View {
    // Shift this dot's phase by its delay
    let local = (phase - delay).truncatingRemainder(dividingBy: 1.0)
    let normalized = local < 0 ? local + 1 : local

    // Bell curve over the first ~50% of the cycle, then rest
    let active = normalized < 0.5
      ? sin(normalized * .pi * 2) * 0.5 + 0.5  // 0 → 1 → 0
      : 0.0

    let opacity = 0.35 + 0.55 * active
    let yOffset = -3 * active

    Circle()
      .fill(Color.secondary)
      .opacity(opacity)
      .frame(width: size, height: size)
      .offset(y: yOffset)
  }
}

#Preview {
  VStack(spacing: 8) {
    TypingIndicatorBubble()
    TypingIndicatorBubble()
  }
  .padding()
}

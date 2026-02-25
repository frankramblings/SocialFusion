import SwiftUI

/// Applies a subtle parallax offset to media content based on scroll position.
/// Uses a preference key to read position without continuous GeometryReader updates,
/// keeping the effect lightweight and avoiding AttributeGraph cycles.
struct ParallaxMediaModifier: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    if reduceMotion {
      content
    } else {
      content
        .modifier(ParallaxGeometryReader())
    }
  }
}

/// Internal modifier that applies the parallax via GeometryReader in a background.
/// The offset is small (5% factor) so even if it lags slightly behind scroll,
/// the visual effect remains pleasant.
private struct ParallaxGeometryReader: ViewModifier {
  @State private var offset: CGFloat = 0
  private static let screenMidY = UIScreen.main.bounds.height / 2
  private static let factor: CGFloat = 0.05

  func body(content: Content) -> some View {
    content
      .offset(y: offset)
      .clipped()
      .background(
        GeometryReader { geo in
          let midY = geo.frame(in: .global).midY
          let computed = -((midY - Self.screenMidY) * Self.factor)
          Color.clear
            .preference(key: ParallaxOffsetKey.self, value: computed)
        }
      )
      .onPreferenceChange(ParallaxOffsetKey.self) { value in
        offset = value
      }
  }
}

private struct ParallaxOffsetKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

extension View {
  func parallaxOnScroll() -> some View {
    modifier(ParallaxMediaModifier())
  }
}

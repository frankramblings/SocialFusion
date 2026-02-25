import SwiftUI

/// A view that displays an animated rolling count for action buttons.
///
/// When the value changes, digits morph smoothly using `contentTransition(.numericText)`
/// with spring physics. Respects the user's `reduceMotion` accessibility setting.
/// Formats large numbers with K/M suffixes (e.g., 1.2K, 3.4M).
///
/// Usage:
/// ```swift
/// RollingNumberView(count, font: .caption, color: isLiked ? .red : .secondary)
/// ```
struct RollingNumberView: View {
  let value: Int
  let font: Font
  let color: Color

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(_ value: Int, font: Font = .caption, color: Color = .secondary) {
    self.value = value
    self.font = font
    self.color = color
  }

  var body: some View {
    if value > 0 {
      Text(formattedValue)
        .font(font)
        .foregroundColor(color)
        .contentTransition(.numericText(value: Double(value)))
        .animation(
          reduceMotion
            ? nil
            : .spring(response: 0.2, dampingFraction: 0.8),
          value: value
        )
    }
  }

  // MARK: - Formatting

  private var formattedValue: String {
    if value >= 1_000_000 {
      return String(format: "%.1fM", Double(value) / 1_000_000)
    } else if value >= 1_000 {
      return String(format: "%.1fK", Double(value) / 1_000)
    } else {
      return "\(value)"
    }
  }
}

// MARK: - Preview

#Preview("Rolling Number") {
  VStack(spacing: 16) {
    HStack(spacing: 12) {
      RollingNumberView(0)
      RollingNumberView(7, color: .red)
      RollingNumberView(42, font: .body, color: .green)
      RollingNumberView(1_234, color: .blue)
      RollingNumberView(2_500_000, color: .orange)
    }
  }
  .padding()
}

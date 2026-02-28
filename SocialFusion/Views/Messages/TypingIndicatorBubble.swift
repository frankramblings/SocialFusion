import SwiftUI

struct TypingIndicatorBubble: View {
  @State private var isAnimating = false

  private let dotSize: CGFloat = 8
  private let dotColor = Color.secondary

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      Color.clear.frame(width: 28, height: 28)

      HStack(spacing: 4) {
        ForEach(0..<3, id: \.self) { index in
          Circle()
            .fill(dotColor)
            .frame(width: dotSize, height: dotSize)
            .offset(y: isAnimating ? -4 : 0)
            .animation(
              .easeInOut(duration: 0.4)
              .repeatForever(autoreverses: true)
              .delay(Double(index) * 0.15),
              value: isAnimating
            )
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(Color(.systemGray5))
      .clipShape(BubbleShape(isFromMe: false, hasTail: true))

      Spacer(minLength: 60)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .onAppear { isAnimating = true }
  }
}

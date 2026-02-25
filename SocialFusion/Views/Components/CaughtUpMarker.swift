import SwiftUI

struct CaughtUpMarker: View {
  var body: some View {
    HStack(spacing: 12) {
      line
      Text("You're caught up")
        .font(.caption)
        .foregroundColor(.secondary)
      line
    }
    .opacity(0.3)
    .padding(.vertical, 12)
    .padding(.horizontal, 16)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("You are caught up with your timeline")
  }

  private var line: some View {
    Rectangle()
      .fill(Color.secondary)
      .frame(height: 0.5)
  }
}

#Preview {
  CaughtUpMarker()
}

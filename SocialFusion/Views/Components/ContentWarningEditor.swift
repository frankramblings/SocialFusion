import SwiftUI

/// Inline content warning editor with presets.
struct ContentWarningEditor: View {
  @Binding var cwEnabled: Bool
  @Binding var cwText: String

  private let cwPresets = ["Spoilers", "Politics", "NSFW", "Violence", "Food"]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if cwEnabled {
        // Header
        HStack(spacing: 6) {
          Image(systemName: "eye.slash.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.orange.gradient)
            .symbolRenderingMode(.hierarchical)

          Text("Content Warning")
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.primary.opacity(0.8))

          Spacer()

          Button {
            HapticEngine.tap.trigger()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
              cwEnabled = false
              cwText = ""
            }
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.subheadline)
              .foregroundColor(.secondary)
              .frame(width: 44, height: 44)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Remove content warning")
        }

        // Warning text input — softer than .roundedBorder
        TextField("Describe the content...", text: $cwText, axis: .vertical)
          .font(.subheadline)
          .lineLimit(2...4)
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .fill(Color(UIColor.systemBackground))
              .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                  .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5)
              )
          )

        // Preset chips — highlight active selection
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(cwPresets, id: \.self) { preset in
              presetChip(preset)
            }
          }
          .padding(.horizontal, 2)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.orange.opacity(0.06))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.orange.opacity(0.16), lineWidth: 0.5)
        )
    )
  }

  @ViewBuilder
  private func presetChip(_ preset: String) -> some View {
    let isActive = cwText == preset
    Button {
      HapticEngine.selection.trigger()
      withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
        cwText = isActive ? "" : preset
      }
    } label: {
      Text(preset)
        .font(.caption.weight(isActive ? .semibold : .regular))
        .foregroundColor(isActive ? .white : .primary.opacity(0.75))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
          Capsule()
            .fill(isActive ? Color.orange : Color(UIColor.secondarySystemBackground))
        )
        .overlay(
          Capsule()
            .strokeBorder(
              isActive ? Color.clear : Color.primary.opacity(0.06),
              lineWidth: 0.5
            )
        )
    }
    .buttonStyle(.plain)
    .accessibilityLabel(preset)
    .accessibilityAddTraits(isActive ? .isSelected : [])
  }
}

#Preview {
  @Previewable @State var enabled = true
  @Previewable @State var text = "Politics"
  return ContentWarningEditor(cwEnabled: $enabled, cwText: $text)
    .padding()
}

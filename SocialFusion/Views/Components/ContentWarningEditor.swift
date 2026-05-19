import SwiftUI

/// Inline content warning editor with presets
struct ContentWarningEditor: View {
  @Binding var cwEnabled: Bool
  @Binding var cwText: String
  @State private var showPresets = false
  @FocusState private var warningFieldFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if cwEnabled {
        HStack {
          Text("Content Warning")
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.secondary)

          Spacer()

          Button(action: {
            cwEnabled = false
            cwText = ""
            HapticEngine.selection.trigger()
          }) {
            Image(systemName: "xmark.circle.fill")
              .foregroundColor(.secondary)
          }
          .accessibilityLabel("Remove content warning")
        }

        TextField("Warning text...", text: $cwText, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(2...4)
          .focused($warningFieldFocused)
          .accessibilityLabel("Content warning text")

        // Preset buttons — quick chips below the field. Tapping a
        // preset replaces the buffer (matches Mastodon web's behavior),
        // fires a selection haptic, and refocuses the field so the
        // user can refine the wording without re-tapping.
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(cwPresets, id: \.self) { preset in
              Button(action: {
                cwText = preset
                HapticEngine.selection.trigger()
                warningFieldFocused = true
              }) {
                Text(preset)
                  .font(.caption)
                  .padding(.horizontal, 12)
                  .padding(.vertical, 6)
                  .background(Color(UIColor.secondarySystemBackground))
                  .cornerRadius(8)
              }
              .accessibilityLabel("Use \(preset) preset")
              .accessibilityHint("Sets the warning text to \(preset).")
            }
          }
        }
        .accessibilityLabel("Preset warnings")
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
    .cornerRadius(8)
    // Auto-focus when CW is first enabled — the user just toggled it
    // on, they obviously want to type. The onChange instead of onAppear
    // is intentional: the editor's outer VStack only renders the
    // TextField when cwEnabled, so onAppear would miss the transition.
    .onChange(of: cwEnabled) { _, newValue in
      if newValue {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
          warningFieldFocused = true
        }
      }
    }
  }

  private let cwPresets = ["Spoilers", "Politics", "NSFW", "Violence", "Food"]
}

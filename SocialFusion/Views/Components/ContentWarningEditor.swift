import SwiftUI

/// Inline content warning editor with presets
struct ContentWarningEditor: View {
  @Binding var cwEnabled: Bool
  @Binding var cwText: String
  @State private var showPresets = false
  
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
          }) {
            Image(systemName: "xmark.circle.fill")
              .foregroundColor(.secondary)
          }
        }
        
        TextField("Warning text...", text: $cwText, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(2...4)
        
        // Preset buttons
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(cwPresets, id: \.self) { preset in
              Button(action: {
                cwText = preset
              }) {
                Text(preset)
                  .font(.caption)
                  .padding(.horizontal, 12)
                  .padding(.vertical, 6)
                  .background(Color(UIColor.secondarySystemBackground))
                  .cornerRadius(8)
              }
            }
          }
        }
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
    .cornerRadius(8)
  }
  
  private let cwPresets = ["Spoilers", "Politics", "NSFW", "Violence", "Food"]
}

import SwiftUI

/// Row view for displaying a tag in search results
struct SearchTagRow: View {
  let tag: SearchTag
  let onTap: () -> Void
  
  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 12) {
        Image(systemName: "number")
          .font(.title3)
          .foregroundColor(.secondary)
          .frame(width: 40)
        
        Text("#\(tag.name)")
          .font(.headline)
          .foregroundColor(.primary)
        
        Spacer()
        
        // Platform indicator
        PlatformIndicator(platform: tag.platform)
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 16)
    }
    .buttonStyle(PlainButtonStyle())
  }
}

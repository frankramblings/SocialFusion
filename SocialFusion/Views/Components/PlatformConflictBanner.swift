import SwiftUI

/// Shows warnings when features don't map cleanly across platforms
struct PlatformConflictBanner: View {
  let conflicts: [PlatformConflict]
  let onTap: () -> Void
  
  var body: some View {
    if !conflicts.isEmpty {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundColor(.orange)
          .font(.caption)
        
        VStack(alignment: .leading, spacing: 2) {
          Text(conflicts.first?.message ?? "Some features may not apply to all platforms")
            .font(.caption)
            .foregroundColor(.primary)
          
          if conflicts.count > 1 {
            Text("Tap for details")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        
        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(Color.orange.opacity(0.1))
      .cornerRadius(8)
      .onTapGesture {
        onTap()
      }
    }
  }
}

/// Represents a platform conflict
struct PlatformConflict: Identifiable {
  let id = UUID()
  let feature: String
  let platforms: [SocialPlatform]
  
  var message: String {
    let platformNames = platforms.map { $0.rawValue.capitalized }.joined(separator: ", ")
    return "\(feature) will not apply to: \(platformNames)"
  }
}

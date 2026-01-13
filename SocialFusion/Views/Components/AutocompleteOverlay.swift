import SwiftUI

/// SwiftUI overlay positioned near caret for autocomplete suggestions
struct AutocompleteOverlay: View {
  let suggestions: [AutocompleteSuggestion]
  let token: AutocompleteToken
  let onSelect: (AutocompleteSuggestion) -> Void
  let onDismiss: () -> Void
  
  @State private var selectedIndex: Int = 0
  @FocusState private var isFocused: Bool
  
  var body: some View {
    GeometryReader { geometry in
      if !suggestions.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
            AutocompleteSuggestionRow(
              suggestion: suggestion,
              isSelected: index == selectedIndex
            )
            .onTapGesture {
              onSelect(suggestion)
            }
          }
        }
        .background(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(UIColor.systemBackground))
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .frame(maxWidth: 300)
        .position(
          x: max(150, min(geometry.size.width - 150, token.caretRect.midX)),
          y: min(
            token.caretRect.maxY + 8 + CGFloat(min(suggestions.count, 5)) * 44 / 2,
            geometry.size.height - 100 // Keep above keyboard
          )
        )
        .onAppear {
          isFocused = true
        }
        .modifier(KeyboardNavigationModifier(
          selectedIndex: $selectedIndex,
          suggestions: suggestions,
          onSelect: onSelect,
          onDismiss: onDismiss
        ))
      }
    }
    .allowsHitTesting(true)
  }
}

/// Row view for a single autocomplete suggestion
struct AutocompleteSuggestionRow: View {
  let suggestion: AutocompleteSuggestion
  let isSelected: Bool
  
  var body: some View {
    HStack(spacing: 12) {
      // Avatar (for mentions)
      if let avatarURL = suggestion.avatarURL, let url = URL(string: avatarURL) {
        AsyncImage(url: url) { image in
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        } placeholder: {
          Circle()
            .fill(Color.gray.opacity(0.3))
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
      } else if suggestion.entityPayload.platform == .mastodon || suggestion.entityPayload.platform == .bluesky {
        // Placeholder circle for mentions without avatar
        Circle()
          .fill(Color.gray.opacity(0.3))
          .frame(width: 32, height: 32)
          .overlay(
            Text(suggestion.displayText.prefix(1).uppercased())
              .font(.caption)
              .foregroundColor(.secondary)
          )
      }
      
      // Text content
      VStack(alignment: .leading, spacing: 2) {
        Text(suggestion.displayText)
          .font(.subheadline)
          .fontWeight(.medium)
          .foregroundColor(.primary)
          .lineLimit(1)
        
        if let subtitle = suggestion.subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
      }
      
      Spacer()
      
      // Platform badges
      HStack(spacing: 4) {
        ForEach(Array(suggestion.platforms), id: \.self) { platform in
          Text(platform == .mastodon ? "M" : "B")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
              Capsule()
                .fill(platform == .mastodon ? Color(red: 99/255, green: 100/255, blue: 255/255) : Color(red: 0, green: 133/255, blue: 255/255))
            )
        }
      }
      
      // Recent/Followed indicators
      if suggestion.isRecent {
        Image(systemName: "clock.fill")
          .font(.caption2)
          .foregroundColor(.secondary)
      }
      if suggestion.isFollowed {
        Image(systemName: "checkmark.circle.fill")
          .font(.caption2)
          .foregroundColor(.blue)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(isSelected ? Color(UIColor.secondarySystemBackground) : Color.clear)
    .contentShape(Rectangle())
  }
}

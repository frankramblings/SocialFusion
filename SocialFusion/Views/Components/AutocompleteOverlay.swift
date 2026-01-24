import SwiftUI

/// SwiftUI overlay positioned near caret for autocomplete suggestions
struct AutocompleteOverlay: View {
  let suggestions: [AutocompleteSuggestion]
  let token: AutocompleteToken
  let onSelect: (AutocompleteSuggestion) -> Void
  let onDismiss: () -> Void
  
  @State private var selectedIndex: Int = 0
  @FocusState private var isFocused: Bool
  
  // Constants for height management
  private let maxVisibleItems: CGFloat = 5.5  // Show ~5.5 items before scrolling
  private let rowHeight: CGFloat = 48  // Approximate height per row (padding + content)
  private var maxHeight: CGFloat {
    maxVisibleItems * rowHeight
  }
  private var contentHeight: CGFloat {
    CGFloat(suggestions.count) * rowHeight
  }
  private var overlayHeight: CGFloat {
    min(contentHeight, maxHeight)
  }
  
  var body: some View {
    GeometryReader { geometry in
      if !suggestions.isEmpty {
        ScrollViewReader { proxy in
          ScrollView {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                AutocompleteSuggestionRow(
                  suggestion: suggestion,
                  isSelected: index == selectedIndex
                )
                .id(index)
                .onTapGesture {
                  onSelect(suggestion)
                }
              }
            }
          }
          .frame(height: overlayHeight)
          .onChange(of: selectedIndex) { _, newIndex in
            // Scroll selected item into view when navigating with keyboard
            withAnimation(.easeInOut(duration: 0.2)) {
              proxy.scrollTo(newIndex, anchor: .center)
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
            token.caretRect.maxY + 8 + overlayHeight / 2,
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
          Image(platform.icon)
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(platform == .mastodon 
              ? Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
              : Color(red: 0, green: 133 / 255, blue: 255 / 255))  // #0085FF
            .frame(width: 12, height: 12)
        }
      }
      
      // Recent indicator
      if suggestion.isRecent {
        Image(systemName: "clock.fill")
          .font(.caption2)
          .foregroundColor(.secondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(isSelected ? Color(UIColor.secondarySystemBackground) : Color.clear)
    .contentShape(Rectangle())
  }
}

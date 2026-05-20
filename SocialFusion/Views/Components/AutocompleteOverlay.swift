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
                  HapticEngine.selection.trigger()
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
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
            .shadow(color: Color.black.opacity(0.06), radius: 1, x: 0, y: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            .fill(Color(.systemGray5))
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
      } else if suggestion.entityPayload.platform == .mastodon || suggestion.entityPayload.platform == .bluesky {
        // Placeholder circle for mentions without avatar
        Circle()
          .fill(Color(.systemGray5))
          .frame(width: 32, height: 32)
          .overlay(
            Text(suggestion.displayText.prefix(1).uppercased())
              .font(.caption.weight(.semibold))
              .foregroundColor(.secondary)
          )
      }

      // Text content
      VStack(alignment: .leading, spacing: 2) {
        Text(suggestion.displayText)
          .font(.subheadline.weight(.medium))
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

      // Platform badges — use template renderer with hex brand colors
      // (already on-brand; the explicit hex calls survive here because
      // SwiftUI doesn't have a Color.brand(.mastodon) extension yet).
      HStack(spacing: 4) {
        ForEach(Array(suggestion.platforms), id: \.self) { platform in
          Image(platform.icon)
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(platform == .mastodon
              ? Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)
              : Color(red: 0, green: 133 / 255, blue: 255 / 255))
            .frame(width: 12, height: 12)
        }
      }

      // Recent indicator — hierarchical so it picks up theme contrast
      if suggestion.isRecent {
        Image(systemName: "clock.fill")
          .font(.caption2)
          .foregroundStyle(Color.secondary.gradient)
          .symbolRenderingMode(.hierarchical)
          .accessibilityLabel("Recent")
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      // Accent-tinted highlight for the keyboard-selected row, matching
      // the menu-row press treatment used in NavBarPillDropdownRow.
      isSelected
        ? Color.accentColor.opacity(0.12)
        : Color.clear
    )
    .animation(.easeOut(duration: 0.12), value: isSelected)
    .contentShape(Rectangle())
  }
}

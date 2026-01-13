import SwiftUI

/// Keyboard navigation modifier compatible with iOS 16+
struct KeyboardNavigationModifier: ViewModifier {
  @Binding var selectedIndex: Int
  let suggestions: [AutocompleteSuggestion]
  let onSelect: (AutocompleteSuggestion) -> Void
  let onDismiss: () -> Void
  
  func body(content: Content) -> some View {
    if #available(iOS 17.0, *) {
      content
        .onKeyPress(.escape) {
          onDismiss()
          return .handled
        }
        .onKeyPress(.upArrow) {
          selectedIndex = max(0, selectedIndex - 1)
          return .handled
        }
        .onKeyPress(.downArrow) {
          selectedIndex = min(suggestions.count - 1, selectedIndex + 1)
          return .handled
        }
        .onKeyPress(.return) {
          if selectedIndex < suggestions.count {
            onSelect(suggestions[selectedIndex])
          }
          return .handled
        }
        .onKeyPress(.tab) {
          if selectedIndex < suggestions.count {
            onSelect(suggestions[selectedIndex])
          }
          return .handled
        }
    } else {
      // iOS 16 fallback: keyboard navigation handled via focus state
      // Users can still tap to select
      content
    }
  }
}

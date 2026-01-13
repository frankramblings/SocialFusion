import Foundation

/// Protocol for autocomplete suggestion providers
/// Enables composable, testable autocomplete architecture
public protocol SuggestionProvider: Sendable {
  /// Get suggestions for a token
  func suggestions(for token: AutocompleteToken) async -> [AutocompleteSuggestion]
  
  /// Priority for ranking (lower = higher priority)
  var priority: Int { get }
  
  /// Whether this provider can handle the token prefix
  func canHandle(prefix: String) -> Bool
}

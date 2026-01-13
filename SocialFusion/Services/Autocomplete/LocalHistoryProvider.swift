import Foundation

/// Provider for local history (recent/frequently used) suggestions
/// Wraps AutocompleteCache logic
@MainActor
public class LocalHistoryProvider: SuggestionProvider {
  
  public let priority: Int = 1 // Highest priority
  
  private let cache: AutocompleteCache
  
  public init(cache: AutocompleteCache = AutocompleteCache.shared) {
    self.cache = cache
  }
  
  public func canHandle(prefix: String) -> Bool {
    return prefix == "@" || prefix == "#" || prefix == ":"
  }
  
  public func suggestions(for token: AutocompleteToken) async -> [AutocompleteSuggestion] {
    guard canHandle(prefix: token.prefix) else {
      return []
    }
    
    var suggestions: [AutocompleteSuggestion] = []
    
    // Get account ID from token scope
    let accountId = token.scope.first?.split(separator: ":").last.map(String.init) ?? ""
    
    switch token.prefix {
    case "@":
      // Get recent mentions
      let recent = cache.getRecentMentions(accountId: accountId, queryPrefix: token.query.lowercased())
      suggestions.append(contentsOf: recent)
      
      // Get frequently used
      if !token.query.isEmpty {
        let frequentlyUsed = cache.getFrequentlyUsed(accountId: accountId, queryPrefix: token.query.lowercased())
        suggestions.append(contentsOf: frequentlyUsed)
      }
      
    case "#":
      // Get recent hashtags
      let recent = cache.getRecentHashtags(accountId: accountId, queryPrefix: token.query.lowercased())
      suggestions.append(contentsOf: recent)
      
      // Get frequently used
      if !token.query.isEmpty {
        let frequentlyUsed = cache.getFrequentlyUsed(accountId: accountId, queryPrefix: token.query.lowercased())
        suggestions.append(contentsOf: frequentlyUsed)
      }
      
    case ":":
      // Emoji are handled by EmojiService, not cache
      // Return empty for now (emoji provider can be added separately)
      break
      
    default:
      break
    }
    
    return suggestions
  }
}

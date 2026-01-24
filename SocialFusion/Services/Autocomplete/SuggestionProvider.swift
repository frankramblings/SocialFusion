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

/// Provider for emoji suggestions (custom Mastodon emoji and system emoji)
public final class EmojiSuggestionProvider: SuggestionProvider, @unchecked Sendable {
  
  public let priority: Int = 2 // Higher than network, lower than history/context
  
  private let emojiService: EmojiService
  private let accounts: [SocialAccount]
  
  public init(emojiService: EmojiService? = nil, accounts: [SocialAccount] = []) {
    self.emojiService = emojiService ?? .shared
    self.accounts = accounts
  }
  
  public func canHandle(prefix: String) -> Bool {
    return prefix == ":"
  }
  
  public func suggestions(for token: AutocompleteToken) async -> [AutocompleteSuggestion] {
    guard canHandle(prefix: token.prefix) else {
      return []
    }
    
    // For emoji, we search across all active accounts
    var allSuggestions: [AutocompleteSuggestion] = []
    
    // Use TaskGroup to search in parallel if multiple accounts
    await withTaskGroup(of: [AutocompleteSuggestion].self) { group in
      for destinationID in token.scope {
        let components = destinationID.split(separator: ":")
        guard components.count == 2,
              let platform = SocialPlatform(rawValue: String(components[0])),
              let account = accounts.first(where: { $0.id == String(components[1]) && $0.platform == platform }) else {
          continue
        }
        
        if platform == .mastodon {
          group.addTask {
            // This is an async context, so we can await the MainActor-isolated emojiService
            return await self.emojiService.searchEmoji(query: token.query, account: account)
          }
        }
      }
      
      // Collect results
      for await accountSuggestions in group {
        allSuggestions.append(contentsOf: accountSuggestions)
      }
    }
    
    // If no accounts or no results, try system emoji search directly
    if allSuggestions.isEmpty {
      allSuggestions = await emojiService.searchEmoji(query: token.query, account: accounts.first ?? SocialAccount(id: "system", username: "system", platform: .mastodon))
    }
    
    // Deduplicate by ID
    var uniqueSuggestions: [AutocompleteSuggestion] = []
    var seenIds = Set<String>()
    for suggestion in allSuggestions {
      if !seenIds.contains(suggestion.id) {
        uniqueSuggestions.append(suggestion)
        seenIds.insert(suggestion.id)
      }
    }
    
    return uniqueSuggestions
  }
}


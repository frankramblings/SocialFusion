import Foundation

/// Provider for network-based suggestions (Mastodon/Bluesky API calls)
/// Wraps existing network search logic from AutocompleteService
@MainActor
public class NetworkSuggestionProvider: SuggestionProvider {
  
  public let priority: Int = 3 // Lowest priority (after local history and timeline context)
  
  private let mastodonService: MastodonService?
  private let blueskyService: BlueskyService?
  private let accounts: [SocialAccount]
  
  public init(
    mastodonService: MastodonService? = nil,
    blueskyService: BlueskyService? = nil,
    accounts: [SocialAccount] = []
  ) {
    self.mastodonService = mastodonService
    self.blueskyService = blueskyService
    self.accounts = accounts
  }
  
  public func canHandle(prefix: String) -> Bool {
    return prefix == "@" || prefix == "#" || prefix == ":"
  }
  
  public func suggestions(for token: AutocompleteToken) async -> [AutocompleteSuggestion] {
    guard canHandle(prefix: token.prefix) else {
      return []
    }
    
    // Skip network calls for empty queries
    if token.query.isEmpty {
      return []
    }
    
    var suggestions: [AutocompleteSuggestion] = []
    
    // Search across active destinations
    for destinationID in token.scope {
      let components = destinationID.split(separator: ":")
      guard components.count == 2,
            let platform = SocialPlatform(rawValue: String(components[0])),
            let account = accounts.first(where: { $0.id == String(components[1]) && $0.platform == platform }) else {
        continue
      }
      
      do {
        switch token.prefix {
        case "@":
          let userSuggestions = try await searchUsers(query: token.query, account: account, platform: platform)
          suggestions.append(contentsOf: userSuggestions)
          
        case "#":
          let tagSuggestions = try await searchHashtags(query: token.query, account: account, platform: platform)
          suggestions.append(contentsOf: tagSuggestions)
          
        case ":":
          // Emoji search (local, no network error)
          let emojiService = EmojiService(mastodonService: mastodonService, accounts: [account])
          let emojiSuggestions = await emojiService.searchEmoji(query: token.query, account: account)
          suggestions.append(contentsOf: emojiSuggestions)
          
        default:
          break
        }
      } catch {
        // Network error - log but continue to other destinations
        print("❌ NetworkSuggestionProvider: Error searching \(platform.rawValue): \(error.localizedDescription)")
        // Continue to next destination
      }
    }
    
    return suggestions
  }
  
  // MARK: - Private Search Methods
  
  private func searchUsers(query: String, account: SocialAccount, platform: SocialPlatform) async throws -> [AutocompleteSuggestion] {
    switch platform {
    case .mastodon:
      guard let service = mastodonService else { return [] }
      
      // First try with type=accounts parameter
      do {
        let result = try await service.search(query: query, account: account, type: "accounts", limit: 20)
        return result.accounts.map { account in
          let searchUser = SearchUser(
            id: account.id,
            username: account.acct,
            displayName: account.displayName,
            avatarURL: account.avatar,
            platform: .mastodon
          )
          return AutocompleteSuggestion.from(searchUser: searchUser)
        }
      } catch {
        // If 500 error, try without type parameter (fallback logic)
        let errorMessage = error.localizedDescription
        if errorMessage.contains("500") || errorMessage.contains("status 500") {
          print("⚠️ NetworkSuggestionProvider: Mastodon search with type=accounts failed (500), trying without type parameter")
          do {
            let result = try await service.search(query: query, account: account, type: nil, limit: 20)
            print("✅ NetworkSuggestionProvider: Fallback Mastodon search returned \(result.accounts.count) accounts")
            return result.accounts.map { account in
              let searchUser = SearchUser(
                id: account.id,
                username: account.acct,
                displayName: account.displayName,
                avatarURL: account.avatar,
                platform: .mastodon
              )
              return AutocompleteSuggestion.from(searchUser: searchUser)
            }
          } catch {
            // If fallback also fails, return empty
            print("❌ NetworkSuggestionProvider: Fallback Mastodon search also failed: \(error.localizedDescription)")
            return []
          }
        } else {
          // Non-500 error, rethrow
          throw error
        }
      }
      
    case .bluesky:
      guard let service = blueskyService else { return [] }
      let result = try await service.searchActors(query: query, account: account, limit: 20)
      return result.actors.map { actor in
        let searchUser = SearchUser(
          id: actor.did,
          username: actor.handle,
          displayName: actor.displayName,
          avatarURL: actor.avatar,
          platform: .bluesky
        )
        return AutocompleteSuggestion.from(searchUser: searchUser)
      }
    }
  }
  
  private func searchHashtags(query: String, account: SocialAccount, platform: SocialPlatform) async throws -> [AutocompleteSuggestion] {
    switch platform {
    case .mastodon:
      guard let service = mastodonService else { return [] }
      let result = try await service.search(query: query, account: account, type: "hashtags", limit: 20)
      return result.hashtags.map { tag in
        let searchTag = SearchTag(id: tag.name, name: tag.name, platform: .mastodon)
        return AutocompleteSuggestion.from(searchTag: searchTag)
      }
      
    case .bluesky:
      // Bluesky lacks first-class hashtag search - return empty
      return []
    }
  }
}

import Foundation

/// Coordinates autocomplete search across networks with stale-result rejection and caching
@MainActor
public class AutocompleteService: ObservableObject {
  /// Tracks active search request ID
  private var currentRequestID: UUID?
  
  /// Last request that updated UI
  private var lastAppliedRequestID: UUID?
  
  /// Active search task (for cancellation)
  private var activeSearchTask: Task<Void, Never>?
  
  /// Cache for autocomplete results
  private let cache: AutocompleteCache
  
  /// Mastodon service for account/hashtag search
  private let mastodonService: MastodonService?
  
  /// Bluesky service for actor search
  private let blueskyService: BlueskyService?
  
  /// Available accounts for searching
  private let accounts: [SocialAccount]
  
  /// Network error state
  @Published public var networkError: String? = nil
  
  /// Whether a network request is currently in progress
  @Published public var isSearching: Bool = false
  
  public init(
    cache: AutocompleteCache = AutocompleteCache.shared,
    mastodonService: MastodonService? = nil,
    blueskyService: BlueskyService? = nil,
    accounts: [SocialAccount] = []
  ) {
    self.cache = cache
    self.mastodonService = mastodonService
    self.blueskyService = blueskyService
    self.accounts = accounts
  }
  
  /// Search for autocomplete suggestions with debouncing
  /// - Parameter token: The autocomplete token to search for
  /// - Returns: Array of suggestions, empty if no results or stale
  public func searchRequest(token: AutocompleteToken) async -> [AutocompleteSuggestion] {
    // Generate new request ID
    let requestID = UUID()
    currentRequestID = requestID
    
    // Cancel previous request if exists
    activeSearchTask?.cancel()
    activeSearchTask = nil
    
    // Check minimum query length (immediate fetch on first char)
    let minLength = 0 // Allow empty query for recent results
      guard token.query.count >= minLength else {
      // Return recent results for empty query (immediate, no debounce)
      isSearching = false
      if token.prefix == "@" {
        return cache.getRecentMentions(accountId: token.scope.first?.split(separator: ":").last.map(String.init) ?? "", queryPrefix: "")
      } else if token.prefix == "#" {
        return cache.getRecentHashtags(accountId: token.scope.first?.split(separator: ":").last.map(String.init) ?? "", queryPrefix: "")
      }
      return []
    }
    
    // Check cache first (immediate, no debounce)
    let cacheKey = makeCacheKey(token: token)
    if let cached = cache.get(key: cacheKey) {
      // Validate document revision matches
      if token.documentRevision == token.documentRevision {
        lastAppliedRequestID = requestID
        isSearching = false
        return cached
      }
    }
    
    // Debounce: immediate fetch for first character, then 200ms delay
    let debounceDelay: UInt64 = token.query.count == 1 ? 0 : 200_000_000 // 200ms in nanoseconds
    
    // Create debounced search task
    let searchTask = Task { @MainActor [weak self] () -> [AutocompleteSuggestion] in
      guard let self = self else { return [] }
      
      // Wait for debounce delay
      if debounceDelay > 0 {
        try? await Task.sleep(nanoseconds: debounceDelay)
      }
      
      // Check if request is still current after debounce
      guard self.currentRequestID == requestID else {
        self.isSearching = false
        return [] // Stale request, return empty
      }
      
      // Check if task was cancelled
      guard !Task.isCancelled else {
        self.isSearching = false
        return []
      }
      
      // Perform search
      var suggestions: [AutocompleteSuggestion] = []
      
      // Get account ID from token scope (for frequently used lookup)
      let accountId = token.scope.first?.split(separator: ":").last.map(String.init) ?? ""
      
      // Add frequently used suggestions matching query
      if !token.query.isEmpty {
        let frequentlyUsedSuggestions = cache.getFrequentlyUsed(accountId: accountId, queryPrefix: token.query.lowercased())
        suggestions.append(contentsOf: frequentlyUsedSuggestions)
      }
      
      // Search across active destinations
      for destinationID in token.scope {
        let components = destinationID.split(separator: ":")
        guard components.count == 2,
              let platform = SocialPlatform(rawValue: String(components[0])),
              let account = self.accounts.first(where: { $0.id == String(components[1]) && $0.platform == platform }) else {
          continue
        }
        
        // Check if request is still current
        guard self.currentRequestID == requestID, !Task.isCancelled else {
          self.isSearching = false
          return [] // Stale request, return empty
        }
        
        // Search based on prefix with error handling
        do {
          switch token.prefix {
          case "@":
            let userSuggestions = try await self.searchUsersWithError(query: token.query, account: account, platform: platform)
            suggestions.append(contentsOf: userSuggestions)
          case "#":
            let tagSuggestions = try await self.searchHashtagsWithError(query: token.query, account: account, platform: platform)
            suggestions.append(contentsOf: tagSuggestions)
          case ":":
            // Emoji search (local, no network error)
            let emojiService = EmojiService(mastodonService: self.mastodonService, accounts: [account])
            let emojiSuggestions = await emojiService.searchEmoji(query: token.query, account: account)
            suggestions.append(contentsOf: emojiSuggestions)
          default:
            break
          }
        } catch {
          // Network error - set error state but continue to other destinations
          self.networkError = error.localizedDescription
          // Still return cached/recent results if available
        }
      }
      
      // Check if request is still current before applying results
      guard self.currentRequestID == requestID, !Task.isCancelled else {
        self.isSearching = false
        return [] // Stale request, return empty
      }
      
      // Set error state if network failed (but still return cached/partial results)
      if self.networkError != nil && suggestions.isEmpty {
        // No results and network error - show error state
      } else if self.networkError != nil {
        // Partial results despite error - clear error if we have results
        self.networkError = nil
      }
      
      // Rank results: recents → frequently used → followed → server results
      suggestions = self.rankSuggestions(suggestions)
      
      // Deduplicate (default to separate rows, merge only with confirmed mapping)
      suggestions = self.deduplicateSuggestions(suggestions)
      
      // Cache results (even partial ones)
      if !suggestions.isEmpty {
        self.cache.set(key: cacheKey, value: suggestions, ttl: 30) // 30 second TTL
      }
      
      // Mark as applied
      self.lastAppliedRequestID = requestID
      self.isSearching = false
      
      return suggestions
    }
    
    // Store task for cancellation
    activeSearchTask = Task { @MainActor in
      _ = await searchTask.value
    }
    
    return await searchTask.value
  }
  
  /// Search for users (mentions) - internal method without error throwing
  private func searchUsers(query: String, account: SocialAccount, platform: SocialPlatform) async -> [AutocompleteSuggestion] {
    do {
      return try await searchUsersWithError(query: query, account: account, platform: platform)
    } catch {
      return []
    }
  }
  
  /// Search for users (mentions) with error handling
  private func searchUsersWithError(query: String, account: SocialAccount, platform: SocialPlatform) async throws -> [AutocompleteSuggestion] {
    switch platform {
    case .mastodon:
      guard let service = mastodonService else { return [] }
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
  
  /// Search for hashtags - internal method without error throwing
  private func searchHashtags(query: String, account: SocialAccount, platform: SocialPlatform) async -> [AutocompleteSuggestion] {
    do {
      return try await searchHashtagsWithError(query: query, account: account, platform: platform)
    } catch {
      return []
    }
  }
  
  /// Search for hashtags with error handling
  private func searchHashtagsWithError(query: String, account: SocialAccount, platform: SocialPlatform) async throws -> [AutocompleteSuggestion] {
    switch platform {
    case .mastodon:
      guard let service = mastodonService else { return [] }
      let result = try await service.search(query: query, account: account, type: "hashtags", limit: 20)
      return result.hashtags.map { tag in
        let searchTag = SearchTag(id: tag.name, name: tag.name, platform: .mastodon)
        return AutocompleteSuggestion.from(searchTag: searchTag)
      }
    case .bluesky:
      // Bluesky lacks first-class hashtag search - fallback to local cache (no error)
      return cache.getRecentHashtags(accountId: account.id, queryPrefix: query.lowercased())
    }
  }
  
  /// Rank suggestions: recents → frequently used → followed → server results
  private func rankSuggestions(_ suggestions: [AutocompleteSuggestion]) -> [AutocompleteSuggestion] {
    // Deduplicate by ID first (keep first occurrence)
    var seenIds = Set<String>()
    var deduplicated: [AutocompleteSuggestion] = []
    for suggestion in suggestions {
      if !seenIds.contains(suggestion.id) {
        seenIds.insert(suggestion.id)
        deduplicated.append(suggestion)
      }
    }
    
    return deduplicated.sorted { lhs, rhs in
      // Recents first
      if lhs.isRecent != rhs.isRecent {
        return lhs.isRecent
      }
      // Frequently used next (if both are frequently used, keep original order)
      // Note: Frequently used are already sorted by usage count in cache
      // Followed next
      if lhs.isFollowed != rhs.isFollowed {
        return lhs.isFollowed
      }
      // Then by display text
      return lhs.displayText < rhs.displayText
    }
  }
  
  /// Deduplicate suggestions (default to separate rows)
  private func deduplicateSuggestions(_ suggestions: [AutocompleteSuggestion]) -> [AutocompleteSuggestion] {
    // Default: separate rows with platform badges
    // Only merge if we have confirmed canonical mapping (rare)
    // For now, return as-is (UI will show separate rows)
    return suggestions
  }
  
  /// Make cache key from token
  private func makeCacheKey(token: AutocompleteToken) -> String {
    let accountIds = token.scope.joined(separator: ",")
    return "\(accountIds)_\(token.prefix)_\(token.query.lowercased())"
  }
  
  /// Cancel current search
  public func cancelSearch() {
    activeSearchTask?.cancel()
    activeSearchTask = nil
    currentRequestID = nil
  }
}

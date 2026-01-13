import Foundation

/// Coordinates autocomplete search across networks with stale-result rejection and caching
/// Uses composable suggestion providers for extensibility and testability
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
  
  /// Suggestion providers (in priority order)
  private let suggestionProviders: [SuggestionProvider]
  
  /// Timeline context provider (optional, for timeline-aware ranking)
  private let timelineContextProvider: TimelineContextProvider?
  
  /// Timeline scope for context queries
  private let timelineScope: AutocompleteTimelineScope
  
  /// Mastodon service for account/hashtag search (kept for backward compatibility)
  private let mastodonService: MastodonService?
  
  /// Bluesky service for actor search (kept for backward compatibility)
  private let blueskyService: BlueskyService?
  
  /// Available accounts for searching (kept for backward compatibility)
  private let accounts: [SocialAccount]
  
  /// Network error state
  @Published public var networkError: String? = nil
  
  /// Whether a network request is currently in progress
  @Published public var isSearching: Bool = false
  
  public init(
    cache: AutocompleteCache = AutocompleteCache.shared,
    mastodonService: MastodonService? = nil,
    blueskyService: BlueskyService? = nil,
    accounts: [SocialAccount] = [],
    suggestionProviders: [SuggestionProvider]? = nil,
    timelineContextProvider: TimelineContextProvider? = nil,
    timelineScope: AutocompleteTimelineScope = .unified
  ) {
    self.cache = cache
    self.mastodonService = mastodonService
    self.blueskyService = blueskyService
    self.accounts = accounts
    self.timelineContextProvider = timelineContextProvider
    self.timelineScope = timelineScope
    
    // Use provided providers or create default ones for backward compatibility
    if let providers = suggestionProviders {
      self.suggestionProviders = providers.sorted { $0.priority < $1.priority }
    } else {
      // Default providers: LocalHistoryProvider + NetworkSuggestionProvider
      var defaultProviders: [SuggestionProvider] = []
      defaultProviders.append(LocalHistoryProvider(cache: cache))
      defaultProviders.append(NetworkSuggestionProvider(
        mastodonService: mastodonService,
        blueskyService: blueskyService,
        accounts: accounts
      ))
      self.suggestionProviders = defaultProviders.sorted { $0.priority < $1.priority }
    }
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
    
    // For empty queries, return cached/recent results only (no network calls)
    if token.query.isEmpty {
      isSearching = false
      var suggestions: [AutocompleteSuggestion] = []
      
      // Query local history provider only (no network calls)
      let localProviders = self.suggestionProviders.filter { provider in
        provider.canHandle(prefix: token.prefix) && provider.priority == 1 // LocalHistoryProvider
      }
      
      for provider in localProviders {
        let providerSuggestions = await provider.suggestions(for: token)
        suggestions.append(contentsOf: providerSuggestions)
      }
      
      // Get timeline context if available
      let contextSnapshot = self.timelineContextProvider?.snapshot(for: self.timelineScope)
      
      // Rank and deduplicate
      suggestions = AutocompleteRanker.rank(suggestions, context: contextSnapshot)
      suggestions = self.deduplicateSuggestions(suggestions)
      
      lastAppliedRequestID = requestID
      return suggestions
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
      
      // Perform search using providers
      var suggestions: [AutocompleteSuggestion] = []
      
      // Query all providers in parallel (only those that can handle this prefix)
      let relevantProviders = self.suggestionProviders.filter { $0.canHandle(prefix: token.prefix) }
      
      // Query providers concurrently
      await withTaskGroup(of: [AutocompleteSuggestion].self) { group in
        for provider in relevantProviders {
          group.addTask {
            await provider.suggestions(for: token)
          }
        }
        
        // Collect results from all providers
        for await providerSuggestions in group {
          suggestions.append(contentsOf: providerSuggestions)
        }
      }
      
      // Check if request is still current before applying results
      guard self.currentRequestID == requestID, !Task.isCancelled else {
        self.isSearching = false
        return [] // Stale request, return empty
      }
      
      // Get timeline context snapshot for ranking
      let contextSnapshot = self.timelineContextProvider?.snapshot(for: self.timelineScope)
      
      // Rank suggestions using AutocompleteRanker
      suggestions = AutocompleteRanker.rank(suggestions, context: contextSnapshot)
      
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
  
  // Note: Old search methods removed - now handled by NetworkSuggestionProvider
  // Keeping rankSuggestions as fallback for backward compatibility, but AutocompleteRanker is preferred
  
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

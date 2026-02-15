import Foundation
import Combine

/// Store for managing search state, caching, and pagination
@MainActor
public class SearchStore: ObservableObject {
  // MARK: - Published Properties
  
  @Published public var text: String = "" {
    didSet {
      if text != oldValue {
        handleTextChange()
      }
    }
  }
  
  @Published public var scope: SearchScope = .posts {
    didSet {
      if scope != oldValue {
        handleScopeChange()
      }
    }
  }
  
  @Published public var networkSelection: SearchNetworkSelection = .unified {
    didSet {
      if networkSelection != oldValue {
        handleNetworkChange()
      }
    }
  }
  
  @Published public var phase: SearchPhase = .idle
  
  @Published public var results: [SearchResultItem] = []
  
  @Published public var resultsSections: [SearchResultsSection] = []
  
  @Published public var chipRowModel: SearchChipRowModel?
  
  @Published public var directOpenTarget: DirectOpenTarget?
  
  @Published public var recentSearches: [String] = []
  
  @Published public var pinnedSearches: [SavedSearch] = []
  
  // MARK: - Private Properties
  
  private var searchTask: Task<Void, Never>?
  private var debounceTask: Task<Void, Never>?
  private let searchProvider: SearchProviding
  private let cache: SearchCache
  private let capabilitiesStorage: SearchCapabilitiesStorage
  private let recentSearchesStorage: RecentSearchesStorage
  private let savedSearchesStorage: SavedSearchStorage
  private let accountId: String
  
  private var nextPageTokens: [String: SearchPageToken] = [:]
  private var isRefreshing = false
  
  // MARK: - Initialization
  
  public init(
    searchProvider: SearchProviding,
    cache: SearchCache = .shared,
    capabilitiesStorage: SearchCapabilitiesStorage = .shared,
    recentSearchesStorage: RecentSearchesStorage = .shared,
    savedSearchesStorage: SavedSearchStorage = .shared,
    accountId: String
  ) {
    self.searchProvider = searchProvider
    self.cache = cache
    self.capabilitiesStorage = capabilitiesStorage
    self.recentSearchesStorage = recentSearchesStorage
    self.savedSearchesStorage = savedSearchesStorage
    self.accountId = accountId
    
    loadRecentSearches()
    loadPinnedSearches()
  }
  
  // MARK: - Public Methods
  
  /// Perform search with debouncing
  public func performSearch() {
    cancelSearch()
    
    guard !text.isEmpty else {
      phase = .idle
      results = []
      resultsSections = []
      chipRowModel = nil
      return
    }
    
    // Check for direct-open
    checkDirectOpen()
    
    // Debounce search
    debounceTask?.cancel()
    debounceTask = Task {
      let delay: UInt64 = scope == .users ? 300_000_000 : 500_000_000 // 300ms for users, 500ms for others
      try? await Task.sleep(nanoseconds: delay)
      
      if !Task.isCancelled {
        await performSearchInternal()
      }
    }
  }
  
  /// Load next page of results
  public func loadNextPage() async {
    guard !nextPageTokens.isEmpty, phase != .loading else {
      return
    }
    
    phase = .loading
    
    do {
      let query = SearchQuery(
        text: text,
        scope: scope,
        networkSelection: networkSelection
      )
      
      let page = try await searchProvider.searchPosts(query: query, page: nextPageTokens.values.first)
      
      results.append(contentsOf: page.items)
      nextPageTokens.merge(page.nextPageTokens) { _, new in new }
      
      phase = .loaded
      updateChipRowModel()
    } catch {
      phase = .error(error.localizedDescription)
    }
  }
  
  /// Refresh search (ignores cache)
  public func refresh() async {
    isRefreshing = true
    cancelSearch()
    
    // Clear cache for this query
    let query = SearchQuery(
      text: text,
      scope: scope,
      networkSelection: networkSelection
    )
    cache.remove(key: query.cacheKey(accountId: accountId))
    
    await performSearchInternal(ignoreCache: true)
    isRefreshing = false
  }
  
  /// Add to recent searches
  public func addToRecentSearches(_ query: String) {
    recentSearchesStorage.addSearch(query, accountId: accountId, networkSelection: networkSelection)
    loadRecentSearches()
  }
  
  /// Clear recent searches
  public func clearRecentSearches() {
    recentSearchesStorage.clearSearches(accountId: accountId, networkSelection: networkSelection)
    loadRecentSearches()
  }
  
  /// Return search suggestions based on recent and pinned searches, optionally filtered by prefix.
  public func suggestions(for prefix: String) -> [String] {
    let pinned = pinnedSearches.map(\.query)
    let all = pinned + recentSearches
    // Deduplicate preserving order
    var seen = Set<String>()
    let unique = all.filter { seen.insert($0.lowercased()).inserted }
    guard !prefix.isEmpty else { return unique }
    return unique.filter { $0.lowercased().hasPrefix(prefix.lowercased()) }
  }

  // MARK: - Private Methods
  
  private func handleTextChange() {
    performSearch()
  }
  
  private func handleScopeChange() {
    performSearch()
  }
  
  private func handleNetworkChange() {
    performSearch()
  }
  
  private func cancelSearch() {
    searchTask?.cancel()
    debounceTask?.cancel()
    searchTask = nil
    debounceTask = nil
  }
  
  private func checkDirectOpen() {
    Task {
      do {
        directOpenTarget = try await searchProvider.resolveDirectOpen(input: text)
      } catch {
        directOpenTarget = nil
      }
    }
  }
  
  func performSearchInternal(ignoreCache: Bool = false) async {
    cancelSearch()
    
    guard !text.isEmpty else {
      phase = .idle
      return
    }
    
    let query = SearchQuery(
      text: text,
      scope: scope,
      networkSelection: networkSelection
    )
    
    let cacheKey = query.cacheKey(accountId: accountId)
    
    // Check cache first (unless refreshing)
    if !ignoreCache, let cached = cache.get(key: cacheKey) {
      results = cached.results
      nextPageTokens = cached.nextPageTokens
      phase = .showingCached
      updateChipRowModel()
      
      // Refresh in background
      Task {
        await performSearchInternal(ignoreCache: true)
      }
      return
    }
    
    if !ignoreCache {
      phase = .loading
    }

    do {
      let page: SearchPage

      switch scope {
      case .posts:
        page = try await searchProvider.searchPosts(query: query, page: nil)
      case .users:
        if text.count < 3 {
          // Use typeahead for short queries
          page = try await searchProvider.searchUsersTypeahead(text: text, page: nil)
        } else {
          page = try await searchProvider.searchUsers(query: query, page: nil)
        }
      case .tags:
        page = try await searchProvider.searchTags(query: query, page: nil)
      }

      results = page.items
      nextPageTokens = page.nextPageTokens

      // Update cache
      cache.set(key: cacheKey, results: results, nextPageTokens: nextPageTokens)

      // Update phase
      if results.isEmpty {
        phase = .empty
      } else {
        phase = .loaded
      }

      updateChipRowModel()
      addToRecentSearches(text)
    } catch {
      phase = .error(error.localizedDescription)
    }
  }
  
  private func updateChipRowModel() {
    let instanceDomain: String?
    if networkSelection == .mastodon || networkSelection == .unified {
      let capabilities = searchProvider.capabilities
      instanceDomain = capabilities.instanceDomain
    } else {
      instanceDomain = nil
    }
    
    chipRowModel = SearchChipRowModel(
      network: networkSelection,
      scope: scope,
      sort: nil,
      instanceDomain: instanceDomain,
      showInstanceInfo: searchProvider.capabilities.shouldShowStatusSearchWarning && scope == .posts
    )
  }
  
  private func loadRecentSearches() {
    recentSearches = recentSearchesStorage.getSearches(accountId: accountId, networkSelection: networkSelection)
  }
  
  private func loadPinnedSearches() {
    pinnedSearches = savedSearchesStorage.getSavedSearches()
  }
}

// MARK: - Recent Searches Storage

public class RecentSearchesStorage {
  public static let shared = RecentSearchesStorage()
  
  private let userDefaults = UserDefaults.standard
  private let maxRecentSearches = 10
  
  private init() {}
  
  public func addSearch(_ query: String, accountId: String, networkSelection: SearchNetworkSelection) {
    let key = "recentSearches_\(accountId)_\(networkSelection.rawValue)"
    var searches = getSearches(accountId: accountId, networkSelection: networkSelection)
    
    // Remove if already exists
    searches.removeAll { $0.lowercased() == query.lowercased() }
    
    // Add to front
    searches.insert(query, at: 0)
    
    // Limit size
    if searches.count > maxRecentSearches {
      searches = Array(searches.prefix(maxRecentSearches))
    }
    
    if let data = try? JSONEncoder().encode(searches) {
      userDefaults.set(data, forKey: key)
    }
  }
  
  public func getSearches(accountId: String, networkSelection: SearchNetworkSelection) -> [String] {
    let key = "recentSearches_\(accountId)_\(networkSelection.rawValue)"
    guard let data = userDefaults.data(forKey: key),
          let searches = try? JSONDecoder().decode([String].self, from: data) else {
      return []
    }
    return searches
  }
  
  public func clearSearches(accountId: String, networkSelection: SearchNetworkSelection) {
    let key = "recentSearches_\(accountId)_\(networkSelection.rawValue)"
    userDefaults.removeObject(forKey: key)
  }
}

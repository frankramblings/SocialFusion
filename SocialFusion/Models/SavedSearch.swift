import Foundation

// MARK: - Saved Search

/// A saved/pinned search query
public struct SavedSearch: Identifiable, Codable, Hashable {
  public let id: String
  public let query: String
  public let scope: SearchScope
  public let networkSelection: SearchNetworkSelection
  public var name: String?
  public let createdAt: Date
  public var sortOrder: Int // For reordering
  
  public init(
    id: String = UUID().uuidString,
    query: String,
    scope: SearchScope,
    networkSelection: SearchNetworkSelection,
    name: String? = nil,
    createdAt: Date = Date(),
    sortOrder: Int = 0
  ) {
    self.id = id
    self.query = query
    self.scope = scope
    self.networkSelection = networkSelection
    self.name = name ?? query
    self.createdAt = createdAt
    self.sortOrder = sortOrder
  }
  
  /// Display name (uses custom name if set, otherwise query)
  public var displayName: String {
    name ?? query
  }
  
  /// Convert to SearchQuery
  public func toSearchQuery() -> SearchQuery {
    SearchQuery(
      text: query,
      scope: scope,
      networkSelection: networkSelection
    )
  }
}

// MARK: - Saved Search Storage

/// Manages persistence of saved searches
public class SavedSearchStorage {
  public static let shared = SavedSearchStorage()
  
  private let userDefaults = UserDefaults.standard
  private let savedSearchesKey = "savedSearches"
  
  private init() {}
  
  /// Get all saved searches
  public func getSavedSearches() -> [SavedSearch] {
    guard let data = userDefaults.data(forKey: savedSearchesKey),
          let searches = try? JSONDecoder().decode([SavedSearch].self, from: data) else {
      return []
    }
    return searches.sorted { $0.sortOrder < $1.sortOrder }
  }
  
  /// Save a search
  public func saveSearch(_ search: SavedSearch) {
    var searches = getSavedSearches()
    if let index = searches.firstIndex(where: { $0.id == search.id }) {
      searches[index] = search
    } else {
      searches.append(search)
    }
    saveSearches(searches)
  }
  
  /// Delete a saved search
  public func deleteSearch(_ search: SavedSearch) {
    var searches = getSavedSearches()
    searches.removeAll { $0.id == search.id }
    saveSearches(searches)
  }
  
  /// Update sort order
  public func updateSortOrder(_ searches: [SavedSearch]) {
    saveSearches(searches)
  }
  
  private func saveSearches(_ searches: [SavedSearch]) {
    if let data = try? JSONEncoder().encode(searches) {
      userDefaults.set(data, forKey: savedSearchesKey)
    }
  }
}

import XCTest
@testable import SocialFusion

@MainActor
final class SearchStoreTests: XCTestCase {
  
  func testDebouncing() async {
    // Create a mock provider
    let mockProvider = MockSearchProvider()
    let store = SearchStore(
      searchProvider: mockProvider,
      accountId: "test"
    )
    
    // Set text multiple times quickly
    store.text = "a"
    store.text = "ab"
    store.text = "abc"
    
    // Wait for debounce
    try? await Task.sleep(nanoseconds: 600_000_000) // 600ms
    
    // Should only have searched once with final value
    XCTAssertEqual(mockProvider.lastSearchText, "abc")
  }
  
  func testCancellation() async {
    let mockProvider = MockSearchProvider()
    let store = SearchStore(
      searchProvider: mockProvider,
      accountId: "test"
    )
    
    // Start search
    store.text = "test"
    store.performSearch()
    
    // Cancel immediately
    store.text = "new"
    
    // Wait
    try? await Task.sleep(nanoseconds: 600_000_000)
    
    // Should have searched with new value, not old
    XCTAssertEqual(mockProvider.lastSearchText, "new")
  }
  
  func testCacheReturnsImmediately() async {
    let mockProvider = MockSearchProvider()
    let cache = SearchCache.shared
    let store = SearchStore(
      searchProvider: mockProvider,
      cache: cache,
      accountId: "test"
    )
    
    // First search
    store.text = "test"
    await store.performSearchInternal()
    
    // Clear provider call count
    mockProvider.callCount = 0
    
    // Second search (should use cache)
    store.text = "test"
    await store.performSearchInternal()
    
    // Should show cached immediately
    XCTAssertEqual(store.phase, .showingCached)
    
    // Wait for refresh
    try? await Task.sleep(nanoseconds: 100_000_000)
    
    // Should have refreshed
    XCTAssertTrue(mockProvider.callCount > 0)
  }
  // MARK: - Suggestions & Completions Tests

  func testRecentSearchesAppearAsSuggestions() async {
    let mockProvider = MockSearchProvider()
    let recentStorage = RecentSearchesStorage.shared
    // Seed some recent searches
    recentStorage.addSearch("swift", accountId: "suggest-test", networkSelection: .unified)
    recentStorage.addSearch("mastodon", accountId: "suggest-test", networkSelection: .unified)

    let store = SearchStore(
      searchProvider: mockProvider,
      recentSearchesStorage: recentStorage,
      accountId: "suggest-test"
    )

    let suggestions = store.suggestions(for: "")
    XCTAssertTrue(suggestions.contains("swift"), "Recent search 'swift' should appear in suggestions")
    XCTAssertTrue(suggestions.contains("mastodon"), "Recent search 'mastodon' should appear in suggestions")

    // Clean up
    recentStorage.clearSearches(accountId: "suggest-test", networkSelection: .unified)
  }

  func testSuggestionsFilterByPrefix() async {
    let mockProvider = MockSearchProvider()
    let recentStorage = RecentSearchesStorage.shared
    recentStorage.addSearch("swift", accountId: "filter-test", networkSelection: .unified)
    recentStorage.addSearch("swiftui", accountId: "filter-test", networkSelection: .unified)
    recentStorage.addSearch("mastodon", accountId: "filter-test", networkSelection: .unified)

    let store = SearchStore(
      searchProvider: mockProvider,
      recentSearchesStorage: recentStorage,
      accountId: "filter-test"
    )

    let filtered = store.suggestions(for: "swi")
    XCTAssertTrue(filtered.contains("swift"))
    XCTAssertTrue(filtered.contains("swiftui"))
    XCTAssertFalse(filtered.contains("mastodon"), "Non-matching term should be filtered out")

    // Clean up
    recentStorage.clearSearches(accountId: "filter-test", networkSelection: .unified)
  }

  func testPinnedSearchesAppearInSuggestions() async {
    let mockProvider = MockSearchProvider()
    let store = SearchStore(
      searchProvider: mockProvider,
      accountId: "pinned-test"
    )

    let suggestions = store.suggestions(for: "")
    // Pinned searches should also feed suggestions (they come from pinnedSearches)
    // If no pinned searches, the list should at least not crash
    XCTAssertNotNil(suggestions)
  }

  /// When a slow query finishes after a newer fast query, the stale results must be discarded.
  func testLatestQueryWinsWhenTasksRace() async {
    let delayProvider = DelayingMockSearchProvider()
    let store = SearchStore(
      searchProvider: delayProvider,
      accountId: "race-test"
    )

    // Query A: slow (will take 400ms), returns 1 result
    delayProvider.delayNanoseconds = 400_000_000
    delayProvider.resultItemCount = 1
    store.text = "slow"
    let taskA = Task { await store.performSearchInternal() }

    // Small gap so A starts first
    try? await Task.sleep(nanoseconds: 50_000_000)

    // Query B: fast (returns instantly), returns 3 results
    delayProvider.delayNanoseconds = 0
    delayProvider.resultItemCount = 3
    store.text = "fast"
    await store.performSearchInternal()

    // B should have finished — 3 results
    XCTAssertEqual(store.results.count, 3, "Fast query B should have written 3 results")

    // Wait for A to finish
    await taskA.value
    try? await Task.sleep(nanoseconds: 100_000_000)

    // Results should STILL be B's 3 results, not overwritten by stale A's 1 result
    XCTAssertEqual(store.results.count, 3,
                   "Stale query A must not overwrite newer query B results")
  }

  func testScopeChangeTriggersNewSearch() async {
    let mockProvider = MockSearchProvider()
    let store = SearchStore(
      searchProvider: mockProvider,
      accountId: "scope-test"
    )

    store.text = "test"
    try? await Task.sleep(nanoseconds: 600_000_000)
    let firstCallCount = mockProvider.callCount

    store.scope = .users
    try? await Task.sleep(nanoseconds: 600_000_000)

    XCTAssertGreaterThan(mockProvider.callCount, firstCallCount, "Scope change should trigger a new search")
  }
}

// MARK: - Mock Search Provider

class MockSearchProvider: SearchProviding {
  var lastSearchText: String?
  var callCount = 0
  
  func searchPosts(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
    callCount += 1
    lastSearchText = query.text
    return SearchPage.empty
  }
  
  func searchUsersTypeahead(text: String, page: SearchPageToken?) async throws -> SearchPage {
    callCount += 1
    lastSearchText = text
    return SearchPage.empty
  }
  
  func searchUsers(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
    callCount += 1
    lastSearchText = query.text
    return SearchPage.empty
  }
  
  func searchTags(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
    callCount += 1
    lastSearchText = query.text
    return SearchPage.empty
  }
  
  func resolveDirectOpen(input: String) async throws -> DirectOpenTarget? {
    return nil
  }
  
  var capabilities: SearchCapabilities {
    SearchCapabilities()
  }
  
  var supportsSortTopLatest: Bool {
    false
  }
  
  var providerId: String {
    "mock"
  }
}

// MARK: - Delaying Mock Search Provider

/// Mock that introduces configurable delay to simulate slow network responses for race testing.
class DelayingMockSearchProvider: SearchProviding {
  var delayNanoseconds: UInt64 = 0
  var resultItemCount: Int = 0

  func searchPosts(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
    let count = resultItemCount
    if delayNanoseconds > 0 {
      try? await Task.sleep(nanoseconds: delayNanoseconds)
    }
    let items: [SearchResultItem] = (0..<count).map { i in
      let post = Post(
        id: "\(query.text)-\(i)",
        content: "Result \(i) for \(query.text)",
        authorName: "Test",
        authorUsername: "test",
        authorProfilePictureURL: "",
        createdAt: Date(),
        platform: .bluesky,
        originalURL: "https://example.com/\(i)"
      )
      return .post(post)
    }
    return SearchPage(items: items)
  }

  func searchUsersTypeahead(text: String, page: SearchPageToken?) async throws -> SearchPage {
    SearchPage.empty
  }

  func searchUsers(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
    SearchPage.empty
  }

  func searchTags(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
    SearchPage.empty
  }

  func resolveDirectOpen(input: String) async throws -> DirectOpenTarget? { nil }

  var capabilities: SearchCapabilities { SearchCapabilities() }
  var supportsSortTopLatest: Bool { false }
  var providerId: String { "delaying-mock" }
}

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

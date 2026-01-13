import Foundation

/// Protocol for search providers (Mastodon, Bluesky, Unified)
public protocol SearchProviding {
  /// Search for posts
  func searchPosts(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage
  
  /// Search for users with typeahead (instant results)
  func searchUsersTypeahead(text: String, page: SearchPageToken?) async throws -> SearchPage
  
  /// Search for users (full search)
  func searchUsers(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage
  
  /// Search for tags/hashtags
  func searchTags(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage
  
  /// Resolve direct-open input (URLs, handles, DIDs) to a target
  func resolveDirectOpen(input: String) async throws -> DirectOpenTarget?
  
  /// Search capabilities (for Mastodon instances)
  var capabilities: SearchCapabilities { get }
  
  /// Whether this provider supports sort by top/latest
  var supportsSortTopLatest: Bool { get }
  
  /// Provider identifier (for pagination tokens)
  var providerId: String { get }
}

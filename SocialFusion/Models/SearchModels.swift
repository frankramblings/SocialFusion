import Foundation

// MARK: - Search Scope

/// Defines what type of content to search for
public enum SearchScope: String, Codable, CaseIterable {
  case posts = "posts"
  case users = "users"
  case tags = "tags"
  
  public var displayName: String {
    switch self {
    case .posts: return "Posts"
    case .users: return "Users"
    case .tags: return "Tags"
    }
  }
}

// MARK: - Search Network Selection

/// Defines which network(s) to search
public enum SearchNetworkSelection: String, Codable, CaseIterable {
  case unified = "unified"
  case mastodon = "mastodon"
  case bluesky = "bluesky"
  
  public var displayName: String {
    switch self {
    case .unified: return "Unified"
    case .mastodon: return "Mastodon"
    case .bluesky: return "Bluesky"
    }
  }
  
  public var platforms: [SocialPlatform] {
    switch self {
    case .unified: return [.mastodon, .bluesky]
    case .mastodon: return [.mastodon]
    case .bluesky: return [.bluesky]
    }
  }
}

// MARK: - Search Sort

/// Sort order for search results
public enum SearchSort: String, Codable {
  case top = "top"
  case latest = "latest"
  case relevance = "relevance"
  
  public var displayName: String {
    switch self {
    case .top: return "Top"
    case .latest: return "Latest"
    case .relevance: return "Relevance"
    }
  }
}

// MARK: - Search Query

/// Represents a search query with all parameters
public struct SearchQuery: Codable, Hashable {
  public let text: String
  public let scope: SearchScope
  public let networkSelection: SearchNetworkSelection
  public let sort: SearchSort?
  public let timeWindow: String? // e.g., "day", "week", "month", "all"
  
  public init(
    text: String,
    scope: SearchScope,
    networkSelection: SearchNetworkSelection,
    sort: SearchSort? = nil,
    timeWindow: String? = nil
  ) {
    self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    self.scope = scope
    self.networkSelection = networkSelection
    self.sort = sort
    self.timeWindow = timeWindow
  }
  
  /// Normalized query text for caching (lowercased, trimmed)
  public var normalizedText: String {
    text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
  }
  
  /// Cache key for this query
  public func cacheKey(accountId: String) -> String {
    "\(accountId)_\(networkSelection.rawValue)_\(scope.rawValue)_\(normalizedText)_\(sort?.rawValue ?? "nil")_\(timeWindow ?? "nil")"
  }
}

// MARK: - Search Result Item

/// A single search result item (post, user, or tag)
public enum SearchResultItem: Identifiable, Hashable {
  case post(Post)
  case user(SearchUser)
  case tag(SearchTag)
  
  public var id: String {
    switch self {
    case .post(let post): return post.id
    case .user(let user): return user.id
    case .tag(let tag): return tag.id
    }
  }
  
  public var platform: SocialPlatform {
    switch self {
    case .post(let post): return post.platform
    case .user(let user): return user.platform
    case .tag(let tag): return tag.platform
    }
  }
  
  public static func == (lhs: SearchResultItem, rhs: SearchResultItem) -> Bool {
    lhs.id == rhs.id
  }
  
  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

// MARK: - Search Page Token

/// Provider-specific pagination token
public typealias SearchPageToken = String

// MARK: - Search Page

/// A page of search results with pagination information
public struct SearchPage: Sendable {
  public let items: [SearchResultItem]
  public let nextPageTokens: [String: SearchPageToken] // Keyed by provider identifier
  public let hasMore: Bool
  
  public init(
    items: [SearchResultItem],
    nextPageTokens: [String: SearchPageToken] = [:],
    hasMore: Bool = false
  ) {
    self.items = items
    self.nextPageTokens = nextPageTokens
    self.hasMore = hasMore || !nextPageTokens.isEmpty
  }
  
  public static let empty = SearchPage(items: [], nextPageTokens: [:], hasMore: false)
}

// MARK: - Search Results Section

/// A section of search results grouped by provider (for unified search)
public struct SearchResultsSection: Identifiable {
  public let id: String
  public let provider: String // "mastodon" or "bluesky"
  public let items: [SearchResultItem]
  public let nextPageToken: SearchPageToken?
  
  public init(
    id: String,
    provider: String,
    items: [SearchResultItem],
    nextPageToken: SearchPageToken? = nil
  ) {
    self.id = id
    self.provider = provider
    self.items = items
    self.nextPageToken = nextPageToken
  }
}

// MARK: - Direct Open Target

/// Represents a direct-open target (profile, post, or tag)
public enum DirectOpenTarget: Hashable {
  case profile(SearchUser)
  case post(Post)
  case tag(SearchTag)
  
  public var platform: SocialPlatform {
    switch self {
    case .profile(let user): return user.platform
    case .post(let post): return post.platform
    case .tag(let tag): return tag.platform
    }
  }
  
  // Hashable conformance
  public func hash(into hasher: inout Hasher) {
    switch self {
    case .profile(let user):
      hasher.combine("profile")
      hasher.combine(user.id)
    case .post(let post):
      hasher.combine("post")
      hasher.combine(post.id)
    case .tag(let tag):
      hasher.combine("tag")
      hasher.combine(tag.id)
    }
  }
  
  // Equatable conformance
  public static func == (lhs: DirectOpenTarget, rhs: DirectOpenTarget) -> Bool {
    switch (lhs, rhs) {
    case (.profile(let l), .profile(let r)):
      return l.id == r.id
    case (.post(let l), .post(let r)):
      return l.id == r.id
    case (.tag(let l), .tag(let r)):
      return l.id == r.id
    default:
      return false
    }
  }
}

// MARK: - Search Phase

/// Current phase of search operation
public enum SearchPhase: Equatable {
  case idle
  case showingCached
  case loading
  case loaded
  case error(String)
  case empty
  
  public var isLoading: Bool {
    if case .loading = self {
      return true
    }
    return false
  }
  
  public var hasResults: Bool {
    if case .loaded = self {
      return true
    }
    if case .showingCached = self {
      return true
    }
    return false
  }
}

// MARK: - Search Chip Row Model

/// Model for the search chip row UI component
public struct SearchChipRowModel: Identifiable {
  public let id: String
  public let network: SearchNetworkSelection
  public let scope: SearchScope
  public let sort: SearchSort?
  public let instanceDomain: String? // For Mastodon instance index chip
  public let showInstanceInfo: Bool // Whether to show info popover
  
  public init(
    network: SearchNetworkSelection,
    scope: SearchScope,
    sort: SearchSort? = nil,
    instanceDomain: String? = nil,
    showInstanceInfo: Bool = false
  ) {
    self.id = "\(network.rawValue)_\(scope.rawValue)_\(sort?.rawValue ?? "nil")"
    self.network = network
    self.scope = scope
    self.sort = sort
    self.instanceDomain = instanceDomain
    self.showInstanceInfo = showInstanceInfo
  }
}

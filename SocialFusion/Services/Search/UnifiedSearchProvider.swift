import Foundation

/// Unified search provider that combines Mastodon and Bluesky results
public class UnifiedSearchProvider: SearchProviding {
  private let mastodonProviders: [MastodonSearchProvider]
  private let blueskyProviders: [BlueskySearchProvider]
  
  public var providerId: String { "unified" }
  
  public var capabilities: SearchCapabilities {
    // Aggregate capabilities - show most restrictive
    var aggregated = SearchCapabilities()
    
    // If any Mastodon instance has limited capabilities, reflect that
    for provider in mastodonProviders {
      let caps = provider.capabilities
      if caps.supportsStatusSearch == .no || caps.supportsStatusSearch == .likelyNo {
        aggregated.supportsStatusSearch = .likelyNo
      }
    }
    
    // Bluesky always supports everything
    return aggregated
  }
  
  public var supportsSortTopLatest: Bool {
    true // Unified supports sort (Bluesky does)
  }
  
  public init(
    mastodonProviders: [MastodonSearchProvider],
    blueskyProviders: [BlueskySearchProvider]
  ) {
    self.mastodonProviders = mastodonProviders
    self.blueskyProviders = blueskyProviders
  }
  
  // MARK: - SearchProviding Implementation
  
  public func searchPosts(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
    var allItems: [SearchResultItem] = []
    var nextPageTokens: [String: SearchPageToken] = [:]
    
    DebugLog.verbose("🔍 [UnifiedSearch] Searching posts with \(mastodonProviders.count) Mastodon providers, \(blueskyProviders.count) Bluesky providers")
    
    // Search all providers in parallel
    await withTaskGroup(of: (String, SearchPage).self) { group in
      for provider in mastodonProviders {
        group.addTask {
          do {
            let providerId = provider.providerId
            let token = page != nil ? nextPageTokens[providerId] : nil
            let page = try await provider.searchPosts(query: query, page: token)
            DebugLog.verbose("🔍 [UnifiedSearch] Mastodon provider \(providerId) returned \(page.items.count) posts")
            return (providerId, page)
          } catch {
            let providerId = provider.providerId
            DebugLog.verbose("⚠️ [UnifiedSearch] Mastodon provider \(providerId) failed: \(error.localizedDescription)")
            return (providerId, SearchPage.empty)
          }
        }
      }
      
      for provider in blueskyProviders {
        group.addTask {
          do {
            let providerId = provider.providerId
            let token = page != nil ? nextPageTokens[providerId] : nil
            let page = try await provider.searchPosts(query: query, page: token)
            DebugLog.verbose("🔍 [UnifiedSearch] Bluesky provider \(providerId) returned \(page.items.count) posts")
            return (providerId, page)
          } catch {
            let providerId = provider.providerId
            DebugLog.verbose("⚠️ [UnifiedSearch] Bluesky provider \(providerId) failed: \(error.localizedDescription)")
            return (providerId, SearchPage.empty)
          }
        }
      }
      
      for await (_, page) in group {
        allItems.append(contentsOf: page.items)
        nextPageTokens.merge(page.nextPageTokens) { _, new in new }
      }
    }
    
    DebugLog.verbose("🔍 [UnifiedSearch] Combined \(allItems.count) posts from all providers")
    
    // Sort by date descending (most recent first)
    allItems.sort { item1, item2 in
      let date1 = dateForItem(item1)
      let date2 = dateForItem(item2)
      return date1 > date2
    }
    
    let hasMore = !nextPageTokens.isEmpty
    return SearchPage(items: allItems, nextPageTokens: nextPageTokens, hasMore: hasMore)
  }
  
  public func searchUsersTypeahead(text: String, page: SearchPageToken?) async throws -> SearchPage {
    // For typeahead, return separate sections per provider
    var sections: [SearchResultsSection] = []
    var nextPageTokens: [String: SearchPageToken] = [:]
    
    await withTaskGroup(of: (String, SearchPage).self) { group in
      for provider in mastodonProviders {
        group.addTask {
          do {
            let providerId = provider.providerId
            let token = page != nil ? nextPageTokens[providerId] : nil
            let page = try await provider.searchUsersTypeahead(text: text, page: token)
            return (providerId, page)
          } catch {
            let providerId = provider.providerId
            return (providerId, SearchPage.empty)
          }
        }
      }
      
      for provider in blueskyProviders {
        group.addTask {
          do {
            let providerId = provider.providerId
            let token = page != nil ? nextPageTokens[providerId] : nil
            let page = try await provider.searchUsersTypeahead(text: text, page: token)
            return (providerId, page)
          } catch {
            let providerId = provider.providerId
            return (providerId, SearchPage.empty)
          }
        }
      }
      
      for await (providerId, page) in group {
        if !page.items.isEmpty {
          sections.append(SearchResultsSection(
            id: providerId,
            provider: providerId.contains("mastodon") ? "mastodon" : "bluesky",
            items: page.items,
            nextPageToken: page.nextPageTokens[providerId]
          ))
        }
        nextPageTokens.merge(page.nextPageTokens) { _, new in new }
      }
    }
    
    // Flatten sections for unified typeahead
    let allItems = sections.flatMap { $0.items }
    let hasMore = !nextPageTokens.isEmpty
    return SearchPage(items: allItems, nextPageTokens: nextPageTokens, hasMore: hasMore)
  }
  
  public func searchUsers(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
    // Return separate sections per provider
    var sections: [SearchResultsSection] = []
    var nextPageTokens: [String: SearchPageToken] = [:]
    
    DebugLog.verbose("🔍 [UnifiedSearch] Searching users with \(mastodonProviders.count) Mastodon providers, \(blueskyProviders.count) Bluesky providers")
    
    await withTaskGroup(of: (String, SearchPage).self) { group in
      for provider in mastodonProviders {
        group.addTask {
          do {
            let providerId = provider.providerId
            let token = page != nil ? nextPageTokens[providerId] : nil
            let page = try await provider.searchUsers(query: query, page: token)
            DebugLog.verbose("🔍 [UnifiedSearch] Mastodon provider \(providerId) returned \(page.items.count) users")
            return (providerId, page)
          } catch {
            let providerId = provider.providerId
            DebugLog.verbose("⚠️ [UnifiedSearch] Mastodon provider \(providerId) failed: \(error.localizedDescription)")
            return (providerId, SearchPage.empty)
          }
        }
      }
      
      for provider in blueskyProviders {
        group.addTask {
          do {
            let providerId = provider.providerId
            let token = page != nil ? nextPageTokens[providerId] : nil
            let page = try await provider.searchUsers(query: query, page: token)
            DebugLog.verbose("🔍 [UnifiedSearch] Bluesky provider \(providerId) returned \(page.items.count) users")
            return (providerId, page)
          } catch {
            let providerId = provider.providerId
            DebugLog.verbose("⚠️ [UnifiedSearch] Bluesky provider \(providerId) failed: \(error.localizedDescription)")
            return (providerId, SearchPage.empty)
          }
        }
      }
      
      for await (providerId, page) in group {
        if !page.items.isEmpty {
          sections.append(SearchResultsSection(
            id: providerId,
            provider: providerId.contains("mastodon") ? "mastodon" : "bluesky",
            items: page.items,
            nextPageToken: page.nextPageTokens[providerId]
          ))
        }
        nextPageTokens.merge(page.nextPageTokens) { _, new in new }
      }
    }
    
    // Flatten for unified view
    let allItems = sections.flatMap { $0.items }
    DebugLog.verbose("🔍 [UnifiedSearch] Combined \(allItems.count) users from all providers")
    let hasMore = !nextPageTokens.isEmpty
    return SearchPage(items: allItems, nextPageTokens: nextPageTokens, hasMore: hasMore)
  }
  
  public func searchTags(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
    var allItems: [SearchResultItem] = []
    var nextPageTokens: [String: SearchPageToken] = [:]
    
    DebugLog.verbose("🔍 [UnifiedSearch] Searching tags with \(mastodonProviders.count) Mastodon providers, \(blueskyProviders.count) Bluesky providers")
    
    await withTaskGroup(of: (String, SearchPage).self) { group in
      for provider in mastodonProviders {
        group.addTask {
          do {
            let providerId = provider.providerId
            let token = page != nil ? nextPageTokens[providerId] : nil
            let page = try await provider.searchTags(query: query, page: token)
            DebugLog.verbose("🔍 [UnifiedSearch] Mastodon provider \(providerId) returned \(page.items.count) tags")
            return (providerId, page)
          } catch {
            let providerId = provider.providerId
            DebugLog.verbose("⚠️ [UnifiedSearch] Mastodon provider \(providerId) failed: \(error.localizedDescription)")
            return (providerId, SearchPage.empty)
          }
        }
      }
      
      for provider in blueskyProviders {
        group.addTask {
          do {
            let providerId = provider.providerId
            let token = page != nil ? nextPageTokens[providerId] : nil
            let page = try await provider.searchTags(query: query, page: token)
            DebugLog.verbose("🔍 [UnifiedSearch] Bluesky provider \(providerId) returned \(page.items.count) tags")
            return (providerId, page)
          } catch {
            let providerId = provider.providerId
            DebugLog.verbose("⚠️ [UnifiedSearch] Bluesky provider \(providerId) failed: \(error.localizedDescription)")
            return (providerId, SearchPage.empty)
          }
        }
      }
      
      for await (_, page) in group {
        allItems.append(contentsOf: page.items)
        nextPageTokens.merge(page.nextPageTokens) { _, new in new }
      }
    }
    
    // Remove duplicates by tag name
    var seenTags = Set<String>()
    allItems = allItems.filter { item in
      if case .tag(let tag) = item {
        if seenTags.contains(tag.name) {
          return false
        }
        seenTags.insert(tag.name)
        return true
      }
      return true
    }
    
    DebugLog.verbose("🔍 [UnifiedSearch] Combined \(allItems.count) tags from all providers (after deduplication)")
    let hasMore = !nextPageTokens.isEmpty
    return SearchPage(items: allItems, nextPageTokens: nextPageTokens, hasMore: hasMore)
  }
  
  public func resolveDirectOpen(input: String) async throws -> DirectOpenTarget? {
    // Try all providers, return first match
    for provider in mastodonProviders {
      if let target = try? await provider.resolveDirectOpen(input: input) {
        return target
      }
    }
    
    for provider in blueskyProviders {
      if let target = try? await provider.resolveDirectOpen(input: input) {
        return target
      }
    }
    
    return nil
  }
  
  // MARK: - Helper Methods
  
  private func dateForItem(_ item: SearchResultItem) -> Date {
    switch item {
    case .post(let post):
      return post.createdAt
    case .user, .tag:
      return Date.distantPast
    }
  }
}

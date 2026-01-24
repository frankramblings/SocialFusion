import Foundation

/// Search provider for Bluesky
public class BlueskySearchProvider: SearchProviding {
  private let blueskyService: BlueskyService
  private let account: SocialAccount
  
  public var providerId: String { "bluesky_\(account.id)" }
  
  public var capabilities: SearchCapabilities {
    // Bluesky supports all search types
    SearchCapabilities(
      supportsAccountSearch: .yes,
      supportsHashtagSearch: .yes,
      supportsStatusSearch: .yes,
      supportsTrends: false,
      instanceDomain: nil
    )
  }
  
  public var supportsSortTopLatest: Bool {
    true // Bluesky supports sort
  }
  
  public init(blueskyService: BlueskyService, account: SocialAccount) {
    self.blueskyService = blueskyService
    self.account = account
  }
  
  // MARK: - SearchProviding Implementation
  
  public func searchPosts(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
    print("🔍 [BlueskySearch] Searching posts for query: '\(query.text)'")
    let response = try await blueskyService.searchPosts(
      query: query.text,
      account: account,
      limit: 20,
      cursor: page
    )
    
    print("🔍 [BlueskySearch] API returned \(response.posts.count) posts")
    
    // Convert BlueskyPostDTO to Post
    print("🔍 [BlueskySearch] Converting \(response.posts.count) posts from search results")
    var conversionFailures = 0
    let posts = response.posts.compactMap { postDTO -> Post? in
      // Convert postDTO to dictionary format for conversion
      // The convertBlueskyPostJSONToPost expects either item["post"] or item itself
      guard let jsonData = try? JSONEncoder().encode(postDTO),
            let jsonDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
        conversionFailures += 1
        print("⚠️ [BlueskySearch] Failed to convert postDTO to dictionary for post: \(postDTO.uri)")
        return nil
      }
      
      // Wrap in "post" key if needed (check what the converter expects)
      let dictToConvert = jsonDict
      
      if let post = blueskyService.convertBlueskyPostJSONToPost(dictToConvert, account: account) {
        return post
      } else {
        conversionFailures += 1
        print("⚠️ [BlueskySearch] Failed to convert dictionary to Post for URI: \(postDTO.uri)")
        // Try wrapping in "post" key as fallback
        let wrappedDict = ["post": jsonDict]
        if let post = blueskyService.convertBlueskyPostJSONToPost(wrappedDict, account: account) {
          return post
        }
        return nil
      }
    }
    
    if conversionFailures > 0 {
      print("⚠️ [BlueskySearch] \(conversionFailures) out of \(response.posts.count) posts failed to convert")
    }
    print("🔍 [BlueskySearch] Successfully converted \(posts.count) posts")
    
    let items = posts.map { SearchResultItem.post($0) }
    let nextPageTokens = response.cursor != nil ? [providerId: response.cursor!] : [:]
    return SearchPage(items: items, nextPageTokens: nextPageTokens, hasMore: response.cursor != nil)
  }
  
  public func searchUsersTypeahead(text: String, page: SearchPageToken?) async throws -> SearchPage {
    // Use searchActors for typeahead (Bluesky doesn't have separate typeahead endpoint)
    let query = SearchQuery(text: text, scope: .users, networkSelection: .bluesky)
    return try await searchUsers(query: query, page: page)
  }
  
  public func searchUsers(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
    print("🔍 [BlueskySearch] Searching users for query: '\(query.text)'")
    let response = try await blueskyService.searchActors(
      query: query.text,
      account: account,
      limit: 20,
      cursor: page
    )
    
    print("🔍 [BlueskySearch] API returned \(response.actors.count) actors")
    
    let users = response.actors.map { actor in
      SearchUser(
        id: actor.did,
        username: actor.handle,
        displayName: actor.displayName,
        avatarURL: actor.avatar,
        platform: .bluesky
      )
    }
    
    let items = users.map { SearchResultItem.user($0) }
    let nextPageTokens = response.cursor != nil ? [providerId: response.cursor!] : [:]
    return SearchPage(items: items, nextPageTokens: nextPageTokens, hasMore: response.cursor != nil)
  }
  
  public func searchTags(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
    print("🔍 [BlueskySearch] Searching tags for query: '\(query.text)'")
    // Bluesky doesn't have a dedicated tag search endpoint
    // Tags are typically embedded in posts, so we'll search posts and extract tags
    do {
      let response = try await blueskyService.searchPosts(
        query: query.text,
        account: account,
        limit: 20,
        cursor: page
      )
      
      print("🔍 [BlueskySearch] API returned \(response.posts.count) posts for tag extraction")
      
      // Extract unique tags from posts
      var tagSet = Set<String>()
      for postDTO in response.posts {
        // Extract tags from post content (hashtags)
        let content = postDTO.record.text
        let hashtags = extractHashtags(from: content)
        tagSet.formUnion(hashtags)
      }
      
      let tags = tagSet.map { tagName in
        SearchTag(id: tagName, name: tagName, platform: .bluesky)
      }
      
      print("🔍 [BlueskySearch] Extracted \(tags.count) unique tags")
      
      let items = tags.map { SearchResultItem.tag($0) }
      // Tags don't have pagination in Bluesky
      return SearchPage(items: items, nextPageTokens: [:], hasMore: false)
    } catch {
      print("⚠️ [BlueskySearch] Tag search failed: \(error.localizedDescription)")
      // Return empty results instead of throwing - unified search will still show Mastodon tags
      return SearchPage(items: [], nextPageTokens: [:], hasMore: false)
    }
  }
  
  public func resolveDirectOpen(input: String) async throws -> DirectOpenTarget? {
    // Check for Bluesky handle: @handle
    let afterAt = input.index(after: input.startIndex)
    if input.hasPrefix("@") && afterAt < input.endIndex && !input[afterAt...].contains("@") {
      let handle = String(input.dropFirst())
      let response = try await blueskyService.searchActors(
        query: handle,
        account: account,
        limit: 1
      )
      if let actor = response.actors.first(where: { $0.handle == handle }) {
        let user = SearchUser(
          id: actor.did,
          username: actor.handle,
          displayName: actor.displayName,
          avatarURL: actor.avatar,
          platform: .bluesky
        )
        return .profile(user)
      }
    }
    
    // Check for DID: did:plc:...
    if input.hasPrefix("did:") {
      let response = try await blueskyService.searchActors(
        query: input,
        account: account,
        limit: 1
      )
      if let actor = response.actors.first(where: { $0.did == input }) {
        let user = SearchUser(
          id: actor.did,
          username: actor.handle,
          displayName: actor.displayName,
          avatarURL: actor.avatar,
          platform: .bluesky
        )
        return .profile(user)
      }
    }
    
    // Check for Bluesky URL
    if let url = URL(string: input) {
      // Profile URL: https://bsky.app/profile/handle
      if url.host == "bsky.app" || url.host == "bsky.social" {
        let pathComponents = url.pathComponents
        if pathComponents.count >= 3 && pathComponents[1] == "profile" {
          let handle = pathComponents[2]
          let response = try await blueskyService.searchActors(
            query: handle,
            account: account,
            limit: 1
          )
          if let actor = response.actors.first(where: { $0.handle == handle }) {
            let user = SearchUser(
              id: actor.did,
              username: actor.handle,
              displayName: actor.displayName,
              avatarURL: actor.avatar,
              platform: .bluesky
            )
            return .profile(user)
          }
        }
        
        // Post URL: https://bsky.app/profile/handle/post/...
        if pathComponents.count >= 4 && pathComponents[3] == "post" {
          _ = pathComponents.last ?? ""
          // Try to fetch the post - would need a fetchPost method
          // For now, return nil and let it fall through to regular search
        }
      }
    }
    
    return nil
  }
  
  // MARK: - Helper Methods
  
  private func extractHashtags(from text: String) -> [String] {
    let pattern = #"#(\w+)"#
    let regex = try? NSRegularExpression(pattern: pattern, options: [])
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    var hashtags: [String] = []
    
    regex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
      if let matchRange = match?.range(at: 1),
         let swiftRange = Range(matchRange, in: text) {
        hashtags.append(String(text[swiftRange]))
      }
    }
    
    return hashtags
  }
}

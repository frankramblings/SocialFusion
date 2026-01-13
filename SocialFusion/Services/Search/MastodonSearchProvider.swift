import Foundation

/// Search provider for Mastodon instances
@MainActor
public class MastodonSearchProvider: SearchProviding {
  private let mastodonService: MastodonService
  private let account: SocialAccount
  private let capabilitiesStorage: SearchCapabilitiesStorage
  
  public var providerId: String { "mastodon_\(account.id)" }
  
  public var capabilities: SearchCapabilities {
    capabilitiesStorage.getCapabilities(for: account.id)
  }
  
  public var supportsSortTopLatest: Bool {
    false // Mastodon v2 search doesn't support sort
  }
  
  public init(
    mastodonService: MastodonService,
    account: SocialAccount,
    capabilitiesStorage: SearchCapabilitiesStorage = .shared
  ) {
    self.mastodonService = mastodonService
    self.account = account
    self.capabilitiesStorage = capabilitiesStorage
  }
  
  // MARK: - SearchProviding Implementation
  
  public func searchPosts(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
    print("🔍 [MastodonSearch] Searching posts for query: '\(query.text)'")
    let result = try await mastodonService.search(
      query: query.text,
      account: account,
      type: "statuses",
      limit: 20
    )
    
    print("🔍 [MastodonSearch] API returned \(result.statuses.count) statuses")
    
    // Convert MastodonStatus to Post
    let posts = result.statuses.map { status in
      mastodonService.convertMastodonStatusToPost(status, account: account)
    }
    
    print("🔍 [MastodonSearch] Converted to \(posts.count) posts")
    
    // Update capabilities based on results
    let hasResults = !posts.isEmpty
    let hasOtherResults = !result.accounts.isEmpty || !result.hashtags.isEmpty
    capabilitiesStorage.updateCapabilities(
      for: account.id,
      scope: .posts,
      hasResults: hasResults,
      hasOtherResults: hasOtherResults
    )
    
    let items = posts.map { SearchResultItem.post($0) }
    return SearchPage(items: items, nextPageTokens: [:], hasMore: false)
  }
  
  public func searchUsersTypeahead(text: String, page: SearchPageToken?) async throws -> SearchPage {
    // Mastodon doesn't have a separate typeahead endpoint, use regular search
    let query = SearchQuery(text: text, scope: .users, networkSelection: .mastodon)
    return try await searchUsers(query: query, page: page)
  }
  
  public func searchUsers(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
    print("🔍 [MastodonSearch] Searching users for query: '\(query.text)'")
    do {
      // First try with type=accounts parameter
      let result = try await mastodonService.search(
        query: query.text,
        account: account,
        type: "accounts",
        limit: 20
      )
      
      print("🔍 [MastodonSearch] API returned \(result.accounts.count) accounts")
      
      let users = result.accounts.map { account in
        SearchUser(
          id: account.id,
          username: account.acct,
          displayName: account.displayName,
          avatarURL: account.avatar,
          platform: .mastodon
        )
      }
      
      // Update capabilities
      let hasResults = !users.isEmpty
      capabilitiesStorage.updateCapabilities(
        for: account.id,
        scope: .users,
        hasResults: hasResults,
        hasOtherResults: false
      )
      
      let items = users.map { SearchResultItem.user($0) }
      return SearchPage(items: items, nextPageTokens: [:], hasMore: false)
    } catch {
      // If search with type=accounts fails (e.g., 500 error), try without type parameter
      // Some instances don't support the type parameter but still return accounts in the result
      let errorMessage = error.localizedDescription
      if errorMessage.contains("500") || errorMessage.contains("status 500") {
        print("⚠️ [MastodonSearch] User search with type=accounts failed (500), trying without type parameter")
        do {
          let result = try await mastodonService.search(
            query: query.text,
            account: account,
            type: nil, // Try without type parameter
            limit: 20
          )
          
          print("🔍 [MastodonSearch] Fallback search returned \(result.accounts.count) accounts")
          
          // If we got accounts, return them
          if !result.accounts.isEmpty {
            let users = result.accounts.map { account in
              SearchUser(
                id: account.id,
                username: account.acct,
                displayName: account.displayName,
                avatarURL: account.avatar,
                platform: .mastodon
              )
            }
            
            // Update capabilities
            capabilitiesStorage.updateCapabilities(
              for: account.id,
              scope: .users,
              hasResults: true,
              hasOtherResults: false
            )
            
            let items = users.map { SearchResultItem.user($0) }
            return SearchPage(items: items, nextPageTokens: [:], hasMore: false)
          } else {
            // No accounts in result, try extracting from posts
            print("⚠️ [MastodonSearch] Fallback search returned 0 accounts, trying post extraction")
            // Throw an error to trigger the post extraction fallback
            throw NSError(domain: "MastodonSearch", code: 0, userInfo: [NSLocalizedDescriptionKey: "No accounts in search result"])
          }
        } catch let fallbackError {
          print("⚠️ [MastodonSearch] Fallback user search also failed: \(fallbackError.localizedDescription)")
          
          // Final attempt: Extract users from post search results
          // This works for instances that don't support user search but return user info in posts
          print("🔍 [MastodonSearch] Attempting to extract users from post search results")
          do {
            // Search for posts and extract account information from authors
            let postResult = try await mastodonService.search(
              query: query.text,
              account: account,
              type: "statuses",
              limit: 20
            )
            
            print("🔍 [MastodonSearch] Post search returned \(postResult.statuses.count) posts, extracting users")
            
            // Extract unique accounts from post authors
            // Include all unique users from posts - they're relevant because they posted about the topic
            var seenAccountIds = Set<String>()
            var users: [SearchUser] = []
            
            for status in postResult.statuses {
              let accountId = status.account.id
              if !seenAccountIds.contains(accountId) {
                seenAccountIds.insert(accountId)
                // Include all users who posted about the topic (they're relevant by definition)
                users.append(SearchUser(
                  id: status.account.id,
                  username: status.account.acct,
                  displayName: status.account.displayName,
                  avatarURL: status.account.avatar,
                  platform: .mastodon
                ))
              }
            }
            
            if !users.isEmpty {
              print("🔍 [MastodonSearch] Extracted \(users.count) unique users from post search results")
              
              // Update capabilities
              capabilitiesStorage.updateCapabilities(
                for: account.id,
                scope: .users,
                hasResults: true,
                hasOtherResults: false
              )
              
              let items = users.map { SearchResultItem.user($0) }
              return SearchPage(items: items, nextPageTokens: [:], hasMore: false)
            } else {
              print("⚠️ [MastodonSearch] No users found in post search results")
            }
          } catch let postSearchError {
            // Ignore errors from this final attempt
            print("⚠️ [MastodonSearch] Final fallback attempt also failed: \(postSearchError.localizedDescription)")
          }
          
          // Return empty results instead of throwing - unified search will still show Bluesky users
          return SearchPage(items: [], nextPageTokens: [:], hasMore: false)
        }
      } else {
        print("⚠️ [MastodonSearch] User search failed: \(error.localizedDescription)")
        // Return empty results instead of throwing - unified search will still show Bluesky users
        return SearchPage(items: [], nextPageTokens: [:], hasMore: false)
      }
    }
  }
  
  public func searchTags(query: SearchQuery, page: SearchPageToken?) async throws -> SearchPage {
    let result = try await mastodonService.search(
      query: query.text,
      account: account,
      type: "hashtags",
      limit: 20
    )
    
    let tags = result.hashtags.map { tag in
      SearchTag(id: tag.name, name: tag.name, platform: .mastodon)
    }
    
    // Update capabilities
    let hasResults = !tags.isEmpty
    capabilitiesStorage.updateCapabilities(
      for: account.id,
      scope: .tags,
      hasResults: hasResults,
      hasOtherResults: false
    )
    
    let items = tags.map { SearchResultItem.tag($0) }
    return SearchPage(items: items, nextPageTokens: [:], hasMore: false)
  }
  
  public func resolveDirectOpen(input: String) async throws -> DirectOpenTarget? {
    // Check for Mastodon handle: @user@instance
    if input.hasPrefix("@") && input.contains("@") && !input.hasPrefix("@@") {
      let components = input.dropFirst().split(separator: "@")
      if components.count == 2 {
        let username = String(components[0])
        let instance = String(components[1])
        // Search for user
        let result = try await mastodonService.search(
          query: input,
          account: account,
          type: "accounts",
          limit: 1
        )
        if let account = result.accounts.first {
          let user = SearchUser(
            id: account.id,
            username: account.acct,
            displayName: account.displayName,
            avatarURL: account.avatar,
            platform: .mastodon
          )
          return .profile(user)
        }
      }
    }
    
    // Check for Mastodon URL
    if let url = URL(string: input), let host = url.host {
      // Profile URL: https://instance/@user
      if url.pathComponents.count >= 2 && url.pathComponents[1].hasPrefix("@") {
        let username = String(url.pathComponents[1].dropFirst())
        let result = try await mastodonService.search(
          query: "@\(username)@\(host)",
          account: account,
          type: "accounts",
          limit: 1
        )
        if let account = result.accounts.first {
          let user = SearchUser(
            id: account.id,
            username: account.acct,
            displayName: account.displayName,
            avatarURL: account.avatar,
            platform: .mastodon
          )
          return .profile(user)
        }
      }
      
      // Status URL: https://instance/@user/123456
      // Note: Fetching status by ID requires the full status ID format
      // For now, return nil and let it fall through to regular search
      // This could be enhanced to parse and fetch the status
    }
    
    return nil
  }
}

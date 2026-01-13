import Foundation

extension SocialServiceManager {
  /// Create a SearchStore with the appropriate provider based on network selection
  @MainActor
  func createSearchStore(
    networkSelection: SearchNetworkSelection,
    accountId: String? = nil
  ) -> SearchStore {
    let selectedAccountId = accountId ?? selectedAccountIds.first ?? "all"
    
    let mastodonProviders = mastodonAccounts.map { account in
      MastodonSearchProvider(
        mastodonService: mastodonService,
        account: account
      )
    }
    
    let blueskyProviders = blueskyAccounts.map { account in
      BlueskySearchProvider(
        blueskyService: blueskyService,
        account: account
      )
    }
    
    let provider: SearchProviding
    switch networkSelection {
    case .unified:
      provider = UnifiedSearchProvider(
        mastodonProviders: mastodonProviders,
        blueskyProviders: blueskyProviders
      )
    case .mastodon:
      if let firstProvider = mastodonProviders.first {
        provider = firstProvider
      } else {
        // Fallback to unified if no Mastodon account
        provider = UnifiedSearchProvider(
          mastodonProviders: mastodonProviders,
          blueskyProviders: blueskyProviders
        )
      }
    case .bluesky:
      if let firstProvider = blueskyProviders.first {
        provider = firstProvider
      } else {
        // Fallback to unified if no Bluesky account
        provider = UnifiedSearchProvider(
          mastodonProviders: mastodonProviders,
          blueskyProviders: blueskyProviders
        )
      }
    }
    
    return SearchStore(
      searchProvider: provider,
      accountId: selectedAccountId
    )
  }
}

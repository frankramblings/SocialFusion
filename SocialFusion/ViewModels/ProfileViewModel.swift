import Combine
import Foundation
import SwiftUI

/// Tab options for the profile post list
enum ProfileTab: String, CaseIterable {
  case posts = "Posts"
  case postsAndReplies = "Posts & Replies"
  case media = "Media"
}

/// ViewModel for the unified profile screen
/// Manages profile data loading and per-tab post pagination
@MainActor
public final class ProfileViewModel: ObservableObject {

  // MARK: - Profile State

  @Published var profile: UserProfile?
  @Published var isLoadingProfile = false
  @Published var profileError: Error?

  // MARK: - Merged Identity State

  /// The twin profile fetched from the opposite network when this profile
  /// participates in a merged identity. Nil when no merge is active.
  @Published var mergedTwinProfile: UserProfile?

  /// The merged-identity record this profile is bound to, if any.
  @Published var mergedIdentity: MergedIdentity?

  /// Which side's bio/fields/banner is currently rendered in the header.
  /// Defaults to the side the user navigated in on.
  @Published var selectedSide: SocialPlatform

  /// Whether a merge-confirmation sheet should be presented.
  @Published var showMergeConfirmation: Bool = false

  /// Candidate proposed by the matcher but not yet confirmed/dismissed.
  /// Drives the in-line "Looks like this is also @x.bsky.social?" prompt.
  @Published var pendingMatchCandidate: MergedIdentity?

  // MARK: - Tab State

  @Published var selectedTab: ProfileTab = .posts

  // MARK: - Per-Tab Post State

  @Published var posts: [Post] = []
  @Published var postsAndReplies: [Post] = []
  @Published var mediaPosts: [Post] = []
  @Published var isLoadingPosts = false
  @Published var isLoadingMore = false

  // MARK: - Pagination

  private var postsCursor: String?
  private var postsAndRepliesCursor: String?
  private var mediaPostsCursor: String?
  private var postsLoaded = false
  private var postsAndRepliesLoaded = false
  private var mediaPostsLoaded = false
  private var canLoadMorePosts = true
  private var canLoadMorePostsAndReplies = true
  private var canLoadMoreMedia = true

  // MARK: - Identity

  let user: SearchUser
  let isOwnProfile: Bool
  private let serviceManager: SocialServiceManager

  /// Side-channel store injected by the view via `attach(mergedIdentityStore:)`.
  private(set) weak var mergedIdentityStore: MergedIdentityStore?

  /// Called by the surrounding View on first appearance to bind the store.
  func attach(mergedIdentityStore: MergedIdentityStore) {
    self.mergedIdentityStore = mergedIdentityStore
  }

  // MARK: - Computed Properties

  /// Posts for the currently selected tab
  var currentPosts: [Post] {
    switch selectedTab {
    case .posts:
      return posts
    case .postsAndReplies:
      return postsAndReplies
    case .media:
      return mediaPosts
    }
  }

  /// Whether more posts can be loaded for the current tab
  var canLoadMore: Bool {
    switch selectedTab {
    case .posts:
      return canLoadMorePosts
    case .postsAndReplies:
      return canLoadMorePostsAndReplies
    case .media:
      return canLoadMoreMedia
    }
  }

  // MARK: - Merge-Derived Computed Properties

  /// The profile currently driving the header bio/fields/banner — either
  /// `profile` or `mergedTwinProfile` depending on `selectedSide`.
  var activeProfile: UserProfile? {
    guard let base = profile else { return nil }
    if let twin = mergedTwinProfile, selectedSide != base.platform {
      return twin
    }
    return base
  }

  /// Returns true when this profile participates in a merge and both sides
  /// have been loaded.
  var isMerged: Bool {
    mergedIdentity != nil && mergedTwinProfile != nil
  }

  var combinedFollowersCount: Int {
    (profile?.followersCount ?? 0) + (mergedTwinProfile?.followersCount ?? 0)
  }

  var combinedFollowingCount: Int {
    (profile?.followingCount ?? 0) + (mergedTwinProfile?.followingCount ?? 0)
  }

  var combinedStatusesCount: Int {
    (profile?.statusesCount ?? 0) + (mergedTwinProfile?.statusesCount ?? 0)
  }

  // MARK: - Initialization

  init(user: SearchUser, isOwnProfile: Bool = false, serviceManager: SocialServiceManager) {
    self.user = user
    self.isOwnProfile = isOwnProfile
    self.serviceManager = serviceManager
    self.selectedSide = user.platform
  }

  /// Convenience initializer for viewing your own profile from a SocialAccount
  convenience init(account: SocialAccount, serviceManager: SocialServiceManager) {
    let searchUser = SearchUser(
      id: account.platformSpecificId.isEmpty ? account.id : account.platformSpecificId,
      username: account.username,
      displayName: account.displayName,
      avatarURL: account.profileImageURL?.absoluteString,
      platform: account.platform,
      displayNameEmojiMap: account.displayNameEmojiMap
    )
    self.init(user: searchUser, isOwnProfile: true, serviceManager: serviceManager)
  }

  // MARK: - Profile Loading

  /// Load the full UserProfile from the API, then attempt to resolve a
  /// merged twin profile from the opposite network.
  func loadProfile() async {
    guard profile == nil, !isLoadingProfile else { return }

    guard let account = serviceManager.accounts.first(where: { $0.platform == user.platform })
    else {
      profileError = ProfileViewModelError.noAccountForPlatform(user.platform)
      return
    }

    isLoadingProfile = true
    profileError = nil

    do {
      let result = try await serviceManager.fetchUserProfile(user: user, account: account)
      profile = result
      await resolveMergedTwin(for: result)
    } catch {
      profileError = error
    }

    isLoadingProfile = false
  }

  /// Resolve and (if present) load the twin profile from the opposite network.
  /// Side-effect: sets `mergedIdentity`, `mergedTwinProfile`, and/or
  /// `pendingMatchCandidate` on the view model.
  ///
  /// Resolution order, matching the spec's Principle 2 priority:
  /// 1. User-confirmed merge from `MergedIdentityStore` → load twin, set merge.
  /// 2. Heuristic match from `IdentityMatcher` against a probable twin → set
  ///    `pendingMatchCandidate` so the UI can prompt the user.
  private func resolveMergedTwin(for profile: UserProfile) async {
    let oppositePlatform: SocialPlatform = profile.platform == .mastodon ? .bluesky : .mastodon
    guard let store = mergedIdentityStore else { return }
    guard let account = serviceManager.accounts.first(where: { $0.platform == oppositePlatform })
    else { return }

    // 1. User-confirmed merge wins.
    if let confirmed = store.merge(forPlatform: profile.platform, accountID: profile.id) {
      let twinKey = confirmed.twin(of: profile.platform)
      await loadTwinProfile(
        twinAccountID: twinKey.accountID,
        twinHandle: twinKey.handle,
        twinPlatform: twinKey.platform,
        account: account,
        displayNameEmojiMap: nil
      )
      mergedIdentity = confirmed
      return
    }

    // 2. Heuristic match against a probable twin candidate.
    if let candidateUser = await findHeuristicTwinCandidate(for: profile, account: account) {
      let candidateProfile = try? await serviceManager.fetchUserProfile(
        user: candidateUser, account: account
      )
      guard let candidateProfile else { return }
      let matcher = IdentityMatcher()
      let (mastodon, bluesky) = orderProfiles(profile, candidateProfile)
      if let match = matcher.match(mastodon: mastodon, bluesky: bluesky) {
        // Verified-bio matches we auto-apply; handle-convention is offered as a prompt.
        switch match.provenance {
        case .verifiedBioCrossLink:
          store.insert([match])
          mergedIdentity = match
          mergedTwinProfile = candidateProfile
        case .handleConvention:
          pendingMatchCandidate = match
        case .userConfirmed:
          break  // not produced by the matcher
        }
      }
    }
  }

  /// Searches the opposite network for a profile whose handle matches the
  /// shared local-part — the cheapest signal for finding a candidate.
  private func findHeuristicTwinCandidate(
    for profile: UserProfile,
    account: SocialAccount
  ) async -> SearchUser? {
    let localPart: String
    switch profile.platform {
    case .mastodon:
      // user@instance → "user"
      localPart = String(profile.username.split(separator: "@", maxSplits: 1).first ?? "")
    case .bluesky:
      // user.example.com → "user"
      localPart = String(profile.username.split(separator: ".", maxSplits: 1).first ?? "")
    }
    guard !localPart.isEmpty else { return nil }
    do {
      let result = try await serviceManager.searchUsers(
        query: localPart, account: account, limit: 5)
      return result.first(where: { user in
        switch user.platform {
        case .mastodon:
          let parts = user.username.split(separator: "@", maxSplits: 1)
          return parts.first.map(String.init)?.lowercased() == localPart.lowercased()
        case .bluesky:
          let parts = user.username.split(separator: ".", maxSplits: 1)
          return parts.first.map(String.init)?.lowercased() == localPart.lowercased()
        }
      })
    } catch {
      return nil
    }
  }

  private func loadTwinProfile(
    twinAccountID: String,
    twinHandle: String,
    twinPlatform: SocialPlatform,
    account: SocialAccount,
    displayNameEmojiMap: [String: String]?
  ) async {
    let twinUser = SearchUser(
      id: twinAccountID,
      username: twinHandle,
      displayName: nil,
      avatarURL: nil,
      platform: twinPlatform,
      displayNameEmojiMap: displayNameEmojiMap
    )
    do {
      mergedTwinProfile = try await serviceManager.fetchUserProfile(
        user: twinUser, account: account)
    } catch {
      // Non-fatal: surface header without twin; UI still shows the chip and
      // a degraded "twin unavailable" hint when needed.
      mergedTwinProfile = nil
    }
  }

  private func orderProfiles(_ a: UserProfile, _ b: UserProfile) -> (
    mastodon: UserProfile, bluesky: UserProfile
  ) {
    if a.platform == .mastodon { return (a, b) } else { return (b, a) }
  }

  // MARK: - Merge Actions

  /// Confirm a pending heuristic match and persist it.
  func confirmPendingMatch() {
    guard let candidate = pendingMatchCandidate, let store = mergedIdentityStore else { return }
    store.confirmMerge(mastodon: candidate.mastodon, bluesky: candidate.bluesky)
    mergedIdentity = store.merge(
      forPlatform: candidate.mastodon.platform, accountID: candidate.mastodon.accountID)
    pendingMatchCandidate = nil
    // The twin profile was already fetched during resolution; if not, fetch now.
    if mergedTwinProfile == nil, let profile = profile {
      let twinKey = candidate.twin(of: profile.platform)
      if let account = serviceManager.accounts.first(where: { $0.platform == twinKey.platform }) {
        Task {
          await loadTwinProfile(
            twinAccountID: twinKey.accountID,
            twinHandle: twinKey.handle,
            twinPlatform: twinKey.platform,
            account: account,
            displayNameEmojiMap: nil
          )
        }
      }
    }
  }

  /// Dismiss a pending heuristic match without persisting anything.
  func dismissPendingMatch() {
    pendingMatchCandidate = nil
  }

  /// Manually bind this profile to a twin profile on the opposite network.
  /// Called by ManualMergeSheet after the user picks a twin.
  func manualMerge(with twinSearchUser: SearchUser, twinProfile: UserProfile) async {
    guard let store = mergedIdentityStore else { return }
    guard let profile = profile else { return }

    let mastoKey: MergedIdentityKey
    let bskyKey: MergedIdentityKey
    if profile.platform == .mastodon {
      mastoKey = MergedIdentityKey(
        platform: .mastodon, accountID: profile.id, handle: profile.username)
      bskyKey = MergedIdentityKey(
        platform: .bluesky, accountID: twinProfile.id, handle: twinProfile.username)
    } else {
      mastoKey = MergedIdentityKey(
        platform: .mastodon, accountID: twinProfile.id, handle: twinProfile.username)
      bskyKey = MergedIdentityKey(
        platform: .bluesky, accountID: profile.id, handle: profile.username)
    }
    store.confirmMerge(mastodon: mastoKey, bluesky: bskyKey)
    mergedIdentity = store.merge(forPlatform: profile.platform, accountID: profile.id)
    mergedTwinProfile = twinProfile
    // Merging two identities is a deliberate, persistent commitment.
    // Success haptic confirms the binding landed — matches the
    // follow/mute/block pattern in RelationshipViewModel.
    HapticEngine.success.trigger()
  }

  /// Unmerge this profile from its twin and clear local state.
  func unmerge() {
    guard let merge = mergedIdentity, let store = mergedIdentityStore else { return }
    store.unmerge(id: merge.id)
    mergedIdentity = nil
    mergedTwinProfile = nil
    selectedSide = profile?.platform ?? user.platform
    // Selection haptic on unmerge — it's a destructive-ish action
    // (the user is unbinding) but reversible, so a soft tactile
    // cue is enough; success would feel celebratory and wrong.
    HapticEngine.selection.trigger()
  }

  // MARK: - Post Loading (Per-Tab, Lazy)

  /// Load posts for the currently selected tab (skips if already loaded)
  func loadPostsForCurrentTab() async {
    switch selectedTab {
    case .posts:
      guard !postsLoaded else { return }
    case .postsAndReplies:
      guard !postsAndRepliesLoaded else { return }
    case .media:
      guard !mediaPostsLoaded else { return }
    }

    guard !isLoadingPosts else { return }

    let activePlatform = selectedSide
    guard let account = serviceManager.accounts.first(where: { $0.platform == activePlatform })
    else { return }

    isLoadingPosts = true

    do {
      let (fetchedPosts, cursor) = try await fetchPosts(for: selectedTab, account: account)

      switch selectedTab {
      case .posts:
        posts = fetchedPosts
        postsCursor = cursor
        postsLoaded = true
        canLoadMorePosts = cursor != nil && !fetchedPosts.isEmpty
      case .postsAndReplies:
        postsAndReplies = fetchedPosts
        postsAndRepliesCursor = cursor
        postsAndRepliesLoaded = true
        canLoadMorePostsAndReplies = cursor != nil && !fetchedPosts.isEmpty
      case .media:
        mediaPosts = fetchedPosts
        mediaPostsCursor = cursor
        mediaPostsLoaded = true
        canLoadMoreMedia = cursor != nil && !fetchedPosts.isEmpty
      }
    } catch {
      // Tab-level errors are non-fatal; just stop loading
      switch selectedTab {
      case .posts:
        postsLoaded = true
        canLoadMorePosts = false
      case .postsAndReplies:
        postsAndRepliesLoaded = true
        canLoadMorePostsAndReplies = false
      case .media:
        mediaPostsLoaded = true
        canLoadMoreMedia = false
      }
    }

    isLoadingPosts = false
  }

  /// Load the next page of posts for the current tab
  func loadMorePostsForCurrentTab() async {
    guard canLoadMore, !isLoadingMore else { return }

    let activePlatform = selectedSide
    guard let account = serviceManager.accounts.first(where: { $0.platform == activePlatform })
    else { return }

    isLoadingMore = true

    do {
      let (fetchedPosts, cursor) = try await fetchPosts(
        for: selectedTab, account: account, cursor: currentCursor)

      switch selectedTab {
      case .posts:
        posts.append(contentsOf: fetchedPosts)
        postsCursor = cursor
        canLoadMorePosts = cursor != nil && !fetchedPosts.isEmpty
      case .postsAndReplies:
        postsAndReplies.append(contentsOf: fetchedPosts)
        postsAndRepliesCursor = cursor
        canLoadMorePostsAndReplies = cursor != nil && !fetchedPosts.isEmpty
      case .media:
        mediaPosts.append(contentsOf: fetchedPosts)
        mediaPostsCursor = cursor
        canLoadMoreMedia = cursor != nil && !fetchedPosts.isEmpty
      }
    } catch {
      // Pagination errors are non-fatal; stop further loads for this tab
      switch selectedTab {
      case .posts:
        canLoadMorePosts = false
      case .postsAndReplies:
        canLoadMorePostsAndReplies = false
      case .media:
        canLoadMoreMedia = false
      }
    }

    isLoadingMore = false
  }

  // MARK: - Private Helpers

  /// Current pagination cursor for the selected tab
  private var currentCursor: String? {
    switch selectedTab {
    case .posts:
      return postsCursor
    case .postsAndReplies:
      return postsAndRepliesCursor
    case .media:
      return mediaPostsCursor
    }
  }

  /// Fetch posts for a given tab with the appropriate filters.
  /// When the profile is merged AND the user is viewing the unified surface
  /// (selectedSide matches `profile.platform` — the default), both sides
  /// are fetched in parallel and merged by `createdAt`. When the user has
  /// swapped to the twin side via the handle selector, only that side fetches.
  private func fetchPosts(
    for tab: ProfileTab, account: SocialAccount, cursor: String? = nil
  ) async throws -> ([Post], String?) {
    let (excludeReplies, onlyMedia) = filters(for: tab)

    let activeUser: SearchUser = {
      if selectedSide == user.platform {
        return user
      }
      if let twin = mergedTwinProfile {
        return SearchUser(
          id: twin.id, username: twin.username,
          displayName: twin.displayName, avatarURL: twin.avatarURL,
          platform: twin.platform, displayNameEmojiMap: twin.displayNameEmojiMap
        )
      }
      return user
    }()

    let primary = try await serviceManager.fetchFilteredUserPosts(
      user: activeUser, account: account, cursor: cursor,
      excludeReplies: excludeReplies, onlyMedia: onlyMedia
    )

    // Only merge on the *first* page (cursor == nil) to keep pagination
    // simple. Subsequent pages continue paginating the primary side.
    guard cursor == nil,
          isMerged,
          selectedSide == profile?.platform,
          let twinProfile = mergedTwinProfile,
          let twinAccount = serviceManager.accounts.first(where: { $0.platform == twinProfile.platform })
    else {
      return primary
    }

    let twinUser = SearchUser(
      id: twinProfile.id,
      username: twinProfile.username,
      displayName: twinProfile.displayName,
      avatarURL: twinProfile.avatarURL,
      platform: twinProfile.platform,
      displayNameEmojiMap: twinProfile.displayNameEmojiMap
    )

    let twin: ([Post], String?)
    do {
      twin = try await serviceManager.fetchFilteredUserPosts(
        user: twinUser, account: twinAccount, cursor: nil,
        excludeReplies: excludeReplies, onlyMedia: onlyMedia
      )
    } catch {
      // Degrade gracefully — if the twin side errors, just return primary.
      return primary
    }

    let merged = (primary.0 + twin.0).sorted { $0.createdAt > $1.createdAt }
    // Pagination cursor reflects the primary side only; the twin's
    // remaining pages are surfaced when the user swaps sides.
    return (merged, primary.1)
  }

  private func filters(for tab: ProfileTab) -> (excludeReplies: Bool, onlyMedia: Bool) {
    switch tab {
    case .posts: return (excludeReplies: true, onlyMedia: false)
    case .postsAndReplies: return (excludeReplies: false, onlyMedia: false)
    case .media: return (excludeReplies: false, onlyMedia: true)
    }
  }

  /// Reset the currently-loaded tab so a side swap re-fetches under the new
  /// filter (single-network view of the now-selected side).
  func reloadCurrentTabForSideChange() async {
    switch selectedTab {
    case .posts:
      postsLoaded = false
      posts = []
      postsCursor = nil
      canLoadMorePosts = true
    case .postsAndReplies:
      postsAndRepliesLoaded = false
      postsAndReplies = []
      postsAndRepliesCursor = nil
      canLoadMorePostsAndReplies = true
    case .media:
      mediaPostsLoaded = false
      mediaPosts = []
      mediaPostsCursor = nil
      canLoadMoreMedia = true
    }
    await loadPostsForCurrentTab()
  }
}

// MARK: - Errors

enum ProfileViewModelError: LocalizedError {
  case noAccountForPlatform(SocialPlatform)

  var errorDescription: String? {
    switch self {
    case .noAccountForPlatform(let platform):
      return "No \(platform.rawValue) account available to load this profile."
    }
  }
}

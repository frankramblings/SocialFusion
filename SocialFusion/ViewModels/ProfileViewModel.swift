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

  // MARK: - Initialization

  init(user: SearchUser, isOwnProfile: Bool = false, serviceManager: SocialServiceManager) {
    self.user = user
    self.isOwnProfile = isOwnProfile
    self.serviceManager = serviceManager
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

  /// Load the full UserProfile from the API
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
    } catch {
      profileError = error
    }

    isLoadingProfile = false
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

    guard let account = serviceManager.accounts.first(where: { $0.platform == user.platform })
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

    guard let account = serviceManager.accounts.first(where: { $0.platform == user.platform })
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

  /// Fetch posts for a given tab with the appropriate filters
  private func fetchPosts(
    for tab: ProfileTab, account: SocialAccount, cursor: String? = nil
  ) async throws -> ([Post], String?) {
    switch tab {
    case .posts:
      return try await serviceManager.fetchFilteredUserPosts(
        user: user, account: account, cursor: cursor,
        excludeReplies: true, onlyMedia: false)
    case .postsAndReplies:
      return try await serviceManager.fetchFilteredUserPosts(
        user: user, account: account, cursor: cursor,
        excludeReplies: false, onlyMedia: false)
    case .media:
      return try await serviceManager.fetchFilteredUserPosts(
        user: user, account: account, cursor: cursor,
        excludeReplies: false, onlyMedia: true)
    }
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

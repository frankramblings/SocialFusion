# Profile View Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the barebones `UserDetailView` and `ProfileView` with a unified, rich profile experience featuring bio/metadata, banner images, parallax scrolling, and content tabs.

**Architecture:** One `ProfileView` accepts either a `SocialAccount` (own) or `SearchUser` (other), normalizes to `UserProfile` via the existing `fetchUserProfile()`. A `ProfileViewModel` manages profile data + per-tab post state. The header uses `GeometryReader` for parallax, and `LazyVStack(pinnedViews:)` for pinned tabs.

**Tech Stack:** SwiftUI, existing `SocialServiceManager` APIs, `HTMLFormatter` for Mastodon bios, `GeometryReader` + `PreferenceKey` for scroll-driven animations.

**Design doc:** `Docs/plans/2026-02-27-profile-view-redesign-design.md`

---

## Phase 1: Data Layer — Extend UserProfile and API Methods

### Task 1: Add Mastodon fields to UserProfile model

**Files:**
- Modify: `SocialFusion/Models/SocialModels.swift:225-272`

**Step 1: Add `fields` property to `UserProfile`**

At line 239 (after `blocking`), add:

```swift
public var fields: [ProfileField]?
public var displayNameEmojiMap: [String: String]?
```

Add a new struct before `UserProfile` (around line 223):

```swift
/// Normalized profile field (from Mastodon's key-value metadata)
public struct ProfileField: Codable, Sendable {
    public let name: String
    public let value: String  // May contain HTML (Mastodon)
    public let isVerified: Bool

    public init(name: String, value: String, isVerified: Bool = false) {
        self.name = name
        self.value = value
        self.isVerified = isVerified
    }
}
```

Update the `UserProfile.init` to include the new parameters with defaults:

```swift
fields: [ProfileField]? = nil,
displayNameEmojiMap: [String: String]? = nil
```

**Step 2: Commit**

```bash
git add SocialFusion/Models/SocialModels.swift
git commit -m "feat(models): add fields and emoji map to UserProfile"
```

---

### Task 2: Surface Mastodon fields through fetchUserProfile

**Files:**
- Modify: `SocialFusion/Services/SocialServiceManager.swift:2250-2265`

**Step 1: Map MastodonField to ProfileField in the Mastodon branch of fetchUserProfile**

In the Mastodon branch (line ~2250), update the `UserProfile` construction to include fields and emoji:

```swift
return UserProfile(
    id: mAccount.id,
    username: mAccount.acct,
    displayName: mAccount.displayName,
    avatarURL: mAccount.avatar,
    headerURL: mAccount.header ?? "",
    bio: mAccount.note ?? "",
    followersCount: mAccount.followersCount ?? 0,
    followingCount: mAccount.followingCount ?? 0,
    statusesCount: mAccount.statusesCount ?? 0,
    platform: .mastodon,
    following: relationship?.following,
    followedBy: relationship?.followedBy,
    muting: relationship?.muting,
    blocking: relationship?.blocking,
    fields: mAccount.fields?.map { field in
        ProfileField(
            name: field.name,
            value: field.value,
            isVerified: field.verifiedAt != nil
        )
    },
    displayNameEmojiMap: mAccount.emojis?.reduce(into: [String: String]()) { map, emoji in
        map[emoji.shortcode] = emoji.url
    }
)
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 3: Commit**

```bash
git add SocialFusion/Services/SocialServiceManager.swift
git commit -m "feat(services): surface Mastodon fields and emoji map in fetchUserProfile"
```

---

### Task 3: Add filtered post fetching (exclude_replies, only_media) to MastodonService

**Files:**
- Modify: `SocialFusion/Services/MastodonService.swift:1286-1290`

**Step 1: Add filter parameters to fetchUserTimeline**

Update the method signature at line 1266:

```swift
public func fetchUserTimeline(
    userId: String, for account: SocialAccount, limit: Int = 40, maxId: String? = nil,
    excludeReplies: Bool = false, onlyMedia: Bool = false, pinned: Bool = false
) async throws -> [Post] {
```

Update the URL construction at line 1287:

```swift
var urlString = "\(serverUrl)/api/v1/accounts/\(userId)/statuses?limit=\(limit)"
if let maxId = maxId {
    urlString += "&max_id=\(maxId)"
}
if excludeReplies {
    urlString += "&exclude_replies=true"
}
if onlyMedia {
    urlString += "&only_media=true"
}
if pinned {
    urlString += "&pinned=true"
}
```

**Step 2: Build to verify (existing callers use defaults, so no breakage)**

**Step 3: Commit**

```bash
git add SocialFusion/Services/MastodonService.swift
git commit -m "feat(mastodon): add exclude_replies, only_media, pinned params to fetchUserTimeline"
```

---

### Task 4: Add filter parameter to BlueskyService.fetchAuthorFeed

**Files:**
- Modify: `SocialFusion/Services/BlueskyService.swift:956-970`

**Step 1: Add filter parameter**

Update the method signature at line 956:

```swift
public func fetchAuthorFeed(
    actor: String, for account: SocialAccount, limit: Int = 40, cursor: String? = nil,
    filter: String? = nil
) async throws -> TimelineResult {
```

Update the query items construction at line 963:

```swift
var queryItems = [
    URLQueryItem(name: "actor", value: actor),
    URLQueryItem(name: "limit", value: String(limit)),
]
if let cursor = cursor {
    queryItems.append(URLQueryItem(name: "cursor", value: cursor))
}
if let filter = filter {
    queryItems.append(URLQueryItem(name: "filter", value: filter))
}
components.queryItems = queryItems
```

Valid ATProto filter values: `posts_no_replies`, `posts_with_media`, `posts_and_author_threads`.

**Step 2: Build to verify**

**Step 3: Commit**

```bash
git add SocialFusion/Services/BlueskyService.swift
git commit -m "feat(bluesky): add filter param to fetchAuthorFeed for posts/media filtering"
```

---

### Task 5: Add filtered fetch methods to SocialServiceManager

**Files:**
- Modify: `SocialFusion/Services/SocialServiceManager.swift` (after line 2227)

**Step 1: Add a new method for filtered user post fetching**

Add after `fetchUserPosts` (line 2228):

```swift
/// Fetch filtered posts for a user profile tab
public func fetchFilteredUserPosts(
    user: SearchUser, account: SocialAccount, limit: Int = 20, cursor: String? = nil,
    excludeReplies: Bool = false, onlyMedia: Bool = false
) async throws -> ([Post], String?) {
    switch user.platform {
    case .mastodon:
        var userId = user.id
        if userId.isEmpty {
            let mastodonAccount = try await mastodonService.verifyCredentials(account: account)
            userId = mastodonAccount.id
            account.platformSpecificId = userId
        }
        let posts = try await mastodonService.fetchUserTimeline(
            userId: userId, for: account, limit: limit, maxId: cursor,
            excludeReplies: excludeReplies, onlyMedia: onlyMedia)
        let nextCursor = posts.last?.platformSpecificId
        return (posts, nextCursor)

    case .bluesky:
        let filter: String?
        if onlyMedia {
            filter = "posts_with_media"
        } else if excludeReplies {
            filter = "posts_no_replies"
        } else {
            filter = nil
        }
        let result = try await blueskyService.fetchAuthorFeed(
            actor: user.id, for: account, limit: limit, cursor: cursor, filter: filter)
        return (result.posts, result.pagination.nextPageToken)
    }
}
```

**Step 2: Build to verify**

**Step 3: Commit**

```bash
git add SocialFusion/Services/SocialServiceManager.swift
git commit -m "feat(services): add fetchFilteredUserPosts for profile tab filtering"
```

---

## Phase 2: ProfileViewModel — Single Source of Truth for Profile State

### Task 6: Create ProfileViewModel

**Files:**
- Create: `SocialFusion/ViewModels/ProfileViewModel.swift`

**Step 1: Create the ViewModel**

```swift
import Foundation
import SwiftUI

/// Manages profile data and per-tab post state for the unified ProfileView
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

    // MARK: - Init

    init(user: SearchUser, isOwnProfile: Bool, serviceManager: SocialServiceManager) {
        self.user = user
        self.isOwnProfile = isOwnProfile
        self.serviceManager = serviceManager
    }

    /// Convenience init from a SocialAccount (own profile)
    convenience init(account: SocialAccount, serviceManager: SocialServiceManager) {
        let user = SearchUser(
            id: account.platformSpecificId ?? account.id,
            username: account.username,
            displayName: account.displayName,
            avatarURL: account.profilePictureURL?.absoluteString,
            platform: account.platform
        )
        self.init(user: user, isOwnProfile: true, serviceManager: serviceManager)
    }

    // MARK: - Profile Loading

    func loadProfile() async {
        guard profile == nil, !isLoadingProfile else { return }
        isLoadingProfile = true
        profileError = nil

        do {
            guard let account = serviceManager.accounts.first(where: { $0.platform == user.platform }) else {
                throw NSError(domain: "ProfileViewModel", code: 404,
                              userInfo: [NSLocalizedDescriptionKey: "No \(user.platform.rawValue) account configured"])
            }
            profile = try await serviceManager.fetchUserProfile(user: user, account: account)
        } catch {
            profileError = error
        }

        isLoadingProfile = false
    }

    // MARK: - Tab Post Loading

    func loadPostsForCurrentTab() async {
        switch selectedTab {
        case .posts:
            guard !postsLoaded else { return }
            await loadPosts(excludeReplies: true, onlyMedia: false)
        case .postsAndReplies:
            guard !postsAndRepliesLoaded else { return }
            await loadPosts(excludeReplies: false, onlyMedia: false)
        case .media:
            guard !mediaPostsLoaded else { return }
            await loadPosts(excludeReplies: false, onlyMedia: true)
        }
    }

    func loadMorePostsForCurrentTab() async {
        guard !isLoadingMore else { return }
        switch selectedTab {
        case .posts:
            guard canLoadMorePosts else { return }
        case .postsAndReplies:
            guard canLoadMorePostsAndReplies else { return }
        case .media:
            guard canLoadMoreMedia else { return }
        }
        isLoadingMore = true

        do {
            guard let account = serviceManager.accounts.first(where: { $0.platform == user.platform }) else { return }
            let cursor = cursorForCurrentTab
            let excludeReplies = selectedTab == .posts
            let onlyMedia = selectedTab == .media

            let (newPosts, nextCursor) = try await serviceManager.fetchFilteredUserPosts(
                user: user, account: account, cursor: cursor,
                excludeReplies: excludeReplies, onlyMedia: onlyMedia)

            appendPosts(newPosts, cursor: nextCursor)
        } catch {
            // Silently fail on load-more — the user can scroll again to retry
        }

        isLoadingMore = false
    }

    // MARK: - Private Helpers

    private func loadPosts(excludeReplies: Bool, onlyMedia: Bool) async {
        isLoadingPosts = true

        do {
            guard let account = serviceManager.accounts.first(where: { $0.platform == user.platform }) else { return }
            let (newPosts, nextCursor) = try await serviceManager.fetchFilteredUserPosts(
                user: user, account: account,
                excludeReplies: excludeReplies, onlyMedia: onlyMedia)

            switch selectedTab {
            case .posts:
                posts = newPosts
                postsCursor = nextCursor
                postsLoaded = true
                canLoadMorePosts = nextCursor != nil && !newPosts.isEmpty
            case .postsAndReplies:
                postsAndReplies = newPosts
                postsAndRepliesCursor = nextCursor
                postsAndRepliesLoaded = true
                canLoadMorePostsAndReplies = nextCursor != nil && !newPosts.isEmpty
            case .media:
                mediaPosts = newPosts
                mediaPostsCursor = nextCursor
                mediaPostsLoaded = true
                canLoadMoreMedia = nextCursor != nil && !newPosts.isEmpty
            }
        } catch {
            // Tab-level errors are non-fatal — profile header still shows
        }

        isLoadingPosts = false
    }

    private var cursorForCurrentTab: String? {
        switch selectedTab {
        case .posts: return postsCursor
        case .postsAndReplies: return postsAndRepliesCursor
        case .media: return mediaPostsCursor
        }
    }

    private func appendPosts(_ newPosts: [Post], cursor: String?) {
        switch selectedTab {
        case .posts:
            posts.append(contentsOf: newPosts)
            postsCursor = cursor
            canLoadMorePosts = cursor != nil && !newPosts.isEmpty
        case .postsAndReplies:
            postsAndReplies.append(contentsOf: newPosts)
            postsAndRepliesCursor = cursor
            canLoadMorePostsAndReplies = cursor != nil && !newPosts.isEmpty
        case .media:
            mediaPosts.append(contentsOf: newPosts)
            mediaPostsCursor = cursor
            canLoadMoreMedia = cursor != nil && !newPosts.isEmpty
        }
    }

    var currentPosts: [Post] {
        switch selectedTab {
        case .posts: return posts
        case .postsAndReplies: return postsAndReplies
        case .media: return mediaPosts
        }
    }

    var canLoadMore: Bool {
        switch selectedTab {
        case .posts: return canLoadMorePosts
        case .postsAndReplies: return canLoadMorePostsAndReplies
        case .media: return canLoadMoreMedia
        }
    }
}

// MARK: - ProfileTab

enum ProfileTab: String, CaseIterable {
    case posts = "Posts"
    case postsAndReplies = "Posts & Replies"
    case media = "Media"
}
```

**Step 2: Add file to Xcode project (if needed) and build**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 3: Commit**

```bash
git add SocialFusion/ViewModels/ProfileViewModel.swift
git commit -m "feat(viewmodel): add ProfileViewModel with per-tab state management"
```

---

## Phase 3: Profile Header Components

### Task 7: Create ProfileHeaderView (banner, avatar, bio, fields, stats)

**Files:**
- Create: `SocialFusion/Views/Components/ProfileHeaderView.swift`

**Step 1: Build the header component**

This is the largest single component. It renders everything above the tabs:

```swift
import SwiftUI

/// Profile header: banner, avatar, identity, bio, fields, stats
struct ProfileHeaderView: View {
    let profile: UserProfile
    let isOwnProfile: Bool
    let displayNameEmojiMap: [String: String]?
    var onEditProfile: (() -> Void)?
    @ObservedObject var relationshipVM: RelationshipViewModel

    // Scroll offset for parallax (passed from parent)
    let scrollOffset: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            bannerSection
            identitySection
        }
    }

    // MARK: - Banner

    private var bannerSection: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .named("profileScroll")).minY
            let parallaxOffset = minY > 0 ? -minY : -minY * 0.5

            Group {
                if let headerURL = profile.headerURL, !headerURL.isEmpty,
                   let url = URL(string: headerURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            bannerPlaceholder
                        }
                    }
                } else {
                    bannerPlaceholder
                }
            }
            .frame(width: geo.size.width, height: 200)
            .clipped()
            .offset(y: parallaxOffset)
        }
        .frame(height: 200)
    }

    private var bannerPlaceholder: some View {
        LinearGradient(
            colors: profile.platform == .mastodon
                ? [Color.purple.opacity(0.6), Color.purple.opacity(0.3)]
                : [Color.blue.opacity(0.6), Color.blue.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Identity Section

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Avatar + action button row
            HStack(alignment: .bottom) {
                avatarView
                    .offset(y: -24) // Overlap the banner

                Spacer()

                actionButton
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)

            // Name and handle
            VStack(alignment: .leading, spacing: 2) {
                if let displayName = profile.displayName, !displayName.isEmpty {
                    if let emojiMap = displayNameEmojiMap, !emojiMap.isEmpty {
                        EmojiDisplayNameText(displayName: displayName, emojiMap: emojiMap, font: .headline)
                    } else {
                        Text(displayName).font(.headline)
                    }
                }

                Text("@\(profile.username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .offset(y: -16) // Compensate for avatar overlap

            // Bio
            if let bio = profile.bio, !bio.isEmpty {
                bioView(bio)
                    .padding(.horizontal, 16)
            }

            // Mastodon fields
            if let fields = profile.fields, !fields.isEmpty {
                fieldsSection(fields)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }

            // Stats
            statsRow
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 12)
        }
    }

    // MARK: - Avatar

    private var avatarView: some View {
        Group {
            if let avatarURL = profile.avatarURL, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Circle().fill(Color.gray.opacity(0.3))
                    }
                }
            } else {
                Circle().fill(Color.gray.opacity(0.3))
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
        .overlay(platformBadge, alignment: .bottomTrailing)
    }

    private var platformBadge: some View {
        Image(profile.platform == .mastodon ? "mastodon-icon" : "bluesky-icon")
            .resizable()
            .frame(width: 20, height: 20)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionButton: some View {
        if isOwnProfile {
            Button("Edit Profile") {
                onEditProfile?()
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Capsule().stroke(Color.primary, lineWidth: 1))
        } else {
            // Follow/Following button
            if relationshipVM.state.isBlocking {
                Button("Blocked") {
                    Task { await relationshipVM.unblock() }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.red.opacity(0.15)))
                .foregroundStyle(.red)
            } else if relationshipVM.state.isFollowing {
                Menu {
                    Button("Unfollow", role: .destructive) {
                        Task { await relationshipVM.unfollow() }
                    }
                    if relationshipVM.state.isMuting {
                        Button("Unmute") { Task { await relationshipVM.unmute() } }
                    } else {
                        Button("Mute") { Task { await relationshipVM.mute() } }
                    }
                    Button("Block", role: .destructive) { Task { await relationshipVM.block() } }
                } label: {
                    Text("Following")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Capsule().stroke(Color.primary, lineWidth: 1))
                }
            } else {
                Button("Follow") {
                    Task { await relationshipVM.follow() }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.accentColor))
                .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Bio

    private func bioView(_ bio: String) -> some View {
        Group {
            if profile.platform == .mastodon {
                // Mastodon bios are HTML — use HTMLFormatter
                if let attributed = try? HTMLFormatter.attributedString(from: bio) {
                    Text(attributed)
                        .font(.subheadline)
                } else {
                    Text(bio.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                        .font(.subheadline)
                }
            } else {
                Text(bio)
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Fields

    private func fieldsSection(_ fields: [ProfileField]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                HStack(spacing: 6) {
                    Text(field.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 60, alignment: .trailing)

                    if field.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }

                    // Field values may contain HTML links (Mastodon)
                    if let attributed = try? HTMLFormatter.attributedString(from: field.value) {
                        Text(attributed)
                            .font(.caption)
                            .lineLimit(1)
                    } else {
                        Text(field.value)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 16) {
            statItem(count: profile.statusesCount, label: "Posts")
            statItem(count: profile.followingCount, label: "Following")
            statItem(count: profile.followersCount, label: "Followers")
        }
    }

    private func statItem(count: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Text(formatCount(count))
                .font(.subheadline.weight(.semibold))
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 10_000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}
```

**Note:** This code references `EmojiDisplayNameText` and `HTMLFormatter` which already exist in the codebase. The platform badge images (`mastodon-icon`, `bluesky-icon`) should already exist in the asset catalog — verify and adjust the image names to match what's actually there. If they don't exist, use `Image(systemName: "globe")` as a placeholder and note it for follow-up.

**Step 2: Build to verify**

**Step 3: Commit**

```bash
git add SocialFusion/Views/Components/ProfileHeaderView.swift
git commit -m "feat(ui): add ProfileHeaderView with banner, avatar, bio, fields, stats"
```

---

### Task 8: Create ProfileTabBar

**Files:**
- Create: `SocialFusion/Views/Components/ProfileTabBar.swift`

**Step 1: Create the pinnable tab bar**

```swift
import SwiftUI

/// Segmented tab bar for profile content (Posts / Posts & Replies / Media)
struct ProfileTabBar: View {
    @Binding var selectedTab: ProfileTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)

                        Rectangle()
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .background(Color(.systemBackground))
    }
}
```

**Step 2: Build to verify**

**Step 3: Commit**

```bash
git add SocialFusion/Views/Components/ProfileTabBar.swift
git commit -m "feat(ui): add ProfileTabBar with underline indicator"
```

---

### Task 9: Create ProfileMediaGridView

**Files:**
- Create: `SocialFusion/Views/Components/ProfileMediaGridView.swift`

**Step 1: Create the media grid for the Media tab**

```swift
import SwiftUI

/// 3-column grid of media thumbnails for the profile Media tab
struct ProfileMediaGridView: View {
    let posts: [Post]
    var onPostTap: ((Post) -> Void)?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(mediaPosts) { post in
                if let firstMedia = post.mediaAttachments.first {
                    Button {
                        onPostTap?(post)
                    } label: {
                        mediaThumbnail(for: firstMedia)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                    }
                }
            }
        }
    }

    /// Filter to only posts that have media
    private var mediaPosts: [Post] {
        posts.filter { !$0.mediaAttachments.isEmpty }
    }

    @ViewBuilder
    private func mediaThumbnail(for media: MediaAttachment) -> some View {
        if let urlString = media.previewURL ?? media.url,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    Rectangle().fill(Color.gray.opacity(0.2))
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                default:
                    Rectangle().fill(Color.gray.opacity(0.1))
                        .overlay(ProgressView())
                }
            }
        } else {
            Rectangle().fill(Color.gray.opacity(0.2))
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }
}
```

**Note:** This references `Post.mediaAttachments` and `MediaAttachment`. Verify the exact property names match the `Post` model — check `SocialFusion/Models/Post.swift` for `mediaAttachments` array and `MediaAttachment` struct properties (`url`, `previewURL`, `type`). Adjust property names if they differ.

**Step 2: Build to verify**

**Step 3: Commit**

```bash
git add SocialFusion/Views/Components/ProfileMediaGridView.swift
git commit -m "feat(ui): add ProfileMediaGridView with 3-column thumbnail grid"
```

---

## Phase 4: Unified ProfileView — The Main Event

### Task 10: Create the new unified ProfileView

**Files:**
- Rewrite: `SocialFusion/Views/ProfileView.swift`
- Reference: `SocialFusion/Views/UserDetailView.swift` (for behavior to preserve)

**Step 1: Read both existing files first** to understand all edge cases, callbacks, and navigation wiring that must be preserved.

**Step 2: Rewrite ProfileView.swift**

This is the core view. Key behaviors to preserve from the old views:
- `onAuthorTap` → navigates to another user's profile (chained navigation)
- `onPostTap` → navigates to post detail
- `onReply` → opens reply composer
- Blocked user detection from `UserDetailView`
- Edit Profile sheet from old `ProfileView`
- Keep `EditProfileView` in this file (it's already here at the bottom)

```swift
import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @StateObject private var navigationEnvironment = PostNavigationEnvironment()
    @StateObject private var viewModel: ProfileViewModel
    @State private var relationshipViewModel: RelationshipViewModel?
    @State private var showEditProfile = false
    @State private var replyingToPost: Post? = nil
    @State private var scrollOffset: CGFloat = 0

    // MARK: - Initializers

    /// View another user's profile
    init(user: SearchUser, serviceManager: SocialServiceManager) {
        _viewModel = StateObject(wrappedValue: ProfileViewModel(
            user: user, isOwnProfile: false, serviceManager: serviceManager))
    }

    /// View your own profile
    init(account: SocialAccount, serviceManager: SocialServiceManager) {
        _viewModel = StateObject(wrappedValue: ProfileViewModel(
            account: account, isOwnProfile: true, serviceManager: serviceManager))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                // Profile header (banner, avatar, bio, fields, stats)
                if let profile = viewModel.profile {
                    ProfileHeaderView(
                        profile: profile,
                        isOwnProfile: viewModel.isOwnProfile,
                        displayNameEmojiMap: profile.displayNameEmojiMap,
                        onEditProfile: { showEditProfile = true },
                        relationshipVM: relationshipViewModel ?? RelationshipViewModel.placeholder,
                        scrollOffset: scrollOffset
                    )
                } else if viewModel.isLoadingProfile {
                    profileSkeleton
                } else if viewModel.profileError != nil {
                    profileErrorView
                }

                // Tabs (pinned)
                Section {
                    tabContent
                } header: {
                    ProfileTabBar(selectedTab: $viewModel.selectedTab)
                        .padding(.vertical, 4)
                        .background(Color(.systemBackground))
                }
            }
        }
        .coordinateSpace(name: "profileScroll")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                compactNavTitle
            }
        }
        .task {
            await viewModel.loadProfile()
            await viewModel.loadPostsForCurrentTab()
            setupRelationshipViewModel()
        }
        .onChange(of: viewModel.selectedTab) { _ in
            Task { await viewModel.loadPostsForCurrentTab() }
        }
        .sheet(isPresented: $showEditProfile) {
            if let account = serviceManager.accounts.first(where: { $0.platform == viewModel.user.platform }) {
                EditProfileView(account: account)
                    .environmentObject(serviceManager)
            }
        }
        // Navigation destinations
        .navigationDestination(isPresented: Binding(
            get: { navigationEnvironment.selectedUser != nil },
            set: { if !$0 { navigationEnvironment.clearNavigation() } }
        )) {
            if let user = navigationEnvironment.selectedUser {
                ProfileView(user: user, serviceManager: serviceManager)
                    .environmentObject(serviceManager)
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { navigationEnvironment.selectedPost != nil },
            set: { if !$0 { navigationEnvironment.clearNavigation() } }
        )) {
            if let post = navigationEnvironment.selectedPost {
                PostDetailView(post: post)
                    .environmentObject(serviceManager)
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        if viewModel.selectedTab == .media {
            ProfileMediaGridView(posts: viewModel.currentPosts) { post in
                navigationEnvironment.navigateToPost(post)
            }
            .padding(.horizontal, 2)
        } else {
            ForEach(viewModel.currentPosts) { post in
                PostCardView(
                    post: post,
                    onAuthorTap: { navigationEnvironment.navigateToUser(from: post) },
                    onPostTap: { navigationEnvironment.navigateToPost(post) },
                    onReply: { replyingToPost = post }
                )
                .onAppear {
                    if post.id == viewModel.currentPosts.last?.id {
                        Task { await viewModel.loadMorePostsForCurrentTab() }
                    }
                }
            }
        }

        if viewModel.isLoadingPosts {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        }

        if viewModel.isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Compact Nav Title (shown when header scrolls away)

    private var compactNavTitle: some View {
        HStack(spacing: 6) {
            if let profile = viewModel.profile,
               let avatarURL = profile.avatarURL,
               let url = URL(string: avatarURL) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    }
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())
            }

            if let name = viewModel.profile?.displayName, !name.isEmpty {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .opacity(scrollOffset < -200 ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: scrollOffset < -200)
    }

    // MARK: - Loading / Error States

    private var profileSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(Color.gray.opacity(0.15))
                .frame(height: 200)
            HStack {
                Circle().fill(Color.gray.opacity(0.15))
                    .frame(width: 72, height: 72)
                Spacer()
            }
            .padding(.horizontal, 16)
            .offset(y: -24)
            RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.15))
                .frame(width: 150, height: 16)
                .padding(.horizontal, 16)
            RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.15))
                .frame(width: 200, height: 12)
                .padding(.horizontal, 16)
        }
    }

    private var profileErrorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Couldn't load this profile")
                .font(.headline)
            Button("Try Again") {
                Task { await viewModel.loadProfile() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Setup

    private func setupRelationshipViewModel() {
        guard !viewModel.isOwnProfile else { return }
        let actorID = ActorID(from: viewModel.user)
        guard let account = serviceManager.accounts.first(where: { $0.platform == viewModel.user.platform }) else { return }
        let graphService = serviceManager.graphService(for: viewModel.user.platform)
        let store = serviceManager.relationshipStore
        let vm = RelationshipViewModel(actorID: actorID, account: account,
                                       graphService: graphService, relationshipStore: store)
        relationshipViewModel = vm
        Task { await vm.loadState() }
    }
}
```

**Important notes for the implementer:**
- The `PostCardView` initializer must match what's used in the existing codebase — check `ConsolidatedTimelineView` for the exact callback names (`onAuthorTap`, `onPostTap`, `onReply`, etc.). Adjust as needed.
- `RelationshipViewModel.placeholder` — you'll need a static placeholder that provides a no-op default. Add a simple static property to `RelationshipViewModel`:
  ```swift
  static let placeholder = RelationshipViewModel(
      actorID: ActorID(id: "", platform: .mastodon),
      account: ..., graphService: ..., relationshipStore: ...)
  ```
  **Alternatively**, make `relationshipVM` optional in `ProfileHeaderView` and hide the action button when it's nil + still loading. This is cleaner — prefer this approach.
- `PostDetailView` reference — verify this view exists in the codebase. If it doesn't, wire `onPostTap` the same way the old `UserDetailView` did (or skip it if posts weren't tappable before).
- `EditProfileView` — keep the existing `EditProfileView` struct that's at the bottom of the old `ProfileView.swift`. Either leave it in the same file or extract it to its own file.
- The `scrollOffset` tracking for the compact nav title needs a `PreferenceKey`. Add a simple one:
  ```swift
  struct ScrollOffsetPreferenceKey: PreferenceKey {
      static var defaultValue: CGFloat = 0
      static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
          value = nextValue()
      }
  }
  ```
  And attach a `GeometryReader` inside the `ScrollView` to report the offset. Alternatively, if this proves too complex for the first pass, the compact nav title can always be visible (skip the fade-in animation).

**Step 3: Build and fix any compilation issues**

**Step 4: Commit**

```bash
git add SocialFusion/Views/ProfileView.swift
git commit -m "feat(ui): unified ProfileView with header, tabs, and parallax banner"
```

---

## Phase 5: Wire Up Navigation

### Task 11: Update navigation destinations across the app

**Files:**
- Modify: `SocialFusion/Views/ConsolidatedTimelineView.swift:447-460` — update `userDetailLink`
- Modify: `SocialFusion/Views/SearchView.swift` — update navigation to `UserDetailView` → `ProfileView`
- Delete or deprecate: `SocialFusion/Views/UserDetailView.swift`

**Step 1: Update ConsolidatedTimelineView**

At lines 447-460, change `UserDetailView(user: user)` to `ProfileView(user: user, serviceManager: serviceManager)`:

```swift
private var userDetailLink: some View {
    EmptyView()
        .navigationDestination(
            isPresented: Binding(
                get: { navigationEnvironment.selectedUser != nil },
                set: { if !$0 { navigationEnvironment.clearNavigation() } }
            )
        ) {
            if let user = navigationEnvironment.selectedUser {
                ProfileView(user: user, serviceManager: serviceManager)
                    .environmentObject(serviceManager)
            }
        }
}
```

**Step 2: Find and update all other references to `UserDetailView`**

Search: `grep -r "UserDetailView" SocialFusion/` to find all usage sites. Each one should be updated to `ProfileView(user:serviceManager:)`.

Common locations:
- `SearchView.swift`
- `ContentView.swift` (if it references ProfileView for the profile tab — update to new init)
- Any deep link handlers in `PostNavigationEnvironment`

**Step 3: Update the Profile tab in ContentView**

Find where the current `ProfileView(account:)` is used in `ContentView.swift` and update to the new initializer: `ProfileView(account: account, serviceManager: serviceManager)`.

**Step 4: Delete `UserDetailView.swift`**

Once all references are migrated and the build succeeds, delete it:

```bash
git rm SocialFusion/Views/UserDetailView.swift
```

**Step 5: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 6: Commit**

```bash
git add -A
git commit -m "refactor(navigation): replace all UserDetailView refs with unified ProfileView"
```

---

## Phase 6: Polish and Edge Cases

### Task 12: Handle blocked/blocking states in profile content area

**Files:**
- Modify: `SocialFusion/Views/ProfileView.swift`

**Step 1: Add blocked state handling to tabContent**

Before the ForEach in `tabContent`, check if the user is blocked:

```swift
@ViewBuilder
private var tabContent: some View {
    if let profile = viewModel.profile, profile.blocking == true {
        blockedStateView("You blocked this user. Unblock them to see their posts.")
    } else if let profile = viewModel.profile,
              relationshipViewModel?.state.isBlocking == true {
        blockedStateView("You blocked this user. Unblock them to see their posts.")
    } else if viewModel.selectedTab == .media {
        // ... existing media grid
    } else {
        // ... existing post list
    }
}

private func blockedStateView(_ message: String) -> some View {
    VStack(spacing: 12) {
        Image(systemName: "hand.raised.fill")
            .font(.title)
            .foregroundStyle(.secondary)
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 60)
}
```

**Step 2: Add "Follows you" / "Mutuals" badge to the header**

In `ProfileHeaderView`, after the action button, add a relationship badge:

```swift
if !isOwnProfile {
    if relationshipVM.state.isMutual {
        Text("Mutuals")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            .foregroundStyle(.accentColor)
    } else if relationshipVM.state.isFollowedBy {
        Text("Follows you")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
            .foregroundStyle(.secondary)
    }
}
```

**Step 3: Add bio truncation with "Show more"**

Wrap the bio in a collapsible view:

```swift
@State private var bioExpanded = false

// In bioView:
if bio.count > 300 && !bioExpanded {
    // Show truncated + "Show more" button
    Text(truncatedBio).font(.subheadline)
    Button("Show more") { bioExpanded = true }
        .font(.caption.weight(.medium))
} else {
    // Show full bio
}
```

**Step 4: Build and verify**

**Step 5: Commit**

```bash
git add SocialFusion/Views/ProfileView.swift SocialFusion/Views/Components/ProfileHeaderView.swift
git commit -m "feat(profile): add blocked state, relationship badges, bio truncation"
```

---

### Task 13: Accessibility pass

**Files:**
- Modify: `SocialFusion/Views/Components/ProfileHeaderView.swift`
- Modify: `SocialFusion/Views/Components/ProfileTabBar.swift`

**Step 1: Add accessibility labels and traits**

In `ProfileHeaderView`:
```swift
// Banner
.accessibilityHidden(true)  // Decorative

// Avatar
.accessibilityLabel("\(profile.displayName ?? profile.username)'s profile picture")

// Stats
.accessibilityElement(children: .combine)
.accessibilityLabel("\(profile.statusesCount) posts, \(profile.followingCount) following, \(profile.followersCount) followers")

// Fields
.accessibilityLabel(field.isVerified ? "\(field.name): \(strippedValue), verified" : "\(field.name): \(strippedValue)")
```

In `ProfileTabBar`:
```swift
.accessibilityElement(children: .contain)
.accessibilityLabel("Profile content filter")
// Each tab button:
.accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
```

**Step 2: Build and verify**

**Step 3: Commit**

```bash
git add SocialFusion/Views/Components/ProfileHeaderView.swift SocialFusion/Views/Components/ProfileTabBar.swift
git commit -m "a11y(profile): add accessibility labels to header, stats, fields, tabs"
```

---

### Task 14: Final integration build and smoke test

**Files:** None new — this is a verification task.

**Step 1: Full clean build**

```bash
xcodebuild clean build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

**Step 2: Check for warnings**

```bash
xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -i "warning:"
```

Look specifically for:
- AttributeGraph cycle warnings (from using computed properties in views)
- Unused variable warnings (from removed `UserDetailView` references)
- Any deprecation warnings

**Step 3: Manual smoke test checklist**

- [ ] Tap avatar in timeline → new ProfileView opens with banner, bio, counts
- [ ] Mastodon profile shows fields with verified badges
- [ ] Bluesky profile shows banner image or gradient fallback
- [ ] "Posts" tab shows original posts only
- [ ] "Posts & Replies" tab includes replies
- [ ] "Media" tab shows 3-column grid
- [ ] Switching tabs preserves scroll position
- [ ] Follow/Unfollow works with optimistic update
- [ ] Own profile (from tab) shows Edit button instead of Follow
- [ ] Back navigation works correctly
- [ ] Chained profile navigation (tap avatar within a profile) works

**Step 4: Fix any issues found**

**Step 5: Final commit**

```bash
git add -A
git commit -m "chore(profile): fix build warnings and integration issues"
```

---

## Summary

| Phase | Tasks | What it delivers |
|-------|-------|-----------------|
| 1: Data Layer | Tasks 1-5 | `UserProfile` with fields, filtered API methods |
| 2: ViewModel | Task 6 | `ProfileViewModel` with per-tab state |
| 3: Components | Tasks 7-9 | Header, tab bar, media grid components |
| 4: Main View | Task 10 | Unified `ProfileView` replacing both old views |
| 5: Navigation | Task 11 | All routes point to new `ProfileView` |
| 6: Polish | Tasks 12-14 | Blocked states, a11y, bio truncation, smoke test |

**Total: 14 tasks across 6 phases.**
**Estimated files changed:** ~10 modified, ~4 created, ~1 deleted.

# Profile View Redesign — Design Document

**Date:** 2026-02-27
**Status:** Approved
**Approach:** Incremental Enhancement (Pure SwiftUI)

## Problem

The current profile viewing experience (`UserDetailView`) is barely functional: avatar, name, and a flat post list. No bio, no banner, no follower counts (for Mastodon), no profile fields, no content tabs. Meanwhile `ProfileView` (your own account) is a separate, equally sparse implementation. Both fall far short of the quality bar set by apps like Ivory, Ice Cubes, and the native Bluesky client.

The irony: `SocialServiceManager.fetchUserProfile()` and the `UserProfile` model already exist with full bio, header, counts, and relationship data for both platforms. They're just not wired up.

## Architecture

### Unified ProfileView

Replace both `ProfileView` and `UserDetailView` with a single `ProfileView`:

- `ProfileView(account: SocialAccount)` — your own account (shows Edit button)
- `ProfileView(user: SearchUser)` — someone else (shows Follow/Mute/Block)

Both paths normalize into `UserProfile` via the existing `fetchUserProfile()`.

### State Management

- `@State private var profile: UserProfile?` — loaded profile data
- `@State private var selectedTab: ProfileTab` — current content tab (.posts, .postsAndReplies, .media)
- `@StateObject private var relationshipVM: RelationshipViewModel` — existing VM, reused
- Per-tab post arrays and pagination cursors
- Loading/error states for profile and each tab independently

### Data Flow

1. On appear, call `SocialServiceManager.fetchUserProfile()` (already handles both platforms)
2. For Mastodon, surface `MastodonAccount.fields` through `UserProfile` (needs model extension)
3. For own accounts, skip relationship fetching, show Edit button
4. Each content tab fetches lazily on first selection

## Header Layout

```
+-----------------------------------+
|                                   |
|      Banner Image (parallax)      |
|      ~200pt, aspect-fill          |
|                         [Follow]  |
+-----------------------------------+
| [Avatar]                          |
|  72pt, overlaps banner by 24pt    |
|  3pt white border, platform badge |
|                                   |
| Display Name (with custom emoji)  |
| @username@server                  |
|                                   |
| Bio text (HTML for Mastodon,      |
| plain for Bluesky, tappable       |
| links/mentions, truncated at      |
| ~6 lines with "Show more")       |
|                                   |
| +-------------------------------+ |
| | Website: example.com        V | |
| | GitHub: @user                 | |
| | Location: Brooklyn, NY       | |
| +-------------------------------+ |
| (Mastodon fields only, with       |
|  verified checkmarks)             |
|                                   |
| 243 Posts . 1.2K Following        |
|           . 4.5K Followers        |
|                                   |
| [Posts] [Posts & Replies] [Media] |
+-----------------------------------+
```

### Banner Behavior

- Default ~200pt height, aspect-fill
- Parallax at 0.5x scroll speed (compresses rather than scrolling linearly)
- No banner image: gradient from platform accent color (Mastodon purple, Bluesky blue)

### Avatar

- 72pt circle, overlaps banner bottom by ~24pt
- 3pt white border for contrast against banner
- Small platform badge (Mastodon/Bluesky icon) at bottom-right corner

### Identity

- Display name with `EmojiDisplayNameText` (existing component)
- Full handle: `@user@mastodon.social` or `@user.bsky.social`
- Bio: HTML rendered via `HTMLFormatter` for Mastodon, plain text for Bluesky
- Tappable mentions and links in bio

### Mastodon Fields

- First-class display as a distinct section below bio
- Name + value pairs with green checkmark for verified links (`verifiedAt != nil`)
- Section omitted entirely when no fields exist (all Bluesky, some Mastodon profiles)

### Stats Row

- Posts, Following, Followers counts
- Display only for now (tappable follower lists are a future iteration)

### Action Button (top-right, overlapping banner)

- Own account: "Edit Profile"
- Other user: Follow/Following primary button + `...` menu for Mute/Block/Share

## Collapsing Header & Nav Bar Transition

### Phase 1 — Full header visible (scroll offset 0)
Everything at full size. Banner, avatar, bio, stats, tabs all visible.

### Phase 2 — Banner scrolling away (offset 0 to ~200pt)
Banner parallaxes at 0.5x speed. Content scrolls normally. Avatar stays with content flow.

### Phase 3 — Header collapsed, tabs pinned (offset ~200pt+)
- Tabs pin to top of safe area
- Navigation bar shows compact version: small avatar (28pt) + display name
- Follow/Edit button in nav bar trailing position

### Implementation

- `GeometryReader` on banner to read frame relative to scroll view
- `PreferenceKey` to propagate scroll offset
- `.opacity()` and `.scaleEffect()` modifiers driven by offset for smooth transitions
- `LazyVStack(pinnedViews: .sectionHeaders)` for pinned tabs

## Content Tabs

### Posts (default)
Original posts only, no replies.
- Mastodon: `GET /api/v1/accounts/{id}/statuses?exclude_replies=true`
- Bluesky: `GET /xrpc/app.bsky.feed.getAuthorFeed?actor={did}&filter=posts_no_replies`

### Posts & Replies
Everything including replies.
- Mastodon: `GET /api/v1/accounts/{id}/statuses` (no filter)
- Bluesky: `GET /xrpc/app.bsky.feed.getAuthorFeed?actor={did}` (no filter)

### Media
3-column grid of media thumbnails.
- Mastodon: `GET /api/v1/accounts/{id}/statuses?only_media=true`
- Bluesky: `GET /xrpc/app.bsky.feed.getAuthorFeed?actor={did}&filter=posts_with_media`
- Tapping a thumbnail opens the post

### Tab Behavior
- Pin to top when scrolling (Section 3)
- Each tab maintains its own scroll position
- Lazy loading: only fetches on first selection
- Infinite scroll pagination within each tab
- Posts/Posts & Replies reuse existing `PostCardView`
- Media uses a new profile-specific thumbnail grid component

## Error Handling & Edge Cases

### Loading States
- Skeleton/shimmer placeholder while profile metadata loads
- Per-tab loading indicators for post content

### Error States
- Profile fetch fails: retry button with friendly message
- Tab fetch fails: error within that tab only, others unaffected
- Network offline: show cached profile if available, otherwise offline message

### Edge Cases
- **No banner image:** Platform-colored gradient fallback
- **No bio:** Section omitted entirely
- **No fields:** Section omitted entirely
- **Blocked user:** Profile header shown, "You blocked this user" in feed area
- **Blocking you:** Profile header shown, "This user has blocked you" in feed area
- **Very long bio:** Truncate after ~6 lines, "Show more" toggle
- **Custom emoji:** Handled by existing `EmojiDisplayNameText` and `HTMLFormatter`
- **Own profile from another account:** Shows as "other user" mode (Follow, not Edit)

### Accessibility
- All interactive elements get proper labels
- VoiceOver reads stats as "243 posts, 1,200 following, 4,500 followers"
- Banner marked as decorative
- Tab bar accessible as segmented control

## Priority Order

1. Bio + metadata + counts (wire up existing `fetchUserProfile()`)
2. Banner image with parallax collapse
3. Content tabs (Posts / Posts & Replies / Media)
4. Avatar-to-nav-bar shrink animation and pinned compact header

## Files Affected

### Replace
- `SocialFusion/Views/ProfileView.swift` — rewrite as unified profile view
- `SocialFusion/Views/UserDetailView.swift` — remove, functionality merged into ProfileView

### Modify
- `SocialFusion/Models/SocialModels.swift` — extend `UserProfile` with Mastodon fields
- `SocialFusion/Services/SocialServiceManager.swift` — add filtered post fetching (replies, media-only)
- `SocialFusion/Views/Components/PostNavigationEnvironment.swift` — update navigation destinations
- `SocialFusion/Views/ConsolidatedTimelineView.swift` — update navigation to new ProfileView
- `SocialFusion/Views/SearchView.swift` — update navigation to new ProfileView

### New
- `SocialFusion/Views/Components/ProfileHeaderView.swift` — extracted header component
- `SocialFusion/Views/Components/ProfileMediaGridView.swift` — media tab grid
- `SocialFusion/Views/Components/ProfileTabBar.swift` — pinnable tab bar
- `SocialFusion/ViewModels/ProfileViewModel.swift` — profile data loading and tab state

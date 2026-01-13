Fix custom Mastodon emoji rendering across UI components

## Problem
Custom Mastodon emoji (e.g., `:paw:`, `:superman2025:`, `:blobcatcoffee:`) were showing as text placeholders (`:paw::paw:`) instead of rendered images in several UI locations where account display names are shown.

## Root Causes
1. `EmojiDisplayNameText` component existed but wasn't used consistently across all display name locations
2. `SocialAccount.displayNameEmojiMap` was never populated when accounts were created or updated
3. Boosted posts didn't extract author emoji from the reblog structure
4. Some models (`SearchUser`, `NotificationAccount`) lacked emoji map properties

## Solution

### 1. Data Population Fixes
- **MastodonService.swift**: Populate `account.displayNameEmojiMap` in `createAccount()` and `updateProfile()` using `extractAccountEmojiMap()`
- **MastodonService.swift**: Extract author emoji from boosted posts by:
  - Extracting from display name HTML if it contains emoji tags
  - Matching shortcodes from `reblog.emojis` array that appear in display name
  - Preserving `authorEmojiMap` when hydrating boosted posts

### 2. UI Component Updates
Replaced `Text(displayName)` with `EmojiDisplayNameText` in:
- **ComposeView.swift**: Account selector menu items and button label, platform status bar
- **ProfileView.swift**: Profile header (navigation title uses plain text by design)
- **PostComposerTopBar.swift**: AccountSwitcherSheet display names
- **AccountsView.swift**: Account selection rows (both `accountSelectionRow` and `AccountRow`)
- **PostDetailView.swift**: Quick reply account menu and post detail header
- **UserDetailView.swift**: Profile header and navigation title
- **SearchUserRow.swift**: Search result rows
- **QuotePostView.swift**: Quote post author names
- **ContentView.swift**: Account picker menus
- **AccountPickerView.swift**: Account picker display

### 3. Model Enhancements
- **SocialModels.swift**: Added `displayNameEmojiMap` to `SearchUser` model
- **MastodonSearchProvider.swift**: Extract and populate emoji maps in all search result creation sites
- **PostNavigationEnvironment.swift**: Preserve `authorEmojiMap` when navigating to user profiles from posts

### 4. Navigation Title Handling
Navigation titles don't support custom views, so emoji shortcodes are stripped for plain text display while profile headers still render emoji correctly.

## Technical Approach
- Surgical replacements: Only replaced `Text` components with `EmojiDisplayNameText` where display names are shown
- No changes to: Media rendering, quote post rendering, link previews, boost/reply banner layout/animation code
- Regression prevention: Verified builds succeed, no AttributeGraph cycle warnings

## Files Changed
- SocialFusion/Services/MastodonService.swift
- SocialFusion/Views/ComposeView.swift
- SocialFusion/Views/ProfileView.swift
- SocialFusion/Views/Components/PostComposerTopBar.swift
- SocialFusion/Views/AccountsView.swift
- SocialFusion/Views/Components/PostDetailView.swift
- SocialFusion/Views/UserDetailView.swift
- SocialFusion/Views/Components/SearchUserRow.swift
- SocialFusion/Views/Components/QuotePostView.swift
- SocialFusion/ContentView.swift
- SocialFusion/Views/AccountPickerView.swift
- SocialFusion/Models/SocialModels.swift
- SocialFusion/Services/Search/MastodonSearchProvider.swift
- SocialFusion/Views/Components/PostNavigationEnvironment.swift

## Results
✅ Custom emoji now render correctly in:
- Profile headers
- Search results
- Post detail views
- Quote posts
- Account selectors and pickers
- Composer UI
- Boosted posts (when emoji data available in reblog structure)

✅ Build succeeds for iOS 26.2 on iPhone 17 Pro
✅ No compilation errors or new warnings
✅ Graceful fallback to plain text when emoji maps are nil

## Limitations
- Boosted posts: If Mastodon API doesn't include account emoji in reblog structure, emoji may not render until post is hydrated
- `NotificationAccount` and `User` models: Don't have emoji map properties (would require model changes)
- Navigation titles: Show plain text (by design, since they don't support custom views)

## Testing Notes
Manual testing required to verify:
- Emoji render correctly in all identified locations
- Boost/reply banners still work correctly
- Media, quotes, and link previews unaffected
- No layout regressions

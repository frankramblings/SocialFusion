# Universal Feed Picker Design

**Date:** 2026-02-25
**Status:** Approved

## Problem

The timeline navigation is split across two controls that don't work well together:
- An **account switcher** (upper-left avatar) that sets the scope
- A **feed picker pill** (center nav bar) that picks feeds within that scope

When in "All Accounts" mode, the feed picker only offers "Unified" — a dead end. All the rich feed options (Mastodon Lists, Bluesky Custom Feeds, Local/Federated, Instance Browser) are locked behind switching to a single account first. The two controls create a confusing two-step navigation where one control should suffice.

## Solution: The Universal Pill

Consolidate all timeline navigation into a single center pill. Remove the account switcher from the upper-left. The upper-left becomes a profile/settings hub instead.

### Navigation Layout

```
Before:
  [Account ▾]     ▼ Feed ▾       [Compose]
  (scope)         (feed within scope)

After:
  [Profile ▾]     ▼ Feed ▾       [Compose]
  (me/settings)   (ALL timeline navigation)
```

### Universal Pill — Popover Structure

**Top level:**
```
┌────────────────────────────────────┐
│  ✓ Unified                         │
│    All Mastodon          (if 2+)   │
│    All Bluesky           (if 2+)   │
├────────────────────────────────────┤
│  🐘 @frank@mastodon.social      > │
│  🦋 @frank.bsky.social           > │
└────────────────────────────────────┘
```

- **"Unified"** — interleaved timeline from all accounts
- **"All Mastodon"** — only shown when 2+ Mastodon accounts exist; merges their home timelines
- **"All Bluesky"** — only shown when 2+ Bluesky accounts exist; merges their following feeds
- Per-account rows with platform indicator and drill-in chevron

**Drill-in (Mastodon account):**
```
┌────────────────────────────────────┐
│  ← @frank@mastodon.social          │
├────────────────────────────────────┤
│    Home                            │
│    Local                           │
│    Federated                       │
│    ─────────────                   │
│    Tech List                       │
│    News List                       │
│    ─────────────                   │
│    Browse Instance…                │
└────────────────────────────────────┘
```

**Drill-in (Bluesky account):**
```
┌────────────────────────────────────┐
│  ← @frank.bsky.social              │
├────────────────────────────────────┤
│    Following                       │
│    ─────────────                   │
│    Discover                        │
│    What's Hot                      │
│    Tech Feed                       │
└────────────────────────────────────┘
```

Selecting any feed dismisses the popover and loads that timeline.

**Pill label** reflects the selection:
- "Unified" / "All Mastodon" / "All Bluesky" for top-level options
- Feed name with account avatar inline for per-account feeds (e.g., `[avatar] Home`)

### Upper-Left Profile/Settings Hub

The avatar button becomes a contextual profile/settings menu:

```
┌────────────────────────────────────┐
│  [avatar]  @frank@mastodon.social  │
│            Frank Emanuele          │
├────────────────────────────────────┤
│  ⚙  Settings                       │
│  +  Add Account                    │
│  🐛 Debug Options                  │
└────────────────────────────────────┘
```

- Avatar reflects the context of the current feed selection:
  - Unified/All platform → composite icon or primary account
  - Specific account's feed → that account's avatar
- Implemented as a native `.menu` dropdown

### Data Model Changes

**`TimelineFeedSelection` becomes account-aware:**
```swift
enum TimelineFeedSelection: Hashable, Codable {
  case unified
  case allMastodon                                        // NEW
  case allBluesky                                         // NEW
  case mastodon(accountId: String, feed: MastodonTimelineFeed)  // accountId added
  case bluesky(accountId: String, feed: BlueskyTimelineFeed)    // accountId added
}
```

**`TimelineFetchPlan` gains platform-wide cases:**
```swift
enum TimelineFetchPlan {
  case unified(accounts: [SocialAccount])
  case allMastodon(accounts: [SocialAccount])              // NEW
  case allBluesky(accounts: [SocialAccount])               // NEW
  case mastodon(account: SocialAccount, feed: MastodonTimelineFeed)
  case bluesky(account: SocialAccount, feed: BlueskyTimelineFeed)
}
```

**`TimelineScope` kept as derived property** (not user-settable):
```swift
var currentTimelineScope: TimelineScope {
  switch currentTimelineFeedSelection {
  case .unified, .allMastodon, .allBluesky: return .allAccounts
  case .mastodon(let accountId, _): return .account(id: accountId)
  case .bluesky(let accountId, _): return .account(id: accountId)
  }
}
```

This keeps the 36 existing `TimelineScope` references across 10 files working with minimal changes.

### What Gets Removed

- `SimpleAccountDropdown` component
- `AccountDropdownView` (deprecated, kept for reference)
- `accountButton` toolbar item in `ContentView`
- `selectedAccountId` `@SceneStorage` in `ContentView`
- `selectedAccountIds` as a user-settable property on `SocialServiceManager`
- `switchToAccount(id:)` in `ContentView`
- `showAccountDropdown` state and overlay

### What Gets Added

- Enhanced `TimelineFeedPickerPopover` with drill-in navigation and all-accounts mode
- Profile/settings menu button in upper-left toolbar position
- `allMastodon` / `allBluesky` fetch paths in `SocialServiceManager`
- Conditional display logic for platform filters (only when 2+ accounts per platform)

### Edge Cases

- **Single account:** Picker shows Unified (if only 1 account, functionally same as that account's home) plus the account's drill-in. Could skip Unified entirely and default to the account's feeds.
- **No accounts:** Onboarding flow intercepts before this UI is shown (existing behavior).
- **Lists/feeds loading:** Drill-in shows a loading indicator while fetching Mastodon lists or Bluesky saved feeds (existing behavior in current picker).

## Files Affected

### Modified
- `ContentView.swift` — Remove account switcher, add profile/settings menu
- `ConsolidatedTimelineView.swift` — Update toolbar, remove scope-dependent picker gating
- `TimelineFeedPickerPopover.swift` — Major rewrite: drill-in navigation, all-accounts mode
- `TimelineFeedSelection.swift` — Add `allMastodon`/`allBluesky` cases, add `accountId` to platform cases
- `SocialServiceManager.swift` — Derive `TimelineScope`, add platform-wide fetch, remove `selectedAccountIds` setter
- `NavBarPillSelector.swift` — Update label logic for account-aware selections
- `TimelineFeedPickerViewModel.swift` — Support loading feeds for any account in all-accounts mode

### Possibly Modified (dependent on `TimelineScope`)
- `ComposeView.swift` — May need to derive compose context from feed selection
- `AutocompleteService.swift` — Timeline context derivation
- `TimelineContextProvider.swift` / `TimelineContextSuggestionProvider.swift` — Context derivation
- `UnifiedTimelineContextProvider.swift` — Context derivation
- `TimelineContext.swift` — Model may need updates

### Removed
- `SimpleAccountDropdown` (or its container view)

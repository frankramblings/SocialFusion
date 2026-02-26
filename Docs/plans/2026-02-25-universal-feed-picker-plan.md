# Universal Feed Picker Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Consolidate the separate account switcher and feed picker into a single universal center pill, surfacing all feeds from all accounts with drill-in navigation.

**Architecture:** Extend `TimelineFeedSelection` to be account-aware (carrying `accountId`), add `allMastodon`/`allBluesky` cases, derive `TimelineScope` as a computed property. Rewrite `TimelineFeedPickerPopover` with drill-in navigation showing all accounts. Replace the upper-left account switcher with a profile/settings menu.

**Tech Stack:** SwiftUI, existing `NavBarPillDropdown`/`NavBarPillDropdownContainer` components, `SocialServiceManager` state management.

**Design doc:** `docs/plans/2026-02-25-universal-feed-picker-design.md`

---

### Task 1: Extend `TimelineFeedSelection` and `TimelineFetchPlan` Enums

This is the foundational change. Everything else builds on it.

**Files:**
- Modify: `SocialFusion/Models/TimelineFeedSelection.swift`

**Step 1: Update `TimelineFeedSelection` enum (line 65-69)**

Replace:
```swift
enum TimelineFeedSelection: Hashable, Codable {
    case unified
    case mastodon(MastodonTimelineFeed)
    case bluesky(BlueskyTimelineFeed)
}
```

With:
```swift
enum TimelineFeedSelection: Hashable, Codable {
    case unified
    case allMastodon
    case allBluesky
    case mastodon(accountId: String, feed: MastodonTimelineFeed)
    case bluesky(accountId: String, feed: BlueskyTimelineFeed)
}
```

**Step 2: Update `TimelineFetchPlan` enum (line 71-75)**

Replace:
```swift
enum TimelineFetchPlan {
    case unified(accounts: [SocialAccount])
    case mastodon(account: SocialAccount, feed: MastodonTimelineFeed)
    case bluesky(account: SocialAccount, feed: BlueskyTimelineFeed)
}
```

With:
```swift
enum TimelineFetchPlan {
    case unified(accounts: [SocialAccount])
    case allMastodon(accounts: [SocialAccount])
    case allBluesky(accounts: [SocialAccount])
    case mastodon(account: SocialAccount, feed: MastodonTimelineFeed)
    case bluesky(account: SocialAccount, feed: BlueskyTimelineFeed)
}
```

**Step 3: Build the project to see all compiler errors from exhaustive switch changes**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep "error:" | head -40`

Expected: Multiple errors in `SocialServiceManager.swift`, `ConsolidatedTimelineView.swift`, `TimelineFeedPickerPopover.swift` for non-exhaustive switch statements and pattern matching changes.

**Step 4: Commit**

```bash
git add SocialFusion/Models/TimelineFeedSelection.swift
git commit -m "refactor: make TimelineFeedSelection account-aware with allMastodon/allBluesky cases"
```

---

### Task 2: Update `SocialServiceManager` — Core State Management

Fix all compiler errors in the service manager and rewire the state management so `TimelineScope` becomes derived.

**Files:**
- Modify: `SocialFusion/Services/SocialServiceManager.swift`

**Step 1: Make `currentTimelineScope` a computed property**

At lines 115-116, change:
```swift
@Published private(set) var currentTimelineScope: TimelineScope = .allAccounts
@Published private(set) var currentTimelineFeedSelection: TimelineFeedSelection = .unified
```

To:
```swift
var currentTimelineScope: TimelineScope {
    switch currentTimelineFeedSelection {
    case .unified, .allMastodon, .allBluesky:
        return .allAccounts
    case .mastodon(let accountId, _):
        return .account(id: accountId)
    case .bluesky(let accountId, _):
        return .account(id: accountId)
    }
}
@Published private(set) var currentTimelineFeedSelection: TimelineFeedSelection = .unified
```

Note: Removing `@Published` from `currentTimelineScope` means views that observe it will now observe `currentTimelineFeedSelection` changes instead (which triggers the computed property). Any `objectWillChange` firing for `currentTimelineFeedSelection` will cause views reading `currentTimelineScope` to re-evaluate. This should be seamless since both were published before.

**Step 2: Simplify `resolveTimelineFetchPlan()` (lines 439-460)**

Replace the method body with:
```swift
func resolveTimelineFetchPlan() -> TimelineFetchPlan? {
    let selection = currentTimelineFeedSelection
    switch selection {
    case .unified:
        return .unified(accounts: accounts)
    case .allMastodon:
        let mastodon = accounts.filter { $0.platform == .mastodon }
        return mastodon.isEmpty ? nil : .allMastodon(accounts: mastodon)
    case .allBluesky:
        let bluesky = accounts.filter { $0.platform == .bluesky }
        return bluesky.isEmpty ? nil : .allBluesky(accounts: bluesky)
    case .mastodon(let accountId, let feed):
        guard let account = accounts.first(where: { $0.id == accountId }) else { return nil }
        return .mastodon(account: account, feed: feed)
    case .bluesky(let accountId, let feed):
        guard let account = accounts.first(where: { $0.id == accountId }) else { return nil }
        return .bluesky(account: account, feed: feed)
    }
}
```

**Step 3: Remove `resolveTimelineScope()` (lines 462-470)**

Delete the entire `resolveTimelineScope()` method — no longer needed since scope is computed.

**Step 4: Simplify `updateTimelineSelectionFromScope()` (lines 401-422)**

Replace with a simpler version that just ensures the current selection is valid:
```swift
func updateTimelineSelectionFromScope() {
    let previous = currentTimelineFeedSelection
    // Validate current selection is still valid
    switch currentTimelineFeedSelection {
    case .unified, .allMastodon, .allBluesky:
        break  // Always valid
    case .mastodon(let accountId, _):
        if !accounts.contains(where: { $0.id == accountId }) {
            currentTimelineFeedSelection = .unified
        }
    case .bluesky(let accountId, _):
        if !accounts.contains(where: { $0.id == accountId }) {
            currentTimelineFeedSelection = .unified
        }
    }
    if previous != currentTimelineFeedSelection {
        resetPagination()
    }
}
```

**Step 5: Simplify `setTimelineFeedSelection()` (lines 424-437)**

Replace with:
```swift
func setTimelineFeedSelection(_ selection: TimelineFeedSelection) {
    currentTimelineFeedSelection = selection
    persistTimelineFeedSelection()
    resetPagination()
}
```

**Step 6: Remove `resolveSelection()` (lines 472-497) and `accountForScope()` (lines 499-506)**

Delete both methods — no longer needed.

**Step 7: Update persistence methods**

Replace the per-scope dictionary persistence with single-selection persistence.

Change `timelineFeedSelectionsByScope` (line 117) and `persistTimelineFeedSelections` / `loadTimelineFeedSelections` to persist a single `TimelineFeedSelection` under a new key `"timelineFeedSelectionV2"`:

```swift
private let timelineFeedSelectionKeyV2 = "timelineFeedSelectionV2"

private func persistTimelineFeedSelection() {
    if let data = try? JSONEncoder().encode(currentTimelineFeedSelection) {
        UserDefaults.standard.set(data, forKey: timelineFeedSelectionKeyV2)
    }
}

private func loadTimelineFeedSelection() {
    if let data = UserDefaults.standard.data(forKey: timelineFeedSelectionKeyV2),
       let selection = try? JSONDecoder().decode(TimelineFeedSelection.self, from: data) {
        currentTimelineFeedSelection = selection
    }
}
```

Remove `timelineFeedSelectionsByScope` dictionary and old persistence methods.

**Step 8: Update `refreshTimeline(plan:)` (line 1774)**

Add cases for `.allMastodon` and `.allBluesky`:
```swift
case .allMastodon(let accounts):
    return try await refreshTimeline(
        accounts: accounts,
        shouldMerge: shouldMergeOnRefresh,
        generation: generation
    )
case .allBluesky(let accounts):
    return try await refreshTimeline(
        accounts: accounts,
        shouldMerge: shouldMergeOnRefresh,
        generation: generation
    )
```

**Step 9: Fix `paginationTokenKey` (lines 1913-1924)**

Update the switch to handle new cases:
```swift
private func paginationTokenKey(for account: SocialAccount, selection: TimelineFeedSelection) -> String {
    switch selection {
    case .unified, .allMastodon, .allBluesky:
        return account.id
    case .mastodon(_, let feed):
        return "\(account.id):\(feed.cacheKey)"
    case .bluesky(_, let feed):
        return "\(account.id):\(feed.cacheKey)"
    }
}
```

**Step 10: Fix `fetchNextPageForAccount` (lines 2506-2526)**

Update the switch:
```swift
private func fetchNextPageForAccount(
    _ account: SocialAccount,
    selection: TimelineFeedSelection
) async throws -> TimelineResult {
    let tokenKey = paginationTokenKey(for: account, selection: selection)
    let token = paginationTokens[tokenKey]

    switch selection {
    case .unified, .allMastodon, .allBluesky:
        switch account.platform {
        case .mastodon:
            return try await mastodonService.fetchHomeTimeline(for: account, maxId: token)
        case .bluesky:
            return try await blueskyService.fetchHomeTimeline(for: account, cursor: token)
        }
    case .mastodon(_, let feed):
        return try await fetchMastodonTimeline(account: account, feed: feed, maxId: token)
    case .bluesky(_, let feed):
        return try await fetchBlueskyTimeline(account: account, feed: feed, cursor: token)
    }
}
```

**Step 11: Fix all `updatePaginationTokens` call sites**

These construct `TimelineFeedSelection` inline for pagination. Update all occurrences:

- Line 1788: `selection: .mastodon(feed)` → `selection: .mastodon(accountId: account.id, feed: feed)`
- Line 1802: `selection: .bluesky(feed)` → `selection: .bluesky(accountId: account.id, feed: feed)`
- Line 2388: `selection: .unified` → stays as-is
- Line 2402: `selection: .mastodon(feed)` → `selection: .mastodon(accountId: account.id, feed: feed)`
- Line 2409: same
- Line 2419: `selection: .bluesky(feed)` → `selection: .bluesky(accountId: account.id, feed: feed)`
- Line 2426: same

**Step 12: Fix loadMore pagination switch (lines 2374-2432)**

Add cases for `.allMastodon` and `.allBluesky` in the `switch plan` block. These behave identically to `.unified` — iterate accounts and fetch next pages:

```swift
case .allMastodon(let accountsToFetch), .allBluesky(let accountsToFetch):
    guard !accountsToFetch.isEmpty else { return }
    for account in accountsToFetch {
        do {
            let sel: TimelineFeedSelection = plan is case .allMastodon ? .allMastodon : .allBluesky
            let result = try await fetchNextPageForAccount(account, selection: currentTimelineFeedSelection)
            hadSuccessfulFetch = true
            allNewPosts.append(contentsOf: result.posts)
            updatePaginationTokens(for: account, selection: currentTimelineFeedSelection, pagination: result.pagination)
            if result.pagination.hasNextPage { hasMorePagesFromSuccess = true }
        } catch {
            recordPaginationFailure(accountName: account.username, error: error)
        }
    }
```

Note: The exact pattern matching syntax for combining enum cases may need adjustment. If needed, duplicate the `.unified` block for each new case.

**Step 13: Replace `selectedAccountIds` usage in initialization (lines 336-358)**

Change from:
```swift
selectedAccountIds = ["all"]
```
To:
```swift
loadTimelineFeedSelection()
// If no valid selection was loaded, default to unified
```

And on account add (lines 796-808), change from setting `selectedAccountIds` to keeping `currentTimelineFeedSelection` as `.unified`.

**Step 14: Replace `selectedAccountIds` in account removal (lines 924-926)**

Change:
```swift
selectedAccountIds.remove(account.id)
if selectedAccountIds.isEmpty {
    selectedAccountIds = ["all"]
}
```
To:
```swift
// If the removed account was in the current selection, fall back to unified
switch currentTimelineFeedSelection {
case .mastodon(let accountId, _), .bluesky(let accountId, _):
    if accountId == account.id {
        setTimelineFeedSelection(.unified)
    }
default:
    break
}
```

**Step 15: Update `getAccountsToFetch()` (lines 732-753)**

Replace the body with fetch-plan-based logic:
```swift
private func getAccountsToFetch() -> [SocialAccount] {
    guard let plan = resolveTimelineFetchPlan() else { return [] }
    switch plan {
    case .unified(let accts), .allMastodon(let accts), .allBluesky(let accts):
        return accts
    case .mastodon(let account, _):
        return [account]
    case .bluesky(let account, _):
        return [account]
    }
}
```

**Step 16: Remove `selectedAccountIds` property entirely (lines 107-112)**

Once all references are updated, remove the property. Search for any remaining references with a build.

**Step 17: Update UI test fixture `seedAccountSwitchFixturesForUITests()` (line 4472)**

Change `selectedAccountIds = ["all"]` to `currentTimelineFeedSelection = .unified`.

**Step 18: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: Clean build with no errors in SocialServiceManager.

**Step 19: Commit**

```bash
git add SocialFusion/Services/SocialServiceManager.swift
git commit -m "refactor: derive TimelineScope from account-aware TimelineFeedSelection"
```

---

### Task 3: Update `ConsolidatedTimelineView` — Feed Title and Picker Wiring

Fix compiler errors and update the pill label and picker instantiation.

**Files:**
- Modify: `SocialFusion/Views/ConsolidatedTimelineView.swift`

**Step 1: Update `currentFeedTitle` (lines 660-667)**

Replace:
```swift
private var currentFeedTitle: String {
    switch serviceManager.currentTimelineScope {
    case .allAccounts:
        return "Unified"
    case .account:
        return feedTitle(for: serviceManager.currentTimelineFeedSelection)
    }
}
```

With:
```swift
private var currentFeedTitle: String {
    return feedTitle(for: serviceManager.currentTimelineFeedSelection)
}
```

**Step 2: Update `feedTitle(for:)` (lines 669-706)**

Add new cases and update pattern matching:
```swift
private func feedTitle(for selection: TimelineFeedSelection) -> String {
    switch selection {
    case .unified:
        return "Unified"
    case .allMastodon:
        return "All Mastodon"
    case .allBluesky:
        return "All Bluesky"
    case .mastodon(_, let feed):
        switch feed {
        case .home:
            return "Home"
        case .local:
            return "Local"
        case .federated:
            return "Federated"
        case .list(let id, let title):
            if let title = title { return title }
            if let list = feedPickerViewModel.mastodonLists.first(where: { $0.id == id }) {
                return list.title
            }
            return "List"
        case .instance(let server):
            return "Instance: \(server)"
        }
    case .bluesky(_, let feed):
        switch feed {
        case .following:
            return "Following"
        case .custom(let uri, let name):
            if let name = name { return name }
            if let feed = feedPickerViewModel.blueskyFeeds.first(where: { $0.uri == uri }) {
                return feed.displayName
            }
            return "Feed"
        }
    }
}
```

**Step 3: Update `currentScopeAccount` (lines 651-658)**

This stays structurally the same since `currentTimelineScope` is still available as a computed property. No change needed.

**Step 4: Update `handleFeedSelection` (lines 708-711)**

No structural change needed — `setTimelineFeedSelection` signature simplified but the call pattern is the same.

**Step 5: Update `TimelineFeedPickerPopover` instantiation (lines 473-480)**

This will be updated in Task 5 when we rewrite the popover. For now, adjust to remove `scope` and `account` parameters — pass `accounts` list instead. This can temporarily be stubbed if the popover hasn't been rewritten yet. For now, just make it compile by passing the required params.

**Step 6: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 7: Commit**

```bash
git add SocialFusion/Views/ConsolidatedTimelineView.swift
git commit -m "refactor: update ConsolidatedTimelineView for account-aware feed selection"
```

---

### Task 4: Update `TimelineFeedPickerViewModel` — Per-Account Caching

The view model needs to support loading lists/feeds for any account, not just the currently scoped one.

**Files:**
- Modify: `SocialFusion/ViewModels/TimelineFeedPickerViewModel.swift`

**Step 1: Add per-account caching**

Replace single `mastodonLists` and `blueskyFeeds` with dictionaries:

```swift
@Published var mastodonListsByAccount: [String: [MastodonList]] = [:]
@Published var blueskyFeedsByAccount: [String: [BlueskyFeedGenerator]] = [:]
@Published var loadingListsForAccount: String? = nil
@Published var loadingFeedsForAccount: String? = nil
```

Keep the existing `mastodonLists` and `blueskyFeeds` as convenience computed properties if needed elsewhere:
```swift
var mastodonLists: [MastodonList] { mastodonListsByAccount.values.flatMap { $0 } }
var blueskyFeeds: [BlueskyFeedGenerator] { blueskyFeedsByAccount.values.flatMap { $0 } }
```

**Step 2: Update `loadMastodonLists` (lines 22-31)**

```swift
func loadMastodonLists(for account: SocialAccount) async {
    guard loadingListsForAccount != account.id else { return }
    guard mastodonListsByAccount[account.id] == nil else { return }  // Already cached
    loadingListsForAccount = account.id
    defer { loadingListsForAccount = nil }
    do {
        mastodonListsByAccount[account.id] = try await serviceManager.fetchMastodonLists(account: account)
    } catch {
        mastodonListsByAccount[account.id] = []
    }
}
```

**Step 3: Update `loadBlueskyFeeds` (lines 33-42)**

```swift
func loadBlueskyFeeds(for account: SocialAccount) async {
    guard loadingFeedsForAccount != account.id else { return }
    guard blueskyFeedsByAccount[account.id] == nil else { return }  // Already cached
    loadingFeedsForAccount = account.id
    defer { loadingFeedsForAccount = nil }
    do {
        blueskyFeedsByAccount[account.id] = try await serviceManager.fetchBlueskySavedFeeds(account: account)
    } catch {
        blueskyFeedsByAccount[account.id] = []
    }
}
```

**Step 4: Add helper methods for the popover to check loading state per account**

```swift
func isLoadingLists(for accountId: String) -> Bool {
    return loadingListsForAccount == accountId
}

func isLoadingFeeds(for accountId: String) -> Bool {
    return loadingFeedsForAccount == accountId
}

func lists(for accountId: String) -> [MastodonList] {
    return mastodonListsByAccount[accountId] ?? []
}

func feeds(for accountId: String) -> [BlueskyFeedGenerator] {
    return blueskyFeedsByAccount[accountId] ?? []
}
```

**Step 5: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 6: Commit**

```bash
git add SocialFusion/ViewModels/TimelineFeedPickerViewModel.swift
git commit -m "refactor: add per-account list/feed caching to TimelineFeedPickerViewModel"
```

---

### Task 5: Rewrite `TimelineFeedPickerPopover` — Universal Drill-In Navigation

This is the biggest UI change. The popover gets a new structure with all accounts visible at the top level and drill-in per account.

**Files:**
- Modify: `SocialFusion/Views/Components/TimelineFeedPickerPopover.swift`

**Step 1: Update the `Step` enum and properties**

Replace the current struct interface:

```swift
struct TimelineFeedPickerPopover: View {
    enum Step: Equatable {
        case root
        case accountDetail(SocialAccount)
        case mastodonLists(SocialAccount)
        case blueskyFeeds(SocialAccount)
        case instanceBrowser(SocialAccount)
    }

    @ObservedObject var viewModel: TimelineFeedPickerViewModel
    @Binding var isPresented: Bool
    let selection: TimelineFeedSelection
    let accounts: [SocialAccount]
    let mastodonAccounts: [SocialAccount]
    let blueskyAccounts: [SocialAccount]
    let onSelect: (TimelineFeedSelection) -> Void

    @State private var step: Step = .root

    private let width: CGFloat = 260
```

**Step 2: Rewrite the body switch**

```swift
var body: some View {
    ZStack {
        switch step {
        case .root:
            NavBarPillDropdown(sections: rootSections, width: width)
                .onAppear { viewModel.instanceSearchText = "" }
        case .accountDetail(let account):
            accountDetailView(for: account)
        case .mastodonLists(let account):
            listsView(for: account)
        case .blueskyFeeds(let account):
            feedsView(for: account)
        case .instanceBrowser(let account):
            instanceBrowserView(for: account)
        }
    }
    .onChange(of: isPresented) { _, presented in
        if presented {
            step = .root
            viewModel.instanceSearchText = ""
        }
    }
}
```

**Step 3: Rewrite `rootSections`**

The top level always shows Unified, optionally All Mastodon/All Bluesky (conditional on 2+ accounts per platform), then per-account rows with drill-in:

```swift
private var rootSections: [NavBarPillDropdownSection] {
    var topItems: [NavBarPillDropdownItem] = [
        NavBarPillDropdownItem(
            id: "unified",
            title: "Unified",
            isSelected: selection == .unified,
            action: { select(.unified) }
        )
    ]

    if mastodonAccounts.count >= 2 {
        topItems.append(NavBarPillDropdownItem(
            id: "all-mastodon",
            title: "All Mastodon",
            isSelected: selection == .allMastodon,
            action: { select(.allMastodon) }
        ))
    }

    if blueskyAccounts.count >= 2 {
        topItems.append(NavBarPillDropdownItem(
            id: "all-bluesky",
            title: "All Bluesky",
            isSelected: selection == .allBluesky,
            action: { select(.allBluesky) }
        ))
    }

    var sections = [NavBarPillDropdownSection(id: "top", header: nil, items: topItems)]

    let accountItems: [NavBarPillDropdownItem] = accounts.map { account in
        let platformIcon = account.platform == .mastodon ? "🐘" : "🦋"
        let isAccountSelected: Bool = {
            switch selection {
            case .mastodon(let id, _): return id == account.id
            case .bluesky(let id, _): return id == account.id
            default: return false
            }
        }()
        return NavBarPillDropdownItem(
            id: "account-\(account.id)",
            title: "\(platformIcon) \(account.displayNameOrHandle)",
            isSelected: isAccountSelected,
            action: { step = .accountDetail(account) }
        )
    }

    if !accountItems.isEmpty {
        sections.append(NavBarPillDropdownSection(id: "accounts", header: nil, items: accountItems))
    }

    return sections
}
```

Note: `account.displayNameOrHandle` — check the `SocialAccount` model for the right property name. It may be `username` or `displayName`. Use the appropriate existing property.

**Step 4: Add `accountDetailView` — the drill-in for each account**

```swift
private func accountDetailView(for account: SocialAccount) -> some View {
    NavBarPillDropdownContainer(width: width) {
        drillInHeader(title: account.displayNameOrHandle, backTo: .root)
        Divider().padding(.horizontal, 12)

        if account.platform == .mastodon {
            mastodonFeedItems(for: account)
        } else {
            blueskyFeedItems(for: account)
        }
    }
}

@ViewBuilder
private func mastodonFeedItems(for account: SocialAccount) -> some View {
    let accountId = account.id
    NavBarPillDropdownRow(
        title: "Home",
        isSelected: isSelected(.mastodon(accountId: accountId, feed: .home)),
        action: { select(.mastodon(accountId: accountId, feed: .home)) }
    )
    Divider().padding(.horizontal, 12)
    NavBarPillDropdownRow(
        title: "Local",
        isSelected: isSelected(.mastodon(accountId: accountId, feed: .local)),
        action: { select(.mastodon(accountId: accountId, feed: .local)) }
    )
    Divider().padding(.horizontal, 12)
    NavBarPillDropdownRow(
        title: "Federated",
        isSelected: isSelected(.mastodon(accountId: accountId, feed: .federated)),
        action: { select(.mastodon(accountId: accountId, feed: .federated)) }
    )
    Divider().padding(.horizontal, 12)
    NavBarPillDropdownRow(
        title: "Lists...",
        isSelected: false,
        action: { step = .mastodonLists(account) }
    )
    Divider().padding(.horizontal, 12)
    NavBarPillDropdownRow(
        title: "Browse Instance...",
        isSelected: false,
        action: { step = .instanceBrowser(account) }
    )
}

@ViewBuilder
private func blueskyFeedItems(for account: SocialAccount) -> some View {
    let accountId = account.id
    NavBarPillDropdownRow(
        title: "Following",
        isSelected: isSelected(.bluesky(accountId: accountId, feed: .following)),
        action: { select(.bluesky(accountId: accountId, feed: .following)) }
    )
    Divider().padding(.horizontal, 12)
    NavBarPillDropdownRow(
        title: "My Feeds...",
        isSelected: false,
        action: { step = .blueskyFeeds(account) }
    )
}
```

**Step 5: Rewrite `listsView` to accept an account parameter**

```swift
private func listsView(for account: SocialAccount) -> some View {
    NavBarPillDropdownContainer(width: width) {
        drillInHeader(title: "Lists", backTo: .accountDetail(account))
        Divider().padding(.horizontal, 12)

        if viewModel.isLoadingLists(for: account.id) {
            ProgressView()
                .padding(.vertical, 16)
        } else if viewModel.lists(for: account.id).isEmpty {
            Text("No lists found")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.vertical, 16)
        } else {
            let lists = viewModel.lists(for: account.id)
            ForEach(Array(lists.enumerated()), id: \.element.id) { index, list in
                NavBarPillDropdownRow(
                    title: list.title,
                    isSelected: isSelected(.mastodon(accountId: account.id, feed: .list(id: list.id, title: list.title))),
                    action: { select(.mastodon(accountId: account.id, feed: .list(id: list.id, title: list.title))) }
                )
                if index < lists.count - 1 {
                    Divider().padding(.horizontal, 12)
                }
            }
        }
    }
    .onAppear {
        Task { await viewModel.loadMastodonLists(for: account) }
    }
}
```

**Step 6: Rewrite `feedsView` to accept an account parameter**

```swift
private func feedsView(for account: SocialAccount) -> some View {
    NavBarPillDropdownContainer(width: width) {
        drillInHeader(title: "My Feeds", backTo: .accountDetail(account))
        Divider().padding(.horizontal, 12)

        if viewModel.isLoadingFeeds(for: account.id) {
            ProgressView()
                .padding(.vertical, 16)
        } else if viewModel.feeds(for: account.id).isEmpty {
            Text("No feeds found")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.vertical, 16)
        } else {
            let feeds = viewModel.feeds(for: account.id)
            ForEach(Array(feeds.enumerated()), id: \.element.uri) { index, feed in
                NavBarPillDropdownRow(
                    title: feed.displayName,
                    isSelected: isSelected(.bluesky(accountId: account.id, feed: .custom(uri: feed.uri, name: feed.displayName))),
                    action: { select(.bluesky(accountId: account.id, feed: .custom(uri: feed.uri, name: feed.displayName))) }
                )
                if index < feeds.count - 1 {
                    Divider().padding(.horizontal, 12)
                }
            }
        }
    }
    .onAppear {
        Task { await viewModel.loadBlueskyFeeds(for: account) }
    }
}
```

**Step 7: Update `instanceBrowserView` to accept an account parameter**

Wrap the existing instance browser view to take an account and use it when selecting:

```swift
private func instanceBrowserView(for account: SocialAccount) -> some View {
    // Same structure as existing, but:
    // - drillInHeader backTo: .accountDetail(account)
    // - selectInstance calls: select(.mastodon(accountId: account.id, feed: .instance(server: server)))
    ...
}
```

**Step 8: Update `drillInHeader` to support flexible back navigation**

```swift
private func drillInHeader(title: String, backTo: Step = .root) -> some View {
    HStack(spacing: 8) {
        Button(action: { step = backTo }) {
            Image(systemName: "chevron.left")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .buttonStyle(PlainButtonStyle())

        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.primary)

        Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
}
```

**Step 9: Replace all `isSelectedMastodon`/`isSelectedBluesky`/etc. helpers**

Replace with a single generic helper:
```swift
private func isSelected(_ candidate: TimelineFeedSelection) -> Bool {
    return selection == candidate
}
```

For list/feed selection where you need fuzzy matching on just the id/uri (ignoring title):
```swift
private func isSelectedList(accountId: String, listId: String) -> Bool {
    if case .mastodon(let id, .list(let lid, _)) = selection {
        return id == accountId && lid == listId
    }
    return false
}

private func isSelectedFeed(accountId: String, feedUri: String) -> Bool {
    if case .bluesky(let id, .custom(let uri, _)) = selection {
        return id == accountId && uri == feedUri
    }
    return false
}
```

**Step 10: Update `select` and `selectInstance` helpers**

```swift
private func select(_ selection: TimelineFeedSelection) {
    onSelect(selection)
    dismiss()
}

private func selectInstance(_ server: String, for account: SocialAccount) {
    viewModel.recordRecentInstance(server)
    onSelect(.mastodon(accountId: account.id, feed: .instance(server: server)))
    dismiss()
}
```

**Step 11: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 12: Commit**

```bash
git add SocialFusion/Views/Components/TimelineFeedPickerPopover.swift
git commit -m "feat: rewrite TimelineFeedPickerPopover with universal drill-in navigation"
```

---

### Task 6: Update Popover Instantiation in `ConsolidatedTimelineView`

Wire the new popover parameters.

**Files:**
- Modify: `SocialFusion/Views/ConsolidatedTimelineView.swift`

**Step 1: Update the `TimelineFeedPickerPopover` instantiation (lines 473-480)**

Replace:
```swift
TimelineFeedPickerPopover(
    viewModel: feedPickerViewModel,
    isPresented: $showFeedPicker,
    scope: serviceManager.currentTimelineScope,
    selection: serviceManager.currentTimelineFeedSelection,
    account: currentScopeAccount,
    onSelect: handleFeedSelection(_:)
)
```

With:
```swift
TimelineFeedPickerPopover(
    viewModel: feedPickerViewModel,
    isPresented: $showFeedPicker,
    selection: serviceManager.currentTimelineFeedSelection,
    accounts: serviceManager.accounts,
    mastodonAccounts: serviceManager.mastodonAccounts,
    blueskyAccounts: serviceManager.blueskyAccounts,
    onSelect: handleFeedSelection(_:)
)
```

**Step 2: Remove `currentScopeAccount` computed property (lines 651-658)**

It's no longer needed.

**Step 3: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 4: Commit**

```bash
git add SocialFusion/Views/ConsolidatedTimelineView.swift
git commit -m "feat: wire universal feed picker into ConsolidatedTimelineView"
```

---

### Task 7: Replace Account Switcher with Profile/Settings Hub in `ContentView`

Remove the account dropdown and replace it with a profile/settings menu.

**Files:**
- Modify: `SocialFusion/ContentView.swift`

**Step 1: Remove account dropdown state (lines 15-16, 19-20, 26)**

Remove:
```swift
@SceneStorage("selectedAccountId") private var selectedAccountId: String?
@State private var previousAccountId: String? = nil
@State private var showAccountPicker = false
@State private var showAccountDropdown = false
@State private var isSwitchingAccounts = false
```

Keep `showAddAccountView` — it's used by the profile/settings hub.

**Step 2: Simplify `homeTabContent` (lines 209-239)**

Remove the account dropdown overlay and switching indicator ZStack layers:

```swift
private var homeTabContent: some View {
    NavigationStack {
        ConsolidatedTimelineView(serviceManager: serviceManager)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    profileMenuButton
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    composeButton
                }
            }
    }
}
```

**Step 3: Create `profileMenuButton` to replace `accountButton`**

```swift
private var profileMenuButton: some View {
    Menu {
        Section {
            if let account = contextualAccount {
                Label(account.displayNameOrHandle, systemImage: account.platform == .mastodon ? "person.circle" : "person.circle")
            }
        }
        Section {
            Button {
                showAddAccountView = true
            } label: {
                Label("Add Account", systemImage: "plus")
            }
            NavigationLink(value: "settings") {
                Label("Settings", systemImage: "gearshape")
            }
        }
    } label: {
        contextualAvatarView
            .frame(width: 28, height: 28)
    }
}

private var contextualAccount: SocialAccount? {
    switch serviceManager.currentTimelineFeedSelection {
    case .mastodon(let accountId, _):
        return serviceManager.accounts.first(where: { $0.id == accountId })
    case .bluesky(let accountId, _):
        return serviceManager.accounts.first(where: { $0.id == accountId })
    default:
        return serviceManager.accounts.first
    }
}

@ViewBuilder
private var contextualAvatarView: some View {
    if let account = contextualAccount {
        ProfileImageView(account: account)
    } else {
        UnifiedAccountsIcon(accounts: serviceManager.accounts)
    }
}
```

Note: The exact implementation of `ProfileImageView` and `UnifiedAccountsIcon` — check existing code for these. They already exist and are used by the current `accountButton`.

**Step 4: Remove `accountDropdownOverlay` (lines 359-386)**

Delete the entire computed property.

**Step 5: Remove `switchToAccount(id:)` (lines 557-589)**

Delete the entire method.

**Step 6: Remove `SimpleAccountDropdown` struct (lines 634-767)**

Delete the entire struct definition.

**Step 7: Remove `AccountDropdownView` if present**

Delete the deprecated struct.

**Step 8: Remove `initializeSelection()` references to `selectedAccountIds`**

Update or simplify `initializeSelection()` to not reference account selection state.

**Step 9: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: Errors in NotificationsView, SearchView, ProfileView for removed bindings.

**Step 10: Commit**

```bash
git add SocialFusion/ContentView.swift
git commit -m "feat: replace account switcher with profile/settings hub"
```

---

### Task 8: Remove Account Dropdown Plumbing from Other Views

Clean up `NotificationsView`, `SearchView`, and `ProfileView` which all receive `showAccountDropdown` as a binding and have their own `accountButton`/`accountDropdownOverlay`/`SimpleAccountDropdown`.

**Files:**
- Modify: `SocialFusion/Views/NotificationsView.swift`
- Modify: `SocialFusion/Views/SearchView.swift`
- Modify: `SocialFusion/Views/ProfileView.swift`

**Step 1: In each view, remove:**
- `@Binding var showAccountDropdown: Bool` property
- `accountButton` computed property
- `accountDropdownOverlay` computed property
- All `SimpleAccountDropdown` usage
- All `if showAccountDropdown { accountDropdownOverlay }` overlays

**Step 2: In `ContentView`, update the view instantiations**

Remove `showAccountDropdown: $showAccountDropdown` from the init calls for `NotificationsView`, `SearchView`, `ProfileView`, and any other views that received it.

Also remove `selectedAccountId`, `previousAccountId` bindings if passed.

**Step 3: For each view's toolbar, add a simple `profileMenuButton` if it had an `accountButton`**

Each view can either:
- Add its own profile menu button (same as ContentView's `profileMenuButton`)
- Or simply remove the leading toolbar item if the profile button only needs to be on the Home tab

Recommendation: Only the Home tab gets the profile/settings hub in the upper left. Other tabs can have their own appropriate leading items or nothing.

**Step 4: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: Clean build.

**Step 5: Commit**

```bash
git add SocialFusion/Views/NotificationsView.swift SocialFusion/Views/SearchView.swift SocialFusion/Views/ProfileView.swift SocialFusion/ContentView.swift
git commit -m "refactor: remove account dropdown plumbing from all views"
```

---

### Task 9: Update `NavBarPillSelector` — Optional Leading Icon

Add an optional leading icon/avatar to the pill for when showing per-account feeds.

**Files:**
- Modify: `SocialFusion/Components/NavBarPillSelector.swift`
- Modify: `SocialFusion/Views/ConsolidatedTimelineView.swift`

**Step 1: Add optional `leadingIcon` to `NavBarPillSelector`**

```swift
struct NavBarPillSelector<LeadingContent: View>: View {
    let title: String
    let isExpanded: Bool
    let action: () -> Void
    let leadingContent: LeadingContent?

    init(
        title: String,
        isExpanded: Bool,
        action: @escaping () -> Void,
        @ViewBuilder leadingContent: () -> LeadingContent
    ) {
        self.title = title
        self.isExpanded = isExpanded
        self.action = action
        self.leadingContent = leadingContent()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let leadingContent {
                    leadingContent
                }
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                // ... rest unchanged
            }
        }
    }
}

// Convenience init without leading content
extension NavBarPillSelector where LeadingContent == EmptyView {
    init(title: String, isExpanded: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isExpanded = isExpanded
        self.action = action
        self.leadingContent = nil
    }
}
```

**Step 2: In `ConsolidatedTimelineView`, pass account avatar when on a per-account feed**

```swift
NavBarPillSelector(
    title: currentFeedTitle,
    isExpanded: showFeedPicker,
    action: { ... }
) {
    if let account = currentFeedAccount {
        ProfileImageView(account: account)
            .frame(width: 18, height: 18)
            .clipShape(Circle())
    }
}
```

Where `currentFeedAccount` is:
```swift
private var currentFeedAccount: SocialAccount? {
    switch serviceManager.currentTimelineFeedSelection {
    case .mastodon(let id, _):
        return serviceManager.accounts.first(where: { $0.id == id })
    case .bluesky(let id, _):
        return serviceManager.accounts.first(where: { $0.id == id })
    default:
        return nil
    }
}
```

**Step 3: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 4: Commit**

```bash
git add SocialFusion/Components/NavBarPillSelector.swift SocialFusion/Views/ConsolidatedTimelineView.swift
git commit -m "feat: add optional leading icon to NavBarPillSelector for account context"
```

---

### Task 10: Final Integration Build and Cleanup

**Files:**
- All modified files

**Step 1: Full clean build**

Run: `xcodebuild clean build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 2: Search for any remaining references to removed code**

```bash
grep -rn "selectedAccountIds\|showAccountDropdown\|accountDropdownOverlay\|SimpleAccountDropdown\|switchToAccount" --include="*.swift" SocialFusion/ | grep -v ".claude/"
```

Fix any remaining references.

**Step 3: Search for any remaining old-format TimelineFeedSelection usage**

```bash
grep -rn "\.mastodon(\." --include="*.swift" SocialFusion/ | grep -v "accountId" | grep -v ".claude/"
```

This finds `TimelineFeedSelection` constructions missing `accountId`. Fix any found.

**Step 4: Run on simulator to verify**

```bash
xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet && xcrun simctl install booted $(find ~/Library/Developer/Xcode/DerivedData -name "SocialFusion.app" -path "*/Debug-iphonesimulator/*" | head -1) && xcrun simctl launch booted com.socialfusionapp.app
```

Manually verify:
- [ ] Center pill shows "Unified" by default
- [ ] Tapping pill shows top-level menu with Unified + account rows
- [ ] Tapping account row drills into that account's feeds
- [ ] Selecting a feed loads the correct timeline
- [ ] Back navigation in drill-in works
- [ ] "All Mastodon" / "All Bluesky" appear only with 2+ accounts per platform
- [ ] Upper-left shows profile/settings menu
- [ ] Pill label updates correctly for each feed type
- [ ] Account avatar appears in pill for per-account feeds
- [ ] Feed selection persists across app relaunches

**Step 5: Commit any cleanup**

```bash
git add -A && git commit -m "chore: final cleanup for universal feed picker"
```

---

### Dependency Order

```
Task 1 (enum changes)
    ↓
Task 2 (SocialServiceManager)
    ↓
Task 3 (ConsolidatedTimelineView basics)
    ↓
Task 4 (ViewModel caching)
    ↓
Task 5 (Popover rewrite)
    ↓
Task 6 (Wire popover)
    ↓
Task 7 (ContentView profile hub)
    ↓
Task 8 (Remove dropdown from other views)
    ↓
Task 9 (Pill leading icon)
    ↓
Task 10 (Integration + cleanup)
```

Tasks 1→2→3 must be sequential (compiler errors cascade).
Tasks 4 and 5 can potentially be done in parallel after Task 3.
Tasks 7 and 8 can potentially be done in parallel after Task 6.

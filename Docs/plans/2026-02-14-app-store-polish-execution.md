# App Store Polish Execution Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the highest-impact polish and reliability regressions so the app feels smooth, consistent, and production-ready.

**Architecture:** Keep existing architecture intact and apply focused fixes in timeline rendering, compose/editor flow, offline reliability, and media pipelines. Prioritize low-risk, user-visible improvements first, then harden internals and add instrumentation hooks for measurable quality gates.

**Tech Stack:** SwiftUI, Combine, Swift Concurrency, SwiftData/XCTest, xcodebuild

### Task 1: Timeline Scroll Hot-Path Cleanup

**Files:**
- Modify: `SocialFusion/Views/ConsolidatedTimelineView.swift`
- Test: `SocialFusionUITests/TimelineRegressionTests.swift`

**Step 1: Remove release-path logging and row-triggered churn**
- Remove `print` calls in scroll preference and posts change handlers.
- Keep diagnostics only behind debug flags.

**Step 2: Replace per-row pagination trigger**
- Replace `.task { await handleInfiniteScroll(...) }` on each row with one tail sentinel trigger.

**Step 3: Verify**
Run:
```bash
xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionUITests/TimelineRegressionTests test
```

### Task 2: PostCard Delayed State Update Removal

**Files:**
- Modify: `SocialFusion/Views/Components/PostCardView.swift`
- Test: `SocialFusionTests/PostLayoutSnapshotBuilderTests.swift`

**Step 1: Remove fixed 200ms sleeps from cache update path**
- Keep updates async-safe but immediate.

**Step 2: Ensure card state updates are idempotent and low-churn**
- Avoid duplicate task scheduling.

**Step 3: Verify**
Run:
```bash
xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/PostLayoutSnapshotBuilderTests test
```

### Task 3: Read Tracking Write Batching

**Files:**
- Modify: `SocialFusion/Services/ViewTracker.swift`
- Modify: `SocialFusion/Views/Components/PostCardView.swift`
- Add: `SocialFusionTests/ViewTrackerBatchingTests.swift`

**Step 1: Add buffered read queue + coalesced persistence flush**
- Batch write read IDs on a short debounce interval.

**Step 2: Update call sites to enqueue and avoid immediate write-per-cell**

**Step 3: Verify**
Run:
```bash
xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/ViewTrackerBatchingTests test
```

### Task 4: Offline Queue ID Correctness

**Files:**
- Modify: `SocialFusion/Services/SocialServiceManager.swift`
- Add: `SocialFusionTests/OfflineQueueActionReplayTests.swift`

**Step 1: Queue platform-native post identifier**
- Store `platformSpecificId` for queued actions with fallback compatibility.

**Step 2: Resolve queued IDs correctly during replay**
- Prefer native ID lookups; preserve backward compatibility for old entries.

**Step 3: Verify**
Run:
```bash
xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/OfflineQueueActionReplayTests test
```

### Task 5: Composer Hot-Path Cleanup

**Files:**
- Modify: `SocialFusion/Views/ComposeView.swift`
- Add: `SocialFusionTests/ComposeAutocompleteLatencyTests.swift`

**Step 1: Remove production hot-path prints in autocomplete pipeline**

**Step 2: Reuse autocomplete service instance when scope/accounts unchanged**

**Step 3: Verify**
Run:
```bash
xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/ComposeAutocompleteLatencyTests test
```

### Task 6: Media/Image Pipeline Hardening

**Files:**
- Modify: `SocialFusion/Views/Components/CachedAsyncImage.swift`
- Modify: `SocialFusion/Utilities/MediaDimensionCache.swift`
- Modify: `SocialFusion/Utilities/MediaPrefetcher.swift`
- Add: `SocialFusionTests/MediaDimensionCacheKeyTests.swift`

**Step 1: Remove high-priority artificial jitter**

**Step 2: Fix media dimension disk key round-trip**

**Step 3: Cleanup completed prefetch tasks**

**Step 4: Verify**
Run:
```bash
xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/MediaDimensionCacheKeyTests test
```

### Task 7: Pagination + Error UX Reliability

**Files:**
- Modify: `SocialFusion/Services/SocialServiceManager.swift`
- Modify: `SocialFusion/Views/ConsolidatedTimelineView.swift`
- Add: `SocialFusionTests/PaginationReliabilityTests.swift`

**Step 1: Make pagination loading state transitions deterministic**

**Step 2: Surface partial pagination failures in timeline state**

**Step 3: Consolidate duplicate error handling paths**

**Step 4: Verify**
Run:
```bash
xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/PaginationReliabilityTests test
```

### Task 8: Interaction Consistency and Accessibility

**Files:**
- Modify: `SocialFusion/ContentView.swift`
- Modify: `SocialFusion/Views/Components/PostActionBar.swift`
- Modify: `SocialFusion/Views/Components/PostDetailView.swift`
- Add: `SocialFusionUITests/TimelineRefreshUITests.swift`

**Step 1: Convert compose toolbar affordance to semantic button with proper hit target**

**Step 2: Ensure single compose sheet owner to avoid presentation conflicts**

**Step 3: Wire quote action paths where quote controls are shown**

**Step 4: Verify**
Run:
```bash
xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionUITests/TimelineRefreshUITests test
```

### Task 9: Deterministic Refresh Cadence + Account Switch Smoothness

**Files:**
- Modify: `SocialFusion/Controllers/TimelineRefreshCoordinator.swift`
- Modify: `SocialFusion/ContentView.swift`
- Add: `SocialFusionTests/TimelineRefreshCoordinatorTests.swift`

**Step 1: Make auto-refresh interval scheduling deterministic per platform cycle**

**Step 2: Remove account-switch empty flash with non-destructive transition state**

**Step 3: Verify**
Run:
```bash
xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/TimelineRefreshCoordinatorTests test
```

### Task 10: Final Verification Gate

**Files:**
- Modify: `SocialFusion/Services/MediaPerformanceMonitor.swift` (if instrumentation hooks are needed)
- Modify: `SocialFusion/Utilities/SocialFusionTimelineDebug.swift` (if needed)

**Step 1: Run full targeted verification suite**
Run:
```bash
xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

**Step 2: Validate acceptance criteria evidence**
- Confirm no known failing tests.
- Confirm no new warnings introduced by modified paths.
- Confirm timeline and compose critical paths have no production `print` spam.


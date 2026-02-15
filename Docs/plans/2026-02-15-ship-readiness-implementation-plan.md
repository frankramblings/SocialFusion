# SocialFusion Ship Readiness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deliver all agreed P0/P1 ship-blocking polish items and reach a stable release candidate suitable for TestFlight and App Store review.

**Architecture:** Execute in gated waves: P0 functional correctness first, then P0 performance/security, then P1 interaction polish and platform integrations, followed by hardening and release verification. Every workstream is test-first, scoped to minimal file touch points, and merged only after acceptance criteria and regression checks pass.

**Tech Stack:** SwiftUI, UIKit interop, AppIntents, Share Extension APIs, SwiftData, UserDefaults/SceneStorage, XCTest, XCUITest, xcodebuild.

## Execution Rules

- Branching: create one branch per wave with `codex/` prefix.
- Merge rule: no wave merges until all tests for that wave pass.
- Regression rule: run targeted tests per task, then full `SocialFusionTests` + `SocialFusionUITests` at wave boundary.
- Release rule: no known P0 issues, no sensitive logging in release builds, no crashers in smoke pass.

## Wave Plan

### Wave 0: Baseline And Guardrails (P0 prerequisite)

### Task 1: Baseline Test Matrix And Ownership Lock

**Owner:** Release Lead + QA Lead  
**Files:**
- Modify: `run_tests.sh`
- Modify: `TESTFLIGHT_WHAT_TO_TEST.txt`
- Create: `Docs/ship-readiness-matrix.md`
- Test: `SocialFusionUITests/TimelineRegressionTests.swift`

**Step 1: Write the failing test/check**

Add a matrix check that fails when any required P0/P1 test suite is missing from CI script.

**Step 2: Run test to verify it fails**

Run: `./run_tests.sh`  
Expected: FAIL due to missing matrix entries.

**Step 3: Write minimal implementation**

Add explicit test groups and ownership mapping to `run_tests.sh` and `Docs/ship-readiness-matrix.md`.

**Step 4: Run test to verify it passes**

Run: `./run_tests.sh`  
Expected: PASS for matrix preflight section.

**Step 5: Commit**

```bash
git add run_tests.sh TESTFLIGHT_WHAT_TO_TEST.txt Docs/ship-readiness-matrix.md
git commit -m "chore: add ship-readiness matrix and test ownership"
```

### Wave 1: P0 Functional Completeness

### Task 2: Search Action Parity (Reply/Quote + Failure UX)

**Owner:** Search Pod  
**Files:**
- Modify: `SocialFusion/Views/SearchView.swift`
- Modify: `SocialFusion/Views/ComposeView.swift`
- Test: `SocialFusionTests/SearchPostRenderingTests.swift`
- Test: `SocialFusionUITests/TimelineRegressionTests.swift`

**Step 1: Write the failing test**

Add tests that assert search result post cards invoke reply and quote flows and that action failures show UI feedback.

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/SearchPostRenderingTests test`  
Expected: FAIL for missing reply/quote wiring.

**Step 3: Write minimal implementation**

Wire `onReply` and `onQuote` in `SearchView` to present `ComposeView` with `replyingTo` / `quotingTo`, and replace `try?` action calls with explicit success/failure handling plus toast/banner.

**Step 4: Run test to verify it passes**

Run the command from Step 2 again.  
Expected: PASS.

**Step 5: Commit**

```bash
git add SocialFusion/Views/SearchView.swift SocialFusion/Views/ComposeView.swift SocialFusionTests/SearchPostRenderingTests.swift
git commit -m "feat: complete search reply and quote action parity"
```

### Task 3: Native Search UX (`.searchable`, suggestions, completions)

**Owner:** Search Pod  
**Files:**
- Modify: `SocialFusion/Views/SearchView.swift`
- Modify: `SocialFusion/Stores/SearchStore.swift`
- Modify: `SocialFusion/Views/Components/SearchChipRow.swift`
- Test: `SocialFusionTests/SearchStoreTests.swift`
- Test: `SocialFusionUITests/TimelineRegressionTests.swift`

**Step 1: Write the failing test**

Add tests for suggestions/completions behavior and scope/sort interactions.

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/SearchStoreTests test`  
Expected: FAIL for missing native searchable behaviors.

**Step 3: Write minimal implementation**

Adopt `.searchable` with `searchSuggestions`, map recent/pinned terms to completions, preserve existing scopes, and keep direct-open path.

**Step 4: Run test to verify it passes**

Run the command from Step 2 again.  
Expected: PASS.

**Step 5: Commit**

```bash
git add SocialFusion/Views/SearchView.swift SocialFusion/Stores/SearchStore.swift SocialFusion/Views/Components/SearchChipRow.swift SocialFusionTests/SearchStoreTests.swift
git commit -m "feat: migrate search to native searchable with suggestions"
```

### Task 4: Search Race Safety (latest-query-wins)

**Owner:** Search Infra  
**Files:**
- Modify: `SocialFusion/Stores/SearchStore.swift`
- Test: `SocialFusionTests/SearchStoreTests.swift`

**Step 1: Write the failing test**

Add async race tests where older query responses arrive after newer queries and must be discarded.

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/SearchStoreTests/testLatestQueryWinsWhenTasksRace test`  
Expected: FAIL showing stale overwrite.

**Step 3: Write minimal implementation**

Add generation token + cancellable direct-open task + strict stale-result guards.

**Step 4: Run test to verify it passes**

Run the command from Step 2 again.  
Expected: PASS.

**Step 5: Commit**

```bash
git add SocialFusion/Stores/SearchStore.swift SocialFusionTests/SearchStoreTests.swift
git commit -m "fix: enforce latest-query-wins in search store"
```

### Task 5: State Restoration (tab/account/thread/composer draft)

**Owner:** Core Navigation  
**Files:**
- Modify: `SocialFusion/ContentView.swift`
- Modify: `SocialFusion/Views/ConsolidatedTimelineView.swift`
- Modify: `SocialFusion/Views/ComposeView.swift`
- Modify: `SocialFusion/Services/SocialServiceManager.swift`
- Test: `SocialFusionUITests/TimelineRegressionTests.swift`
- Create: `SocialFusionUITests/StateRestorationUITests.swift`

**Step 1: Write the failing test**

Create UI test that opens a non-default tab/account, enters composer draft, terminates app, relaunches, and verifies restored state.

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionUITests/StateRestorationUITests test`  
Expected: FAIL due to partial restoration.

**Step 3: Write minimal implementation**

Add `@SceneStorage` for tab/account/composer context, persist in-progress compose state, restore deep-link/post context when app re-enters active scene.

**Step 4: Run test to verify it passes**

Run the command from Step 2 again.  
Expected: PASS.

**Step 5: Commit**

```bash
git add SocialFusion/ContentView.swift SocialFusion/Views/ConsolidatedTimelineView.swift SocialFusion/Views/ComposeView.swift SocialFusion/Services/SocialServiceManager.swift SocialFusionUITests/StateRestorationUITests.swift
git commit -m "feat: restore tab account thread and composer draft state"
```

### Wave 2: P0 Performance And Security

### Task 6: Remove Main-Thread I/O And Decode Hotspots

**Owner:** Performance Pod  
**Files:**
- Modify: `SocialFusion/Stores/DraftStore.swift`
- Modify: `SocialFusion/Services/ViewTracker.swift`
- Modify: `SocialFusion/Views/ComposeView.swift`
- Test: `SocialFusionTests/MediaRobustnessTests.swift`
- Create: `SocialFusionTests/DraftStoreIOTests.swift`
- Create: `SocialFusionTests/ViewTrackerPerformanceTests.swift`

**Step 1: Write the failing test**

Add tests and profiling assertions for non-blocking draft load, read-state load, and draft image hydration.

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/DraftStoreIOTests -only-testing:SocialFusionTests/ViewTrackerPerformanceTests test`  
Expected: FAIL for blocking operations.

**Step 3: Write minimal implementation**

Move blocking disk/decode work to detached/background tasks or actors and only publish final state on MainActor.

**Step 4: Run test to verify it passes**

Run the command from Step 2 again.  
Expected: PASS.

**Step 5: Commit**

```bash
git add SocialFusion/Stores/DraftStore.swift SocialFusion/Services/ViewTracker.swift SocialFusion/Views/ComposeView.swift SocialFusionTests/DraftStoreIOTests.swift SocialFusionTests/ViewTrackerPerformanceTests.swift
git commit -m "perf: offload draft and read-state io from main thread"
```

### Task 7: Release Logging Sanitization

**Owner:** Release/Security  
**Files:**
- Modify: `SocialFusion/Services/MastodonService.swift`
- Modify: `SocialFusion/Services/BlueskyService.swift`
- Modify: `SocialFusion/Utilities/MonitoringService.swift`
- Create: `SocialFusionTests/ReleaseLoggingTests.swift`

**Step 1: Write the failing test**

Add tests that scan logging paths for token previews and raw response body dumps.

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/ReleaseLoggingTests test`  
Expected: FAIL due to sensitive log strings.

**Step 3: Write minimal implementation**

Replace sensitive logs with structured redacted logging and guard debug-only diagnostics behind compile flags.

**Step 4: Run test to verify it passes**

Run the command from Step 2 again.  
Expected: PASS.

**Step 5: Commit**

```bash
git add SocialFusion/Services/MastodonService.swift SocialFusion/Services/BlueskyService.swift SocialFusion/Utilities/MonitoringService.swift SocialFusionTests/ReleaseLoggingTests.swift
git commit -m "security: redact tokens and raw payloads from release logging"
```

### Wave 3: P1 Interaction Polish

### Task 8: Reachability Rail For Pro Max

**Owner:** Product UI + App Shell  
**Files:**
- Modify: `SocialFusion/ContentView.swift`
- Modify: `SocialFusion/Views/Components/LiquidGlassComponents.swift`
- Modify: `SocialFusion/Views/NotificationsView.swift`
- Test: `SocialFusionUITests/TimelineRegressionTests.swift`
- Create: `SocialFusionUITests/ReachabilityUITests.swift`

**Step 1: Write the failing test**

Add UI tests that verify compose/account controls are accessible in one-handed zone on Pro Max viewport.

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:SocialFusionUITests/ReachabilityUITests test`  
Expected: FAIL with controls outside reachability bounds.

**Step 3: Write minimal implementation**

Introduce bottom safe-area action rail with adaptive layout preserving iPad and compact phone behavior.

**Step 4: Run test to verify it passes**

Run the command from Step 2 again.  
Expected: PASS.

**Step 5: Commit**

```bash
git add SocialFusion/ContentView.swift SocialFusion/Views/Components/LiquidGlassComponents.swift SocialFusion/Views/NotificationsView.swift SocialFusionUITests/ReachabilityUITests.swift
git commit -m "feat: add thumb-zone action rail for one-handed reachability"
```

### Task 9: Fullscreen Media Gesture Ergonomics

**Owner:** Media Pod  
**Files:**
- Modify: `SocialFusion/Views/Components/FullscreenMediaView.swift`
- Test: `SocialFusionTests/MediaRobustnessTests.swift`
- Create: `SocialFusionUITests/FullscreenMediaGestureUITests.swift`

**Step 1: Write the failing test**

Add UI gesture tests asserting horizontal swipes switch media reliably without harming zoom/pan/dismiss.

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionUITests/FullscreenMediaGestureUITests test`  
Expected: FAIL at current swipe friction threshold.

**Step 3: Write minimal implementation**

Tune drag threshold and direction arbitration logic to reduce gesture conflict.

**Step 4: Run test to verify it passes**

Run the command from Step 2 again.  
Expected: PASS.

**Step 5: Commit**

```bash
git add SocialFusion/Views/Components/FullscreenMediaView.swift SocialFusionUITests/FullscreenMediaGestureUITests.swift
git commit -m "fix: reduce gesture friction in fullscreen media swiping"
```

### Wave 4: P1 Platform Integrations

### Task 10: Share Extension Target

**Owner:** Platform Integrations  
**Files:**
- Modify: `SocialFusion.xcodeproj/project.pbxproj`
- Create: `SocialFusionShareExtension/ShareViewController.swift`
- Create: `SocialFusionShareExtension/Info.plist`
- Create: `SocialFusionShareExtension/ShareExtension.entitlements`
- Modify: `SocialFusion/Views/ComposeView.swift`
- Create: `SocialFusionUITests/ShareExtensionFlowUITests.swift`

**Step 1: Write the failing test**

Add ingestion tests for text/URL/media payload handoff into compose.

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionUITests/ShareExtensionFlowUITests test`  
Expected: FAIL because extension target and handoff path do not exist.

**Step 3: Write minimal implementation**

Create Share Extension target, parse supported UTTypes, and hand off to compose deep-link/draft pipeline.

**Step 4: Run test to verify it passes**

Run the command from Step 2 again.  
Expected: PASS.

**Step 5: Commit**

```bash
git add SocialFusion.xcodeproj/project.pbxproj SocialFusionShareExtension SocialFusion/Views/ComposeView.swift SocialFusionUITests/ShareExtensionFlowUITests.swift
git commit -m "feat: add share extension for url text and media ingestion"
```

### Task 11: App Intents And Shortcuts Upgrade

**Owner:** Automation/Intents  
**Files:**
- Modify: `SocialFusion/Intents/AppShortcuts.swift`
- Modify: `SocialFusion/Intents/ShareToSocialFusionIntent.swift`
- Modify: `SocialFusion/Intents/PostWithConfirmationIntent.swift`
- Modify: `SocialFusion/Intents/OpenHomeTimelineIntent.swift`
- Modify: `SocialFusion/Intents/SetActiveAccountIntent.swift`
- Create: `SocialFusionTests/AppIntentsTests.swift`

**Step 1: Write the failing test**

Add intent tests asserting structured outputs, account/feed parameters, and limited forced foreground open behavior.

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/AppIntentsTests test`  
Expected: FAIL for deep-link-only behavior.

**Step 3: Write minimal implementation**

Return useful intent result values, add parameters, and support background-safe execution paths where possible.

**Step 4: Run test to verify it passes**

Run the command from Step 2 again.  
Expected: PASS.

**Step 5: Commit**

```bash
git add SocialFusion/Intents/AppShortcuts.swift SocialFusion/Intents/*.swift SocialFusionTests/AppIntentsTests.swift
git commit -m "feat: upgrade app intents with structured outputs and parameters"
```

### Task 12: Notification Permission UX Hardening

**Owner:** Notifications Owner  
**Files:**
- Modify: `SocialFusion/ContentView.swift`
- Modify: `SocialFusion/Views/SettingsView.swift`
- Modify: `SocialFusion/Services/NotificationManager.swift`
- Create: `SocialFusionUITests/NotificationPermissionUITests.swift`

**Step 1: Write the failing test**

Add UI tests ensuring no notification prompt is shown on root appear without explicit user action.

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionUITests/NotificationPermissionUITests test`  
Expected: FAIL due to eager prompt.

**Step 3: Write minimal implementation**

Move prompt to explicit user-triggered settings action and keep background scheduling behind granted state.

**Step 4: Run test to verify it passes**

Run the command from Step 2 again.  
Expected: PASS.

**Step 5: Commit**

```bash
git add SocialFusion/ContentView.swift SocialFusion/Views/SettingsView.swift SocialFusion/Services/NotificationManager.swift SocialFusionUITests/NotificationPermissionUITests.swift
git commit -m "fix: make notification permission requests user-initiated"
```

### Task 13: Multi-Scene iPad Support + Scene Restoration

**Owner:** iPad Platform Owner  
**Files:**
- Modify: `SocialFusion/Info.plist`
- Modify: `SocialFusion/SocialFusionApp.swift`
- Modify: `SocialFusion/ContentView.swift`
- Create: `SocialFusionUITests/MultiSceneUITests.swift`

**Step 1: Write the failing test**

Add multi-scene UI test validating independent scene state restoration.

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -only-testing:SocialFusionUITests/MultiSceneUITests test`  
Expected: FAIL while multi-scenes are disabled.

**Step 3: Write minimal implementation**

Enable multiple scenes in plist and ensure scene-local selection/restoration state in app shell.

**Step 4: Run test to verify it passes**

Run the command from Step 2 again.  
Expected: PASS.

**Step 5: Commit**

```bash
git add SocialFusion/Info.plist SocialFusion/SocialFusionApp.swift SocialFusion/ContentView.swift SocialFusionUITests/MultiSceneUITests.swift
git commit -m "feat: enable iPad multi-scene support with independent restoration"
```

### Wave 5: Release Candidate Hardening

### Task 14: Full Regression, Soak, And Ship Gate

**Owner:** Release Lead + QA Lead  
**Files:**
- Modify: `TESTFLIGHT_WHAT_TO_TEST.txt`
- Modify: `TESTFLIGHT_WHAT_TO_TEST_POST_6d0b365.txt`
- Create: `Docs/ship-readiness-signoff.md`

**Step 1: Write the failing check**

Create signoff checklist with explicit pass/fail gates for all P0/P1 tasks.

**Step 2: Run test to verify it fails**

Run:
- `xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
- `xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' test`

Expected: FAIL until all workstreams are complete.

**Step 3: Write minimal implementation**

Fix remaining regressions and complete signoff evidence in `Docs/ship-readiness-signoff.md`.

**Step 4: Run test to verify it passes**

Re-run commands from Step 2.  
Expected: PASS, with no critical warnings and no known P0 issues.

**Step 5: Commit**

```bash
git add TESTFLIGHT_WHAT_TO_TEST.txt TESTFLIGHT_WHAT_TO_TEST_POST_6d0b365.txt Docs/ship-readiness-signoff.md
git commit -m "chore: finalize ship-readiness signoff and testflight checklist"
```

## Final Exit Criteria

- All P0 tasks completed and accepted.
- All P1 tasks completed and accepted.
- Search, restoration, and compose flows pass on iPhone 17 Pro and iPhone 17 Pro Max.
- Multi-scene and restoration pass on iPad Pro 13-inch.
- No sensitive logs in release configuration.
- Unit tests + UI tests pass in CI and local release candidate runs.
- TestFlight checklist and signoff docs are complete.

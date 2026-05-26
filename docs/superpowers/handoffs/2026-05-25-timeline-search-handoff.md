# Timeline Search — Resume Handoff

**Plan:** `docs/superpowers/plans/2026-05-17-timeline-search.md` (12 tasks)

**State on `main` at session end (2026-05-25):** Tasks 1–4 complete (data + filter layer). Tasks 5–12 not started. Build green, full test suite 438 passing / 0 failing locally before push.

**Last commits on this plan (newest first):**
- `92f6314` test(search): assert TimelineBufferFilter scans 500 posts in <100ms
- (Task 3) feat(search): add TimelineBufferFilter with content/author/tag matching
- `95592fd` feat(search): add timeline search models (hit, context, phase, section)
- `f42340c` feat(search): add bufferSnapshot() accessor on UnifiedTimelineController

All four pushed to `origin/main`.

---

## What's done

Read the plan for full context. Brief recap of what already exists so you don't redo it:

| Task | File | Status |
|---|---|---|
| 1 | `SocialFusion/Controllers/UnifiedTimelineController.swift` — `bufferSnapshot()` method | done |
| 2 | `SocialFusion/Models/TimelineSearchModels.swift` — `TimelineSearchHit`, `TimelineSearchContext`, `TimelineSearchPhase`, `TimelineSearchSection` | done |
| 3 | `SocialFusion/Utilities/TimelineBufferFilter.swift` + `SocialFusionTests/TimelineBufferFilterTests.swift` (10 tests) | done |
| 4 | `SocialFusionTests/TimelineSearchPerformanceTests.swift` (3 tests, measured 1.2ms for 500 posts) | done |

## What's left

Tasks 5–12 in the plan, in order:
- **Task 5** — `TimelineSearchRemoteDriver.swift` + tests (TDD). Wraps `UnifiedSearchProvider` to expose a Combine publisher.
- **Task 6** — `TimelineSearchViewModel.swift` + tests (TDD). The big one. Holds layered state, debounces ~250ms, fires both layers in parallel.
- **Task 7** — `TimelineSearchSectionHeader.swift` (small reusable component).
- **Task 8** — `TimelineSearchView.swift` overlay. LazyVStack of sections inside `safeAreaInset(.top)` chrome.
- **Task 9** — Wire into `ConsolidatedTimelineView`: swipe-down gesture + redundant search button + overlay presentation.
- **Task 10** — Manual simulator smoke (no code).
- **Task 11** — Optional pinned-timeline scoping (passes the `TimelineSearchContext` from the pin's metadata).
- **Task 12** — Full test sweep + acceptance verification.

---

## Gotchas learned this session — apply to remaining tasks

### Post init argument order

The plan's test fixtures put `authorId: "..."` at the end of `Post(...)`. **Wrong.** Real init order in `SocialFusion/Models/Post.swift:764` is:

```swift
id, content, authorName, authorUsername, authorId, authorProfilePictureURL,
createdAt, platform, originalURL, attachments, mentions, tags, ...
```

`authorId` comes **before** `authorProfilePictureURL`, not at the end. Already corrected in `TimelineBufferFilterTests.swift` and `TimelineSearchPerformanceTests.swift`. Future tests in this plan (Tasks 5, 6) must use the correct order or the build fails.

### pbxproj is hand-edited, not xcodegen'd locally

Every new `.swift` file requires four pbxproj entries. The pattern is mechanical but easy to get wrong. Pattern, with one source file + one test file:

1. **PBXBuildFile section** (~lines 280–320): one entry per source target the file belongs to
2. **PBXFileReference section** (~lines 480–520): one entry declaring the file
3. **PBXGroup section** (~lines 1080+): add file ref to the appropriate group's `children` list
4. **PBXSourcesBuildPhase section** (~lines 1900+): add build-file ref to the target's compile list

Generate unique 24-char hex IDs (use any UUID generator, strip dashes, take first 24 chars and uppercase).

Reference patterns from this session:
- Models group: search for `PinnedTimeline.swift` to see the four-section pattern
- Utilities group: `TimelineBufferFilter.swift` shows the pattern for `SocialFusion/Utilities/`
- Tests target: separate Sources phase at line ~2000 — `PinnedTimelineStoreTests.swift` is the template

### Build cycles are slow (~30 min) when pbxproj structure changes

Xcode rebuilds derived data when project structure shifts. Batch as many file additions as possible per build cycle. For Tasks 5–6, write the driver + VM + their test files together, then build once.

### `xcodebuild test` exit code 1 is often false alarm

The build helper script uses `grep -c "Test Case .* failed"` after the test run. When 0 tests fail, grep returns exit 1 (matched nothing). The pipeline inherits that exit code even when **TEST SUCCEEDED**. Always check the log output, not just the exit code.

### SourceKit phantoms

Whenever a new file is added or a type signature changes, SourceKit's `cannot find type 'X' in scope` diagnostics flood the file list. These are not real — xcodebuild compiles fine. Ignore them; trust the actual build output.

### `TaskGroup` for fan-out

Pattern used in `fetchAccountGroupTimeline` (SocialServiceManager) — replicate for remote-driver fan-out across both networks in Task 5. One-side failures should NOT fail the whole search; per-task try/catch + return nil, then filter nils out of the collected results.

### `PostCardView` is heavy

`PostCardView` in `SocialFusion/Views/Components/PostCardView.swift` requires many environment objects + ~15 init parameters. **Task 8 should not use it as-is** for search result rows. Either:
- Build a minimal `TimelineSearchResultRow` that renders just avatar + author + content snippet + timestamp + platform badge
- Or refactor `PostCardView` to extract a `PostCardLightweightVariant` (more work, more reuse)

Recommend the row approach for Task 8 — keep search-result rendering decoupled from the timeline's full card.

---

## Project state

- **Branch**: `main`
- **Last commit on `main`**: `92f6314 test(search): assert TimelineBufferFilter scans 500 posts in <100ms`
- **Tag for archeology**: none specific to this plan; the wholesale Fuse merge from earlier is at `pre-merge-main` (local-only).
- **Build**: green on iPhone 17 Pro simulator
- **Tests**: 438 passing, 0 failing locally (last full sweep before push)

## Quick verification commands for resume

```bash
# Confirm Tasks 1-4 are on main
git log --oneline | grep "feat(search)\|test(search)" | head -5

# Run the existing search tests
xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/TimelineBufferFilterTests
xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/TimelineSearchPerformanceTests

# Inspect the models that's-Task-2 added
grep -n "TimelineSearchHit\|TimelineSearchContext\|TimelineSearchPhase\|TimelineSearchSection" SocialFusion/Models/TimelineSearchModels.swift
```

## Suggested resume sequence

1. Read this handoff + the plan file (`docs/superpowers/plans/2026-05-17-timeline-search.md`).
2. Verify Tasks 1–4 still build (`xcodebuild build ...`).
3. Start at **Task 5** (remote driver). The plan walks it task-by-task.
4. Group pbxproj entries: write Tasks 5 + 6 source + test files together, then one build cycle.
5. Tasks 7–9 are UI — use the iPhone 17 Pro simulator for visual verification (UI changes are hard to validate from xcodebuild alone).
6. Task 10 is manual smoke on simulator + physical device.
7. Task 11 wires pinned-timeline scoping — uses `PinnedTimelineStore` (shipped last session, see `feat(pins):` commits if unfamiliar).
8. Task 12 is the acceptance gate — run the full suite, verify the performance budget, smoke on device.

## When you're done

Push to `origin/main`; CI/TestFlight builds automatically. Re-install on Frank's iPhone 17 Pro (UDID `00008150-000139C63480401C`) for hands-on verification.

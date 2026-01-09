# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Commands

- Build the iOS app (Xcode project):
  ```bash path=null start=null
  xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 15' build
  ```
- Run all iOS tests (unit + UI as applicable):
  ```bash path=null start=null
  xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 15' test
  ```
- Run a single iOS test (example):
  ```bash path=null start=null
  xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 15' \
    -only-testing:SocialFusionTests/AppLoggerTests/testLogLevels test
  ```
- Open the project in Xcode:
  ```bash path=null start=null
  open SocialFusion.xcodeproj
  ```
- Clean builds:
  ```bash path=null start=null
  xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion clean && \
  xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion build
  ```
- Swift Package (CLI module) – build, test, run:
  ```bash path=null start=null
  # Build
  swift build
  # Run executable
  swift run SocialFusion
  # Run all tests
  swift test
  # Run a single test (examples)
  swift test --filter AppLoggerTests
  swift test --filter AppLoggerTests/testLogLevels
  ```
- Project scripts:
  ```bash path=null start=null
  ./run_tests.sh            # architecture checks + sample builds
  ./debug_deployment.sh     # deployment/debug sanity checks for iOS devices
  ```
- Lint/format: Not configured in this repo. If you add SwiftLint or swift-format later, document the commands here.

## Architecture (high level)

The repository contains two closely related code targets:

1) iOS app (SwiftUI, Xcode project: `SocialFusion.xcodeproj`)
- Organization under `SocialFusion/`:
  - Models: post/account/platform types and normalization helpers (e.g., `Post.swift`, `SocialModels.swift`).
  - Services: API clients and orchestration for Mastodon and Bluesky (e.g., `MastodonService.swift`, `BlueskyService.swift`, `SocialServiceManager.swift`, `OAuthManager.swift`, `KeychainService.swift`).
  - Networking: request/config plumbing (`NetworkService.swift`, `ConnectionManager.swift`).
  - Stores: stateful coordinators for post actions and timelines (`PostActionStore.swift`, `UnifiedPostStore.swift`).
  - ViewModels: timeline and post-level state (`TimelineViewModel.swift`, `PostViewModel.swift`).
  - Views: SwiftUI UI layer including reusable components (e.g., `PostCardView.swift`, `UnifiedTimelineView.swift`, `Components/*`).
  - Utilities/Extensions: shared helpers, formatters, error handling, feature flags, and HTML utilities.
- Data flow (big picture):
  - User actions → ViewModels/Stores → Services (network/auth) → Models/Normalization → State update → Views render.
  - Timeline orchestration is coordinated by controllers like `UnifiedTimelineController.swift` and `TimelineController.swift` with stores handling mutations.

2) Swift Package (SPM) at repo root (`package.swift`)
- Targets under `Sources/` and `Tests/` provide a small executable and shared infrastructure (logging, errors) separate from the app.
- Useful for fast CLI builds/tests (`swift build`, `swift test`) independent of the Xcode UI target.

Key cross-cutting pieces
- Authentication, account management, and token/keychain handling: `AccountManager`, `OAuthManager`, `KeychainService`.
- Social backends: `MastodonAPIClient`/`MastodonService`, `BlueskyAPIClient`/`BlueskyService`, unified via `SocialServiceManager` and normalization types.
- Media/link preview plumbing and performance: `GIFUnfurlingService`, `MediaMemoryManager`, `HTMLFormatter`, `LinkPreview*` components.
- Logging and diagnostics: `Sources/SocialFusion/Logger.swift`, `StructuredLogger.swift` (package), plus app-level error handling utilities.

## Important repository guidance pulled from existing rule files

From `.cursor/rules` (abridged to essentials for agents):
- Systematic debugging: search for exact UI strings first, trace data flow end-to-end, verify the executing code path before proposing fixes. Avoid assumptions and circular reasoning.
- Testing workflow: always complete the build → install → test loop in simulator, and only claim success with concrete verification of the originally reported scenario.
- Dependency tracing: when changing symbols or data structures, find and update all usages across files in the same edit session; avoid leaving broken references.
- Regression prevention: preserve existing functionality/UX/accessibility; verify no regressions after changes.
- Practical notes: prefer an iOS simulator configuration that matches current Xcode support; avoid direct manual edits to `project.pbxproj` unless necessary.

From `README.md` (key highlights only)
- Platform: iOS 16+ (SwiftUI). Authentication via OAuth (Mastodon) and AT Protocol (Bluesky). Unified timeline with rich media, link previews, and accessibility support.
- Tooling: Swift 6.0; tested with modern Xcode (badges indicate 17.x). Use `⌘R` to run and `⌘U` to test in Xcode; example `xcodebuild test` command provided above.

## Notes for future agents
- Prefer Xcode-based builds/tests for the iOS app target; use SwiftPM (`swift build`/`swift test`) for the package under `Sources/` and `Tests/`.
- If adding lint/format, introduce config files and update this document with the exact commands.
- The repo includes top-level iOS test bundles (`SocialFusionTests/`, `SocialFusionUITests/`) as well as SPM tests under `Tests/`; choose commands accordingly when running single tests.

## Key context from CLAUDE.md
- Product vision: unified social client for Mastodon and Bluesky with a unified timeline; support viewing per-platform timelines (all Mastodon, all Bluesky) as well as a combined view.
- Planned UX capabilities: timeline pinning (e.g., Mastodon lists, Bluesky feeds, custom account groupings) and streamlined cross-network publishing.
- Architectural intent: modular and extensible timelines/post rendering driven by protocols and generics; maintain fluid interactions, subtle animations, and robust error handling.
- Platform direction: SwiftUI shared code with iOS app target; shared SPM modules also compile for macOS (per `package.swift`). Favor shared abstractions when updating core models/services.

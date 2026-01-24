# AGENTS.md

This file consolidates agent guidance for working in this repository. It is derived from CLAUDE.md, WARP.md, and GEMINI.md.

## Developer Persona

You are a senior developer with deep Apple ecosystem experience since 1984. You value industrial design quality, subtle UI, and elegant interactions. You admire indie Apple developers (IconFactory, TapBots, OmniGroup, Rogue Amoeba, _davidsmith, Marco Arment, John Siracusa, John Voorhees, John Gruber, Brent Simmons, Studio Neat). You are aiming for a breakthrough interaction on the level of pull-to-refresh: sophisticated in its simplicity.

## Product Vision

SocialFusion is a unified social client for Mastodon and Bluesky (with future federated networks), providing a single clean timeline and seamless cross-network interaction and posting.

Core features:
- Unified timeline for Mastodon + Bluesky
- Media handling (images, video, GIFs, YouTube embeds)
- Multi-account management and easy switching
- Cross-platform posting
- Timeline filtering (all Mastodon, all Bluesky, unified, or custom)
- Future: pinnable timelines (Mastodon lists, Bluesky feeds, filtered account groups)

## Architecture Overview

Entry flow:
- SocialFusionApp -> LaunchAnimationView (conditional) -> OnboardingView (no accounts) -> ContentView
- ContentView uses TabView (iPhone) or NavigationSplitView (iPad)
- ConsolidatedTimelineView is the canonical timeline

Key components:
- Services: SocialServiceManager, MastodonAPIClient, BlueskyAPIClient, PostNormalizer
- State: UnifiedTimelineController (source of truth), TimelineViewModel/PostViewModel, stores (PostActionStore, DraftStore, UnifiedPostStore)
- Networking: ConnectionManager, NetworkConfig (retry, backoff, concurrency)
- UI: PostCardView, MediaGridView, FullscreenMediaView, PostLinkPreview, NativeYouTubePlayer, StabilizedAsyncImage

Patterns:
- Protocol-driven design and platform abstraction
- EnvironmentObject service injection
- Optimistic updates with rollback
- Configuration-driven behavior via Info.plist (TimelineConfiguration)

## Coding Constraints

- SwiftUI-first for UI; wrap UIKit via representables only when needed.
- MVVM: business logic lives in ViewModels, not Views.
- Single responsibility and protocol-driven abstractions.
- Keep diffs small and focused; do not rewrite whole files without necessity.
- Maintain existing folder structure and naming.
- Do not add dependencies without explicit confirmation.
- Follow existing code style (2-space indentation, clear naming).
- Avoid AttributeGraph cycles by caching computed properties used in View rendering.
- Use @MainActor for state that updates UI.
- Provide graceful error handling and user-friendly messages.
- Media polish: alt text support, proper video cleanup, rounded corners (8pt), fullscreen dismiss gestures.

## Systematic Debugging and Safety

- Search for exact UI strings and trace data flow end-to-end.
- Verify the executing code path before proposing fixes; avoid assumptions.
- When changing symbols or data structures, update all usages in the same edit session.
- Preserve existing functionality, UX, and accessibility.
- Prefer minimal, precise changes over large rewrites.

## Build and Test Commands

Xcode project (iOS app):
- Build:
  xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
- Test:
  xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
- Single test example:
  xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:SocialFusionTests/AppLoggerTests/testLogLevels test
- Clean builds:
  xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion clean && \
  xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion build
- Open in Xcode:
  open SocialFusion.xcodeproj

Swift Package (CLI module):
- swift build
- swift run SocialFusion
- swift test
- swift test --filter AppLoggerTests
- swift test --filter AppLoggerTests/testLogLevels

Project scripts:
- ./run_tests.sh
- ./debug_deployment.sh

## Testing Expectations

- Prefer Xcode-based builds/tests for the iOS app target.
- Use SwiftPM for the package under Sources/ and Tests/.
- Only claim success after verifying the original scenario in the simulator.

## Key Files

- App entry: SocialFusion/SocialFusionApp.swift
- Main UI: SocialFusion/ContentView.swift
- Canonical timeline: SocialFusion/Views/ConsolidatedTimelineView.swift
- Services: SocialFusion/Services/SocialServiceManager.swift
- Models: SocialFusion/Models/Post.swift
- Controllers: SocialFusion/Controllers/UnifiedTimelineController.swift
- ViewModels: SocialFusion/ViewModels/TimelineViewModel.swift
- Components: SocialFusion/Views/Components/PostCardView.swift
- Networking: SocialFusion/Networking/ConnectionManager.swift
- Utilities: SocialFusion/Utilities/TokenManager.swift

## Current Known Issues (Context)

- Remaining AttributeGraph cycle warnings (mostly resolved)
- Quote post fallbacks need improvement
- Some error states lack UI feedback (TODOs in TimelineViewModel)
- TokenManager getClientId/getClientSecret are stubbed

## Development Notes

- Focus on polish and refinement rather than large rewrites.
- Consult recent repo .md files for context on specific fixes.
- If you add lint/format tooling, update AGENTS.md with exact commands.

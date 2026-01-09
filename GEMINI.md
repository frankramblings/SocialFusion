# SocialFusion - AI Development Guide for Gemini

## Developer Persona

You are a senior developer who has been in the Apple ecosystem since 1984. You're a Macintosh OG. You've been doing front-end and full-stack work for years. You've got an eye for design, and you appreciate the industrial design and UI design that make Apple products unique. You've followed trends in languages, APIs, design, UX/UI over the years and you are always on the cutting edge. You admire indie developers like the IconFactory, TapBots, the OmniGroup, Rogue Amoeba, _davidsmith, Marco Arment, John Siracusa, John Voorhees, John Gruber, Brent Simmons, Studio Neat.

You are on the verge of a major breakthrough on the magnitude of pull-to-refresh; the kind of natural interaction that apps will begin to adopt widely because it seems so obvious once you see it; it's sophisticated in its simplicity, just as Steve Jobs intended.

## App Purpose & Architecture

**Vision**: A unified social media client for Mastodon and Bluesky (with plans for other federated networks). The goal is to bring all your federated feeds into one clean, modern interface where you can interact with them all seamlessly, as well as publish across networks easily. It's the unified timeline we all need.

**Core Features**:
- Unified timeline aggregating Mastodon and Bluesky posts
- Advanced media handling (images, videos, GIFs, YouTube embeds)
- Multi-account management with easy switching
- Cross-platform posting capabilities
- Timeline filtering (all Mastodon, all Bluesky, unified, or custom combinations)
- Future: Pinnable timelines (Mastodon lists, Bluesky feeds, filtered account groups)

**Architecture Highlights**:
- Modular and extensible with protocols and generics driving timelines and post rendering
- Emphasis on subtle animations, fluid interactions, and thoughtful error handling
- Compatible with iOS/macOS/iPadOS with a shared codebase leveraging SwiftUI
- Target: iOS 17+ with some iOS 16+ API compatibility

## Architecture Overview

### Entry Point & Flow
```
SocialFusionApp (@main)
├── LaunchAnimationView (conditional)
├── OnboardingView (if no accounts)
└── ContentView (main app)
    ├── TabView (iPhone) / NavigationSplitView (iPad)
    └── ConsolidatedTimelineView (canonical timeline)
```

### Core Components

**Service Layer**:
- `SocialServiceManager`: Central hub for account management, timeline fetching, caching, post operations
- `MastodonAPIClient`: Protocol-based Mastodon API implementation
- `BlueskyAPIClient`: Protocol-based Bluesky/ATProto API implementation
- `PostNormalizer`: Transforms platform-specific posts into unified Post model

**State Management** (Three-tier):
- **Controllers**: `UnifiedTimelineController` (single source of truth)
- **ViewModels**: `PostViewModel`, `TimelineViewModel`
- **Stores**: `PostActionStore` (like/repost state), `DraftStore` (draft posts), `UnifiedPostStore`

**Networking**:
- `ConnectionManager`: Singleton with concurrent queue, rate limiting, circuit breaker pattern
- `NetworkConfig`: Retry logic (2 attempts, 1.5x backoff), timeout values, concurrency limits
- Token-based authentication with automatic refresh

**UI Components**:
- `PostCardView`: Individual post rendering with actions
- `MediaGridView`: Image/video gallery with fullscreen support
- `FullscreenMediaView`: Horizontal swiping media viewer
- `PostLinkPreview`: URL preview cards
- `NativeYouTubePlayer`: YouTube embed support
- `StabilizedAsyncImage`: Image loading with caching

**Key Patterns**:
- Environment Object Propagation for service injection
- Optimistic Updates with rollback on failure
- Protocol-Driven Design for platform abstraction
- Configuration-Driven behavior via Info.plist (TimelineConfiguration)

## Current Status

### What Works
✅ Unified timeline/feed with Mastodon + Bluesky posts
✅ Multi-account management and switching
✅ Link previews with caching
✅ Advanced media playback (images, videos, audio, YouTube)
✅ Account authentication (OAuth for Mastodon, session tokens for Bluesky)
✅ Post interactions (like, repost, reply, quote)
✅ Profile navigation from usernames and avatars
✅ Fullscreen media with horizontal swiping
✅ Draft post auto-save and recovery
✅ Position restoration with smart fallback strategies

### Known Issues
⚠️ AttributeGraph cycle warnings (mostly resolved in Phase 3 migration)
⚠️ Quote post fallbacks need improvement
⚠️ Some error states lack UI feedback (see TODOs in TimelineViewModel)
⚠️ TokenManager has stub implementations for getClientId/getClientSecret

### Recent Improvements
- Fixed video audio hijacking issues
- Fixed boost/reply banners with expansion
- Added rounded corners to media
- Enabled profile navigation from usernames/avatars
- Resolved AttributeGraph cycles via property caching and architectural fixes

### Next 3 Tasks
1. **Propagate Error UI Feedback**: Implement toast/banner notifications for timeline errors (addresses TODOs in ViewModels/TimelineViewModel.swift:266, 284, 499, 553)
2. **Complete TokenManager**: Implement proper client credential retrieval (Utilities/TokenManager.swift:253-254)
3. **Quote Post Fallback**: Improve FetchQuotePostView error handling and generic link preview fallback

## Build and Test Commands

### Xcode GUI
1. Open `SocialFusion.xcodeproj` in Xcode
2. Select the "SocialFusion" scheme
3. Choose iPhone 16 Pro Simulator (or your preferred iOS 17+ device)
4. Build and Run (⌘R) or Test (⌘U)

### Command Line (via `xcodebuild`)
- **Build the app**:
  ```bash
  xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 15' build
  ```
- **Run all tests**:
  ```bash
  xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 15' test
  ```
- **Run a single test**:
  ```bash
  xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 15' \
    -only-testing:SocialFusionTests/AppLoggerTests/testLogLevels test
  ```
- **Clean builds**:
  ```bash
  xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion clean
  ```

### Swift Package Manager (for `Sources/` and `Tests/`)
- **Build**: `swift build`
- **Run executable**: `swift run SocialFusion`
- **Run all tests**: `swift test`
- **Run a single test**: `swift test --filter AppLoggerTests/testLogLevels`

## Coding Constraints

### SwiftUI-First Approach
- Use SwiftUI for all new UI components
- UIKit only for compatibility or when SwiftUI lacks functionality
- Wrap UIKit components with `UIViewRepresentable`/`UIViewControllerRepresentable`

### Architecture Patterns
- **MVVM pattern**: Keep business logic out of Views, use ViewModels
- **Single Responsibility**: Each component should have one clear purpose
- **Protocol-Driven**: Use protocols for platform abstraction (see MastodonAPIClient/BlueskyAPIClient)
- **Environment Objects**: Inject services via `@EnvironmentObject` for loose coupling

### Code Quality
- Keep diffs small and focused; never rewrite whole files unless absolutely required
- Maintain existing folder structure and naming conventions
- No new dependencies (CocoaPods/SPM) without explicit confirmation
- Follow existing code style (2-space indentation, clear naming)
- Avoid over-engineering: only make changes that are directly requested or clearly necessary

### Performance & Stability
- Avoid AttributeGraph cycles: cache computed properties used in View rendering
- Use `@MainActor` for published state that updates UI
- Implement optimistic updates with rollback for better perceived performance
- Monitor memory usage for media-heavy timelines

### Error Handling
- Graceful degradation (e.g., show placeholder when image fails to load)
- User-friendly error messages (avoid technical jargon)
- TODO: Add toast/banner notifications for network errors

## Key Files Reference

### App Entry & Main UI
- `SocialFusion/SocialFusionApp.swift` - App entry point with state objects
- `SocialFusion/ContentView.swift` - Main container with TabView/SplitView
- `SocialFusion/Views/ConsolidatedTimelineView.swift` - Canonical timeline view

### Core Services
- `SocialFusion/Services/SocialServiceManager.swift` - Central service hub
- `SocialFusion/Services/MastodonAPIClient.swift` - Mastodon API
- `SocialFusion/Services/BlueskyAPIClient.swift` - Bluesky API
- `SocialFusion/Services/OAuthManager.swift` - OAuth flow handling

### Models
- `SocialFusion/Models/Post.swift` - Unified post model
- `SocialFusion/Models/SocialAccount.swift` - Account model
- `SocialFusion/Models/TimelineState.swift` - Timeline state management
- `SocialFusion/Models/MastodonModels.swift` - Platform-specific models
- `SocialFusion/Models/BlueskyModels.swift` - Platform-specific models

### Controllers & ViewModels
- `SocialFusion/Controllers/UnifiedTimelineController.swift` - Single source of truth for timeline
- `SocialFusion/ViewModels/PostViewModel.swift` - Single post state
- `SocialFusion/ViewModels/TimelineViewModel.swift` - Timeline operations

### UI Components
- `SocialFusion/Views/Components/PostCardView.swift` - Post rendering
- `SocialFusion/Views/Components/MediaGridView.swift` - Media gallery
- `SocialFusion/Views/Components/FullscreenMediaView.swift` - Fullscreen media viewer
- `SocialFusion/Views/Components/PostLinkPreview.swift` - Link preview cards
- `SocialFusion/Views/Components/PostActionBar.swift` - Like/repost/reply buttons

### Networking
- `SocialFusion/Networking/ConnectionManager.swift` - Network coordination
- `SocialFusion/Networking/NetworkConfig.swift` - Network settings

### Utilities
- `SocialFusion/Utilities/TokenManager.swift` - Token refresh logic
- `SocialFusion/Utilities/KeychainManager.swift` - Secure storage
- `SocialFusion/Utilities/HTMLFormatter.swift` - HTML to AttributedString
- `SocialFusion/Utilities/TimeFormatters.swift` - Relative time formatting

## Notes for AI Assistants

- **Systematic Debugging**: Search for exact UI strings first, trace data flow end-to-end, and verify the executing code path before proposing fixes. Avoid assumptions.
- **Testing Workflow**: Always complete the build → install → test loop in the simulator. Only claim success after verifying the fix for the originally reported scenario.
- **Dependency Tracing**: When changing symbols or data structures, find and update all usages across all files. Do not leave broken references.
- **Regression Prevention**: Preserve existing functionality, UX, and accessibility. Verify no regressions after changes.
- **Project Context**: This project is in active development. Focus on polish and refinement rather than large rewrites. The developer values simplicity and elegance.
- **Consult History**: Check git history (`git log --oneline -20`) and the various `.md` files in the root for context on recent changes and specific fixes.
- **Small Changes**: When in doubt, make the smallest change that solves the problem.

---

*Last Updated: 2026-01-09

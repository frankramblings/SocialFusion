# SocialFusion - AI Development Guide

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
- Direct Messages with real-time streaming, group chats, reactions, typing indicators
- Redesigned profile view with cinematic scrolling and parallax effects
- Share Extension for sharing content from other apps
- Share as Image post export
- App Intents / Siri Shortcuts integration
- Enhanced search across platforms with filtering and trending content
- Autocomplete for mentions and hashtags
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
├── LaunchAnimationView (first launch after update)
├── OnboardingView (if no accounts)
└── ContentView (main app)
    ├── TabView (iPhone) / NavigationSplitView (iPad)
    │   ├── Home → ConsolidatedTimelineView (canonical timeline)
    │   ├── Messages → DirectMessagesView (DM inbox + ChatView)
    │   ├── Notifications → NotificationsView
    │   ├── Search → SearchView
    │   └── Profile → ProfileView (cinematic scrolling)
    └── Settings (SettingsView)
```

### Core Components

**Service Layer**:
- `SocialServiceManager`: Central hub for account management, timeline fetching, caching, post operations
- `MastodonAPIClient` / `BlueskyAPIClient`: Protocol-based API implementations
- `MastodonService` / `BlueskyService`: Platform-specific service wrappers
- `PostNormalizerImpl`: Transforms platform-specific posts into unified Post model
- `ChatStreamService`: Real-time chat event streaming (with `MastodonChatStreamProvider`, `BlueskyPollStreamProvider`)
- `NotificationManager`: Background notification polling
- `AutomaticTokenRefreshService`: Token lifecycle management
- `SocialGraphService` / `BlueskyGraphService` / `MastodonGraphService`: Follow graph queries
- `AutocompleteService`: Mention/hashtag autocomplete
- `GIFUnfurlingService`: GIF extraction and preview
- `KeychainService`: Production-ready keychain wrapper (singleton)

**State Management** (Three-tier):
- **Controllers**: `UnifiedTimelineController` (single source of truth), `AccountTimelineController`, `TimelineRefreshCoordinator`
- **ViewModels**: `PostViewModel`, `ProfileViewModel`, `MessagesViewModel`, `TimelineFeedPickerViewModel`, `RelationshipViewModel`, `FullscreenMediaCoordinator`
- **Stores**: `PostActionStore` (like/repost state with author-level propagation), `PostActionCoordinator`, `DraftStore` (draft posts), `DraftPersistenceQueue`, `UnifiedPostStore`, `CanonicalPostStore`, `RelationshipStore`, `SearchStore`, `SearchCache`

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
✅ Fullscreen media with horizontal swiping
✅ Draft post auto-save and recovery
✅ Position restoration with smart fallback strategies
✅ Direct Messages with real-time streaming (Mastodon WebSocket, Bluesky polling)
✅ Group conversations with multi-select creation
✅ Message reactions (Bluesky), deletion, editing (Mastodon)
✅ Typing indicators and read receipts (Bluesky)
✅ Redesigned profile view with cinematic scrolling, parallax, avatar docking
✅ Profile tabs (Posts, Posts & Replies, Media) with filtered content
✅ Enhanced search across platforms with filtering and trending
✅ Share Extension for sharing from other apps
✅ Share as Image post export
✅ Siri Shortcuts / App Intents integration
✅ Launch animation (purple/blue circle fusion)
✅ Onboarding flow with carousel pages
✅ Autocomplete for mentions and hashtags
✅ Credentials migration from UserDefaults to Keychain
✅ Token refresh with automatic lifecycle management

### Known Issues
⚠️ AttributeGraph cycle warnings (mostly resolved, occasional edge cases)
⚠️ Quote post fallbacks need improvement (FetchQuotePostView is complex)
⚠️ Some error states lack UI feedback (TODOs in TimelineViewModel.swift:499, 553)

### Recent Improvements
- Beta readiness fixes: privacy manifest, privacy descriptions, URL scheme, build number, feature flag fixes
- Share Extension target added to Xcode project with deep link implementation
- Debug validation view gated behind `#if DEBUG`
- Build numbers switched from `GITHUB_RUN_NUMBER` to `git rev-list HEAD --count` for deterministic CI builds
- Redesigned profile view with cinematic scroll effects and UIKit KVO tracking
- Full Direct Messages system with real-time streaming
- Share Extension and Share as Image features
- App Intents / Siri Shortcuts integration
- Enhanced search with unified multi-platform provider
- Launch animation and onboarding flow
- Credentials migration to Keychain (completed Feb 2026)
- TokenManager fully implemented (getClientId/getClientSecret resolved)
- Fixed AttributeGraph crash on Mastodon profile HTML rendering
- In-conversation search with highlight and navigation

### Next 3 Tasks
1. **Propagate Error UI Feedback**: Implement toast/banner notifications for timeline errors (addresses TODOs in ViewModels/TimelineViewModel.swift:499, 553)
2. **Quote Post Fallback**: Improve FetchQuotePostView error handling and generic link preview fallback
3. **Pinnable Timelines**: Implement pinnable timelines for Mastodon lists, Bluesky feeds, and custom account groups

## Build Instructions

1. Open `SocialFusion.xcodeproj` in Xcode
2. Select the "SocialFusion" scheme
3. Choose iPhone 17 Pro Simulator (or your preferred iOS 17+ device)
4. Build and Run (⌘R)

**Note**: Requires Xcode 15+ and iOS 17+ SDK

### CI / TestFlight
- GitHub Actions workflow: `.github/workflows/ci.yml`
- Pushes to `main` trigger build + TestFlight deployment
- Build numbers use `git rev-list HEAD --count` (deterministic, always increasing)
- `project.yml` (xcodegen) regenerates `project.pbxproj` in CI — changes to project settings must also be reflected in `project.yml`
- Local builds use `CURRENT_PROJECT_VERSION = 1` from `project.pbxproj`; CI overrides via command line

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

### Media Handling
- Always provide alt text support for accessibility
- Implement proper cleanup for video players to prevent audio hijacking
- Use rounded corners on media for polish (8pt radius standard)
- Support fullscreen with dismiss gestures

## Key Files Reference

### App Entry & Main UI
- `SocialFusion/SocialFusionApp.swift` - App entry point with state objects
- `SocialFusion/ContentView.swift` - Main container with TabView/SplitView
- `SocialFusion/Views/ConsolidatedTimelineView.swift` - Canonical timeline view
- `SocialFusion/Views/LaunchAnimationView.swift` - First-launch animation
- `SocialFusion/Views/OnboardingView.swift` - Onboarding carousel

### Core Services
- `SocialFusion/Services/SocialServiceManager.swift` - Central service hub
- `SocialFusion/Services/MastodonAPIClient.swift` - Mastodon API
- `SocialFusion/Services/BlueskyAPIClient.swift` - Bluesky API
- `SocialFusion/Services/MastodonService.swift` - Mastodon service wrapper
- `SocialFusion/Services/BlueskyService.swift` - Bluesky service wrapper
- `SocialFusion/Services/OAuthManager.swift` - OAuth flow handling
- `SocialFusion/Services/PostNormalizerImpl.swift` - Post normalization
- `SocialFusion/Services/KeychainService.swift` - Keychain wrapper (singleton)
- `SocialFusion/Services/AutomaticTokenRefreshService.swift` - Token lifecycle
- `SocialFusion/Services/ChatStreamService.swift` - Real-time chat streaming
- `SocialFusion/Services/NotificationManager.swift` - Background notifications
- `SocialFusion/Services/AutocompleteService.swift` - Mention/hashtag autocomplete

### Models
- `SocialFusion/Models/Post.swift` - Unified post model
- `SocialFusion/Models/SocialAccount.swift` - Account model
- `SocialFusion/Models/TimelineState.swift` - Timeline state management
- `SocialFusion/Models/MastodonModels.swift` - Platform-specific models
- `SocialFusion/Models/BlueskyModels.swift` - Platform-specific models
- `SocialFusion/Models/DraftPost.swift` - Draft post model
- `SocialFusion/Models/ChatStreamModels.swift` - Chat event models
- `SocialFusion/Models/SearchModels.swift` - Search result models
- `SocialFusion/Models/RelationshipState.swift` - Follow/mute/block state

### Controllers & ViewModels
- `SocialFusion/Controllers/UnifiedTimelineController.swift` - Single source of truth for timeline
- `SocialFusion/Controllers/AccountTimelineController.swift` - Single-account timeline
- `SocialFusion/Controllers/TimelineRefreshCoordinator.swift` - Refresh orchestration
- `SocialFusion/ViewModels/PostViewModel.swift` - Single post state
- `SocialFusion/ViewModels/TimelineViewModel.swift` - Timeline operations (deprecated, kept for compat)
- `SocialFusion/ViewModels/ProfileViewModel.swift` - Profile view state with tab-based pagination
- `SocialFusion/ViewModels/MessagesViewModel.swift` - Chat/DM state
- `SocialFusion/ViewModels/RelationshipViewModel.swift` - Follow/mute/block state

### Stores
- `SocialFusion/Stores/PostActionStore.swift` - Like/repost state with author-level propagation
- `SocialFusion/Stores/PostActionCoordinator.swift` - Post action coordination
- `SocialFusion/Stores/DraftStore.swift` - Draft persistence
- `SocialFusion/Stores/UnifiedPostStore.swift` - Cross-platform post operations
- `SocialFusion/Stores/RelationshipStore.swift` - Relationship state
- `SocialFusion/Stores/SearchStore.swift` - Search state

### State
- `SocialFusion/State/TimelineConfiguration.swift` - Timeline config
- `SocialFusion/State/TimelineBuffer.swift` - Timeline buffering
- `SocialFusion/State/SmartPositionManager.swift` - Scroll position management

### Views - Profile
- `SocialFusion/Views/ProfileView.swift` - Unified profile with cinematic scrolling
- `SocialFusion/Views/Components/ProfileHeaderView.swift` - Banner, avatar, bio with parallax
- `SocialFusion/Views/Components/ProfileTabBar.swift` - Posts/Replies/Media tabs
- `SocialFusion/Views/Components/ProfileMediaGridView.swift` - Media grid

### Views - Messages
- `SocialFusion/Views/Messages/DirectMessagesView.swift` - DM inbox
- `SocialFusion/Views/Messages/ChatView.swift` - Conversation view
- `SocialFusion/Views/Messages/MessageBubble.swift` - iMessage-style bubbles
- `SocialFusion/Views/Messages/NewConversationView.swift` - Create conversation
- `SocialFusion/Views/Messages/MessageReactionView.swift` - Emoji reactions
- `SocialFusion/Views/Messages/TypingIndicatorBubble.swift` - Typing animation

### Views - Other
- `SocialFusion/Views/ComposeView.swift` - Post composition
- `SocialFusion/Views/SearchView.swift` - Multi-platform search
- `SocialFusion/Views/NotificationsView.swift` - Notifications
- `SocialFusion/Views/SettingsView.swift` - App settings

### UI Components
- `SocialFusion/Views/Components/PostCardView.swift` - Post rendering
- `SocialFusion/Views/Components/MediaGridView.swift` - Media gallery
- `SocialFusion/Views/Components/FullscreenMediaView.swift` - Fullscreen media viewer
- `SocialFusion/Views/Components/PostLinkPreview.swift` - Link preview cards
- `SocialFusion/Views/Components/PostActionBar.swift` - Like/repost/reply buttons

### Feature Modules
- `SocialFusion/ShareAsImage/` - Post screenshot/export feature (18 files)
- `SocialFusion/Intents/` - Siri Shortcuts / App Intents (10+ files)
- `SocialFusionShareExtension/` - Share Extension for sharing from other apps
- `SocialFusion/Services/Search/` - Unified search providers (Mastodon, Bluesky, unified)

### Networking
- `SocialFusion/Networking/ConnectionManager.swift` - Network coordination
- `SocialFusion/Networking/NetworkConfig.swift` - Network settings

### Utilities
- `SocialFusion/Utilities/TokenManager.swift` - Token refresh logic
- `SocialFusion/Utilities/KeychainManager.swift` - Legacy keychain utility (used by TokenManager)
- `SocialFusion/Utilities/HTMLFormatter.swift` - HTML to AttributedString
- `SocialFusion/Utilities/TimeFormatters.swift` - Relative time formatting

## Common Development Tasks

### Adding a New Feature
1. Create a branch: `git checkout -b feature/your-feature-name`
2. Identify affected components (consult architecture overview above)
3. Keep changes focused and minimal
4. Test on iPhone and iPad simulators
5. Check for AttributeGraph warnings in console
6. Commit with descriptive message following existing style

### Fixing a Bug
1. Reproduce the issue reliably
2. Identify root cause (check recent commits, git log)
3. Fix in smallest possible changeset
4. Verify fix doesn't introduce regressions
5. Update any relevant documentation

### Adding Platform Support (Future)
1. Create new API client conforming to existing protocol pattern
2. Add platform-specific models
3. Extend PostNormalizer with new platform transformer
4. Update SocialServiceManager to include new platform
5. Add platform badge/icon to UI components

## Testing & Validation

### Manual Testing Checklist
- [ ] Launch app with no accounts (onboarding flow)
- [ ] Add Mastodon account via OAuth
- [ ] Add Bluesky account via credentials
- [ ] View unified timeline (both platforms mixed)
- [ ] Switch between individual account views
- [ ] Like/unlike a post (optimistic update)
- [ ] Repost/unrepost a post
- [ ] Reply to a post
- [ ] View fullscreen media with horizontal swipe
- [ ] Compose and publish a new post
- [ ] Navigate to user profile from avatar/username
- [ ] Profile view: scroll cinematic effects, tab switching (Posts/Replies/Media)
- [ ] Direct Messages: send/receive, group chat, reactions
- [ ] Search: query across platforms, filter by scope
- [ ] Share Extension: share content from another app
- [ ] Share as Image: export a post as screenshot
- [ ] Check memory usage (should be < 150MB for typical timeline)
- [ ] Verify no AttributeGraph warnings in console

### Beta Validation
The app includes a built-in validation view (DEBUG builds only):
- Long-press the compose button (pencil icon) to access `TimelineValidationDebugView`
- Runs automated tests for timeline loading, functionality, performance, account management
- Success rate should be ≥ 80% for beta readiness

## Notes for AI Assistants

- This project is in active development; major features added recently include Messages, Profile redesign, and Share as Image
- Focus on polish and refinement rather than large rewrites
- The developer values simplicity and elegance over complexity
- When in doubt, make the smallest change that solves the problem
- Check git history for context on recent changes: `git log --oneline -20`
- `TimelineViewModel` is deprecated — `UnifiedTimelineController` is the canonical timeline source of truth
- `KeychainService.shared` is the production keychain wrapper; `KeychainManager` is a separate legacy utility
- Profile view uses UIKit KVO for scroll tracking (SwiftUI ScrollView limitation workaround)
- Chat streaming uses WebSocket for Mastodon, polling for Bluesky
- `TimelineValidationDebugView` is `#if DEBUG` gated — not accessible in Release builds
- `postActionsV2` feature flag is enabled by default in all builds (was previously disabled in Release)
- `PrivacyInfo.xcprivacy` declares UserDefaults API usage (Apple requirement since May 2024)
- CI uses xcodegen to regenerate the project — always update `project.yml` alongside `project.pbxproj` for build settings

---

*Last Updated: 2026-03-04*

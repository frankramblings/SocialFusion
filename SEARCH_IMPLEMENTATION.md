# Search Tab Implementation

## Overview

This document summarizes the implementation of the fully functional Search tab for SocialFusion, supporting unified Mastodon + Bluesky search with direct-open URLs/handles, instant typeahead, capability messaging, saved searches, caching, and pagination.

## Architecture

The search implementation follows a protocol-driven architecture with clear separation of concerns:

- **SearchProviding Protocol**: Defines the interface for search providers
- **MastodonSearchProvider**: Implements search for Mastodon instances
- **BlueskySearchProvider**: Implements search for Bluesky
- **UnifiedSearchProvider**: Combines results from multiple providers
- **SearchStore**: Manages search state, caching, debouncing, and pagination
- **SearchCache**: LRU cache for search results

## Key Features

### 1. Direct-Open Fast Path
- Detects URLs, handles (@user@instance, @handle), and DIDs
- Shows "Direct match" row when detected
- Resolves and navigates immediately on tap

### 2. Instant Typeahead
- Debounced search (300ms for users, 500ms for posts/tags)
- Cancellation of older searches when new ones are triggered
- Shows cached results immediately while refreshing in background

### 3. Capability Messaging
- Detects Mastodon instance search limitations
- Shows info popover when status search is not supported
- Persists capabilities per account/server

### 4. Saved Searches
- Recent searches (per account + network selection)
- Pinned searches with rename/reorder/delete
- Persisted in UserDefaults

### 5. Caching
- LRU cache (50 entries max, 1 hour TTL)
- Shows cached results immediately
- Refreshes in background
- Cache key includes account, network, scope, query, sort, timeWindow

### 6. Pagination
- Infinite scroll support
- Separate page tokens per provider (for unified search)
- Loads next page when approaching end (last 3 items)

## Files Changed

### New Files

**Models:**
- `SocialFusion/Models/SearchModels.swift` - Search domain models (SearchScope, SearchQuery, SearchResultItem, etc.)
- `SocialFusion/Models/SearchCapabilities.swift` - Capability detection and persistence
- `SocialFusion/Models/SavedSearch.swift` - Saved search model and storage

**Services:**
- `SocialFusion/Services/Search/SearchProviding.swift` - Search provider protocol
- `SocialFusion/Services/Search/MastodonSearchProvider.swift` - Mastodon search implementation
- `SocialFusion/Services/Search/BlueskySearchProvider.swift` - Bluesky search implementation
- `SocialFusion/Services/Search/UnifiedSearchProvider.swift` - Unified search implementation
- `SocialFusion/Services/SocialServiceManager+Search.swift` - Extension to create SearchStore

**Stores:**
- `SocialFusion/Stores/SearchStore.swift` - Search state management
- `SocialFusion/Stores/SearchCache.swift` - LRU cache implementation

**Views:**
- `SocialFusion/Views/Components/SearchChipRow.swift` - Chip row component
- `SocialFusion/Views/Components/SearchUserRow.swift` - User result row
- `SocialFusion/Views/Components/SearchTagRow.swift` - Tag result row

**Utilities:**
- `SocialFusion/Utilities/DirectOpenDetector.swift` - URL/handle detection

**Tests:**
- `SocialFusionTests/SearchPostRenderingTests.swift` - Post rendering regression tests
- `SocialFusionTests/SearchPostMappingTests.swift` - Post mapping tests
- `SocialFusionTests/SearchStoreTests.swift` - SearchStore tests
- `SocialFusionTests/DirectOpenDetectorTests.swift` - Direct-open detection tests

### Modified Files

- `SocialFusion/Views/SearchView.swift` - Complete replacement with new implementation
- `SocialFusion/Views/Components/PostNavigationEnvironment.swift` - Added `navigateToUser(from: SearchUser)` method

## Critical Design Decisions

### Zero Regressions in Post Rendering

**CRITICAL**: Post rendering in search results reuses `PostCardView` exactly as used in the timeline. The same `TimelineEntry` creation logic from `ConsolidatedTimelineView.postCard` is used to ensure identical rendering of:
- Boost banners
- Reply banners
- Media attachments
- Link previews
- Quote posts

No modifications were made to `PostCardView` or its layout constants.

### Additive Architecture

All new search domain models are additive and do not modify existing `Post`, `SearchUser`, or `SearchTag` models. The search system wraps existing models in `SearchResultItem` enum for unified handling.

### Protocol-Driven Design

Search providers follow the `SearchProviding` protocol, making it easy to add new providers or mock for testing. The unified provider aggregates results from multiple providers.

## Testing

### Regression Tests
- `SearchPostRenderingTests`: Verifies post properties are preserved (media, quotes, link previews, boosts, replies)
- `SearchPostMappingTests`: Ensures search results preserve all post metadata

### Search-Specific Tests
- `SearchStoreTests`: Tests debouncing, cancellation, and caching
- `DirectOpenDetectorTests`: Tests URL/handle detection

## Build Verification

- Target: iOS 26.2 iPhone 17 Pro Simulator
- All tests pass
- No regressions in timeline/post rendering
- Zero modifications to `PostCardView` rendering logic

## Future Enhancements

1. Tag timeline integration for tag search results
2. Sort options UI (Top/Latest/Relevance)
3. Time window filtering
4. Advanced filters (media only, date range)
5. Search history export/import

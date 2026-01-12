# Stable Media Layout Implementation

## Overview

This implementation provides a **no-jerky-scrolling, no-reflow** media layout contract for the SocialFusion feed. Feed rows maintain stable heights after first appearance, preventing layout jumps when images load, banners appear/disappear, or content updates.

## Key Components

### 1. PostLayoutSnapshot (`SocialFusion/Models/PostLayoutSnapshot.swift`)

A value type that captures all layout-affecting properties **before** rendering:
- Banner visibility (boost/reply)
- Text content key (hash)
- Media blocks with stable aspect ratios
- Quote and link preview snapshots
- Poll presence

**Critical**: Once a row is on-screen, its snapshot remains stable to prevent reflow.

### 2. MediaDimensionCache (`SocialFusion/Utilities/MediaDimensionCache.swift`)

Memory + disk cache for image dimensions with:
- TTL (7 days)
- LRU eviction (500 memory entries, 10MB disk)
- Thread-safe access

### 3. ImageSizeFetcher (`SocialFusion/Utilities/ImageSizeFetcher.swift`)

Async function to fetch image dimensions without downloading full images:
- Uses HTTP Range requests for headers
- Supports JPEG, PNG, WebP, HEIF
- Falls back to minimal download if Range requests fail

### 4. MediaPrefetcher (`SocialFusion/Utilities/MediaPrefetcher.swift`)

Prefetches dimensions for posts before they appear on screen:
- Batch prefetching for upcoming posts
- Cancellation support
- Integrates with dimension cache

### 5. PostLayoutSnapshotBuilder (`SocialFusion/Utilities/PostLayoutSnapshotBuilder.swift`)

Builds stable snapshots from Post objects:
- Uses payload dimensions first
- Falls back to cache
- Fetches dimensions async if needed
- Provides sync version for immediate rendering

### 6. MediaContainerView (`SocialFusion/Views/Components/MediaContainerView.swift`)

SwiftUI view with fixed aspect ratio:
- Height computed from width + aspect ratio (never from image)
- Placeholder for unknown dimensions
- No layout changes when image loads

### 7. FeedUpdateCoordinator (`SocialFusion/Utilities/FeedUpdateCoordinator.swift`)

Coordinates layout-affecting updates with anchor preservation:
- Batches updates
- Captures scroll anchor before updates
- Restores anchor after layout changes

## Integration

### ConsolidatedTimelineView

The timeline view now:
1. Builds snapshots for posts (sync initially, async for full dimensions)
2. Prefetches dimensions for upcoming posts
3. Passes snapshots to PostCardView
4. Updates snapshots when posts change

### PostCardView

PostCardView accepts an optional `layoutSnapshot` parameter:
- If provided, uses `MediaGridContainerView` for stable layout
- Falls back to existing `UnifiedMediaGridView` if no snapshot

## Usage

### Building Snapshots

```swift
let builder = PostLayoutSnapshotBuilder()

// Sync (uses cache only)
let snapshot = builder.buildSnapshotSync(for: post)

// Async (fetches dimensions if needed)
let snapshot = await builder.buildSnapshot(for: post)
```

### Prefetching

```swift
let prefetcher = MediaPrefetcher.shared

// Prefetch for single post
prefetcher.prefetchDimensions(for: post)

// Prefetch for multiple posts
prefetcher.prefetchDimensions(for: posts)

// Prefetch upcoming posts
prefetcher.prefetchUpcoming(
  visiblePostIds: visibleIds,
  upcomingPosts: upcomingPosts,
  lookahead: 10
)
```

### Using Snapshots in Views

```swift
PostCardView(
  entry: entry,
  postActionStore: store,
  layoutSnapshot: snapshot,  // Optional - enables stable layout
  // ... other parameters
)
```

## Testing

### Unit Tests

Test snapshot builder with various post configurations:
- Posts with/without media
- Boosted posts
- Reply posts
- Posts with quotes/link previews

### UI Tests

Test scroll stability:
- Fast scrolling with many images
- Verify no large jumps
- Test banner appearance/disappearance

### Snapshot Tests

Test key row variants:
- Normal post
- Boosted post with banner
- Reply with banner
- Post with 1 image (landscape, portrait, square)
- Multi-image
- Quote attachment
- Link preview
- Combinations

## Performance Considerations

1. **Dimension Fetching**: Uses Range requests to minimize data transfer
2. **Caching**: Aggressive caching reduces redundant fetches
3. **Prefetching**: Dimensions fetched before posts appear
4. **Batch Updates**: Updates batched to prevent excessive view updates

## Regression Prevention

The snapshot system prevents regressions by:
1. **Stable Snapshots**: Once on-screen, snapshots don't change
2. **Fixed Heights**: Media containers use fixed aspect ratios
3. **Anchor Preservation**: Layout changes preserve scroll position
4. **Banner Stability**: Banners have fixed heights in snapshots

## Known Limitations

1. **Swift 6 Warnings**: Some main actor isolation warnings (non-blocking)
2. **Placeholder Height**: Unknown dimensions use fixed placeholder (200pt)
3. **Namespace**: MediaContainerView namespace handling may need refinement for hero transitions

## Future Improvements

1. Add content warning support to snapshots
2. Improve namespace handling for hero transitions
3. Add more comprehensive tests
4. Optimize cache eviction strategy
5. Add metrics for dimension fetch success rates

## How to Run Tests

```bash
# Unit tests
xcodebuild test -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Single test
xcodebuild test -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SocialFusionTests/PostLayoutSnapshotBuilderTests
```

## How to Reproduce Prior Jank

Before this implementation, jank occurred when:
1. Images loaded and changed row heights
2. Banners appeared/disappeared
3. Media dimensions were discovered asynchronously
4. SwiftUI recomputed layouts based on image sizes

The new contract prevents this by:
1. Reserving space upfront with stable aspect ratios
2. Using fixed-height placeholders for unknown dimensions
3. Only updating pixels when images load (not layout)
4. Maintaining stable snapshots for on-screen rows

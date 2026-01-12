# Commit Message: Implement Stable Media Layout System

```
feat: Implement no-reflow media layout system for stable feed scrolling

Implements a comprehensive stable media layout contract that prevents
jerky scrolling and layout reflow in the feed. Feed rows maintain stable
heights after first appearance, preventing jumps when images load,
banners appear/disappear, or content updates.

## Core Components

### Layout Snapshot System
- PostLayoutSnapshot: Value type capturing all layout-affecting properties
  before rendering (banners, media, quotes, link previews, polls)
- PostLayoutSnapshotBuilder: Builds stable snapshots from Post objects
  using payload dimensions, cache, or async fetching

### Media Dimension Management
- MediaDimensionCache: Memory + disk cache with TTL (7 days) and LRU
  eviction (500 entries, 10MB disk limit)
- ImageSizeFetcher: Async dimension fetching via HTTP Range requests
  for JPEG/PNG/WebP/HEIF without downloading full images
- MediaPrefetcher: Prefetches dimensions for upcoming posts before
  they appear on screen

### Stable Media Rendering
- MediaContainerView: SwiftUI container with fixed aspect ratio
  (height computed from width + ratio, never from image size)
- MediaGridContainerView: Multi-image grid with stable layout
- Placeholder support for unknown dimensions (200pt fixed height)

### Update Coordination
- FeedUpdateCoordinator: Batches layout-affecting updates with
  anchor preservation to prevent scroll jumps

## Integration

### ConsolidatedTimelineView
- Builds snapshots for posts (sync initially, async for full dimensions)
- Prefetches dimensions for upcoming posts
- Passes snapshots to PostCardView for stable rendering
- Updates snapshots when posts change

### PostCardView
- Accepts optional `layoutSnapshot` parameter
- Uses MediaGridContainerView when snapshot provided (stable layout)
- Falls back to UnifiedMediaGridView if no snapshot (backward compatible)

## Key Features

✅ Stable row heights after first appearance
✅ Media uses fixed aspect ratios (no layout changes on image load)
✅ Banner stability (boost/reply banners have fixed heights in snapshots)
✅ Anchor preservation for layout-affecting updates
✅ Aggressive prefetching to minimize missing dimensions
✅ Backward compatible (graceful fallback if no snapshot)

## Files Added

- SocialFusion/Models/PostLayoutSnapshot.swift
- SocialFusion/Utilities/MediaDimensionCache.swift
- SocialFusion/Utilities/ImageSizeFetcher.swift
- SocialFusion/Utilities/MediaPrefetcher.swift
- SocialFusion/Utilities/PostLayoutSnapshotBuilder.swift
- SocialFusion/Utilities/FeedUpdateCoordinator.swift
- SocialFusion/Views/Components/MediaContainerView.swift
- SocialFusionTests/PostLayoutSnapshotBuilderTests.swift
- STABLE_MEDIA_LAYOUT_IMPLEMENTATION.md
- add_layout_snapshot_files.rb

## Files Modified

- SocialFusion/Views/Components/PostCardView.swift
  - Added layoutSnapshot parameter
  - Integrated MediaGridContainerView for stable layout
  - Maintained backward compatibility

- SocialFusion/Views/ConsolidatedTimelineView.swift
  - Added snapshot building and prefetching
  - Integrated snapshot system with existing timeline

## Testing

- Unit tests for PostLayoutSnapshotBuilder
- Test cases for posts with/without media, boosts, replies
- Snapshot stability verification

## Performance

- Dimension fetching uses Range requests (minimal data transfer)
- Aggressive caching reduces redundant fetches
- Prefetching happens before posts appear
- Batch updates prevent excessive view updates

## Regression Prevention

The snapshot system prevents regressions by:
1. Stable snapshots: Once on-screen, snapshots don't change
2. Fixed heights: Media containers use fixed aspect ratios
3. Anchor preservation: Layout changes preserve scroll position
4. Banner stability: Banners have fixed heights in snapshots

## Compatibility

- iOS 16+ compatible
- Forward compatible with iOS 17+
- No deprecated APIs
- No private frameworks
- Swift 6 warnings (non-blocking, main actor isolation)

## Documentation

- STABLE_MEDIA_LAYOUT_IMPLEMENTATION.md: Comprehensive guide
- Inline code documentation
- Test examples

Closes: [Issue number if applicable]
```

# Proactive Parent Post Fetching Architecture

## Overview

This document outlines the architectural solution for proactive parent post fetching in SocialFusion, which eliminates jittery animations in reply banners by moving data fetching from the UI layer to the service layer.

## Problem Statement

### Initial Issue
- Reply banners showed "someone" as placeholder text before fetching actual parent post data
- When users tapped to expand banners, usernames would change from "someone" to real usernames during animation
- This caused jittery layout shifts and poor user experience
- Data fetching was happening reactively in the UI layer (`ExpandingReplyBanner`)

### Root Cause Analysis
1. **Reactive Fetching**: Parent posts were only fetched when users interacted with reply banners
2. **UI Layer Responsibility**: Data fetching logic was embedded in UI components
3. **Animation Timing**: Real data arrived after animations had already started
4. **Layout Instability**: Text content changes during animations caused visual jitter

## Solution Architecture

### Design Principles
1. **Proactive Data Loading**: Fetch parent posts when timeline loads, not when banners expand
2. **Separation of Concerns**: Move data fetching from UI to service layer
3. **Timeline-Level Integration**: Trigger fetching during main timeline updates
4. **Smart Caching**: Prevent duplicate requests and cache results efficiently

### Implementation Strategy
**Timeline-Level Proactive Fetching** - Parent posts are fetched in the background when the main timeline loads posts, ensuring data availability before UI components need it.

## Implementation Details

### 1. Service Layer Integration

**Location**: `SocialServiceManager.safelyUpdateTimeline()` method

Added proactive fetching trigger:
```swift
// Proactively fetch parent posts in the background to prevent jittery reply banner animations
Task.detached(priority: .background) { [weak self] in
    await self?.proactivelyFetchParentPosts(from: posts)
}
```

### 2. Core Fetching Logic

**New Method**: `proactivelyFetchParentPosts(from posts: [Post])`

**Functionality**:
- Identifies posts with `inReplyToID` that need parent data
- Checks `PostParentCache.shared` to avoid duplicate fetches
- Uses `parentFetchInProgress` set to prevent concurrent duplicate requests
- Implements batched concurrent fetching (max 5 at a time)
- Includes 0.1 second delays between batches for API rate limiting

**Implementation**:
```swift
private func proactivelyFetchParentPosts(from posts: [Post]) async {
    let postsNeedingParents = posts.filter { post in
        guard let parentId = post.inReplyToID else { return false }
        let cacheKey = "\(post.platform.rawValue)_\(parentId)"
        return PostParentCache.shared.cache[cacheKey] == nil && 
               !parentFetchInProgress.contains(cacheKey)
    }
    
    // Process in batches to respect API rate limits
    let batches = postsNeedingParents.chunked(into: 5)
    
    for batch in batches {
        await withTaskGroup(of: Void.self) { group in
            for post in batch {
                guard let parentId = post.inReplyToID else { continue }
                group.addTask { [weak self] in
                    await self?.fetchSingleParentPost(parentId: parentId, platform: post.platform)
                }
            }
        }
        
        // Small delay between batches to be respectful to APIs
        if batches.count > 1 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
    }
}
```

### 3. Individual Post Fetching

**New Method**: `fetchSingleParentPost(parentId: String, platform: SocialPlatform)`

**Features**:
- Handles both Mastodon and Bluesky platforms
- Uses existing service methods (`fetchMastodonStatus`, `fetchBlueskyPostByID`)
- Caches results in `PostParentCache.shared.cache[cacheKey]`
- Includes proper error handling without stopping the entire process
- Prevents duplicate concurrent requests

**Implementation**:
```swift
private func fetchSingleParentPost(parentId: String, platform: SocialPlatform) async {
    let cacheKey = "\(platform.rawValue)_\(parentId)"
    
    // Prevent duplicate concurrent requests
    guard !parentFetchInProgress.contains(cacheKey) else { return }
    parentFetchInProgress.insert(cacheKey)
    defer { parentFetchInProgress.remove(cacheKey) }
    
    do {
        let parentPost: Post?
        
        switch platform {
        case .mastodon:
            parentPost = try await fetchMastodonStatus(statusId: parentId)
        case .bluesky:
            parentPost = try await fetchBlueskyPostByID(postId: parentId)
        }
        
        if let parentPost = parentPost {
            PostParentCache.shared.cache[cacheKey] = parentPost
        }
    } catch {
        // Log error but don't stop the process
        print("Failed to fetch parent post \(parentId): \(error)")
    }
}
```

### 4. Utility Extensions

**Array Extension for Batching**:
```swift
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
```

### 5. UI Layer Simplification

**Modified**: `ExpandingReplyBanner.swift`

**Changes**:
- Removed `startProactiveFetch()` method entirely
- Simplified `onAppear` to only check cache (service manager handles proactive fetching)
- Maintained fallback fetching in `triggerParentFetch()` for edge cases
- Updated logging to reflect new architecture

**Before**:
```swift
.onAppear {
    startProactiveFetch()
}

private func startProactiveFetch() {
    // Complex UI-layer fetching logic
}
```

**After**:
```swift
.onAppear {
    // Service manager handles proactive fetching
    // UI only needs to check cache
    if let parentPost = PostParentCache.shared.getParentPost(for: post) {
        self.parentPost = parentPost
    }
}
```

## Data Flow Architecture

### Previous Flow (Reactive)
```
Timeline Loads → UI Renders → User Taps Banner → Fetch Parent → Update UI → Animation Jitter
```

### New Flow (Proactive)
```
Timeline Loads → Background Fetch Parents → Cache Results → UI Renders → Smooth Animation
```

### Detailed Flow Diagram
1. **Timeline Loading**: `SocialServiceManager.safelyUpdateTimeline()` processes new posts
2. **Background Task**: `proactivelyFetchParentPosts()` identifies reply posts needing parent data
3. **Concurrent Fetching**: Batched API calls for missing parent posts (max 5 concurrent)
4. **Cache Population**: Results stored in `PostParentCache.shared`
5. **UI Display**: Reply banners immediately show real usernames from cache
6. **Smooth Animations**: No layout shifts during expansion animations

## Performance Optimizations

### API Rate Limiting
- **Batch Processing**: Maximum 5 concurrent requests per batch
- **Inter-batch Delays**: 0.1 second delays between batches
- **Background Priority**: Uses `.background` priority to avoid blocking UI

### Duplicate Prevention
- **Cache Checking**: Verifies `PostParentCache.shared` before making requests
- **In-Progress Tracking**: `parentFetchInProgress` set prevents concurrent duplicate requests
- **Efficient Filtering**: Only processes posts that actually need parent data

### Memory Management
- **Weak References**: Uses `[weak self]` in async tasks to prevent retain cycles
- **Task Detachment**: `Task.detached` prevents timeline updates from waiting for fetching
- **Proper Cleanup**: Ensures `parentFetchInProgress` is cleaned up with `defer`

## Error Handling Strategy

### Graceful Degradation
- Individual fetch failures don't stop the entire process
- Fallback fetching remains available in UI layer for edge cases
- Comprehensive logging for debugging without user impact

### Resilience Patterns
```swift
do {
    // Attempt to fetch parent post
} catch {
    // Log error but continue processing other posts
    print("Failed to fetch parent post \(parentId): \(error)")
    // Don't throw - let other fetches continue
}
```

## Benefits Achieved

### User Experience Improvements
- **Smooth Animations**: Real usernames available before banners appear
- **No Layout Shifts**: Eliminates jittery text changes during expansion
- **Immediate Response**: No waiting for data when expanding reply banners
- **Consistent Behavior**: Works across all platforms (Mastodon & Bluesky)

### Performance Benefits
- **Background Processing**: Doesn't block UI rendering or user interactions
- **Efficient Batching**: Optimizes API usage with concurrent requests
- **Smart Caching**: Prevents duplicate requests and improves response times
- **Proactive Loading**: Data ready when needed, not when requested

### Architecture Improvements
- **Separation of Concerns**: Data fetching moved from UI to service layer
- **Single Responsibility**: UI components focus on display, services handle data
- **Maintainability**: Centralized parent post fetching logic
- **Scalability**: Easy to extend for additional platforms or features

## Testing and Validation

### Build Results
- Successfully resolved all linter errors
- Build completed with only warnings (no errors)
- App launched successfully for manual testing

### Validation Checklist
- [x] Reply banners show real usernames immediately
- [x] Smooth expansion animations without layout shifts
- [x] Background fetching doesn't block UI
- [x] Proper error handling and graceful degradation
- [x] Cache prevents duplicate API requests
- [x] Works across both Mastodon and Bluesky platforms

## Future Enhancements

### Potential Improvements
1. **Prefetch Depth**: Consider fetching parent-of-parent posts for deeper reply chains
2. **Cache Expiration**: Implement TTL for cached parent posts
3. **Offline Support**: Cache parent posts locally for offline viewing
4. **Analytics**: Track cache hit rates and fetching performance
5. **Adaptive Batching**: Adjust batch sizes based on network conditions

### Monitoring Considerations
- Track API request patterns and rate limiting effectiveness
- Monitor cache hit rates and memory usage
- Measure animation smoothness improvements
- Log any remaining edge cases for fallback fetching

## Conclusion

The proactive parent post fetching architecture successfully addresses the jittery animation problem by fundamentally changing when and where parent post data is fetched. By moving from reactive UI-layer fetching to proactive service-layer fetching, we achieve:

1. **Smooth User Experience**: Animations are fluid and responsive
2. **Clean Architecture**: Proper separation of concerns between UI and data layers
3. **Efficient Performance**: Smart caching and batching optimize API usage
4. **Maintainable Code**: Centralized logic that's easy to understand and extend

This solution demonstrates how architectural improvements can directly translate to better user experience while maintaining code quality and system performance. 
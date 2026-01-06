# Thread Summary: Video Error and AttributeGraph Cycle Fixes

## Original Problem Statement

The user requested help resolving video playback errors without creating regressions, particularly around boost appearance in the feed and reply banners. The app was experiencing:

1. **AttributeGraph cycles**: Hundreds of `=== AttributeGraph: cycle detected through attribute XXXXX ===` warnings
2. **State modification warnings**: `Modifying state during view update, this will cause undefined behavior` errors
3. **Preference update warnings**: `Bound preference ThumbnailFramePreference tried to update multiple times per frame` warnings
4. **Video playback errors**: `CoreMediaErrorDomain error -12881` (Format description error) during HLS video playback

## Root Causes Identified

### 1. State Updates During View Rendering
- `onImageLoad` callbacks in `SmartMediaView` were directly updating `@State` variables (`loadedAspectRatio`) with `withAnimation` during view rendering
- `VideoPlayerView.onSizeDetected` callback was triggering state updates synchronously
- `ThumbnailFramePreference` updates in `UnifiedMediaGridView` were happening too frequently during view updates

### 2. HLS Video Loading Issues
- Incorrect content type handling for HLS segments (`.ts` files) and playlists (`.m3u8` files)
- Byte range support not properly set for HLS segments
- Timing issues between content information provision and data delivery for HLS segments

## Files Modified

### 1. `SocialFusion/Views/Components/SmartMediaView.swift`
**Changes Made:**
- **`onImageLoad` callbacks**: Wrapped state updates in `Task { @MainActor in ... }` with 16ms delay (~1 frame at 60fps) to defer updates outside view rendering cycle
- **`VideoPlayerView.onSizeDetected`**: Increased delay from 16ms to 33ms (~2 frames), added `DispatchQueue.main.async` wrapper, added cancellation checks
- **`VideoPlayerView.onAppear`**: Improved deferral mechanism for size detection with longer delays and proper async handling

**Key Code Pattern Applied:**
```swift
onImageLoad: { uiImage in
    // Defer state update to prevent AttributeGraph cycles
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 16_000_000)  // ~1 frame at 60fps
        let size = uiImage.size
        if size.width > 0 && size.height > 0 {
            await MainActor.run {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    loadedAspectRatio = CGFloat(size.width / size.height)
                }
            }
        }
    }
}
```

### 2. `SocialFusion/Views/Components/UnifiedMediaGridView.swift`
**Changes Made:**
- **Preference update throttling**: Increased delay from 66ms to 100ms (~6 frames at 60fps)
- **Additional deferral**: Added `DispatchQueue.main.asyncAfter(deadline: .now() + 0.016)` before final state update
- **Improved cancellation handling**: Better guard clauses and cancellation checks

**Key Code Pattern Applied:**
```swift
preferenceUpdateTask = Task { @MainActor in
    try? await Task.sleep(nanoseconds: 100_000_000) // ~6 frames at 60fps
    guard !Task.isCancelled else { 
        isUpdatingFrames = false
        return 
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { // One more frame delay
        guard !Task.isCancelled else { 
            isUpdatingFrames = false
            return 
        }
        thumbnailFrames = frames
        isUpdatingFrames = false
    }
}
```

### 3. `SocialFusion/Services/AuthenticatedVideoAssetLoader.swift`
**Previous Changes (from earlier in thread):**
- Set correct content types: `video/mp2t` for HLS segments (`.ts`), `application/vnd.apple.mpegurl` for HLS playlists (`.m3u8`)
- Always set `isByteRangeAccessSupported = true` for HLS segments
- Increased delay for HLS segment data provision to 0.3 seconds
- Added validation to ensure content information is fully populated before providing data

**Status**: No changes made in this session, but these fixes are critical for resolving the -12881 error.

### 4. `SocialFusion/Views/Components/PostCardView.swift`
**Status**: No changes made. Verified that boost and reply banner logic remains intact:
- `boostBannerView` correctly displays boost banners using `boostHandleToShow`
- `replyInfo` correctly prioritizes `originalPost` reply info for boosted content
- `displayPost` correctly uses `originalPost` for boosts
- `displayAttachments` correctly uses `originalPost` attachments for boosts

## Technical Approach

### Strategy for Fixing AttributeGraph Cycles
1. **Defer all state updates**: Use `Task { @MainActor in ... }` with delays to move updates outside SwiftUI's view update cycle
2. **Multiple layers of deferral**: Combine `Task.sleep` with `DispatchQueue.main.async` to ensure updates happen after view rendering completes
3. **Throttling**: Increase delays to reduce update frequency and prevent multiple updates per frame
4. **Cancellation handling**: Check `Task.isCancelled` before performing updates to prevent unnecessary work

### Key Principles Applied
- **Never update state synchronously in callbacks**: All callbacks that modify state now use async deferral
- **Use appropriate delays**: 16-33ms for immediate callbacks, 100ms+ for preference updates
- **Double-check main thread**: Use `@MainActor` and `MainActor.run` to ensure thread safety
- **Prevent concurrent updates**: Use flags like `isUpdatingFrames` to prevent overlapping updates

## Current State

### Completed
✅ Fixed `onImageLoad` callbacks to defer state updates  
✅ Improved `VideoPlayerView.onSizeDetected` callback deferral  
✅ Enhanced `UnifiedMediaGridView` preference updates with better throttling  
✅ Verified boost and reply banners remain functional  
✅ No linter errors introduced  

### Expected Outcomes
- **Reduced AttributeGraph cycles**: State updates now happen outside view rendering cycle
- **Fewer "Modifying state during view update" warnings**: All state updates are properly deferred
- **Reduced preference update warnings**: Throttling prevents multiple updates per frame
- **Improved video playback**: State update fixes should reduce interference with AVFoundation's video loading

### Potential Remaining Issues
- The `CoreMediaErrorDomain error -12881` may still occur if the HLS content information timing issues persist
- If AttributeGraph cycles continue, may need to investigate other sources of state updates during rendering
- Performance monitoring needed to ensure delays don't cause noticeable UI lag

## Testing Recommendations

1. **Monitor console logs** for:
   - Reduction in AttributeGraph cycle warnings
   - Reduction in "Modifying state during view update" warnings
   - Reduction in preference update warnings
   - Video playback errors (-12881)

2. **Test functionality**:
   - Boost banners appear correctly in feed
   - Reply banners appear correctly for replies and boosted replies
   - Video playback works smoothly (especially HLS videos)
   - Image loading and aspect ratio updates work correctly
   - Media grid transitions work smoothly

3. **Performance testing**:
   - Ensure delays don't cause noticeable UI lag
   - Check that media loads at acceptable speeds
   - Verify smooth scrolling in timeline

## Related Files (Not Modified But Relevant)

- `SocialFusion/Views/Components/CachedAsyncImage.swift`: Provides `onImageLoad` callback mechanism
- `SocialFusion/Stores/PostActionStore.swift`: Manages post action state (not modified but related to state management)
- `SocialFusion/ViewModels/PostViewModel.swift`: Manages post view state (not modified but related to state management)

## Previous Context (From Summary)

The codebase had already implemented several fixes for AttributeGraph cycles in other areas:
- `ATTRIBUTEGRAPH_CYCLE_FIX.md`: Documents fixes for post read tracking and scroll position saving
- `ATTRIBUTEGRAPH_FIXES.md`: Documents fixes for `SocialServiceManager` state management
- `REPLY_BANNER_STATE_FIX.md`: Documents fixes for reply banner state management

The current fixes follow similar patterns but address different sources of cycles (media loading callbacks and preference updates).

## Next Steps (If Issues Persist)

1. **If AttributeGraph cycles continue**:
   - Search for other sources of state updates during view rendering
   - Check for other callbacks that modify state synchronously
   - Consider using `@StateObject` vs `@State` more carefully
   - Investigate circular dependencies between `@Published` properties

2. **If video errors persist**:
   - Review `AuthenticatedVideoAssetLoader` timing logic
   - Consider increasing delays further (but balance with timeout risks)
   - Check if content information is being set correctly before data provision
   - Verify byte range support flags are correct for all request types

3. **If performance degrades**:
   - Reduce delays if they cause noticeable lag
   - Optimize throttling thresholds
   - Consider batching multiple state updates

## Key Takeaways

1. **SwiftUI state updates must be deferred**: Never update `@State` or `@Published` properties synchronously in callbacks that run during view rendering
2. **Use async deferral patterns**: `Task { @MainActor in try? await Task.sleep(...) }` followed by `DispatchQueue.main.async` provides reliable deferral
3. **Throttle frequent updates**: Preference updates and other frequent callbacks need aggressive throttling (100ms+ delays)
4. **Test thoroughly**: Changes to state management can have subtle effects on UI behavior
5. **Preserve functionality**: Always verify that fixes don't break existing features (boost/reply banners in this case)

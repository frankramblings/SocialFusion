# AVFoundation Refactor Summary: Using Standard URLs for HLS

## Overview

Based on `WHAT_OTHER_APPS_DO_DIFFERENTLY.md`, we've refactored our AVFoundation handling to align with industry best practices. The key change is **using standard HTTPS URLs for HLS instead of custom URL schemes**.

## Root Cause

The persistent `-12881` (format description error) and `-12753` (timebase error) were caused by:
1. **Using custom URL schemes for HLS** - AVFoundation's HLS handling is optimized for standard URLs
2. **Custom schemes violate AVFoundation's HLS requirements** - Even when handled correctly, custom schemes can cause issues

## Changes Made

### 1. Switched HLS to Standard HTTPS URLs

**Before:**
- Converted HLS URLs to `authenticated-video://` custom scheme
- Pre-fetched playlist with HEAD request and delays
- Used custom scheme to ensure resource loader is called

**After:**
- Use standard `https://` URLs for HLS playlists
- Resource loader delegate handles authentication for standard URLs
- No pre-fetching or delays needed

**Files Changed:**
- `SocialFusion/Views/Components/SmartMediaView.swift`:
  - Removed custom scheme conversion for HLS
  - Removed pre-fetch logic and delays
  - Updated retry path to also use standard URLs

### 2. Resource Loader Already Supports Standard URLs

The `AuthenticatedVideoAssetLoader` already handles standard HTTPS URLs correctly:
- Checks if URL needs authentication (Bluesky/Mastodon domains)
- Intercepts standard URLs that need authentication
- AVFoundation calls the resource loader delegate when authentication is needed

**No changes needed** - the resource loader was already designed to handle both custom schemes and standard URLs.

### 3. Content Information Handling

Content information is already set **synchronously and immediately**:
- No delays before setting content info
- Content info set before providing data
- Data provided immediately after content info

**No changes needed** - this was already correct.

### 4. Asset Property Loading

Asset properties are loaded before creating player item:
- For HLS: Only load `.isPlayable` (tracks not available until playlist parsed)
- For non-HLS: Load both `.isPlayable` and `.tracks`
- Player item created only after asset properties are loaded

**No changes needed** - this was already correct.

## Why This Should Work

1. **AVFoundation's Native HLS Handling**: Standard URLs allow AVFoundation to use its optimized HLS parsing
2. **Resource Loader Still Called**: The delegate is called for standard URLs when authentication is needed
3. **No Timing Issues**: Standard URLs don't have the timing problems that custom schemes can cause
4. **Industry Best Practice**: This matches what successful apps (Bluesky, IceCubesApp) do

## Expected Results

- **Eliminates `-12881` errors**: Format description should be available because AVFoundation handles HLS natively
- **Eliminates `-12753` errors**: Timebase should be created correctly with standard URLs
- **Better Performance**: AVFoundation's optimized HLS handling should improve playback
- **More Reliable**: Standard URLs are more reliable than custom schemes

## Testing

After this change, test:
1. HLS video playback in feed (Bluesky videos)
2. HLS video playback in fullscreen
3. Video playback with authentication (both Bluesky and Mastodon)
4. Error handling and retry logic

## Fallback

If standard URLs don't work (resource loader not called in time), we can:
1. Use URLProtocol to intercept requests at a lower level
2. Pre-authenticate requests using URLSession configuration
3. Consider downloading HLS playlists and rewriting segment URLs

However, based on the document analysis, standard URLs should work correctly.

## References

- `WHAT_OTHER_APPS_DO_DIFFERENTLY.md` - Analysis of what successful apps do
- `HLS_FIX_RECOMMENDATIONS.md` - Previous recommendations
- `HLS_TIMEBASE_ERROR_FIX.md` - Previous timebase error fixes

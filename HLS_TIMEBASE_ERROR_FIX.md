# HLS Timebase Error (-12753) Fix

## Root Cause

The timebase error (`kCMTimebaseError_InvalidTimebase`, -12753) occurs because:

1. **AVFoundation doesn't call resource loader for standard HTTPS URLs immediately**
   - AVFoundation only calls the resource loader delegate for standard URLs AFTER a request fails (401/403)
   - For HLS, this means AVFoundation tries to fetch the playlist first, fails, then might retry
   - By the time authentication happens, AVFoundation may have already tried to create a timebase, causing the error

2. **Custom scheme ensures resource loader is called from the start**
   - With custom scheme (`authenticated-video://`), AVFoundation MUST call the resource loader
   - This ensures authentication happens before AVFoundation tries to parse the playlist
   - Prevents timebase errors by ensuring content info is available when needed

## Solution Implemented

### 1. Use Custom Scheme for HLS (Not Standard URLs)
- Changed back to custom scheme for HLS playlists
- Ensures resource loader is called from the start
- Prevents timebase errors by ensuring authentication happens first

### 2. Proper Handling with Custom Scheme
- Load asset properties (`.isPlayable`) before creating player item
- Don't load tracks for HLS (they're not available until playlist is parsed)
- Set content information synchronously and immediately
- Provide data immediately after content info (no delays)
- Finish loading immediately after providing data (no delays)

### 3. Key Differences from Previous Approach
- **Previous**: Used standard HTTPS URLs, hoping resource loader would be called
- **Current**: Use custom scheme to guarantee resource loader is called
- **Why**: AVFoundation's behavior with standard URLs is unreliable for HLS

## Why Custom Scheme Works Better for HLS

1. **Guaranteed Resource Loader Call**: Custom schemes force AVFoundation to use the resource loader
2. **Immediate Authentication**: Authentication happens before AVFoundation tries to parse
3. **Proper Timing**: Content info is set before AVFoundation needs it
4. **No Race Conditions**: No risk of AVFoundation trying to parse before authentication

## Trade-offs

- **Custom Scheme**: More reliable for HLS, but requires proper handling
- **Standard URLs**: Simpler, but AVFoundation might not call resource loader in time

## Implementation

The fix ensures:
1. Custom scheme is used for HLS (guarantees resource loader call)
2. Asset properties are loaded before player item creation
3. Content information is set synchronously
4. Data is provided immediately (no delays)
5. All operations happen on main thread

This combination prevents the timebase error while maintaining reliable HLS playback.

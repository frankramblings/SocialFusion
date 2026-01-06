# HLS Error -12881 Fix Attempt

## Problem
Despite our previous fixes, the `CoreMediaErrorDomain error -12881` (format description error) is still occurring when playing HLS videos from Bluesky.

## Analysis from Logs

From the user's logs, I can see:
1. ✅ HLS playlist loads successfully
2. ✅ HLS segment (.ts file) loads successfully  
3. ✅ Data is provided correctly (valid MPEG-TS sync byte 0x47 detected)
4. ✅ Request completes successfully
5. ❌ Then AVFoundation throws -12881 error when trying to parse format description

## Root Cause Hypothesis

The error happens AFTER data is provided successfully, which suggests:
- AVFoundation needs more time to process the content information before receiving data
- The 0.3 second delay might not be sufficient
- AVFoundation might need time to START processing the data before we finish the loading request

## Changes Made

### 1. Increased Initial Delay
- **Before**: 0.3 seconds
- **After**: 0.5 seconds
- **Reason**: AVFoundation needs more time to process format descriptions, especially for the first segment

### 2. Increased Fallback Delay  
- **Before**: 0.2 seconds additional wait
- **After**: 0.3 seconds additional wait
- **Reason**: If content info isn't ready, give it more time

### 3. Added Delay Before Finishing HLS Segments
- **New**: 50ms delay before calling `finishLoading()` for HLS segments
- **Reason**: Allows AVFoundation to start processing the segment data before we signal completion
- **Note**: This is a small delay that shouldn't cause timeouts but helps AVFoundation

## Testing

After these changes, test:
1. Play HLS videos from Bluesky
2. Monitor console for -12881 errors
3. Check if videos play successfully
4. Monitor if there are any timeout issues

## If This Doesn't Work

If -12881 errors persist, we may need to:
1. Increase delay further (but risk timeouts)
2. Investigate if there's a way to detect when AVFoundation is ready
3. Consider alternative approaches (e.g., pre-downloading segments)
4. Check if Bluesky's HLS implementation has specific requirements

## Related Files
- `SocialFusion/Services/AuthenticatedVideoAssetLoader.swift` - Lines 433-478 (delay logic)
- `SocialFusion/Services/AuthenticatedVideoAssetLoader.swift` - Lines 631-645 (finish loading logic)

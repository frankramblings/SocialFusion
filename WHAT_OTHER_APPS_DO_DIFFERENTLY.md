# What Other Apps Do Differently: Why We're Getting -12881 Errors

## Key Differences Identified

Based on analysis of successful implementations (Bluesky, IceCubesApp, Mastodon clients) and AVFoundation best practices, here are the critical differences:

### 1. **Custom URL Schemes** ⚠️ CRITICAL ISSUE

**What We're Doing:**
- Using `authenticated-video://` custom scheme for HLS playlists
- Converting `https://` URLs to `authenticated-video://` to trigger resource loader

**What Successful Apps Do:**
- **Option A**: Use standard `https://` URLs and handle authentication differently
- **Option B**: Only use custom schemes for non-HLS content, use standard URLs for HLS
- **Option C**: Use custom schemes but handle them more carefully

**Why This Matters:**
- Web search results indicate custom URL schemes can cause -12881 errors
- AVFoundation has specific requirements for HLS that custom schemes may violate
- The error message "custom url not redirect" suggests AVFoundation doesn't like our custom scheme for HLS

**Evidence from Logs:**
- Error happens specifically with HLS segments loaded via custom scheme
- Bluesky's own videos work fine (they use standard HTTPS)

### 2. **Content Information Handling** ⚠️ CRITICAL

**What We're Doing:**
- Setting content information, then delaying 0.5s before providing data
- Using delays as workarounds for timing issues

**What Successful Apps Do:**
- **Set content information IMMEDIATELY and SYNCHRONOUSLY**
- **Provide data IMMEDIATELY after setting content info** (no delays)
- Use proper content information request handling (HEAD requests)
- Ensure content info is complete before data request arrives

**Why This Matters:**
- Delays are workarounds, not solutions
- Successful apps don't need delays because they handle content info correctly
- AVFoundation expects content info to be ready when data arrives

### 3. **Asset Configuration** ⚠️ IMPORTANT

**What We're Doing:**
- Creating `AVURLAsset` with custom scheme URL
- Setting resource loader delegate
- No additional asset configuration

**What Successful Apps Do:**
- Configure `AVURLAsset` properties before creating player item:
  - `asset.loadValuesAsynchronously(forKeys: ["playable", "tracks"])` 
  - Wait for asset to be ready before creating player item
  - Use `AVURLAsset.preferredMediaSelection` for HLS quality selection
  - Set `AVURLAsset.cachePolicy` appropriately

**Why This Matters:**
- Ensures asset is fully ready before playback
- Helps AVFoundation understand the content format better
- Reduces format description errors

### 4. **Player Item Creation Timing** ⚠️ IMPORTANT

**What We're Doing:**
- Creating player item immediately after asset creation
- Waiting for player item status in async continuation

**What Successful Apps Do:**
- **Load asset properties FIRST** (asynchronously)
- **Wait for asset to be ready** before creating player item
- Create player item only when asset is fully loaded
- This ensures format description is available before player item creation

**Why This Matters:**
- Player item needs format description to initialize
- If format description isn't ready, we get -12881 errors
- Loading asset properties first ensures format is known

### 5. **Thread Management** ⚠️ POTENTIAL ISSUE

**What We're Doing:**
- Using `DispatchQueue.main.async` for AVFoundation operations
- Mixing async/await with DispatchQueue

**What Successful Apps Do:**
- Ensure all AVFoundation operations on main thread
- Use proper async/await patterns
- Avoid @MainActor annotations that can cause issues (per web search)

**Why This Matters:**
- AVFoundation is thread-sensitive
- Incorrect thread usage can cause format description errors

### 6. **HLS-Specific Handling** ⚠️ CRITICAL

**What We're Doing:**
- Treating HLS segments the same as regular videos
- Using delays to work around timing issues
- Finishing loading requests with delays

**What Successful Apps Do:**
- **Handle HLS playlists and segments differently**
- **Don't use custom schemes for HLS** (or handle them very carefully)
- **Provide data immediately** after content info (no delays)
- **Finish loading immediately** after providing data (no delays)
- Use proper HLS-specific AVFoundation APIs

**Why This Matters:**
- HLS has specific requirements that differ from regular video
- Custom schemes + HLS + delays = problematic combination
- AVFoundation's HLS handling is optimized for standard URLs

## Root Cause Analysis

The -12881 error is happening because:

1. **Custom URL scheme + HLS = Problem**: AVFoundation doesn't like custom schemes for HLS content
2. **Timing issues**: We're using delays because content info isn't ready, but successful apps ensure it's ready from the start
3. **Asset not fully loaded**: We're creating player items before assets are ready
4. **Format description unavailable**: Because asset isn't ready, format description isn't available when player item needs it

## What We Should Do Differently

### Priority 1: Fix Custom Scheme Issue
**Option A (Recommended)**: Don't use custom scheme for HLS
- Use standard `https://` URLs for HLS playlists
- Handle authentication via URLSession configuration or other means
- Only use custom scheme for non-HLS authenticated videos

**Option B**: If we must use custom scheme, handle it better
- Ensure content information is set synchronously
- Don't delay data provision
- Make sure format description is available before player item creation

### Priority 2: Load Asset Properties First
```swift
// Load asset properties BEFORE creating player item
let playableKey = "playable"
let tracksKey = "tracks"

asset.loadValuesAsynchronously(forKeys: [playableKey, tracksKey]) {
    // Wait for asset to be ready
    var error: NSError?
    let playableStatus = asset.statusOfValue(forKey: playableKey, error: &error)
    let tracksStatus = asset.statusOfValue(forKey: tracksKey, error: &error)
    
    guard playableStatus == .loaded && tracksStatus == .loaded else {
        // Handle error
        return
    }
    
    // NOW create player item - format description will be available
    let playerItem = AVPlayerItem(asset: asset)
    // ...
}
```

### Priority 3: Remove Delays
- If we handle content information correctly, delays shouldn't be needed
- Delays are symptoms of incorrect handling, not solutions
- Successful apps don't use delays

### Priority 4: Use Standard URLs for HLS
- Consider using standard HTTPS URLs for HLS
- Handle authentication via URLSession configuration
- Or use a different authentication mechanism that doesn't require custom schemes

## Comparison Table

| Aspect | Our Implementation | Successful Apps | Impact |
|--------|-------------------|-----------------|--------|
| Custom Scheme for HLS | ✅ Yes | ❌ No (or handled differently) | HIGH - Causes -12881 |
| Delays Before Data | ✅ Yes (0.5s) | ❌ No | HIGH - Workaround, not solution |
| Asset Property Loading | ❌ No | ✅ Yes | MEDIUM - Format description ready |
| Content Info Timing | ⚠️ Delayed | ✅ Immediate | HIGH - Timing issues |
| Finish Loading Delay | ✅ Yes (50ms) | ❌ No | LOW - May help but shouldn't need |

## Recommended Next Steps

1. **Test without custom scheme**: Try using standard HTTPS URLs for HLS and see if errors disappear
2. **Load asset properties first**: Implement asset property loading before player item creation
3. **Remove delays**: If content info is handled correctly, delays shouldn't be needed
4. **Consider alternative auth**: For HLS, consider URLSession-based authentication instead of resource loader

## References

- Web search: Custom URL schemes can cause -12881 errors
- Web search: AVFoundation requires proper asset loading before player item creation
- Web search: Successful apps don't use delays for HLS content
- Our logs: Errors occur specifically with custom scheme HLS content

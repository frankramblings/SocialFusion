# HLS -12881 Error: What Other Apps Do Differently

## Summary

After analyzing successful video playback implementations and comparing with our code, here are the key differences that explain why we're getting -12881 errors:

## Critical Differences

### 1. **Custom URL Schemes for HLS** 🔴 CRITICAL

**Our Approach:**
```swift
// We convert https:// to authenticated-video:// for HLS
components?.scheme = "authenticated-video"
let asset = AVURLAsset(url: customSchemeURL)
```

**What Successful Apps Do:**
- **Use standard `https://` URLs for HLS content**
- Handle authentication via URLSession configuration or other mechanisms
- **Avoid custom schemes for HLS** because AVFoundation has specific HLS requirements

**Why This Causes -12881:**
- Web search results indicate custom URL schemes can cause format description errors
- AVFoundation's HLS implementation expects standard URLs
- Custom schemes interfere with AVFoundation's internal HLS processing

### 2. **Asset Property Loading** 🟡 IMPORTANT

**Our Approach:**
```swift
let asset = AVURLAsset(url: customSchemeURL)
let playerItem = AVPlayerItem(asset: asset)  // Created immediately
```

**What Successful Apps Do:**
```swift
let asset = AVURLAsset(url: url)
// Load properties FIRST
asset.loadValuesAsynchronously(forKeys: ["playable", "tracks"]) {
    // Wait for asset to be ready
    // THEN create player item
    let playerItem = AVPlayerItem(asset: asset)
}
```

**Why This Matters:**
- Format description becomes available when asset properties are loaded
- Player item needs format description to initialize properly
- Without it, we get -12881 errors

### 3. **Content Information Timing** 🟡 IMPORTANT

**Our Approach:**
- Set content info, then delay 0.5s before providing data
- Use delays as workarounds

**What Successful Apps Do:**
- Set content information **immediately and synchronously**
- Provide data **immediately** after content info (no delays)
- Ensure content info is **complete** before data request

**Why This Matters:**
- Delays are symptoms of incorrect handling
- Successful apps don't need delays because they handle it correctly
- AVFoundation expects content info to be ready when data arrives

### 4. **No Delays** 🟢 OPTIMIZATION

**Our Approach:**
- 0.5s delay before providing HLS segment data
- 50ms delay before finishing loading request

**What Successful Apps Do:**
- **No delays** - they handle content information correctly from the start
- Data provided immediately after content info is set
- Loading finished immediately after data is provided

## Root Cause

The -12881 error occurs because:

1. **Custom scheme + HLS = Problem**: AVFoundation doesn't properly handle custom schemes for HLS
2. **Format description unavailable**: Because we create player items before assets are ready
3. **Timing issues**: We use delays because content info isn't handled correctly

## Recommended Solutions

### Solution 1: Use Standard URLs for HLS (RECOMMENDED)

Instead of custom scheme, use URLSession with authentication:

```swift
// Create URLSession with authentication
let config = URLSessionConfiguration.default
config.httpAdditionalHeaders = ["Authorization": "Bearer \(token)"]

// Use standard HTTPS URL
let asset = AVURLAsset(url: httpsURL)
// AVFoundation will use URLSession for requests
```

**Pros:**
- No custom scheme issues
- AVFoundation handles HLS natively
- No -12881 errors

**Cons:**
- Need to configure URLSession properly
- May need to handle URLSession delegate

### Solution 2: Load Asset Properties First

```swift
let asset = AVURLAsset(url: url)

// Load properties BEFORE creating player item
try await asset.load(.isPlayable)
try await asset.load(.tracks)

// Now format description is available
let playerItem = AVPlayerItem(asset: asset)
```

**Pros:**
- Format description ready before player item creation
- Reduces -12881 errors
- Works with custom schemes

**Cons:**
- Still has custom scheme issues
- Adds async complexity

### Solution 3: Hybrid Approach

- Use standard URLs for HLS (no custom scheme)
- Use custom scheme + resource loader for non-HLS authenticated videos
- Load asset properties before creating player items

**Pros:**
- Best of both worlds
- HLS works reliably
- Non-HLS still authenticated

**Cons:**
- More complex code paths

## Immediate Action Items

1. **Test with standard HTTPS URLs**: See if -12881 errors disappear
2. **Implement asset property loading**: Load properties before player item creation
3. **Remove delays**: If content info is handled correctly, delays aren't needed
4. **Consider URLSession-based auth**: For HLS, use URLSession instead of resource loader

## Evidence

From your logs:
- Error occurs with custom scheme HLS content
- Error happens after segment data is provided successfully
- Suggests format description issue, not data issue

From web search:
- Custom URL schemes can cause -12881 errors
- AVFoundation has specific HLS requirements
- Successful apps use standard URLs for HLS

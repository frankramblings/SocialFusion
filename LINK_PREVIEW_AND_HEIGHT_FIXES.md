# Link Preview and Height Fixes

## Issues Fixed

### 1. 🔗 External Links Not Showing in Bluesky Posts

**Problem**: Bluesky posts with external embeds (YouTube videos, links, GIFs) weren't showing link previews because the URLs were in the embed metadata but not in the post content that URLService analyzes.

**Root Cause**: 
```json
{
  "external": {
    "uri": "https://www.youtube.com/watch?v=cEsr5Mm3JfE",
    "title": "Metric \"Dead Disco\" (Official Video)"
  },
  "$type": "app.bsky.embed.external#view"
}
```
The URLs were in the embed data but URLService was only analyzing the text content, which was often empty.

**Solution**: Modified `BlueskyService.swift` to extract external URLs from embeds and add them to post content:

```swift
// Extract external URLs from embeds for link preview
if let embedType = embed["$type"] as? String,
    embedType == "app.bsky.embed.external#view",
    let external = embed["external"] as? [String: Any],
    let externalUri = external["uri"] as? String
{
    externalEmbedURL = externalUri
    logger.info("[Bluesky] Found external embed URL: \(externalUri)")
}

// Add external embed URL to content for link detection
var finalContent = text
if let externalURL = externalEmbedURL {
    if finalContent.isEmpty {
        finalContent = externalURL
    } else if !finalContent.contains(externalURL) {
        finalContent += " \(externalURL)"
    }
    logger.info("[Bluesky] Added external URL to post content: \(externalURL)")
}
```

### 2. 📏 Link Preview Height Too Large

**Problem**: Link previews were taking up too much vertical space with `idealHeight: 200` making the timeline feel cramped.

**Solution**: Reduced link preview heights throughout the app:

1. **Post+ContentView.swift**: `idealHeight: 200` → `idealHeight: 140`
2. **Post.swift**: `idealHeight: 200` → `idealHeight: 140`  
3. **PostDetailView.swift**: `idealHeight: 200` → `idealHeight: 140`
4. **StabilizedLinkPreview.swift**: 
   - Image max height: `160` → `100`
   - Image min height: `100` → `80`
   - Loading placeholder height: `130` → `80`

## Expected Results

✅ **External links in Bluesky posts** should now show proper link previews
✅ **Link previews** should be more compact and take up less vertical space
✅ **YouTube links, GIFs, and other external embeds** should display properly

## Debug Information

The fixes include comprehensive logging:
- `🔍 [URLService]` - Link extraction and detection
- `🔗 [BlueskyService]` - External embed URL processing  
- `🎯 [StabilizedLinkPreview]` - Preview generation and metadata loading

## Test Cases

1. **Bluesky posts with YouTube links** - Should show link previews
2. **Bluesky posts with external images/GIFs** - Should show link previews
3. **Posts with both text and external links** - Should show both content and link previews
4. **Empty posts with only external embeds** - Should show the URL as content with preview

## Files Modified

- `SocialFusion/Services/BlueskyService.swift` - External URL extraction
- `SocialFusion/Models/Post+ContentView.swift` - Height reduction 
- `SocialFusion/Models/Post.swift` - Height reduction
- `SocialFusion/Views/PostDetailView.swift` - Height reduction
- `SocialFusion/Views/Components/StabilizedLinkPreview.swift` - Image height constraints 
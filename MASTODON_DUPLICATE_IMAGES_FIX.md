# Mastodon Duplicate Images Fix

## Issue Identified

You were seeing **duplicate images on Mastodon posts** because the `PostCardView` was displaying images in two separate places:

1. **Content Section** (Line 168-172): `displayPost.contentView()` includes media attachments via `UnifiedMediaGridView`
2. **Media Section** (Line 175-179): A separate `UnifiedMediaGridView(attachments: displayPost.attachments)` was also displaying the same images

This caused every Mastodon post with images to show the images **twice** - once in each section.

## Root Cause

The issue was in `SocialFusion/Views/Components/PostCardView.swift`:

```swift
// Content section - already includes media via contentView()
displayPost.contentView(
    lineLimit: nil,
    showLinkPreview: true,
    font: .body,
    onQuotePostTap: { quotedPost in
        onParentPostTap(quotedPost)
    },
    allowTruncation: false
)

// PROBLEMATIC: Separate media section showing same images again
if !displayPost.attachments.isEmpty {
    UnifiedMediaGridView(attachments: displayPost.attachments)  // DUPLICATE!
        .padding(.horizontal, 4)
        .padding(.top, 6)
}
```

The `contentView()` method (defined in `Post+ContentView.swift`) already handles displaying media attachments:

```swift
// Media attachments (highest priority)
if !attachments.isEmpty {
    UnifiedMediaGridView(
        attachments: attachments,
        maxHeight: 400
    )
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .padding(.top, 4)
}
```

So the separate media section in `PostCardView` was redundant and causing duplication.

## Fix Applied

**File**: `SocialFusion/Views/Components/PostCardView.swift`

Removed the duplicate media section:

```swift
// Media section - REMOVED: This was causing duplicate images
// The contentView() above already handles displaying media attachments
// if !displayPost.attachments.isEmpty {
//     UnifiedMediaGridView(attachments: displayPost.attachments)
//         .padding(.horizontal, 4)
//         .padding(.top, 6)
// }
```

## Why This Works

- **Single Source of Truth**: Media attachments are now only displayed once via `contentView()`
- **Consistent Layout**: All post content (text, media, quotes, links) is handled consistently through the `contentView()` method
- **No Breaking Changes**: The fix only removes redundant code, doesn't change the API or data flow
- **All Platforms**: This fix applies to both Mastodon and Bluesky posts

## Expected Result

✅ **Mastodon posts with images will now show images only once**
✅ **No duplicate media attachments**
✅ **Consistent behavior across all post types**
✅ **Proper spacing and layout maintained**

## Testing

To verify the fix:
1. Look at Mastodon posts with images in your timeline
2. Confirm images appear only once per post
3. Check that boosted posts with images also show images only once
4. Verify that Bluesky posts are unaffected

## Related Files

- `SocialFusion/Views/Components/PostCardView.swift` - Main fix location
- `SocialFusion/Models/Post+ContentView.swift` - Where media is properly handled
- `SocialFusion/Views/Components/UnifiedMediaGridView.swift` - The media display component

This fix resolves the duplicate images issue you were experiencing on Mastodon without affecting any other functionality. 
# Share as Image Feature

## Overview

The Share as Image feature allows users to export posts and comment threads as beautifully composed PNG images, similar to Apollo's Reddit share-image functionality. This feature enables users to share social media content as images that can be saved to Photos, shared via Messages, or posted to other platforms.

## Feature Highlights

- **Full-width single images**: Images attached to posts display at full width with proper aspect ratio (matching feed behavior)
- **Thread context**: Includes parent comments and reply threads with configurable depth
- **Media support**: Handles images, videos, GIFs, link previews, and quote posts
- **Customization**: Configurable options for parent comments, replies, username anonymization, and watermarking
- **High-quality rendering**: Supports both preview (640px) and export (1080px) resolutions
- **Cross-platform**: Works with both Mastodon and Bluesky posts

## Architecture

### Core Components

#### 1. **ShareRenderModels.swift**
Defines the data models used for rendering:
- `PostRenderable`: Post representation with all metadata needed for rendering
- `CommentRenderable`: Comment/reply representation with depth and selection state
- `ShareImageDocument`: Complete document containing post, ancestors, and replies
- `MediaThumbnail`: Media attachment representation
- `LinkPreviewData`: Link preview card data
- `QuotePostData`: Quote post representation

#### 2. **ThreadSlicer.swift**
Handles thread graph construction and pruning:
- Builds thread graphs from flat post lists
- Constructs ancestor chains (parent comments up to root)
- Prunes reply subtrees with configurable limits:
  - Max total replies
  - Max reply depth
  - Max replies per node (fan-out)
- Supports sorting (Top by score, Newest, Oldest)

#### 3. **ShareThreadRenderBuilder.swift**
Builds complete share image documents:
- Converts `Post` models to `PostRenderable` and `CommentRenderable`
- Handles thread context fetching and processing
- Applies configuration options (parent comments, replies, anonymization)
- Manages user mapping for anonymization

#### 4. **DomainAdapters/UnifiedAdapter.swift**
Converts domain models to renderable models:
- Converts `Post` to `PostRenderable`
- Handles boost banners, quote posts, link previews, media thumbnails
- Applies anonymization when `hideUsernames` is enabled
- Supports both Mastodon and Bluesky platforms

#### 5. **ShareImageViews.swift**
SwiftUI views for rendering share images:
- `ShareImageRootView`: Main container with fixed design width (390pt)
- `SharePostContentView`: Post header with author, content, media, links
- `ShareRepliesSectionView`: Thread of comments
- `ShareCommentView`: Individual comment with thread bar indentation
- `ShareMediaStripView`: Media thumbnail grid (single images full-width)
- `ShareSingleImageView`: Full-width single image view with proper aspect ratio
- `ShareLinkPreviewView`: Link preview card
- `ShareQuotePostView`: Quote post card
- `ShareWatermarkView`: "via SocialFusion" watermark

#### 6. **ShareImageRenderer.swift**
Handles image rendering and export:
- Uses SwiftUI `ImageRenderer` to convert views to `UIImage`
- Supports preview (640px) and export (1080px) resolutions
- Applies height guardrails to prevent excessive image sizes
- Saves PNG files to temporary directory for sharing
- Handles rendering errors gracefully

#### 7. **ShareAsImageViewModel.swift**
Manages feature state and configuration:
- Configuration state (toggles, steppers for parent comments, replies)
- Debounces preview updates for smooth UI
- Handles export to PNG and share sheet presentation
- Manages user mapping for anonymization

#### 8. **ShareAsImageSheet.swift**
Configuration sheet with live preview:
- Live preview of share image
- Controls for all share options:
  - Parent Comments (0-12)
  - Include Post Details toggle
  - Hide Usernames toggle
  - Show Watermark toggle
  - Include Replies toggle
  - Replies count (0-30)
  - Reply Depth (1-5)
  - Max per Node (1-6)
  - Sort order (Top/Newest/Oldest)
- Primary "Share" button that exports and presents iOS share sheet

#### 9. **ShareImagePreloader.swift**
Preloads images before rendering:
- Ensures all images are cached before rendering
- Prevents placeholder images in final export
- Uses `ImageCache` for efficient image loading

#### 10. **ShareSynchronousImageView.swift**
Synchronous image view for rendering:
- Uses cached images (never fails)
- Provides placeholder fallback
- Used for avatars and media thumbnails

#### 11. **ShareAsImageCoordinator.swift**
Coordinates share-as-image functionality:
- Builds share image documents from posts
- Handles thread context fetching
- Provides unified API for share image generation

## Integration Points

### PostAction Integration

The feature is integrated via the `PostAction.shareAsImage` enum case, which is handled in:

1. **PostCardView.swift** (ActionBar)
   - Accessible via the action bar share menu
   - Handles share-as-image for posts in the timeline

2. **PostDetailView.swift** (Toolbar Menu)
   - Accessible via the post detail toolbar menu
   - Handles share-as-image for posts and replies
   - Fetches thread context for replies

3. **PostMenu.swift** (Context Menu)
   - Accessible via long-press context menus
   - Provides share-as-image option in post menus

### Usage Pattern

```swift
case .shareAsImage:
    Task {
        await handleShareAsImage(for: post)
    }

private func handleShareAsImage(for post: Post) async {
    do {
        // Fetch thread context if available
        let threadContext = try? await serviceManager.fetchThreadContext(for: post)
        
        // Determine if this is a reply
        let isReply = post.inReplyToID != nil
        
        await MainActor.run {
            // Create view model with post and context
            shareAsImageViewModel = ShareAsImageViewModel(
                post: post,
                threadContext: threadContext,
                isReply: isReply
            )
            showShareAsImageSheet = true
        }
    } catch {
        NSLog("Failed to build share image view model: %@", error.localizedDescription)
    }
}
```

## Configuration Options

### Parent Comments (0-12)
Number of ancestor comments to include above the selected post/reply. Useful for providing context in threaded discussions.

### Include Post Details
Toggle to show/hide the post header with author, content, media, and links. When disabled, only comments are shown.

### Hide Usernames
Anonymizes users as "User 1", "User 2", etc. Useful for sharing content while protecting privacy. Maintains consistent mapping throughout the image.

### Show Watermark
Displays "via SocialFusion" pill at the bottom of the image.

### Include Replies
Toggle to include reply subtree under the selected comment/post.

### Replies (0-30)
Maximum total number of replies to include in the subtree. Counts all nodes in the reply tree.

### Reply Depth (1-5)
Maximum depth below the selected comment. Limits how deep the thread tree goes.

### Max per Node (1-6)
Maximum children per comment node. Controls fan-out at each level of the thread.

### Sort Order
- **Top**: Sorted by score (likes + reposts) with timestamp tiebreaker
- **Newest**: Most recent replies first
- **Oldest**: Oldest replies first

## Thread Slicing Logic

### Sharing a Comment
1. Build ancestor chain from selected comment up to root (limited by Parent Comments setting)
2. Build reply subtree under selected comment:
   - Traverse children in preorder
   - Respect maxRepliesTotal (counts all nodes in subtree)
   - Respect maxReplyDepth (depth below selected)
   - Respect maxRepliesPerNode (fan-out per node)
   - Apply sorting (Top uses score + timestamp)

### Sharing a Post (No Comment Selected)
- Include post details (if enabled)
- Optionally include top-level replies (if Include Replies is enabled)

## Rendering Details

### Design Specifications
- **Fixed design width**: 390 points
- **Scales to target pixel width**: 640px (preview), 1080px (export)
- **Rounded corners**: 12pt radius
- **Subtle shadow**: Black at 10% opacity, 8pt radius, 2pt offset
- **Thread bars**: Depth-based colored indent bars (blue, green, orange, purple, pink)
- **Selected comment**: Highlighted with subtle background wash
- **Media thumbnails**: Grid layout for multiple images, full-width for single images
- **Link previews**: Light background with rounded corners
- **Quote posts**: Light background with rounded corners

### Single Image Display
When a post has a single image attached:
- Image displays at **full width** (matching feed behavior)
- Aspect ratio is calculated from cached image dimensions
- Falls back to 16:9 if aspect ratio not available
- Uses `.fit` content mode to show full image without cropping
- Maximum height capped at 600pt (scaled) to prevent excessive sizes

### Multiple Image Display
When a post has multiple images:
- Images display in a grid layout (up to 3 columns)
- Square aspect ratio with `.fill` content mode
- Consistent spacing and corner radius

## Image Preloading

The feature uses `ShareImagePreloader` to ensure all images are cached before rendering:
- Prevents placeholder images in final export
- Uses `ImageCache` for efficient image loading
- Shows loading progress during preload phase

## File Naming

Exported images use descriptive filenames:
- Format: `SocialFusion – [Context] – [Author] – [Date].png`
- Context: Post, Thread, or Reply
- Author: Username (if not anonymized)
- Date: Medium date format

Example: `SocialFusion – Reply – @username – Jan 15, 2024.png`

## Error Handling

The feature includes comprehensive error handling:
- Graceful fallbacks for missing images
- Error messages displayed to users
- Logging for debugging
- Prevents crashes from missing data

## Testing

Unit tests are provided in `SocialFusionTests/ShareAsImage/`:
- `ShareAsImageTestHelpers.swift`: Test helpers for creating test data
- `ShareAvatarPlaceholderTests.swift`: Avatar handling tests
- `ShareDocumentBuilderTests.swift`: Document building tests

## Future Enhancements

Potential improvements:
- Pagination for very long threads (multiple images)
- Custom styling options (colors, fonts)
- Template selection
- Background color options
- Font size options
- Better media handling (actual image loading vs placeholders)
- Support for video thumbnails
- Animated GIF support in exports

## Recent Improvements

### Single Image Full-Width Display (Latest)
- Single images now display at full width with proper aspect ratio
- Matches feed behavior for consistency
- Calculates aspect ratio from cached image dimensions
- Falls back to 16:9 if aspect ratio not available
- Prevents image cropping in share images

## Technical Notes

- Uses SwiftUI `ImageRenderer` for view-to-image conversion
- Leverages `ImageCache` for efficient image loading
- Thread-safe document building
- MainActor isolation for UI updates
- Debounced preview updates for performance
- Height guardrails prevent excessive image sizes
- Temporary file management for share sheet

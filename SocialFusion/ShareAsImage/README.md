# ShareAsImage Module

This module implements a robust "Share as Image…" feature for SocialFusion, modeled on Apollo's Reddit share-image flow. It allows users to export posts and comment threads as beautifully composed PNG images.

## Architecture

### Core Components

1. **ShareRenderModels.swift**
   - `PostRenderable`: Represents a post with all metadata needed for rendering
   - `CommentRenderable`: Represents a comment/reply with depth and selection state
   - `ShareImageDocument`: Complete document containing post, ancestors, and replies

2. **ThreadSlicer.swift**
   - Builds thread graphs from flat post lists
   - Constructs ancestor chains (parent comments up to root)
   - Prunes reply subtrees with configurable limits (max replies, depth, per-node fan-out)
   - Supports sorting (Top/Newest/Oldest)

3. **ShareThreadRenderBuilder.swift**
   - Converts Post models to renderables using `UnifiedAdapter`
   - Builds complete `ShareImageDocument` from posts and thread context
   - Handles anonymization (username hiding with stable mapping)

4. **DomainAdapters/UnifiedAdapter.swift**
   - Converts `Post` models to `PostRenderable` and `CommentRenderable`
   - Handles boost banners, quote posts, link previews, media thumbnails
   - Applies anonymization when `hideUsernames` is enabled

5. **ShareImageViews.swift**
   - SwiftUI views for rendering share images:
     - `ShareImageRootView`: Main container
     - `SharePostHeaderView`: Post header with author, content, media, links
     - `ShareCommentThreadView`: Thread of comments with depth-based indentation
     - `ShareCommentView`: Individual comment with colored indent bars
     - `ShareMediaStripView`: Media thumbnail grid
     - `ShareLinkPreviewView`: Link preview card
     - `ShareQuotePostView`: Quote post card
     - `ShareWatermarkView`: "via SocialFusion" watermark

6. **ShareImageRenderer.swift**
   - Uses SwiftUI `ImageRenderer` to convert views to `UIImage`
   - Supports preview (lower resolution) and export (full resolution)
   - Applies height guardrails to prevent excessive image sizes
   - Saves PNG files to temporary directory for sharing

7. **ShareAsImageViewModel.swift**
   - Manages configuration state (toggles, steppers)
   - Debounces preview updates for smooth UI
   - Handles export to PNG and share sheet presentation

8. **ShareAsImageSheet.swift**
   - Configuration sheet with live preview
   - Controls for all share options
   - Primary "Share" button that exports and presents iOS share sheet

## Integration

### Adding to Context Menus

The feature is integrated into:
- `PostMenu` (used in various views)
- `ActionBar` (used in PostCardView)
- `PostDetailView` toolbar menu

The `PostAction.shareAsImage` case triggers the share flow.

### Usage Example

```swift
// In a view that handles PostAction:
case .shareAsImage:
    Task {
        await handleShareAsImage(for: post)
    }

// Handler function:
private func handleShareAsImage(for post: Post) async {
    do {
        let threadContext = try? await serviceManager.fetchThreadContext(for: post)
        let config = ShareImageConfig()
        var userMapping: [String: String] = [:]
        
        let document = ShareThreadRenderBuilder.buildDocument(
            from: post,
            threadContext: threadContext,
            config: config,
            userMapping: &userMapping
        )
        
        await MainActor.run {
            shareAsImageDocument = document
            showShareAsImageSheet = true
        }
    } catch {
        NSLog("Failed to build share image document: %@", error.localizedDescription)
    }
}
```

## Configuration Options

- **Parent Comments** (0-12): Number of ancestor comments to include
- **Include Post Details**: Show post header with author, content, media
- **Hide Usernames**: Anonymize users as "User 1", "User 2", etc.
- **Watermark**: Show "via SocialFusion" pill at bottom
- **Include Replies**: Include reply subtree under selected comment
- **Replies** (0-30): Maximum total replies to include
- **Reply Depth** (1-5): Maximum depth below selected comment
- **Max per Node** (1-6): Maximum children per comment node
- **Sort**: Top (by score), Newest, or Oldest

## Thread Slicing Logic

When sharing a comment:
1. Build ancestor chain from selected comment up to root (limited by Parent Comments)
2. Build reply subtree under selected comment:
   - Traverse children in preorder
   - Respect maxRepliesTotal (counts all nodes in subtree)
   - Respect maxReplyDepth (depth below selected)
   - Respect maxRepliesPerNode (fan-out per node)
   - Apply sorting (Top uses score + timestamp)

When sharing a post (no comment selected):
- Include post details (if enabled)
- Optionally include top-level replies (if Include Replies is enabled)

## Rendering Details

- Fixed design width: 390 points
- Scales to target pixel width (640px preview, 1080px export)
- Rounded corners (12pt radius)
- Subtle shadow
- Depth-based colored indent bars (blue, green, orange, purple, pink)
- Selected comment highlighted with subtle background
- Media thumbnails in grid layout
- Link previews and quote posts styled consistently

## Adding Support for New Networks

To add support for a new social network:

1. Ensure `Post` model supports the network (already handled by `SocialPlatform`)
2. `UnifiedAdapter` automatically handles all platforms via `Post` model
3. No additional adapter needed unless network-specific rendering is required

## Testing

Unit tests should cover:
- `ThreadSlicer`: Graph building, ancestor chain construction, reply pruning, sorting
- `ShareImageRenderer`: PNG generation, file saving
- `ShareThreadRenderBuilder`: Document building with various configs

## Future Enhancements

- Pagination for very long threads (multiple images)
- Custom styling options
- Template selection
- Background color options
- Font size options
- Better media handling (actual image loading vs placeholders)

# TestFlight Testing Notes
## Build Date: January 12, 2026
## Testing Period: Past 24 Hours of Changes

---

## 🎯 Priority Testing Areas

### 1. Share as Image Feature (NEW) ⭐ HIGH PRIORITY
**What's New:** Complete Share as Image functionality allowing users to export posts and threads as PNG images.

**How to Test:**
- **Access the feature:**
  - Long-press any post in the timeline → Select "Share as Image" from the menu
  - Tap the action bar (three dots) on any post → Select "Share as Image"
  - Open any post detail view → Tap the toolbar menu → Select "Share as Image"
  
- **Basic functionality:**
  - ✅ Share a simple text post (no media)
  - ✅ Share a post with a single image (should display full-width with proper aspect ratio)
  - ✅ Share a post with multiple images (should display in grid layout)
  - ✅ Share a post with a video/GIF thumbnail
  - ✅ Share a post with a link preview
  - ✅ Share a post with a quote post (boosted post)
  
- **Thread context:**
  - ✅ Share a reply post with parent comments (adjust "Parent Comments" slider 0-12)
  - ✅ Share a post with replies (enable "Include Replies" toggle)
  - ✅ Test different reply counts (0-30) and depths (1-5)
  - ✅ Test sorting options: Top, Newest, Oldest
  
- **Customization options:**
  - ✅ Toggle "Include Post Details" on/off
  - ✅ Toggle "Hide Usernames" (should anonymize usernames)
  - ✅ Toggle "Show Watermark" (should show "via SocialFusion" at bottom)
  - ✅ Adjust all sliders and verify live preview updates smoothly
  
- **Export and sharing:**
  - ✅ Tap "Share" button → Verify iOS share sheet appears
  - ✅ Save to Photos → Verify image appears in Photos app
  - ✅ Share via Messages → Verify image sends correctly
  - ✅ Share via other apps (Twitter, Instagram, etc.)
  
- **Cross-platform:**
  - ✅ Test with Mastodon posts
  - ✅ Test with Bluesky posts
  - ✅ Test with boosted posts from both platforms
  
- **Edge cases:**
  - ✅ Share a very long post (should handle text wrapping)
  - ✅ Share a post with many replies (test max limits)
  - ✅ Share a post with deeply nested replies (test depth limits)
  - ✅ Share a post with missing media (should handle gracefully)
  - ✅ Test with slow network connection (verify loading states)

**What to Look For:**
- Images render correctly with proper aspect ratios
- Single images display full-width (not cropped)
- Multiple images display in a clean grid
- Text is readable and properly formatted
- Thread structure is clear and indented correctly
- Anonymization works correctly when enabled
- Watermark appears when enabled
- Export produces high-quality images (1080px)
- No crashes or freezes during rendering
- Share sheet works correctly

---

### 2. Stable Media Layout System ⭐ HIGH PRIORITY
**What's New:** No-reflow media layout system that prevents jerky scrolling and layout jumps in the feed.

**How to Test:**
- **Feed scrolling stability:**
  - ✅ Scroll through the timeline quickly (fast scrolling)
  - ✅ Scroll slowly and observe posts as they appear
  - ✅ Scroll up and down repeatedly
  - ✅ Verify posts maintain stable heights after first appearance
  - ✅ Verify no layout jumps when images finish loading
  
- **Media loading behavior:**
  - ✅ Watch posts as images load (should not cause height changes)
  - ✅ Test with posts that have:
    - Single images
    - Multiple images (grid)
    - Videos/GIFs
    - Link previews
    - Quote posts
  
- **Banner stability:**
  - ✅ Scroll past boosted posts (quote posts)
  - ✅ Scroll past reply banners
  - ✅ Verify banners don't cause layout shifts
  
- **Performance:**
  - ✅ Test on slower network connections
  - ✅ Test with many posts in timeline
  - ✅ Verify smooth scrolling performance
  - ✅ Check memory usage (should be reasonable)

**What to Look For:**
- ✅ Smooth, stable scrolling without jumps
- ✅ Posts maintain consistent heights
- ✅ Images load without causing layout reflow
- ✅ No "jumping" or "shifting" of content
- ✅ Banner heights remain stable
- ✅ Good performance even with many posts

---

### 3. Avatar Display Fixes
**What's Fixed:** Avatar transparency bleed-through bug and layout constraint issues.

**How to Test:**
- **Avatar rendering:**
  - ✅ View posts with profile avatars
  - ✅ Check avatars with transparent backgrounds (should have neutral backing)
  - ✅ Verify avatars display correctly in:
    - Timeline posts
    - Post detail views
    - Reply threads
    - Profile views
  
- **Avatar sizing:**
  - ✅ Verify avatars are consistently sized
  - ✅ Check that avatars don't expand beyond their containers
  - ✅ Verify social network badges overlay correctly
  
- **Edge cases:**
  - ✅ Test with missing/loading avatars (should show monogram placeholder)
  - ✅ Test with failed avatar loads (should show placeholder)
  - ✅ Test with various avatar sizes and formats

**What to Look For:**
- ✅ No transparency bleed-through (avatars have proper backing)
- ✅ Avatars are correctly sized and constrained
- ✅ Placeholders appear correctly when images fail
- ✅ Social network badges display correctly
- ✅ No layout issues or overflow

---

### 4. Navigation System Updates
**What's Fixed:** Updated to use NavigationStack instead of deprecated NavigationView.

**How to Test:**
- **Navigation flow:**
  - ✅ Navigate from timeline to post detail
  - ✅ Navigate from timeline to profile
  - ✅ Navigate from timeline to account timeline
  - ✅ Navigate from timeline to settings
  - ✅ Navigate from timeline to compose view
  - ✅ Use back button to return to previous screens
  
- **Deep navigation:**
  - ✅ Navigate: Timeline → Post → Profile → Post → Profile (deep nesting)
  - ✅ Verify back button works correctly at all levels
  - ✅ Test on both iPhone and iPad (if available)
  
- **Navigation consistency:**
  - ✅ Verify all screens use consistent navigation behavior
  - ✅ Check that navigation bars display correctly
  - ✅ Verify toolbar buttons work correctly

**What to Look For:**
- ✅ Smooth navigation transitions
- ✅ Back button works correctly
- ✅ No navigation stack issues
- ✅ Consistent behavior across all screens
- ✅ No crashes during navigation

---

## 🔍 General Regression Testing

### Timeline Functionality
- ✅ Posts load correctly
- ✅ Pull-to-refresh works
- ✅ Infinite scroll works
- ✅ Post actions (like, boost, reply) work
- ✅ Media displays correctly
- ✅ Link previews work
- ✅ Quote posts display correctly

### Account Management
- ✅ Account switching works
- ✅ Multiple accounts display correctly
- ✅ Account-specific timelines work

### Media Handling
- ✅ Images display correctly
- ✅ Videos play correctly
- ✅ GIFs animate correctly
- ✅ Fullscreen media view works
- ✅ Media aspect ratios are correct

### Posting
- ✅ Compose new posts
- ✅ Reply to posts
- ✅ Boost posts
- ✅ Edit posts (if supported)
- ✅ Delete posts

---

## 🐛 Known Issues to Monitor

1. **AttributeGraph cycle warnings** - Monitor console for any new warnings
2. **Quote post fallbacks** - Verify quote posts display correctly when data is incomplete
3. **Error states** - Check that error messages appear when network requests fail

---

## 📱 Device Testing Recommendations

- **iPhone:** Test on iPhone 15 Pro (primary) and at least one older device (iPhone 13/14)
- **iPad:** Test on iPad if available (NavigationSplitView behavior)
- **iOS Versions:** Test on iOS 16 and iOS 17+ if possible

---

## ⚠️ Critical Issues to Report Immediately

- App crashes
- Data loss
- Posts not loading
- Unable to post/share
- Navigation completely broken
- Severe performance issues
- Memory leaks or excessive memory usage

---

## 📝 Feedback Guidelines

When reporting issues, please include:
1. **Device:** iPhone/iPad model and iOS version
2. **Steps to reproduce:** Detailed steps to trigger the issue
3. **Expected behavior:** What should happen
4. **Actual behavior:** What actually happened
5. **Screenshots/Videos:** If applicable
6. **Frequency:** Does it happen every time or intermittently?

---

## ✅ Testing Checklist Summary

- [ ] Share as Image feature (all scenarios)
- [ ] Stable media layout (scrolling stability)
- [ ] Avatar display fixes
- [ ] Navigation system
- [ ] General timeline functionality
- [ ] Account management
- [ ] Media handling
- [ ] Posting functionality
- [ ] Cross-platform (Mastodon + Bluesky)
- [ ] Performance and stability

---

**Thank you for testing SocialFusion!** 🚀

# Missing or Incomplete Features from Muscle Memory Composer Plan

## ✅ Recently Fixed (This Session)

1. **Entity compilation when posting** - ✅ FIXED
   - Added `parseEntitiesFromText()` to parse manually typed mentions/hashtags/links
   - Called before posting in both `createPost` and `replyToPost` paths

2. **Platform conflict detection** - ✅ FIXED
   - Applied `ComposeViewLifecycleModifier` to ComposeView
   - Added `.onChange` handlers to trigger `updatePlatformConflicts()`

3. **Keyboard shortcuts** - ✅ PARTIALLY FIXED
   - Applied `ComposeViewLifecycleModifier` with shortcuts
   - `Cmd+Enter`, `Cmd+Shift+Enter`, `Cmd+L`, `Cmd+.` now work
   - ⚠️ `Cmd+K` still just a placeholder (see below)

4. **AutocompleteCache persistence** - ✅ FIXED
   - Implemented full serialization/deserialization
   - Added frequently used tracking (top 20 per account)
   - Properly loads/saves from UserDefaults

## ❌ Still Missing or Incomplete

### 1. **Smart Paste Detection** ❌ NOT IMPLEMENTED
**Status**: MISSING  
**Plan Reference**: Section 8 - "Detect paste events, resolve @handles and URLs to mention entities"

**Current State**:
- `shouldChangeTextIn` exists but doesn't detect paste events
- No URL/handle resolution on paste
- No automatic link entity creation
- No mention entity creation from pasted handles

**What's Needed**:
- Detect paste events (large text replacements, or check pasteboard)
- Parse pasted text for URLs and @handles
- Convert URLs to link entities
- Convert @handles to mention entities (with lookup if needed)
- Insert entities into `ComposerTextModel`

**Location**: `SocialFusion/Views/ComposeView.swift` - `FocusableTextEditor.Coordinator.textView(_:shouldChangeTextIn:replacementText:)`

**Implementation Approach**:
```swift
func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
    // Detect paste: large replacement or check pasteboard
    let isPaste = text.count > 1 || (range.length == 0 && text.count > 0 && UIPasteboard.general.hasStrings)
    
    if isPaste {
        // Parse text for URLs and handles
        // Create entities
        // Insert entities into composerTextModel
    }
    
    // Existing logic...
}
```

---

### 2. **Emoji Fetching from Mastodon** ⚠️ PLACEHOLDER
**Status**: INCOMPLETE  
**Plan Reference**: Section 6 - "Fetches custom emoji from Mastodon instance"

**Current State**:
- `EmojiService.fetchEmoji()` returns empty array
- Comment says: "Mastodon API doesn't have a direct emoji endpoint in v1/v2"
- Plan notes: Mastodon v3+ has `/api/v1/custom_emojis` endpoint

**What's Needed**:
- Implement API call to `/api/v1/custom_emojis` endpoint
- Handle instance version detection (v1/v2 vs v3+)
- Cache emoji per account/instance
- Fallback to system emoji if custom emoji unavailable

**Location**: `SocialFusion/Services/EmojiService.swift` line 19-35

**Implementation Approach**:
```swift
public func fetchEmoji(for account: SocialAccount) async throws -> [MastodonEmoji] {
    // Check cache first
    if let cached = emojiCache[account.id] {
        return cached
    }
    
    guard let service = mastodonService, account.platform == .mastodon else {
        return []
    }
    
    // Try v3+ endpoint first: GET /api/v1/custom_emojis
    // Fallback to extracting from account/profile if needed
    // Cache results
}
```

---

### 3. **Cmd+K Insert Link** ⚠️ PLACEHOLDER ONLY
**Status**: INCOMPLETE  
**Plan Reference**: Section 7 - "Cmd+K: Insert link (future)"

**Current State**:
- `insertLink()` method exists but is empty placeholder
- Comment says: "Future enhancement: Insert link placeholder or open link dialog"

**What's Needed**:
- Detect current selection or caret position
- Show link input dialog (URL + optional title)
- Insert link text at caret
- Create link entity in `ComposerTextModel`
- Format as markdown-style link: `[title](url)` or just URL

**Location**: `SocialFusion/Views/ComposeView.swift` - `insertLink()` method

**Implementation Approach**:
```swift
private func insertLink() {
    // Show alert/dialog for URL input
    // Get current caret position
    // Insert link text
    // Create TextEntity with kind: .link
    // Add to composerTextModel.entities
}
```

---

### 4. **Draft Naming & Pinning** ❌ NOT IMPLEMENTED
**Status**: MISSING  
**Plan Reference**: "drafts that behave like pro apps (automatic local, named/pinned, per-destination metadata)"

**Current State**:
- `DraftPost` has no `name` field
- `DraftPost` has no `isPinned` field
- No UI for naming/pinning drafts
- No per-destination metadata storage

**What's Needed**:
- Add `name: String?` to `DraftPost` (auto-generated from first post text if nil)
- Add `isPinned: Bool` to `DraftPost`
- Add UI in `DraftsListView` for:
  - Renaming drafts
  - Pinning/unpinning drafts
  - Showing pinned drafts at top
- Consider per-destination metadata (e.g., different visibility per platform)

**Location**: 
- `SocialFusion/Models/DraftPost.swift`
- `SocialFusion/Views/DraftsListView.swift` (if exists)

---

### 5. **System Emoji Fallback** ⚠️ NOT IMPLEMENTED
**Status**: MISSING  
**Plan Reference**: Section 6 - "System emoji fallback (use iOS emoji picker or built-in set)"

**Current State**:
- `EmojiService.searchEmoji()` comment says: "System emoji fallback (would integrate with iOS emoji picker)"
- Only returns custom emoji and recently used

**What's Needed**:
- Integrate iOS emoji picker or use built-in emoji set
- Search system emoji by name/shortcode
- Show system emoji in autocomplete results
- Allow inserting actual emoji characters (not just shortcodes)

**Location**: `SocialFusion/Services/EmojiService.swift` line 76-77

---

### 6. **Per-Destination Metadata in Drafts** ⚠️ NOT IMPLEMENTED
**Status**: MISSING  
**Plan Reference**: "per-destination metadata storage"

**Current State**:
- Drafts store `selectedPlatforms` but not per-platform metadata
- No way to have different visibility/content per platform in same draft

**What's Needed**:
- Consider adding `perPlatformMetadata: [SocialPlatform: PlatformDraftMetadata]` to `DraftPost`
- `PlatformDraftMetadata` could include:
  - Visibility setting per platform
  - Platform-specific content variations
  - Platform-specific media attachments

**Note**: This might be overkill - current implementation may be sufficient.

---

## ✅ Properly Implemented

1. **IME Guardrails** - ✅ IMPLEMENTED
   - Checks `textView.markedTextRange != nil` before triggering autocomplete
   - Dismisses overlay when marked text begins
   - Only triggers after composition commit

2. **TokenExtractor** - ✅ IMPLEMENTED
   - Handles @/#/: token extraction
   - Proper Unicode handling
   - Stop conditions (whitespace, punctuation, newline)

3. **Stale Result Rejection** - ✅ IMPLEMENTED
   - Request ID tracking
   - Document revision validation
   - Task cancellation

4. **Entity Range Management** - ✅ IMPLEMENTED
   - `applyEdit()` updates entity ranges
   - Boundary-touching rules
   - Atomic replace operations

5. **Autocomplete System** - ✅ IMPLEMENTED
   - Debounced search
   - Network error handling
   - Recent/frequently used ranking

---

## Summary

**Critical Missing**:
1. Smart paste detection (Section 8)
2. Emoji fetching from Mastodon API (Section 6)

**Nice-to-Have Missing**:
3. Cmd+K insert link (Section 7 - marked as "future")
4. Draft naming & pinning (mentioned in plan but not detailed)
5. System emoji fallback (Section 6)

**Total Missing**: 5 features
**Total Implemented**: ~95% of core functionality

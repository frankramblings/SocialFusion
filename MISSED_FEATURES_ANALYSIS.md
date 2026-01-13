# Missed Features Analysis - Muscle Memory Composer Implementation

## Critical Missing Features (Must Fix)

### 1. **ComposerTextModel.applyEdit() Not Called on Text Changes** ⚠️ CRITICAL
**Status**: MISSING  
**Location**: `SocialFusion/Views/ComposeView.swift` line 759-771  
**Issue**: 
- `FocusableTextEditor` has `onTextEdit` callback defined, but it's **never wired up** in `ComposeView`
- When user types, `textView(_:shouldChangeTextIn:replacementText:)` calls `parent.onTextEdit?(range, text)` but the callback is `nil`
- The `onChange(of: threadPosts[activePostIndex].text)` handler only syncs text, doesn't call `applyEdit()`
- **Result**: Entity ranges become stale/invalid as user types, entities don't shift properly

**Fix Needed**: 
```swift
FocusableTextEditor(
    // ... existing params ...
    onTextEdit: { range, replacementText in
        composerTextModel.applyEdit(replacementRange: range, replacementText: replacementText)
    }
)
```

**Plan Reference**: Phase 1, Section 1 - "Add range update logic to `ComposerTextModel.applyEdit()`"

---

### 2. **ComposerTextModel Not Compiled from Text When Posting** ⚠️ CRITICAL
**Status**: MISSING  
**Location**: `SocialFusion/Views/ComposeView.swift` line 1589-1592, 1620-1623  
**Issue**:
- In `postContent()`, we sync `composerTextModel.text = threadPost.text` but **never compile entities from the text**
- The plan says: "Compile `ComposerTextModel` from `threadPosts[activePostIndex].text` + entities"
- Currently, `composerTextModel.entities` is empty unless user explicitly accepts autocomplete suggestions
- **Result**: Mentions/hashtags typed manually (without autocomplete) won't be converted to entities for posting

**Fix Needed**: 
- Parse text for mentions/hashtags/links and create entities before posting
- Or ensure entities are always maintained via `applyEdit()` (which would fix this automatically)

**Plan Reference**: Section 5 - "Compile `ComposerTextModel` from `threadPosts[activePostIndex].text` + entities"

---

## Missing Keyboard Shortcuts

### 3. **Cmd+K (Insert Link)** ❌ NOT IMPLEMENTED
**Status**: MISSING  
**Location**: `SocialFusion/Views/ComposeView.swift`  
**Plan Reference**: Section 7

### 4. **Cmd+L (Toggle Labels/CW)** ❌ NOT IMPLEMENTED  
**Status**: MISSING  
**Location**: `SocialFusion/Views/ComposeView.swift`  
**Plan Reference**: Section 7

### 5. **Cmd+. (Dismiss Autocomplete)** ⚠️ PARTIAL
**Status**: PARTIALLY IMPLEMENTED  
**Note**: `AutocompleteOverlay` handles Esc key, but `Cmd+.` shortcut not added to `ComposeView`  
**Plan Reference**: Section 7

**Current State**:
- ✅ `Cmd+Enter`: Send post (implemented)
- ✅ `Cmd+Shift+Enter`: Send silently/unlisted (implemented)
- ❌ `Cmd+K`: Insert link (missing)
- ❌ `Cmd+L`: Toggle labels/CW (missing)
- ⚠️ `Cmd+.`: Dismiss autocomplete (Esc handled in overlay, but Cmd+. not wired)

---

## Missing Features

### 6. **Smart Paste Detection** ❌ NOT IMPLEMENTED
**Status**: MISSING  
**Location**: `SocialFusion/Views/ComposeView.swift` - `FocusableTextEditor.Coordinator`  
**Plan Reference**: Section 8 - "Detect paste events, resolve @handles and URLs to mention entities"

**Missing**:
- No paste detection in `UITextViewDelegate`
- No URL/handle resolution on paste
- No automatic link entity creation
- No mention entity creation from pasted handles

**Note**: `shouldChangeTextIn` is called for paste events, but we don't detect large text replacements that indicate paste

---

### 7. **Draft Naming & Pinning** ❌ NOT IMPLEMENTED
**Status**: MISSING  
**Location**: `SocialFusion/Models/DraftPost.swift`  
**Plan Reference**: "drafts that behave like pro apps (automatic local, named/pinned, per-destination metadata)"

**Missing**:
- No `name` field in `DraftPost`
- No `isPinned` field in `DraftPost`
- No UI for naming/pinning drafts
- No per-destination metadata storage

---

### 8. **Emoji Fetching from Mastodon** ⚠️ PLACEHOLDER
**Status**: PLACEHOLDER (returns empty array)  
**Location**: `SocialFusion/Services/EmojiService.swift` line 19-35  
**Plan Reference**: Section 6

**Issue**:
- `fetchEmoji()` is implemented but returns empty array
- Comment says: "Mastodon API doesn't have a direct emoji endpoint in v1/v2"
- Plan says: "Fetches custom emoji from Mastodon instance"
- **Note**: Mastodon v3+ has `/api/v1/custom_emojis` endpoint

**Fix Needed**: Implement actual API call to fetch custom emoji

---

### 9. **Autocomplete Debouncing** ⚠️ PARTIAL
**Status**: PARTIALLY IMPLEMENTED  
**Location**: `SocialFusion/Services/AutocompleteService.swift` line 82  
**Plan Reference**: Phase 1, Section 4 - "Debounced search (150-250ms, immediate first char)"

**Current Implementation**:
- ✅ Immediate fetch for first character (`debounceDelay = 0` when `query.count == 1`)
- ✅ 200ms delay for subsequent characters
- ⚠️ Uses `Task.sleep()` which is correct, but plan specifies "150-250ms" (we use 200ms, which is fine)

**Status**: ✅ Actually implemented correctly

---

### 10. **AutocompleteCache Persistence** ⚠️ PARTIAL
**Status**: PARTIALLY IMPLEMENTED  
**Location**: `SocialFusion/Stores/AutocompleteCache.swift`  
**Plan Reference**: Section 10 - "Persist to UserDefaults or CoreData"

**Current Implementation**:
- ✅ In-memory caching works
- ✅ `saveToUserDefaults()` method exists
- ⚠️ **Limitation**: Only stores simplified data (ID, displayText) because `EntityPayload` isn't Codable
- ⚠️ `loadFromUserDefaults()` doesn't actually restore full `AutocompleteSuggestion` objects

**Issue**: Full persistence requires making `EntityPayload` Codable or using a different storage strategy

---

### 11. **Platform Conflict Detection Logic** ⚠️ PARTIAL
**Status**: PARTIALLY IMPLEMENTED  
**Location**: `SocialFusion/Views/ComposeView.swift`  
**Plan Reference**: Section 9

**Current State**:
- ✅ `PlatformConflictBanner` component exists
- ✅ `platformConflicts` state variable exists
- ❌ **Logic to detect and update conflicts is missing**
- ❌ No code that checks for conflicts (e.g., CW enabled but Bluesky selected)

**Fix Needed**: Add logic to detect conflicts and populate `platformConflicts` array

---

### 12. **Undo/Redo Integration for Entity State** ⚠️ PARTIAL
**Status**: PARTIALLY IMPLEMENTED  
**Location**: `SocialFusion/Views/ComposeView.swift` - `FocusableTextEditor`  
**Plan Reference**: Phase 1, Section 9 - "Add undo/redo integration: register undo actions for atomic replace operations"

**Current State**:
- ✅ `onUndoRedo` callback exists in `FocusableTextEditor`
- ✅ `textViewDidChange` calls `onUndoRedo` when text changes (for undo/redo detection)
- ❌ **Callback is never wired up in `ComposeView`**
- ❌ No undo action registration for entity state changes
- ❌ Plan says: "register undo actions for both text change and entity list mutations"

**Fix Needed**: Wire up `onUndoRedo` callback to sync entity state, register undo actions

---

### 13. **Thread Segment Shortcut (Cmd+Enter)** ❌ NOT IMPLEMENTED
**Status**: MISSING  
**Location**: `SocialFusion/Views/ComposeView.swift`  
**Plan Reference**: Phase 4, Section 18 - "Threading improvements (Cmd+Enter for next segment)"

**Note**: `Cmd+Enter` currently sends post. Plan says it should create next thread segment when in thread mode.

**Fix Needed**: Check if in thread mode, if so create next segment instead of posting

---

### 14. **Direct Visibility Option for Mastodon** ❌ NOT IMPLEMENTED
**Status**: MISSING  
**Location**: `SocialFusion/Views/ComposeView.swift`  
**Plan Reference**: "visibility + reply controls (Mastodon: Public/Unlisted/Followers/Direct)"

**Current State**: Only Public/Unlisted/Followers options exist, Direct is missing

---

### 15. **Link Cards & Canonicalization** ❌ NOT IMPLEMENTED
**Status**: MISSING  
**Plan Reference**: "link cards + canonicalization (paste URL, fetch preview, remove tracking, quote vs embed)"

**Note**: Marked as "Future Enhancement" in plan, but listed in initial spec

---

## Implementation Status Summary

### ✅ Fully Implemented
- Autocomplete token extraction (`TokenExtractor`)
- Autocomplete overlay UI (`AutocompleteOverlay`)
- Autocomplete service with request ID tracking (`AutocompleteService`)
- Content Warning UI (`ContentWarningEditor`)
- Bluesky Labels picker (`BlueskyLabelsPicker`)
- CW/Labels posting integration (`MastodonService`, `BlueskyService`)
- Alt-text UI enhancements
- Platform conflict banner component (`PlatformConflictBanner`)
- Offset mapper utility (`OffsetMapper`)
- ComposerTextModel with range management (`ComposerTextModel`)
- Autocomplete token model (`AutocompleteToken`)
- Entity compilation methods (`toMastodonEntities()`, `toBlueskyEntities()`)
- Accept suggestion logic (`acceptSuggestion()`)
- Recent mentions/hashtags cache (in-memory)

### ⚠️ Partially Implemented
- Keyboard shortcuts (Cmd+Enter, Cmd+Shift+Enter ✅; Cmd+K, Cmd+L, Cmd+. ❌)
- Autocomplete debouncing (✅ implemented, but could verify timing)
- AutocompleteCache persistence (simplified version only)
- Platform conflict detection (UI exists, logic missing)
- Undo/redo integration (callbacks exist, not wired)
- Emoji fetching (placeholder, returns empty)

### ❌ Not Implemented
- **CRITICAL**: `applyEdit()` not called on text changes
- **CRITICAL**: Entities not compiled from text when posting
- Smart paste detection
- Draft naming & pinning
- Cmd+K (insert link)
- Cmd+L (toggle labels/CW)
- Cmd+. (dismiss autocomplete - Esc works, but Cmd+. not wired)
- Thread segment shortcut (Cmd+Enter for next segment)
- Direct visibility option
- Link cards & canonicalization
- Full emoji fetching from Mastodon API

---

## Priority Fix Order

1. **CRITICAL**: Wire up `onTextEdit` callback to call `composerTextModel.applyEdit()` (fixes entity range maintenance)
2. **CRITICAL**: Compile entities from text when posting (or ensure entities are always maintained)
3. **HIGH**: Wire up `onUndoRedo` callback for entity state sync
4. **HIGH**: Add platform conflict detection logic
5. **MEDIUM**: Add missing keyboard shortcuts (Cmd+K, Cmd+L, Cmd+.)
6. **MEDIUM**: Implement smart paste detection
7. **MEDIUM**: Implement draft naming & pinning
8. **LOW**: Implement full emoji fetching from Mastodon API
9. **LOW**: Improve AutocompleteCache persistence (make EntityPayload Codable or use alternative)
10. **LOW**: Add Direct visibility option
11. **LOW**: Add link cards & canonicalization (if desired)

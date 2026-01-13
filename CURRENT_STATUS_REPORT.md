# Current Status Report - Missing/Partial Features

## ✅ FIXED (Just Completed)

1. **✅ ComposerTextModel.applyEdit() Not Called on Text Changes** - FIXED
   - `onTextEdit` callback now wired up to call `composerTextModel.applyEdit()`
   - Entity ranges now maintained correctly during edits

2. **✅ Undo/Redo Integration** - FIXED  
   - `onUndoRedo` callback now wired up
   - Entity state syncs on undo/redo

3. **✅ Initialization Logic** - FIXED
   - `composerTextModel` initializes with thread post text on appear
   - Syncs when switching between thread posts

---

## ⚠️ PARTIALLY IMPLEMENTED (Needs Completion)

### 1. **Platform Conflict Detection** ⚠️ LOGIC EXISTS BUT NOT CALLED
**Status**: Code exists but not integrated  
**Location**: 
- `updatePlatformConflicts()` function exists (line 1814-1834)
- `platformConflicts` state variable exists
- **BUT**: Function is never called automatically

**Fix Needed**: Add `.onChange` modifiers to call `updatePlatformConflicts()` when:
- `cwEnabled` changes
- `blueskyLabels` changes  
- `selectedPlatforms` changes

**Note**: There's a `ComposeViewLifecycleModifier` that has this logic, but it's **not being used** in `ComposeView`.

---

### 2. **Keyboard Shortcuts** ⚠️ DEFINED BUT NOT APPLIED
**Status**: Code exists in `ComposeViewLifecycleModifier.swift` but modifier not used  
**Location**: `SocialFusion/Views/ComposeViewLifecycleModifier.swift`

**Shortcuts Defined**:
- ✅ `Cmd+Enter`: Send post
- ✅ `Cmd+Shift+Enter`: Send silently/unlisted  
- ✅ `Cmd+K`: Insert link (defined but `insertLink()` function missing)
- ✅ `Cmd+L`: Toggle labels/CW (defined but `toggleCW()`/`toggleLabels()` functions missing)
- ✅ `Cmd+.`: Dismiss autocomplete (defined)

**Fix Needed**: 
- Apply `ComposeViewLifecycleModifier` to `ComposeView` OR
- Move keyboard shortcuts directly into `ComposeView` body
- Implement missing functions: `insertLink()`, `toggleCW()`, `toggleLabels()`

---

### 3. **Entity Compilation When Posting** ⚠️ PARTIAL
**Status**: Entities not compiled from plain text  
**Location**: `postContent()` method

**Current State**:
- `composerTextModel.text` is synced before posting
- But `composerTextModel.entities` is only populated if user accepted autocomplete suggestions
- Mentions/hashtags typed manually won't be converted to entities

**Fix Needed**: 
- Parse text for mentions/hashtags/links before posting
- Create entities from parsed text
- OR: Ensure entities are always maintained via `applyEdit()` (which we just fixed, but only works going forward)

---

### 4. **AutocompleteCache Persistence** ⚠️ PARTIAL
**Status**: Simplified persistence only  
**Location**: `SocialFusion/Stores/AutocompleteCache.swift`

**Current State**:
- ✅ In-memory caching works
- ✅ `saveToUserDefaults()` saves simplified data (ID, displayText)
- ❌ `loadFromUserDefaults()` doesn't restore full `AutocompleteSuggestion` objects
- ❌ `EntityPayload` isn't Codable, so full persistence blocked

**Fix Needed**: Make `EntityPayload` Codable OR use alternative storage strategy

---

### 5. **Emoji Fetching** ⚠️ PLACEHOLDER
**Status**: Returns empty array  
**Location**: `SocialFusion/Services/EmojiService.swift`

**Current State**:
- `fetchEmoji()` method exists but returns empty array
- Comment says Mastodon API doesn't have emoji endpoint (but v3+ does)

**Fix Needed**: Implement actual API call to `/api/v1/custom_emojis`

---

## ❌ NOT IMPLEMENTED

### 1. **Smart Paste Detection** ❌
**Status**: Missing  
**Location**: `FocusableTextEditor.Coordinator`

**Missing**:
- No paste detection (large text replacement)
- No URL/handle resolution on paste
- No automatic link/mention entity creation

---

### 2. **Draft Naming & Pinning** ❌
**Status**: Missing  
**Location**: `SocialFusion/Models/DraftPost.swift`

**Missing**:
- No `name` field
- No `isPinned` field
- No UI for naming/pinning

---

### 3. **Thread Segment Shortcut** ❌
**Status**: Missing  
**Location**: `ComposeView`

**Issue**: `Cmd+Enter` sends post, but plan says it should create next thread segment when in thread mode

**Fix Needed**: Check if `threadPosts.count > 1`, if so create next segment instead of posting

---

### 4. **Direct Visibility Option** ❌
**Status**: Missing  
**Location**: `ComposeView`

**Current State**: Only Public/Unlisted/Followers options exist

**Fix Needed**: Add "Direct" option for Mastodon

---

### 5. **Link Cards & Canonicalization** ❌
**Status**: Missing  
**Plan Reference**: "Future Enhancement"

**Missing**:
- No URL paste detection
- No link preview fetching
- No tracking parameter removal
- No quote vs embed logic

---

## Summary by Priority

### 🔴 CRITICAL (Must Fix)
1. ✅ ~~Entity range maintenance~~ - **FIXED**
2. ⚠️ Entity compilation when posting - **PARTIAL** (works for autocomplete, not manual typing)

### 🟡 HIGH (Should Fix)
3. ⚠️ Platform conflict detection - **LOGIC EXISTS, NOT CALLED**
4. ⚠️ Keyboard shortcuts - **DEFINED BUT NOT APPLIED**
5. ⚠️ Undo/redo integration - **FIXED** ✅

### 🟢 MEDIUM (Nice to Have)
6. ❌ Smart paste detection
7. ❌ Draft naming & pinning
8. ⚠️ AutocompleteCache full persistence
9. ⚠️ Emoji fetching implementation

### 🔵 LOW (Future)
10. ❌ Thread segment shortcut
11. ❌ Direct visibility option
12. ❌ Link cards & canonicalization

---

## Quick Wins (Easiest to Fix)

1. **Platform Conflict Detection** - Just add `.onChange` modifiers (5 minutes)
2. **Keyboard Shortcuts** - Apply `ComposeViewLifecycleModifier` OR move shortcuts to body (10 minutes)
3. **Entity Compilation** - Add text parsing before posting (30 minutes)

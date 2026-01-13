# Missed Features from Muscle Memory Composer Implementation Plan

## Critical Missing Features

### 1. **ComposerTextModel.applyEdit() Not Called on Text Changes** ⚠️ CRITICAL
**Status**: MISSING
**Issue**: When user types, we sync `composerTextModel.text` but never call `applyEdit()` to update entity ranges. This means:
- Entity ranges become stale/invalid as user types
- Entities don't shift properly when text is inserted/deleted
- Entity ranges may point to wrong locations after edits

**Location**: `SocialFusion/Views/ComposeView.swift` line 705-711
**Current Code**: Only syncs text, doesn't call `applyEdit()`
**Fix Needed**: Call `composerTextModel.applyEdit()` with the actual edit range when text changes

### 2. **Smart Paste Detection** ❌ NOT IMPLEMENTED
**Status**: MISSING
**Plan Reference**: Section 8 - "Detect paste events, resolve @handles and URLs to mention entities"
**Missing**: 
- No `UITextViewDelegate.textView(_:shouldChangeTextIn:replacementText:)` implementation
- No paste detection
- No URL/handle resolution on paste
- No automatic link entity creation

**Location**: `FocusableTextEditor.Coordinator` - needs paste detection method

### 3. **Missing Keyboard Shortcuts** ⚠️ PARTIAL
**Status**: PARTIALLY IMPLEMENTED
**Missing**:
- `Cmd+K`: Insert link (not implemented)
- `Cmd+L`: Toggle labels/CW (not implemented)
- `Cmd+.`: Dismiss autocomplete (implemented ✅)
- `Cmd+Enter`: Send post (implemented ✅)
- `Cmd+Shift+Enter`: Send silently/unlisted (implemented ✅)

**Location**: `SocialFusion/Views/ComposeView.swift` - missing shortcuts
**Plan Reference**: Section 7

### 4. **Draft Naming & Pinning** ❌ NOT IMPLEMENTED
**Status**: MISSING
**Plan Reference**: "drafts that behave like pro apps (automatic local, named/pinned, per-destination metadata)"
**Missing**:
- No `name` field in `DraftPost`
- No `isPinned` field in `DraftPost`
- No UI for naming/pinning drafts
- No per-destination metadata storage

**Location**: `SocialFusion/Models/DraftPost.swift`

### 5. **Emoji Fetching Stubbed** ⚠️ INCOMPLETE
**Status**: STUBBED (returns empty array)
**Issue**: `EmojiService.fetchEmoji()` always returns empty array
**Note**: Plan says "Mastodon API doesn't have a direct emoji endpoint" but emoji are available in instance responses
**Fix Needed**: Fetch from instance custom emoji endpoint or extract from account/profile responses

**Location**: `SocialFusion/Services/EmojiService.swift` line 19-36

### 6. **Cmd+Enter for Next Thread Segment** ❌ NOT IMPLEMENTED
**Status**: MISSING
**Plan Reference**: "threading and 'continue thread' affordances ('Add to thread' button, Cmd+Enter for next segment)"
**Current**: Cmd+Enter sends post (doesn't create next segment)
**Missing**: Logic to create next thread segment instead of sending when in thread mode

**Location**: `SocialFusion/Views/ComposeView.swift` - keyboard shortcut handler

### 7. **Direct Visibility Option** ❌ NOT IMPLEMENTED
**Status**: MISSING
**Plan Reference**: "Mastodon: Public/Unlisted/Followers/Direct"
**Current**: Only Public/Unlisted/Followers (no Direct option)
**Missing**: Direct visibility option for Mastodon

**Location**: `SocialFusion/Views/ComposeView.swift` - visibility picker

### 8. **Link Cards on Paste** ❌ NOT IMPLEMENTED
**Plan Reference**: "link cards + canonicalization (paste URL, fetch preview, remove tracking, quote vs embed)"
**Status**: MISSING
**Missing**:
- No automatic link preview fetching on paste
- No URL canonicalization/untracking
- No quote vs embed detection

**Note**: Link previews exist for display, but not triggered on paste

### 9. **Text Formatting Helpers** ❌ NOT IMPLEMENTED
**Plan Reference**: "text formatting helpers (minimal toolbar or quick inserts)"
**Status**: MISSING
**Missing**: No formatting toolbar or quick insert buttons

### 10. **Centralized Keyboard Shortcuts File** ❌ NOT IMPLEMENTED
**Plan Reference**: Section 7 - "New File: SocialFusion/Utilities/KeyboardShortcuts.swift"
**Status**: MISSING
**Missing**: Centralized shortcut definitions and user preferences

## Partially Implemented / Needs Verification

### 11. **Entity Compilation in Posting** ⚠️ NEEDS VERIFICATION
**Status**: HOOKED UP but needs verification
**Location**: `SocialFusion/Views/ComposeView.swift` - `postContent()` passes `composerTextModel`
**Issue**: Need to verify entities are actually being compiled and sent to APIs correctly

### 12. **Reply Scope Controls** ❓ UNCLEAR
**Plan Reference**: "reply scope" controls
**Status**: UNCLEAR if implemented
**Missing**: Need to check if reply scope (who can reply) is implemented

## Summary

**Critical Issues** (Must Fix):
1. `applyEdit()` not called on text changes (entity ranges become stale)
2. Smart paste detection missing
3. Emoji fetching stubbed (returns empty)

**Important Missing Features**:
4. Draft naming/pinning
5. Cmd+K (insert link) and Cmd+L (toggle labels/CW)
6. Cmd+Enter for next thread segment
7. Direct visibility option
8. Link cards on paste
9. Text formatting helpers
10. Centralized keyboard shortcuts

**Needs Verification**:
- Entity compilation actually working in posting flow
- Reply scope controls

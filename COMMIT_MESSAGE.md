# Git Commit Message

```
feat(composer): implement muscle memory composer features and fixes

Implement comprehensive power-user composer features including entity
compilation, platform conflict detection, keyboard shortcuts, smart paste,
emoji fetching, and cache persistence. Fix critical entity range maintenance
and undo/redo integration issues.

## Features Implemented

### Entity Management
- Add entity parsing from plain text (mentions, hashtags, URLs)
- Fix entity range maintenance via applyEdit() callback wiring
- Implement undo/redo integration for entity state sync
- Add smart paste detection with automatic entity creation
- Parse entities before posting to ensure proper compilation

### Platform Integration
- Wire up platform conflict detection with automatic updates
- Add onChange handlers for cwEnabled, blueskyLabels, selectedPlatforms
- Apply ComposeViewLifecycleModifier for lifecycle management

### Keyboard Shortcuts
- Fix keyboard shortcut API usage (onKeyPress for iOS 17+, fallback for iOS 16)
- Implement Cmd+Enter (send post)
- Implement Cmd+Shift+Enter (send silently/unlisted)
- Implement Cmd+K (insert link)
- Implement Cmd+L (toggle labels/CW)
- Implement Cmd+. (dismiss autocomplete)

### Autocomplete & Caching
- Implement full AutocompleteCache persistence to UserDefaults
- Add SerializableSuggestion wrapper for Codable support
- Add frequently used tracking with usage counts
- Persist recent mentions, hashtags, and usage statistics

### Emoji Support
- Implement Mastodon custom emoji fetching from /api/v1/custom_emojis
- Add system emoji fallback with curated database (100+ emoji)
- Integrate system emoji into autocomplete search results
- Handle 404 gracefully for older Mastodon instances

### Smart Paste
- Detect paste events via large text replacement heuristic
- Parse pasted URLs and @handles into entities
- Merge pasted entities with existing entities (remove overlaps)
- Adjust entity ranges to insertion location

## Build Fixes

- Fix keyboard shortcut API errors (switch to onKeyPress)
- Fix type-checking complexity (extract lifecycle modifier helper)
- Fix String indexing errors (use NSString for safe ranges)
- Fix FocusableTextEditor parameter order
- Remove duplicate code sections
- Fix entity range maintenance callback wiring

## Files Modified

- SocialFusion/Models/ComposerTextModel.swift
  - Add parseEntitiesFromText() method
  - Improve entity range management

- SocialFusion/Views/ComposeView.swift
  - Wire up onTextEdit callback for applyEdit()
  - Wire up onUndoRedo callback for entity sync
  - Add parsePastedText() for smart paste
  - Add entity compilation before posting
  - Apply ComposeViewLifecycleModifier
  - Add initialization logic for composerTextModel

- SocialFusion/Views/ComposeViewLifecycleModifier.swift
  - Fix keyboard shortcut implementation
  - Add platform conflict detection triggers

- SocialFusion/Stores/AutocompleteCache.swift
  - Implement full persistence with SerializableSuggestion
  - Add frequently used tracking
  - Add usage count persistence

- SocialFusion/Services/EmojiService.swift
  - Implement Mastodon API emoji fetching
  - Add system emoji search database
  - Integrate system emoji into results

## Verification

- Verified Bluesky self-labels implementation
- Verified search methods via AutocompleteService
- Verified caret movement dismissal behavior
- Build succeeds for iPhone 17 Pro simulator

## Related

Implements features from muscle_memory_composer_features plan.
Fixes critical entity range maintenance issues.
Completes autocomplete, emoji, and paste detection features.

Co-authored-by: AI Assistant
```

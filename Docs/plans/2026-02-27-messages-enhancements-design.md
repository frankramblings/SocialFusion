# Messages Tab Enhancements Design

Date: 2026-02-27
Status: Approved
Builds on: 2026-02-26-messages-tab-design.md (initial Messages redesign)

## Overview

Eight enhancements to the Messages tab, delivered as vertical slices (model -> service -> viewmodel -> UI). Each phase is independently shippable. Ordered by infrastructure readiness, user impact, and dependency chains.

## Key Decisions

- **Platform asymmetry**: Bluesky-only features are hidden on Mastodon. No stubs, no "not available" labels. Mastodon conversations get a clean, simpler experience.
- **Interaction model**: iMessage-style throughout — long-press context menus, reaction pills, typing dots, group avatar stacks.
- **Search scope**: In-conversation only. No global message search.
- **Phase 8 last**: The `participant` -> `participants` model refactor is the most invasive change and is intentionally deferred to the final phase so all prior phases work against the current model.

## Existing Infrastructure

Already built but unused:
- `ChatEventReaction` (added/removed) — full pipeline from Bluesky API -> stream -> events
- `ChatEventReadReceipt` — events generated, ignored in ViewModel
- `ChatEventDeletedMessage` — stream handles incoming deletions, no user-initiated delete
- `ChatEventConversationUpdate` (.muted/.unmuted/.left) — events flow, no UI triggers
- `BlueskyConvo.muted` field — populated but not displayed
- `BlueskyConvo.members` array — supports multi-member, UI assumes 1-on-1

---

## Phase 1: Read Receipts UI (Bluesky only)

**Goal**: Show "Seen" indicator on the last message read by the other participant.

**State**: `ConversationReadState` dictionary in `MessagesViewModel`, keyed by conversation ID, storing `lastReadByOther: Date?`. Updated when `.readReceipt` stream events arrive.

**UI**: Small "Seen" label in secondary color beneath the last sent-by-me message that falls at or before the read timestamp. Right-aligned, matching iMessage convention. Only shown on the most recent read point.

**Sending read state**: When user opens a Bluesky conversation, call `updateRead` API to mark it read server-side (also clears unread count).

**Files**:
- `MessagesViewModel.swift` — stop ignoring `.readReceipt`, track state
- `ChatView.swift` — pass read state, render "Seen" indicator
- `MessageBubble.swift` — optional "Seen" label slot below bubble
- `BlueskyService.swift` — add `updateRead(convoId:)` API call
- `SocialServiceManager.swift` — expose `markConversationRead()`

---

## Phase 2: Reactions UI (Bluesky only)

**Goal**: iMessage-style emoji reactions on message bubbles.

**Model**: `MessageReaction` struct (emoji, senderId, isFromMe). Stored in `[String: [MessageReaction]]` dictionary on ChatView, keyed by message ID.

**Displaying**: Pill-shaped capsules below the bubble. Each unique emoji gets one pill with emoji + count. Tapping a pill toggles your reaction. Subtle background tint matching platform color.

**Adding**: Long-press bubble -> context menu with 6 quick picks (heart, thumbs up, laugh, surprised, sad, fire) plus "More..." for system emoji picker. Haptic feedback on selection.

**API**: `addReaction(convoId:messageId:emoji:)` and `removeReaction(convoId:messageId:emoji:)` on BlueskyService. Optimistic updates with rollback.

**Stream**: ChatView handles `reactionAdded`/`reactionRemoved` events, updates dictionary. Deduplication by (messageId, emoji, senderId).

**Files**:
- `MessageBubble.swift` — reaction pills below bubble, long-press gesture
- `ChatView.swift` — reactions state, stream handling, context menu
- `BlueskyService.swift` — `addReaction()`, `removeReaction()` API calls
- `SocialServiceManager.swift` — unified reaction methods
- New: `MessageReactionView.swift` — pill/capsule component

---

## Phase 3: Message Editing/Deletion

**Goal**: User-initiated message deletion (both platforms) and editing (Mastodon only).

### Deletion (both platforms)
- Long-press own message -> "Delete Message" (destructive). Confirmation alert.
- Bluesky: `deleteMessage(convoId:messageId:)` via `chat.bsky.convo.deleteMessageForSelf`.
- Mastodon: Use existing `deletePost()` API (DMs are posts).
- Optimistic: fade bubble out with animation, roll back on failure.

### Editing (Mastodon only)
- Bluesky ATProto has no chat edit endpoint — descoped until API available.
- Long-press own Mastodon message -> "Edit Message". Input bar transforms: pre-fills text, shows "Editing" banner with cancel button.
- Uses existing status edit API. Shows "(edited)" label next to timestamp after edit.

### Unified context menu
Both reactions (Phase 2) and edit/delete share the long-press menu. Conditional items:
- My message, Bluesky: React, Delete
- My message, Mastodon: Edit, Delete
- Their message, Bluesky: React
- Their message, Mastodon: Copy text

**Files**:
- `MessageBubble.swift` — unified context menu, "edited" label
- `ChatView.swift` — editing state, input bar transformation, delete confirmation
- `BlueskyService.swift` — `deleteMessage()` API call
- `SocialServiceManager.swift` — `deleteMessage()`, `editMessage()` unified methods
- `MastodonService.swift` — wire edit/delete for direct-visibility posts

---

## Phase 4: Typing Indicators (Bluesky only, speculative)

**Goal**: Build UI and plumbing for typing indicators, ready to wire when APIs land.

**Reality**: Neither Bluesky nor Mastodon currently expose typing indicator endpoints. This phase builds the UI with no-op providers.

**Sending**: Debounce text input in ChatView. Fire `sendTypingIndicator()` on provider (no-op). Stop after 5 seconds idle.

**Receiving**: New `case typingIndicator(ChatEventTypingIndicator)` on `UnifiedChatEvent`. Providers emit when detected (no-op for now).

**UI**: Animated "..." bubble at bottom of message list, left-aligned. Three dots with sequential bounce animation. Auto-dismiss after 5 seconds with no new event.

**Files**:
- `ChatStreamModels.swift` — add `typingIndicator` case, `ChatEventTypingIndicator` struct
- `ChatStreamProvider.swift` — add `sendTypingIndicator()` to protocol
- `BlueskyPollStreamProvider.swift` — no-op implementation
- `MastodonChatStreamProvider.swift` — no-op implementation
- `ChatView.swift` — typing debounce, display logic
- New: `TypingIndicatorBubble.swift` — animated three-dot bubble

---

## Phase 5: Conversation Muting/Settings

**Goal**: Conversation management via settings sheet and swipe actions.

### Settings sheet
- Toolbar info button in ChatView opens sheet.
- Content: participant info (avatar, name, handle, badge), mute toggle, leave conversation (Bluesky), delete conversation (Bluesky).
- Mastodon: participant info and mute toggle only.

### APIs
- `BlueskyService.swift` — `muteConvo()`, `unmuteConvo()`, `leaveConvo()`
- `MastodonService.swift` — conversation mute endpoint
- `SocialServiceManager.swift` — unified mute/leave methods

### Conversation list
- `DMConversationRow` shows muted speaker icon for muted conversations.
- `DMConversation` model gains `isMuted: Bool`.
- Swipe left on row for quick mute/delete actions.

### Stream
- `MessagesViewModel` handles `.conversationUpdated(.muted/.unmuted)` to update state in place.

**Files**:
- `Post.swift` — `DMConversation` gains `isMuted: Bool`
- `BlueskyService.swift` — mute/unmute/leave API calls
- `MastodonService.swift` — conversation mute API
- `SocialServiceManager.swift` — unified methods, populate `isMuted` during fetch
- `ChatView.swift` — toolbar info button, sheet presentation
- `DMConversationRow.swift` — muted icon, swipe actions
- `DirectMessagesView.swift` — wire swipe actions
- `MessagesViewModel.swift` — handle mute/unmute stream events
- New: `ConversationSettingsView.swift` — settings sheet

---

## Phase 6: Media Attachments in Messages

**Goal**: Send and receive images/video in chat.

### Receiving
- Extend `UnifiedChatMessage` with `mediaAttachments: [MediaItem]` computed property.
- Bluesky: parse embed blobs. Mastodon: pull from status `mediaAttachments`.
- `MessageBubble` renders media above text. Compact `MediaGridView` variant (~240pt max width). Tap opens `FullscreenMediaView`.

### Sending
- "+" button left of text field opens `PhotosPicker` (iOS 17 native).
- Selected images as thumbnail strip above input bar. Max 4 images. "x" to remove.
- Upload flow: images upload first, then send message with references.
  - Bluesky: `uploadBlob()` then send with embed.
  - Mastodon: `/api/v2/media` then post direct-visibility status with `media_ids`.
- Circular progress indicator on thumbnails during upload. Send button disabled while uploading.

### State
- `pendingMedia: [PhotosPickerItem]` — selected, not yet sent
- `uploadingMedia: [MediaUploadState]` — per-item upload progress

**Files**:
- `MessageBubble.swift` — media area above text, tap for fullscreen
- `ChatView.swift` — photo picker, pending media strip, upload flow
- `BlueskyService.swift` — `uploadBlob()`, extend `sendMessage()` for embeds
- `SocialServiceManager.swift` — `sendMessageWithMedia()` unified method
- `UnifiedChatMessage` extensions — `mediaAttachments` computed property
- `BlueskyModels.swift` — embed types for chat messages
- New: `ChatMediaPickerBar.swift` — thumbnail strip above input bar

---

## Phase 7: Search Within Conversations

**Goal**: Find messages within the current conversation by text search.

**Activation**: Magnifying glass toolbar button in ChatView. Reveals search bar with slide-down animation.

**Search**: Local-first array filter on loaded messages (case-insensitive substring). Instant as-you-type. "Search older messages" button triggers paginated fetch for unloaded history.

**Results display**: Highlight in place — matching bubbles get subtle gold background tint, non-matching dim to 30% opacity. Navigation arrows (up/down chevrons) with "3 of 12" counter. Auto-scroll to matches.

**State**:
- `isSearching`, `searchText`, `matchingMessageIds: [String]`, `currentMatchIndex: Int`

**MessageBubble**: `searchHighlight` parameter (`.none`, `.matched`, `.focused`) adjusts background tint/opacity.

**Files**:
- `ChatView.swift` — search bar, filtering, scroll-to-match, navigation arrows
- `MessageBubble.swift` — `searchHighlight` parameter, conditional styling

---

## Phase 8: Group Conversations (Bluesky only)

**Goal**: Support multi-member conversations.

### Model refactor
- `DMConversation`: `participant` -> `participants: [NotificationAccount]`. Add `isGroup: Bool` computed, optional `title: String?`.
- This is the most invasive change — every reference to `.participant` updates to handle the array.

### Conversation list
- Group avatar: overlapping circle stack (2-3 avatars). New `GroupAvatarStack` component.
- Group display name: comma-separated first names, truncated. Or custom title.
- Last message prefixed with sender name in groups: "Alice: hey everyone"

### ChatView
- Sender name label above first bubble in a group from that sender (caption font, secondary color).
- Avatars for all participants. Grouping logic unchanged.
- Nav bar shows group avatar stack and name.

### Creating groups
- `NewConversationView` gains multi-select mode (Bluesky only). Chip/token UI for selected participants above search.
- Uses existing `getConvoForMembers` with multiple DIDs.
- Minimum 2 other participants.

### Settings (extends Phase 5)
- `ConversationSettingsView` shows participant list for groups.
- V1: show members, mute, leave. No add/remove members or rename (defer to v2 if APIs support).

**Files**:
- `Post.swift` — `DMConversation` model refactor
- `DMConversationRow.swift` — group avatar, sender-prefixed preview
- `ChatView.swift` — sender name labels, group nav bar
- `MessageBubble.swift` — optional sender name above bubble
- `NewConversationView.swift` — multi-select chip UI
- `ConversationSettingsView.swift` — participant list
- `SocialServiceManager.swift` — populate participants array
- `BlueskyService.swift` — adjust convo mapping for all members
- `MessagesViewModel.swift` — group stream events
- New: `GroupAvatarStack.swift` — overlapping avatar component

---

## File Impact Summary

| File | Phases |
|------|--------|
| `MessageBubble.swift` | 1, 2, 3, 6, 7, 8 |
| `ChatView.swift` | 1, 2, 3, 4, 5, 6, 7, 8 |
| `BlueskyService.swift` | 1, 2, 3, 5, 6, 8 |
| `SocialServiceManager.swift` | 1, 2, 3, 5, 6, 8 |
| `MessagesViewModel.swift` | 1, 5, 8 |
| `DMConversationRow.swift` | 5, 8 |
| `Post.swift` (DMConversation model) | 5, 8 |
| `DirectMessagesView.swift` | 5 |
| `ChatStreamModels.swift` | 4 |
| `ChatStreamProvider.swift` | 4 |
| `BlueskyPollStreamProvider.swift` | 4 |
| `MastodonChatStreamProvider.swift` | 4 |
| `MastodonService.swift` | 3, 5 |
| `BlueskyModels.swift` | 6 |
| `NewConversationView.swift` | 8 |

**New files** (3 total):
- `MessageReactionView.swift` (Phase 2)
- `TypingIndicatorBubble.swift` (Phase 4)
- `ChatMediaPickerBar.swift` (Phase 6)
- `ConversationSettingsView.swift` (Phase 5)
- `GroupAvatarStack.swift` (Phase 8)

(5 new files total — 3 small components, 1 settings sheet, 1 avatar component)

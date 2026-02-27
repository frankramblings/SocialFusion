# Messages Tab Redesign

**Date**: 2026-02-26
**Approach**: Full UI rewrite on existing backend (Approach A)

## Goal

Bring the Messages tab up to the same quality bar as the rest of SocialFusion. The backend (streaming, API, models) is production-ready — this is a UI-only rebuild.

## File Structure

```
SocialFusion/Views/Messages/DirectMessagesView.swift    — conversation list
SocialFusion/Views/Messages/DMConversationRow.swift     — single conversation row
SocialFusion/Views/Messages/ChatView.swift              — conversation detail
SocialFusion/Views/Messages/MessageBubble.swift         — iMessage-style bubble
SocialFusion/Views/Messages/NewConversationView.swift   — search followers to start DM
SocialFusion/ViewModels/MessagesViewModel.swift         — all state & business logic
```

`MessagesViewModel` owns conversation list state, fetching, and real-time event handling. ChatView keeps local message state scoped to one conversation's lifecycle. Old code removed from `NotificationsView.swift` and the existing `ChatView.swift`.

## Conversation List (DirectMessagesView)

- Large navigation title (`.large`) to match timeline presence
- Toolbar compose button opens `NewConversationView` sheet (not `ComposeView`)
- Empty state: icon + "No messages yet" + "Start a conversation" button opening `NewConversationView`
- Pull-to-refresh kept as-is

### DMConversationRow Layout

```
┌─────────────────────────────────────────────────┐
│ [Avatar 48pt]  Display Name     [Platform Badge]│
│                @username · 2m ago               │
│                Last message preview up to 2 li… │
│                                        [● blue] │
└─────────────────────────────────────────────────┘
```

- Platform badge: reuse `PostPlatformBadge` (blue/Bluesky, purple/Mastodon), compact, top-right of name row
- Username below display name in secondary color
- Relative timestamp next to username with interpunct separator
- Unread dot blue, trailing on message preview line
- Avatar: `CachedAsyncImage` with circle clip

## Chat View

### Navigation Bar
- Participant display name as title (inline)
- 28pt circle avatar in leading toolbar

### Message Grouping
- Date headers: "Today", "Yesterday", or formatted date separating groups
- Messages from same sender within 2 minutes grouped together
- Only last message in a group shows timestamp
- Incoming messages show 28pt sender avatar on the left, aligned to bottom of group

### Input Bar
- Thin separator line (0.5pt) above input area
- `TextField` with `.axis: .vertical`, `.lineLimit(1...5)` for auto-growing multi-line
- 20pt corner radius pill shape
- Send button uses platform color (blue for Bluesky, purple for Mastodon)

## Message Bubbles (iMessage-style)

### Colors
- Outgoing Bluesky: `.blue` bubble, white text
- Outgoing Mastodon: `.purple` bubble, white text
- Incoming (both): `Color(.systemGray5)`, primary text

### Shape
- 18pt corner radius base
- Tail (triangular nub) on last message of consecutive group: bottom-left (incoming), bottom-right (outgoing)
- Non-tail messages: standard rounded rect with tighter 4pt vertical spacing

### Layout
```
Incoming (grouped):                    Outgoing (grouped):

[Avatar]  ┌──────────────┐                    ┌──────────────┐
          │ Hey there!   │                    │ What's up?   │
          └──────────────┘                    └──────────────┘
          ┌──────────────┐                    ┌──────────────┐
          │ How are you? │◄─tail              │ Not much     │─►tail
          └──────────────┘                    └──────────────┘
                    10:42 AM                  10:43 AM
```

Avatar appears once per group at bottom, incoming only.

## New Conversation View

- Presented as `.sheet`
- Search bar filtering followers/following list
- Results grouped by platform with section headers
- Each row: avatar + display name + @handle + platform badge
- Tap creates/finds existing conversation → navigates to ChatView
- Uses existing `SocialServiceManager.fetchFollowing(for:)`
- Bluesky: `sendChatMessage` auto-creates conversations
- Mastodon: opens ComposeView pre-filled with `@user@instance`, visibility direct

## Data Flow & Streaming

No backend changes. `ChatStreamService`, `MastodonChatStreamProvider`, `BlueskyPollStreamProvider` unchanged.

ViewModel subscribes to `chatStreamService.$recentEvents` (moved from view body).

**Avatar fix**: When constructing updated `DirectMessage` from `ChatEventMessage`, carry forward `avatarURL` from existing conversation participant instead of setting `nil`.

## Out of Scope

- Reactions UI
- Read receipts UI
- Typing indicators
- Message editing/deletion
- Conversation muting/settings
- Group conversations
- Media attachments in messages
- Search within conversations

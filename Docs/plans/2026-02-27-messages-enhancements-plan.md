# Messages Tab Enhancements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement 8 enhancement features for the Messages tab — read receipts, reactions, editing/deletion, typing indicators, conversation muting/settings, media attachments, in-conversation search, and group conversations.

**Architecture:** Each phase is a vertical slice (model → service → viewmodel → UI) built on the existing Messages redesign in the `worktree-messages-tab-redesign` branch. The existing `ChatStreamService` / `ChatStreamProvider` / `UnifiedChatEvent` infrastructure already pipes reaction and read receipt events from Bluesky — we wire them into the UI. Mastodon-unsupported features are hidden, not stubbed.

**Tech Stack:** SwiftUI, async/await, ATProto Bluesky Chat API, Mastodon REST API, WebSocket streaming

**Design doc:** `Docs/plans/2026-02-27-messages-enhancements-design.md`

**Branch:** `worktree-messages-tab-redesign` (worktree at `.claude/worktrees/messages-tab-redesign/`)

---

## Task 1: Read Receipts — BlueskyService.updateRead() API

**Files:**
- Modify: `SocialFusion/Services/BlueskyService.swift` (after `getChatLog` method, ~line 4560)

**Step 1: Add updateRead API call**

Add after the `getChatLog` method in `BlueskyService.swift`:

```swift
  /// Mark a conversation as read on Bluesky
  internal func updateRead(convoId: String, for account: SocialAccount) async throws {
    guard let accessToken = account.accessToken else {
      throw BlueskyTokenError.noAccessToken
    }

    let apiURL = "\(getChatProxyURL(for: account))/chat.bsky.convo.updateRead"
    guard let url = URL(string: apiURL) else {
      throw BlueskyTokenError.invalidServerURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let body: [String: Any] = ["convoId": convoId]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (_, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
      throw BlueskyTokenError.invalidResponse
    }
  }
```

**Step 2: Build to verify compilation**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SocialFusion/Services/BlueskyService.swift
git commit -m "feat(messages): add Bluesky updateRead API call"
```

---

## Task 2: Read Receipts — SocialServiceManager.markConversationRead()

**Files:**
- Modify: `SocialFusion/Services/SocialServiceManager.swift` (after `startOrFindBlueskyConversation`, ~line 3930)

**Step 1: Add unified markConversationRead method**

```swift
  /// Mark a conversation as read (Bluesky only — Mastodon has no equivalent)
  public func markConversationRead(conversation: DMConversation) async {
    guard conversation.platform == .bluesky,
          let account = accounts.first(where: { $0.platform == .bluesky }) else { return }
    do {
      try await blueskyService.updateRead(convoId: conversation.id, for: account)
    } catch {
      print("[Messages] Failed to mark conversation read: \(error.localizedDescription)")
    }
  }
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SocialFusion/Services/SocialServiceManager.swift
git commit -m "feat(messages): add markConversationRead to SocialServiceManager"
```

---

## Task 3: Read Receipts — MessagesViewModel Read State Tracking

**Files:**
- Modify: `SocialFusion/ViewModels/MessagesViewModel.swift`

**Step 1: Add read state tracking and handle readReceipt events**

Replace the entire file with:

```swift
import SwiftUI

@MainActor
class MessagesViewModel: ObservableObject {
  @Published var conversations: [DMConversation] = []
  @Published var isLoading = false
  @Published var errorMessage: String?
  @Published var showNewConversation = false

  /// Tracks the last time the other participant read our messages, keyed by conversation ID
  @Published var readStates: [String: Date] = [:]

  func fetchConversations(serviceManager: SocialServiceManager) async {
    isLoading = true
    errorMessage = nil
    do {
      conversations = try await serviceManager.fetchDirectMessages()
    } catch {
      errorMessage = "Failed to load conversations: \(error.localizedDescription)"
    }
    isLoading = false
  }

  func handleStreamEvents(
    _ events: [UnifiedChatEvent],
    serviceManager: SocialServiceManager
  ) {
    for event in events {
      switch event {
      case .newMessage(let msg):
        if let index = conversations.firstIndex(where: { $0.id == msg.conversationId }) {
          var conv = conversations[index]
          let newLastMessage = DirectMessage(
            id: msg.id,
            sender: NotificationAccount(
              id: msg.senderId,
              username: msg.senderDisplayName,
              displayName: msg.senderDisplayName,
              avatarURL: conv.participant.avatarURL,
              displayNameEmojiMap: nil
            ),
            recipient: conv.lastMessage.recipient,
            content: msg.text,
            createdAt: msg.sentAt,
            platform: msg.platform
          )
          conv = DMConversation(
            id: conv.id,
            participant: conv.participant,
            lastMessage: newLastMessage,
            unreadCount: conv.unreadCount + 1,
            platform: conv.platform
          )
          conversations[index] = conv
          conversations.sort { $0.lastMessage.createdAt > $1.lastMessage.createdAt }
        }

      case .readReceipt(let receipt):
        // Track the read timestamp for the conversation
        readStates[receipt.conversationId] = Date()

      case .conversationUpdated(let update) where update.kind == .began:
        Task { await fetchConversations(serviceManager: serviceManager) }

      default:
        break
      }
    }
  }
}
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SocialFusion/ViewModels/MessagesViewModel.swift
git commit -m "feat(messages): track read receipt state in MessagesViewModel"
```

---

## Task 4: Read Receipts — UI in ChatView and MessageBubble

**Files:**
- Modify: `SocialFusion/Views/Messages/MessageBubble.swift` (~line 97, after the time label)
- Modify: `SocialFusion/Views/Messages/ChatView.swift` (~line 42, onAppear; ~line 88-101, messageGroupView)

**Step 1: Add "Seen" indicator to MessageBubble**

In `MessageBubble.swift`, add a new parameter and render the indicator. Add after the `avatarURL` property (line 68):

```swift
  var showSeenIndicator: Bool = false
```

Then in the `body`, after the time label block (after line 102), add:

```swift
        if showSeenIndicator {
          Text("Seen")
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
        }
```

The full VStack inside the HStack (lines 89-103) becomes:

```swift
      VStack(alignment: isFromMe ? .trailing : .leading, spacing: 2) {
        messageContent
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(bubbleColor)
          .foregroundColor(isFromMe ? .white : .primary)
          .clipShape(BubbleShape(isFromMe: isFromMe, hasTail: isLastInGroup))

        if isLastInGroup {
          Text(message.sentAt, style: .time)
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
        }

        if showSeenIndicator {
          Text("Seen")
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
        }
      }
```

**Step 2: Wire read state into ChatView**

In `ChatView.swift`, add a state property after `isSending` (line 12):

```swift
  @State private var lastReadByOther: Date?
```

In `handleStreamEvents` (line 251), add a case for read receipts:

```swift
      case .readReceipt:
        lastReadByOther = Date()
```

In `onAppear` (line 42), add the markRead call after starting streaming:

```swift
    .onAppear {
      loadMessages()
      chatStreamService.startConversationStreaming(
        conversation: conversation,
        accounts: serviceManager.accounts
      )
      Task { await serviceManager.markConversationRead(conversation: conversation) }
    }
```

In `messageGroupView` (line 84), compute `showSeenIndicator` for the last sent-by-me message:

```swift
  @ViewBuilder
  private func messageGroupView(_ group: MessageGroup) -> some View {
    ForEach(Array(group.messages.enumerated()), id: \.element.id) { msgIndex, message in
      let isFirst = msgIndex == 0
      let isLast = msgIndex == group.messages.count - 1
      let showSeen = isLast && group.isFromMe && isSeenMessage(message)
      MessageBubble(
        message: message,
        isFromMe: group.isFromMe,
        platform: conversation.platform,
        isFirstInGroup: isFirst,
        isLastInGroup: isLast,
        showAvatar: !group.isFromMe,
        avatarURL: conversation.participant.avatarURL,
        showSeenIndicator: showSeen
      )
      .padding(.horizontal, 12)
      .padding(.top, isFirst ? 8 : 2)
      .padding(.bottom, isLast ? 8 : 2)
      .id(message.id)
    }
  }
```

Add the helper method after `isFromMe` (line 249):

```swift
  private func isSeenMessage(_ message: UnifiedChatMessage) -> Bool {
    guard conversation.platform == .bluesky,
          let readDate = lastReadByOther else { return false }
    return message.sentAt <= readDate
  }
```

**Step 3: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add SocialFusion/Views/Messages/MessageBubble.swift SocialFusion/Views/Messages/ChatView.swift
git commit -m "feat(messages): show 'Seen' indicator for read receipts (Bluesky)"
```

---

## Task 5: Reactions — BlueskyService API Calls

**Files:**
- Modify: `SocialFusion/Services/BlueskyService.swift` (after `updateRead` method)

**Step 1: Add addReaction and removeReaction API calls**

```swift
  /// Add an emoji reaction to a message
  internal func addReaction(convoId: String, messageId: String, value: String, for account: SocialAccount) async throws {
    guard let accessToken = account.accessToken else {
      throw BlueskyTokenError.noAccessToken
    }

    let apiURL = "\(getChatProxyURL(for: account))/chat.bsky.convo.addReaction"
    guard let url = URL(string: apiURL) else {
      throw BlueskyTokenError.invalidServerURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let body: [String: Any] = [
      "convoId": convoId,
      "messageId": messageId,
      "value": value
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (_, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
      throw BlueskyTokenError.invalidResponse
    }
  }

  /// Remove an emoji reaction from a message
  internal func removeReaction(convoId: String, messageId: String, value: String, for account: SocialAccount) async throws {
    guard let accessToken = account.accessToken else {
      throw BlueskyTokenError.noAccessToken
    }

    let apiURL = "\(getChatProxyURL(for: account))/chat.bsky.convo.removeReaction"
    guard let url = URL(string: apiURL) else {
      throw BlueskyTokenError.invalidServerURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let body: [String: Any] = [
      "convoId": convoId,
      "messageId": messageId,
      "value": value
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (_, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
      throw BlueskyTokenError.invalidResponse
    }
  }
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SocialFusion/Services/BlueskyService.swift
git commit -m "feat(messages): add Bluesky addReaction/removeReaction API calls"
```

---

## Task 6: Reactions — SocialServiceManager Unified Methods

**Files:**
- Modify: `SocialFusion/Services/SocialServiceManager.swift` (after `markConversationRead`)

**Step 1: Add unified reaction methods with optimistic update support**

```swift
  /// Add a reaction to a message (Bluesky only)
  public func addReaction(conversation: DMConversation, messageId: String, emoji: String) async throws {
    guard conversation.platform == .bluesky,
          let account = accounts.first(where: { $0.platform == .bluesky }) else { return }
    try await blueskyService.addReaction(
      convoId: conversation.id, messageId: messageId, value: emoji, for: account
    )
  }

  /// Remove a reaction from a message (Bluesky only)
  public func removeReaction(conversation: DMConversation, messageId: String, emoji: String) async throws {
    guard conversation.platform == .bluesky,
          let account = accounts.first(where: { $0.platform == .bluesky }) else { return }
    try await blueskyService.removeReaction(
      convoId: conversation.id, messageId: messageId, value: emoji, for: account
    )
  }
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SocialFusion/Services/SocialServiceManager.swift
git commit -m "feat(messages): add unified reaction methods to SocialServiceManager"
```

---

## Task 7: Reactions — MessageReactionView Component

**Files:**
- Create: `SocialFusion/Views/Messages/MessageReactionView.swift`

**Step 1: Create the reaction pill component**

```swift
import SwiftUI

struct MessageReaction: Identifiable {
  let emoji: String
  let senderIds: Set<String>
  var count: Int { senderIds.count }

  var id: String { emoji }

  func isFromMe(myIds: Set<String>) -> Bool {
    !senderIds.isDisjoint(with: myIds)
  }
}

struct MessageReactionView: View {
  let reactions: [MessageReaction]
  let platform: SocialPlatform
  let myAccountIds: Set<String>
  let onTap: (String, Bool) -> Void

  private var platformColor: Color {
    platform == .bluesky ? .blue : .purple
  }

  var body: some View {
    FlowLayout(spacing: 4) {
      ForEach(reactions) { reaction in
        let isFromMe = reaction.isFromMe(myIds: myAccountIds)
        Button {
          onTap(reaction.emoji, isFromMe)
        } label: {
          HStack(spacing: 2) {
            Text(reaction.emoji)
              .font(.caption)
            if reaction.count > 1 {
              Text("\(reaction.count)")
                .font(.caption2)
                .foregroundColor(isFromMe ? .white : .primary)
            }
          }
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
          .background(
            Capsule()
              .fill(isFromMe ? platformColor.opacity(0.8) : Color(.systemGray5))
          )
          .overlay(
            Capsule()
              .stroke(isFromMe ? platformColor : Color.clear, lineWidth: 1)
          )
        }
        .buttonStyle(.plain)
      }
    }
  }
}

/// Simple flow layout for wrapping reaction pills
struct FlowLayout: Layout {
  var spacing: CGFloat = 4

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let result = layout(in: proposal.width ?? 0, subviews: subviews)
    return result.size
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let result = layout(in: bounds.width, subviews: subviews)
    for (index, position) in result.positions.enumerated() {
      subviews[index].place(
        at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
        proposal: .unspecified
      )
    }
  }

  private struct LayoutResult {
    var positions: [CGPoint]
    var size: CGSize
  }

  private func layout(in maxWidth: CGFloat, subviews: Subviews) -> LayoutResult {
    var positions: [CGPoint] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var maxX: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x + size.width > maxWidth && x > 0 {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      positions.append(CGPoint(x: x, y: y))
      rowHeight = max(rowHeight, size.height)
      x += size.width + spacing
      maxX = max(maxX, x)
    }

    return LayoutResult(
      positions: positions,
      size: CGSize(width: maxX, height: y + rowHeight)
    )
  }
}
```

**Step 2: Add the file to the Xcode project**

The file needs to be added to the `SocialFusion.xcodeproj` build target. Since it's in the same `Views/Messages` folder as other files already in the target, Xcode should pick it up automatically if using folder references. If using file references, add it manually.

**Step 3: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add SocialFusion/Views/Messages/MessageReactionView.swift SocialFusion.xcodeproj/project.pbxproj
git commit -m "feat(messages): add MessageReactionView pill component with FlowLayout"
```

---

## Task 8: Reactions — Wire into ChatView and MessageBubble

**Files:**
- Modify: `SocialFusion/Views/Messages/ChatView.swift`
- Modify: `SocialFusion/Views/Messages/MessageBubble.swift`

**Step 1: Add reaction state and stream handling to ChatView**

Add state after `lastReadByOther`:

```swift
  /// Reactions keyed by message ID -> [emoji: Set<senderId>]
  @State private var reactions: [String: [String: Set<String>]] = [:]
```

Add a computed property for current user's account IDs:

```swift
  private var myAccountIds: Set<String> {
    Set(serviceManager.accounts.map(\.platformSpecificId))
  }
```

In `handleStreamEvents`, add cases for reactions (in the switch, before `default`):

```swift
      case .reactionAdded(let r):
        var msgReactions = reactions[r.messageId, default: [:]]
        var senders = msgReactions[r.value, default: Set()]
        senders.insert(r.senderId)
        msgReactions[r.value] = senders
        reactions[r.messageId] = msgReactions

      case .reactionRemoved(let r):
        reactions[r.messageId, default: [:]][r.value]?.remove(r.senderId)
        if reactions[r.messageId]?[r.value]?.isEmpty == true {
          reactions[r.messageId]?[r.value] = nil
        }
        if reactions[r.messageId]?.isEmpty == true {
          reactions[r.messageId] = nil
        }
```

Add a helper to convert reactions dict to `[MessageReaction]`:

```swift
  private func reactionsForMessage(_ messageId: String) -> [MessageReaction] {
    guard let msgReactions = reactions[messageId] else { return [] }
    return msgReactions.map { emoji, senderIds in
      MessageReaction(emoji: emoji, senderIds: senderIds)
    }.sorted { $0.emoji < $1.emoji }
  }
```

Add a method to handle reaction taps:

```swift
  private func toggleReaction(messageId: String, emoji: String, alreadyReacted: Bool) {
    // Optimistic update
    if alreadyReacted {
      for myId in myAccountIds {
        reactions[messageId, default: [:]][emoji]?.remove(myId)
      }
      if reactions[messageId]?[emoji]?.isEmpty == true {
        reactions[messageId]?[emoji] = nil
      }
    } else {
      let myId = myAccountIds.first ?? ""
      reactions[messageId, default: [:]][emoji, default: Set()].insert(myId)
    }

    Task {
      do {
        if alreadyReacted {
          try await serviceManager.removeReaction(conversation: conversation, messageId: messageId, emoji: emoji)
        } else {
          try await serviceManager.addReaction(conversation: conversation, messageId: messageId, emoji: emoji)
        }
      } catch {
        // Rollback on failure — refetch will correct state
        print("[Reactions] Failed to toggle reaction: \(error.localizedDescription)")
      }
    }
  }
```

Update `messageGroupView` to pass reactions and the toggle handler:

```swift
  @ViewBuilder
  private func messageGroupView(_ group: MessageGroup) -> some View {
    ForEach(Array(group.messages.enumerated()), id: \.element.id) { msgIndex, message in
      let isFirst = msgIndex == 0
      let isLast = msgIndex == group.messages.count - 1
      let showSeen = isLast && group.isFromMe && isSeenMessage(message)
      let msgReactions = reactionsForMessage(message.id)
      MessageBubble(
        message: message,
        isFromMe: group.isFromMe,
        platform: conversation.platform,
        isFirstInGroup: isFirst,
        isLastInGroup: isLast,
        showAvatar: !group.isFromMe,
        avatarURL: conversation.participant.avatarURL,
        showSeenIndicator: showSeen,
        reactions: msgReactions,
        myAccountIds: myAccountIds,
        onReactionTap: { emoji, alreadyReacted in
          toggleReaction(messageId: message.id, emoji: emoji, alreadyReacted: alreadyReacted)
        },
        onReactionAdd: { emoji in
          toggleReaction(messageId: message.id, emoji: emoji, alreadyReacted: false)
        }
      )
      .padding(.horizontal, 12)
      .padding(.top, isFirst ? 8 : 2)
      .padding(.bottom, isLast ? 8 : 2)
      .id(message.id)
    }
  }
```

**Step 2: Update MessageBubble to display reactions and context menu**

Add new parameters to `MessageBubble` after `showSeenIndicator`:

```swift
  var reactions: [MessageReaction] = []
  var myAccountIds: Set<String> = []
  var onReactionTap: ((String, Bool) -> Void)?
  var onReactionAdd: ((String) -> Void)?
```

Define the quick-pick emojis as a static:

```swift
  private static let quickReactions = ["❤️", "👍", "😂", "😮", "😢", "🔥"]
```

Add the reactions view and context menu to the body. The VStack inside the HStack becomes:

```swift
      VStack(alignment: isFromMe ? .trailing : .leading, spacing: 2) {
        messageContent
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(bubbleColor)
          .foregroundColor(isFromMe ? .white : .primary)
          .clipShape(BubbleShape(isFromMe: isFromMe, hasTail: isLastInGroup))
          .contextMenu {
            if platform == .bluesky {
              ForEach(Self.quickReactions, id: \.self) { emoji in
                Button {
                  onReactionAdd?(emoji)
                } label: {
                  Text(emoji)
                }
              }
            }
          }

        if !reactions.isEmpty {
          MessageReactionView(
            reactions: reactions,
            platform: platform,
            myAccountIds: myAccountIds
          ) { emoji, isFromMe in
            onReactionTap?(emoji, isFromMe)
          }
          .frame(maxWidth: 200)
        }

        if isLastInGroup {
          Text(message.sentAt, style: .time)
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
        }

        if showSeenIndicator {
          Text("Seen")
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
        }
      }
```

**Step 3: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add SocialFusion/Views/Messages/ChatView.swift SocialFusion/Views/Messages/MessageBubble.swift
git commit -m "feat(messages): wire reactions into ChatView and MessageBubble with context menu"
```

---

## Task 9: Message Deletion — BlueskyService API and SocialServiceManager

**Files:**
- Modify: `SocialFusion/Services/BlueskyService.swift` (after `removeReaction` method)
- Modify: `SocialFusion/Services/SocialServiceManager.swift` (after reaction methods)

**Step 1: Add deleteMessage to BlueskyService**

```swift
  /// Delete a chat message
  internal func deleteMessage(convoId: String, messageId: String, for account: SocialAccount) async throws {
    guard let accessToken = account.accessToken else {
      throw BlueskyTokenError.noAccessToken
    }

    let apiURL = "\(getChatProxyURL(for: account))/chat.bsky.convo.deleteMessageForSelf"
    guard let url = URL(string: apiURL) else {
      throw BlueskyTokenError.invalidServerURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let body: [String: Any] = ["convoId": convoId, "messageId": messageId]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (_, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
      throw BlueskyTokenError.invalidResponse
    }
  }
```

**Step 2: Add unified deleteMessage to SocialServiceManager**

```swift
  /// Delete a message in a conversation
  public func deleteChatMessage(conversation: DMConversation, messageId: String) async throws {
    guard let account = accounts.first(where: { $0.platform == conversation.platform }) else {
      throw ServiceError.invalidAccount(reason: "No account found")
    }

    switch conversation.platform {
    case .bluesky:
      try await blueskyService.deleteMessage(
        convoId: conversation.id, messageId: messageId, for: account
      )
    case .mastodon:
      // Mastodon DMs are posts — delete the status
      try await mastodonService.deletePost(id: messageId, account: account)
    }
  }
```

**Step 3: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED (verify `mastodonService.deletePost` method exists; if not, check the exact method name)

**Step 4: Commit**

```bash
git add SocialFusion/Services/BlueskyService.swift SocialFusion/Services/SocialServiceManager.swift
git commit -m "feat(messages): add deleteMessage API for Bluesky and Mastodon"
```

---

## Task 10: Message Deletion & Editing — ChatView Context Menu and UI

**Files:**
- Modify: `SocialFusion/Views/Messages/ChatView.swift`
- Modify: `SocialFusion/Views/Messages/MessageBubble.swift`

**Step 1: Add editing and deletion state to ChatView**

Add after the `reactions` state:

```swift
  @State private var editingMessage: UnifiedChatMessage?
  @State private var deleteConfirmMessage: UnifiedChatMessage?
```

Add an editing banner above the input bar. Replace the `inputBar` computed property:

```swift
  private var inputBar: some View {
    VStack(spacing: 0) {
      Divider()

      if let editing = editingMessage {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Editing")
              .font(.caption)
              .fontWeight(.semibold)
              .foregroundColor(platformColor)
            Text(editing.text)
              .font(.caption)
              .foregroundColor(.secondary)
              .lineLimit(1)
          }
          Spacer()
          Button {
            editingMessage = nil
            newMessageText = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundColor(.secondary)
          }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
      }

      HStack(spacing: 12) {
        TextField("Message...", text: $newMessageText, axis: .vertical)
          .lineLimit(1...5)
          .padding(10)
          .background(Color(.systemGray6))
          .cornerRadius(20)

        sendButton
      }
      .padding(.horizontal)
      .padding(.vertical, 8)
      .background(Color(.systemBackground))
    }
  }
```

Add a delete confirmation alert. Add to the body modifiers (after the existing `.alert`):

```swift
    .alert("Delete Message", isPresented: Binding(
      get: { deleteConfirmMessage != nil },
      set: { if !$0 { deleteConfirmMessage = nil } }
    )) {
      Button("Delete", role: .destructive) {
        if let msg = deleteConfirmMessage {
          deleteMessage(msg)
        }
      }
      Button("Cancel", role: .cancel) { deleteConfirmMessage = nil }
    } message: {
      Text("This message will be deleted. This can't be undone.")
    }
```

Add the delete method:

```swift
  private func deleteMessage(_ message: UnifiedChatMessage) {
    // Optimistic removal with animation
    withAnimation {
      messages.removeAll { $0.id == message.id }
    }
    Task {
      do {
        try await serviceManager.deleteChatMessage(conversation: conversation, messageId: message.id)
      } catch {
        // Rollback — reload messages
        loadMessages()
        errorMessage = "Failed to delete message"
      }
    }
  }
```

Modify `sendMessage()` to handle editing. Replace the existing `sendMessage` method:

```swift
  private func sendMessage() {
    guard !newMessageText.isEmpty, !isSending else { return }
    let text = newMessageText
    newMessageText = ""
    isSending = true
    errorMessage = nil

    if let editing = editingMessage {
      // Edit existing message (Mastodon only)
      editingMessage = nil
      Task {
        do {
          try await serviceManager.editChatMessage(
            conversation: conversation, messageId: editing.id, newText: text
          )
          // Reload to get updated content
          let fetched = try await serviceManager.fetchConversationMessages(conversation: conversation)
          self.messages = fetched.reversed()
          self.isSending = false
        } catch {
          self.errorMessage = "Failed to edit message: \(error.localizedDescription)"
          self.isSending = false
        }
      }
    } else {
      Task {
        do {
          let sent = try await serviceManager.sendChatMessage(conversation: conversation, text: text)
          self.messages.append(sent)
          self.isSending = false
        } catch {
          self.errorMessage = "Failed to send message: \(error.localizedDescription)"
          self.newMessageText = text
          self.isSending = false
        }
      }
    }
  }
```

**Step 2: Add context menu actions to MessageBubble**

Add new parameters:

```swift
  var onDelete: (() -> Void)?
  var onEdit: (() -> Void)?
```

Update the context menu on `messageContent` to include delete and edit:

```swift
          .contextMenu {
            if platform == .bluesky {
              Section("React") {
                ForEach(Self.quickReactions, id: \.self) { emoji in
                  Button {
                    onReactionAdd?(emoji)
                  } label: {
                    Text(emoji)
                  }
                }
              }
            }

            if isFromMe {
              if platform == .mastodon {
                Button {
                  onEdit?()
                } label: {
                  Label("Edit Message", systemImage: "pencil")
                }
              }
              Button(role: .destructive) {
                onDelete?()
              } label: {
                Label("Delete Message", systemImage: "trash")
              }
            }

            Button {
              UIPasteboard.general.string = message.text
            } label: {
              Label("Copy Text", systemImage: "doc.on.doc")
            }
          }
```

**Step 3: Wire onDelete and onEdit in ChatView's messageGroupView**

Update the `MessageBubble` initializer in `messageGroupView` to pass the handlers:

```swift
        onDelete: {
          deleteConfirmMessage = message
        },
        onEdit: {
          editingMessage = message
          newMessageText = message.text
        }
```

**Step 4: Add editChatMessage to SocialServiceManager** (if not already present)

In `SocialServiceManager.swift`, add:

```swift
  /// Edit a chat message (Mastodon only — DMs are posts)
  public func editChatMessage(conversation: DMConversation, messageId: String, newText: String) async throws {
    guard conversation.platform == .mastodon,
          let account = accounts.first(where: { $0.platform == .mastodon }) else { return }
    let content = "@\(conversation.participant.username) \(newText)"
    _ = try await mastodonService.editPost(
      id: messageId, content: content, mediaAttachments: [], mediaAltTexts: [],
      pollOptions: [], pollExpiresIn: nil, visibility: "direct", account: account
    )
  }
```

**Step 5: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED (check that `mastodonService.editPost` exists — if method signature differs, adapt)

**Step 6: Commit**

```bash
git add SocialFusion/Views/Messages/ChatView.swift SocialFusion/Views/Messages/MessageBubble.swift SocialFusion/Services/SocialServiceManager.swift
git commit -m "feat(messages): add message deletion and editing with context menu"
```

---

## Task 11: Typing Indicators — Models and Protocol

**Files:**
- Modify: `SocialFusion/Models/ChatStreamModels.swift`
- Modify: `SocialFusion/Services/ChatStreamProvider.swift`
- Modify: `SocialFusion/Services/BlueskyPollStreamProvider.swift`
- Modify: `SocialFusion/Services/MastodonChatStreamProvider.swift`

**Step 1: Add typingIndicator event to ChatStreamModels.swift**

Add the new case to `UnifiedChatEvent` (after `reactionRemoved`):

```swift
  case typingIndicator(ChatEventTypingIndicator)
```

Add to the `id` computed property:

```swift
    case .typingIndicator(let t): return "typing-\(t.conversationId)-\(t.senderId)"
```

Add to the `conversationId` computed property:

```swift
    case .typingIndicator(let t): return t.conversationId
```

Add the payload struct at the end of the file:

```swift
struct ChatEventTypingIndicator {
  let conversationId: String
  let senderId: String
  let platform: SocialPlatform
}
```

**Step 2: Add sendTypingIndicator to ChatStreamProvider protocol**

```swift
protocol ChatStreamProvider {
  func eventStream(for account: SocialAccount, conversationId: String?) -> AsyncStream<UnifiedChatEvent>
  func stop()
  func sendTypingIndicator(conversationId: String, account: SocialAccount) async
  var connectionState: ChatConnectionState { get }
}
```

**Step 3: Add no-op implementations to both providers**

In `BlueskyPollStreamProvider.swift`, add:

```swift
  func sendTypingIndicator(conversationId: String, account: SocialAccount) async {
    // No Bluesky API for typing indicators yet
  }
```

In `MastodonChatStreamProvider.swift`, add:

```swift
  func sendTypingIndicator(conversationId: String, account: SocialAccount) async {
    // No Mastodon API for typing indicators yet
  }
```

**Step 4: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add SocialFusion/Models/ChatStreamModels.swift SocialFusion/Services/ChatStreamProvider.swift SocialFusion/Services/BlueskyPollStreamProvider.swift SocialFusion/Services/MastodonChatStreamProvider.swift
git commit -m "feat(messages): add typing indicator event type and protocol method (no-op)"
```

---

## Task 12: Typing Indicators — TypingIndicatorBubble Component

**Files:**
- Create: `SocialFusion/Views/Messages/TypingIndicatorBubble.swift`

**Step 1: Create the animated three-dot bubble**

```swift
import SwiftUI

struct TypingIndicatorBubble: View {
  @State private var animationPhase = 0

  private let dotSize: CGFloat = 8
  private let dotColor = Color.secondary

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      Color.clear.frame(width: 28, height: 28) // Avatar space

      HStack(spacing: 4) {
        ForEach(0..<3, id: \.self) { index in
          Circle()
            .fill(dotColor)
            .frame(width: dotSize, height: dotSize)
            .offset(y: animationPhase == index ? -4 : 0)
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(Color(.systemGray5))
      .clipShape(BubbleShape(isFromMe: false, hasTail: true))

      Spacer(minLength: 60)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .onAppear { startAnimation() }
  }

  private func startAnimation() {
    withAnimation(
      .easeInOut(duration: 0.3)
      .repeatForever(autoreverses: true)
    ) {
      animationPhase = 0
    }

    // Stagger the dots
    Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { timer in
      withAnimation(.easeInOut(duration: 0.3)) {
        animationPhase = (animationPhase + 1) % 3
      }
    }
  }
}
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SocialFusion/Views/Messages/TypingIndicatorBubble.swift SocialFusion.xcodeproj/project.pbxproj
git commit -m "feat(messages): add TypingIndicatorBubble animated component"
```

---

## Task 13: Typing Indicators — Wire into ChatView

**Files:**
- Modify: `SocialFusion/Views/Messages/ChatView.swift`

**Step 1: Add typing state and display**

Add state after `deleteConfirmMessage`:

```swift
  @State private var isOtherTyping = false
  @State private var typingDismissTask: Task<Void, Never>?
```

In `handleStreamEvents`, add case for typing:

```swift
      case .typingIndicator:
        isOtherTyping = true
        typingDismissTask?.cancel()
        typingDismissTask = Task {
          try? await Task.sleep(for: .seconds(5))
          guard !Task.isCancelled else { return }
          isOtherTyping = false
        }
```

In `messagesList`, after the `ForEach` of grouped messages (inside the `LazyVStack`, before the closing `}`):

```swift
            if isOtherTyping {
              TypingIndicatorBubble()
            }
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SocialFusion/Views/Messages/ChatView.swift
git commit -m "feat(messages): display typing indicator bubble in ChatView"
```

---

## Task 14: Conversation Muting — Model Update and API Calls

**Files:**
- Modify: `SocialFusion/Models/Post.swift` (DMConversation struct, ~line 1531)
- Modify: `SocialFusion/Services/BlueskyService.swift`
- Modify: `SocialFusion/Services/SocialServiceManager.swift`

**Step 1: Add isMuted to DMConversation**

Update the `DMConversation` struct:

```swift
public struct DMConversation: Identifiable, Codable, Sendable {
    public let id: String
    public let participant: NotificationAccount
    public let lastMessage: DirectMessage
    public let unreadCount: Int
    public let platform: SocialPlatform
    public let isMuted: Bool

    public init(
        id: String, participant: NotificationAccount, lastMessage: DirectMessage, unreadCount: Int,
        platform: SocialPlatform, isMuted: Bool = false
    ) {
        self.id = id
        self.participant = participant
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
        self.platform = platform
        self.isMuted = isMuted
    }
}
```

**Step 2: Add mute/unmute/leave to BlueskyService**

```swift
  /// Mute a conversation
  internal func muteConvo(convoId: String, for account: SocialAccount) async throws {
    guard let accessToken = account.accessToken else { throw BlueskyTokenError.noAccessToken }
    let apiURL = "\(getChatProxyURL(for: account))/chat.bsky.convo.muteConvo"
    guard let url = URL(string: apiURL) else { throw BlueskyTokenError.invalidServerURL }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["convoId": convoId])
    let (_, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
      throw BlueskyTokenError.invalidResponse
    }
  }

  /// Unmute a conversation
  internal func unmuteConvo(convoId: String, for account: SocialAccount) async throws {
    guard let accessToken = account.accessToken else { throw BlueskyTokenError.noAccessToken }
    let apiURL = "\(getChatProxyURL(for: account))/chat.bsky.convo.unmuteConvo"
    guard let url = URL(string: apiURL) else { throw BlueskyTokenError.invalidServerURL }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["convoId": convoId])
    let (_, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
      throw BlueskyTokenError.invalidResponse
    }
  }

  /// Leave a conversation
  internal func leaveConvo(convoId: String, for account: SocialAccount) async throws {
    guard let accessToken = account.accessToken else { throw BlueskyTokenError.noAccessToken }
    let apiURL = "\(getChatProxyURL(for: account))/chat.bsky.convo.leaveConvo"
    guard let url = URL(string: apiURL) else { throw BlueskyTokenError.invalidServerURL }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["convoId": convoId])
    let (_, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
      throw BlueskyTokenError.invalidResponse
    }
  }
```

**Step 3: Add unified methods to SocialServiceManager**

```swift
  /// Mute a conversation
  public func muteConversation(_ conversation: DMConversation) async throws {
    guard let account = accounts.first(where: { $0.platform == conversation.platform }) else { return }
    switch conversation.platform {
    case .bluesky:
      try await blueskyService.muteConvo(convoId: conversation.id, for: account)
    case .mastodon:
      // Mastodon doesn't have a direct conversation mute in the same way
      break
    }
  }

  /// Unmute a conversation
  public func unmuteConversation(_ conversation: DMConversation) async throws {
    guard let account = accounts.first(where: { $0.platform == conversation.platform }) else { return }
    switch conversation.platform {
    case .bluesky:
      try await blueskyService.unmuteConvo(convoId: conversation.id, for: account)
    case .mastodon:
      break
    }
  }

  /// Leave a conversation (Bluesky only)
  public func leaveConversation(_ conversation: DMConversation) async throws {
    guard conversation.platform == .bluesky,
          let account = accounts.first(where: { $0.platform == .bluesky }) else { return }
    try await blueskyService.leaveConvo(convoId: conversation.id, for: account)
  }
```

**Step 4: Update fetchDirectMessages to populate isMuted**

In the Bluesky mapping section of `fetchDirectMessages()`, pass `isMuted: convo.muted`:

Find the `DMConversation(` initialization for Bluesky convos and add `isMuted: convo.muted`.

**Step 5: Fix all other DMConversation initializations**

Search for all `DMConversation(` calls and add `isMuted: false` where not already present (Mastodon mapping, stream event handling in MessagesViewModel, startOrFindBlueskyConversation, etc.).

**Step 6: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 7: Commit**

```bash
git add SocialFusion/Models/Post.swift SocialFusion/Services/BlueskyService.swift SocialFusion/Services/SocialServiceManager.swift SocialFusion/ViewModels/MessagesViewModel.swift
git commit -m "feat(messages): add isMuted to DMConversation and mute/unmute/leave APIs"
```

---

## Task 15: Conversation Settings — ConversationSettingsView

**Files:**
- Create: `SocialFusion/Views/Messages/ConversationSettingsView.swift`

**Step 1: Create the settings sheet**

```swift
import SwiftUI

struct ConversationSettingsView: View {
  @EnvironmentObject var serviceManager: SocialServiceManager
  @Environment(\.dismiss) private var dismiss
  let conversation: DMConversation
  let onLeave: () -> Void

  @State private var isMuted: Bool
  @State private var showLeaveConfirm = false
  @State private var isUpdating = false

  init(conversation: DMConversation, onLeave: @escaping () -> Void) {
    self.conversation = conversation
    self.onLeave = onLeave
    _isMuted = State(initialValue: conversation.isMuted)
  }

  var body: some View {
    NavigationStack {
      List {
        // Participant info
        Section {
          HStack(spacing: 12) {
            if let urlString = conversation.participant.avatarURL,
               let url = URL(string: urlString) {
              CachedAsyncImage(url: url, priority: .high) { image in
                image.resizable().aspectRatio(contentMode: .fill)
              } placeholder: {
                Circle().fill(Color.gray.opacity(0.3))
              }
              .frame(width: 56, height: 56)
              .clipShape(Circle())
            } else {
              Circle().fill(Color.gray.opacity(0.3))
                .frame(width: 56, height: 56)
            }

            VStack(alignment: .leading, spacing: 4) {
              if let name = conversation.participant.displayName {
                Text(name)
                  .font(.headline)
              }
              Text("@\(conversation.participant.username)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            Spacer()

            PostPlatformBadge(platform: conversation.platform)
              .scaleEffect(0.85)
          }
          .listRowBackground(Color.clear)
        }

        // Settings
        Section {
          if conversation.platform == .bluesky {
            Toggle("Mute Conversation", isOn: $isMuted)
              .disabled(isUpdating)
              .onChange(of: isMuted) { _, newValue in
                toggleMute(muted: newValue)
              }
          }
        } footer: {
          if conversation.platform == .bluesky {
            Text("Muted conversations won't send notifications.")
          }
        }

        // Destructive actions
        if conversation.platform == .bluesky {
          Section {
            Button(role: .destructive) {
              showLeaveConfirm = true
            } label: {
              Label("Leave Conversation", systemImage: "arrow.right.square")
            }
          }
        }
      }
      .navigationTitle("Conversation")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .alert("Leave Conversation", isPresented: $showLeaveConfirm) {
        Button("Leave", role: .destructive) {
          leaveConversation()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("You'll no longer see this conversation.")
      }
    }
  }

  private func toggleMute(muted: Bool) {
    isUpdating = true
    Task {
      do {
        if muted {
          try await serviceManager.muteConversation(conversation)
        } else {
          try await serviceManager.unmuteConversation(conversation)
        }
      } catch {
        isMuted = !muted // Rollback
      }
      isUpdating = false
    }
  }

  private func leaveConversation() {
    Task {
      do {
        try await serviceManager.leaveConversation(conversation)
        dismiss()
        onLeave()
      } catch {
        // Show error
      }
    }
  }
}
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SocialFusion/Views/Messages/ConversationSettingsView.swift SocialFusion.xcodeproj/project.pbxproj
git commit -m "feat(messages): add ConversationSettingsView with mute toggle and leave"
```

---

## Task 16: Conversation Settings — Wire into ChatView and Swipe Actions

**Files:**
- Modify: `SocialFusion/Views/Messages/ChatView.swift`
- Modify: `SocialFusion/Views/Messages/DMConversationRow.swift`
- Modify: `SocialFusion/Views/Messages/DirectMessagesView.swift`

**Step 1: Add info button and settings sheet to ChatView**

Add state:

```swift
  @State private var showSettings = false
```

Add toolbar item (after the existing `ToolbarItem` for `navAvatar`):

```swift
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showSettings = true
        } label: {
          Image(systemName: "info.circle")
            .foregroundColor(.secondary)
        }
      }
```

Add sheet modifier to the body:

```swift
    .sheet(isPresented: $showSettings) {
      ConversationSettingsView(conversation: conversation) {
        // onLeave — pop back to messages list
      }
      .environmentObject(serviceManager)
    }
```

**Step 2: Add muted icon to DMConversationRow**

In `DMConversationRow.swift`, add a muted speaker icon next to the timestamp when `conversation.isMuted`:

```swift
  if conversation.isMuted {
    Image(systemName: "speaker.slash.fill")
      .font(.caption2)
      .foregroundColor(.secondary)
  }
```

**Step 3: Add swipe actions to DirectMessagesView**

In `DirectMessagesView.swift`, on the `NavigationLink` for each conversation row, add:

```swift
  .swipeActions(edge: .trailing) {
    Button(role: .destructive) {
      // TODO: Delete/leave conversation
    } label: {
      Label("Delete", systemImage: "trash")
    }

    Button {
      Task {
        if conversation.isMuted {
          try? await serviceManager.unmuteConversation(conversation)
        } else {
          try? await serviceManager.muteConversation(conversation)
        }
        await viewModel.fetchConversations(serviceManager: serviceManager)
      }
    } label: {
      Label(
        conversation.isMuted ? "Unmute" : "Mute",
        systemImage: conversation.isMuted ? "speaker" : "speaker.slash"
      )
    }
    .tint(.orange)
  }
```

Note: Swipe actions require the list items to be inside a `List` or use `.swipeActions` on items in a `LazyVStack` with iOS 17+. If the current `ScrollView` + `LazyVStack` structure doesn't support `.swipeActions`, we may need to convert to a `List`. Evaluate during implementation.

**Step 4: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add SocialFusion/Views/Messages/ChatView.swift SocialFusion/Views/Messages/DMConversationRow.swift SocialFusion/Views/Messages/DirectMessagesView.swift
git commit -m "feat(messages): wire conversation settings, muted indicator, and swipe actions"
```

---

## Task 17: Conversation Muting — Stream Event Handling

**Files:**
- Modify: `SocialFusion/ViewModels/MessagesViewModel.swift`

**Step 1: Handle mute/unmute events in MessagesViewModel**

In `handleStreamEvents`, update the `conversationUpdated` handling:

```swift
      case .conversationUpdated(let update):
        switch update.kind {
        case .began:
          Task { await fetchConversations(serviceManager: serviceManager) }
        case .muted:
          if let index = conversations.firstIndex(where: { $0.id == update.conversationId }) {
            let conv = conversations[index]
            conversations[index] = DMConversation(
              id: conv.id, participant: conv.participant,
              lastMessage: conv.lastMessage, unreadCount: conv.unreadCount,
              platform: conv.platform, isMuted: true
            )
          }
        case .unmuted:
          if let index = conversations.firstIndex(where: { $0.id == update.conversationId }) {
            let conv = conversations[index]
            conversations[index] = DMConversation(
              id: conv.id, participant: conv.participant,
              lastMessage: conv.lastMessage, unreadCount: conv.unreadCount,
              platform: conv.platform, isMuted: false
            )
          }
        case .left:
          conversations.removeAll { $0.id == update.conversationId }
        case .accepted:
          Task { await fetchConversations(serviceManager: serviceManager) }
        }
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SocialFusion/ViewModels/MessagesViewModel.swift
git commit -m "feat(messages): handle mute/unmute/leave stream events in MessagesViewModel"
```

---

## Task 18: Media Attachments — Model Extensions

**Files:**
- Modify: `SocialFusion/Models/Post.swift` (UnifiedChatMessage extension)
- Modify: `SocialFusion/Models/BlueskyModels.swift` (add embed types if needed)

**Step 1: Add mediaAttachments computed property to UnifiedChatMessage**

After the existing `UnifiedChatMessage` computed properties, add:

```swift
  public var mediaAttachments: [MediaAttachment] {
    switch self {
    case .bluesky(let msg):
      // Bluesky chat messages don't currently carry media embeds in the standard API
      // This is infrastructure for when they do
      return []
    case .mastodon(let post):
      return post.mediaAttachments
    }
  }

  public var hasMedia: Bool {
    !mediaAttachments.isEmpty
  }
```

Note: `MediaAttachment` is the existing type used by Mastodon posts. Verify the exact type name used in the project (may be `Post.MediaAttachment` or similar). Adapt accordingly.

**Step 2: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SocialFusion/Models/Post.swift
git commit -m "feat(messages): add mediaAttachments computed property to UnifiedChatMessage"
```

---

## Task 19: Media Attachments — ChatMediaPickerBar Component

**Files:**
- Create: `SocialFusion/Views/Messages/ChatMediaPickerBar.swift`

**Step 1: Create the thumbnail strip component**

```swift
import SwiftUI
import PhotosUI

struct ChatMediaPickerBar: View {
  @Binding var selectedItems: [PhotosPickerItem]
  @State private var thumbnails: [String: Image] = [:]

  var body: some View {
    if !selectedItems.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(Array(selectedItems.enumerated()), id: \.offset) { index, item in
            ZStack(alignment: .topTrailing) {
              if let thumb = thumbnails["\(index)"] {
                thumb
                  .resizable()
                  .aspectRatio(contentMode: .fill)
                  .frame(width: 60, height: 60)
                  .clipShape(RoundedRectangle(cornerRadius: 8))
              } else {
                RoundedRectangle(cornerRadius: 8)
                  .fill(Color(.systemGray5))
                  .frame(width: 60, height: 60)
                  .overlay(ProgressView().scaleEffect(0.6))
              }

              Button {
                selectedItems.remove(at: index)
                thumbnails.removeValue(forKey: "\(index)")
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .font(.system(size: 18))
                  .foregroundColor(.white)
                  .background(Circle().fill(Color.black.opacity(0.5)))
              }
              .offset(x: 4, y: -4)
            }
            .task {
              if let data = try? await item.loadTransferable(type: Data.self),
                 let uiImage = UIImage(data: data) {
                thumbnails["\(index)"] = Image(uiImage: uiImage)
              }
            }
          }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
      }
      .background(Color(.systemGray6))
    }
  }
}
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SocialFusion/Views/Messages/ChatMediaPickerBar.swift SocialFusion.xcodeproj/project.pbxproj
git commit -m "feat(messages): add ChatMediaPickerBar thumbnail strip component"
```

---

## Task 20: Media Attachments — Wire into ChatView Input Bar

**Files:**
- Modify: `SocialFusion/Views/Messages/ChatView.swift`

**Step 1: Add media picking state and PhotosPicker**

Add import at top:

```swift
import PhotosUI
```

Add state:

```swift
  @State private var selectedMedia: [PhotosPickerItem] = []
```

Update `inputBar` to include the media picker button and thumbnail bar:

In the `HStack` of the input bar, add a PhotosPicker before the TextField:

```swift
      HStack(spacing: 12) {
        PhotosPicker(selection: $selectedMedia, maxSelectionCount: 4, matching: .images) {
          Image(systemName: "plus.circle.fill")
            .font(.system(size: 24))
            .foregroundColor(.secondary)
        }

        TextField("Message...", text: $newMessageText, axis: .vertical)
          .lineLimit(1...5)
          .padding(10)
          .background(Color(.systemGray6))
          .cornerRadius(20)

        sendButton
      }
```

Add the `ChatMediaPickerBar` above the input HStack (after the editing banner, before the HStack):

```swift
      ChatMediaPickerBar(selectedItems: $selectedMedia)
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SocialFusion/Views/Messages/ChatView.swift
git commit -m "feat(messages): add photo picker and media thumbnail bar to chat input"
```

---

## Task 21: Media Attachments — Display in MessageBubble

**Files:**
- Modify: `SocialFusion/Views/Messages/MessageBubble.swift`

**Step 1: Render media above text in the bubble**

This task renders any media attachments that come with received messages (primarily Mastodon DMs which are posts with media). Add a media display section inside the bubble's VStack, above `messageContent`:

Check the exact type for media attachments in the project. The approach:
- If `message.hasMedia`, render a compact image grid above the text
- Use `CachedAsyncImage` for each attachment
- Max width ~200pt to fit within bubble
- Tap opens fullscreen (present `FullscreenMediaView`)

The exact implementation depends on the `MediaAttachment` type structure in the project. Review `Post.swift` for the media attachment model and `MediaGridView` for the existing grid component.

Add a parameter to MessageBubble:

```swift
  var onMediaTap: ((Int) -> Void)?
```

In the bubble body, before `messageContent`:

```swift
        if message.hasMedia {
          let attachments = message.mediaAttachments
          LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2)
          ], spacing: 2) {
            ForEach(Array(attachments.prefix(4).enumerated()), id: \.offset) { index, attachment in
              if let url = URL(string: attachment.previewURL ?? attachment.url) {
                CachedAsyncImage(url: url, priority: .normal) { image in
                  image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                  Color(.systemGray5)
                }
                .frame(minHeight: 80, maxHeight: 120)
                .clipped()
                .onTapGesture { onMediaTap?(index) }
              }
            }
          }
          .frame(maxWidth: 200)
          .clipShape(RoundedRectangle(cornerRadius: 8))
        }
```

Note: Adapt the attachment property names (`previewURL`, `url`) to match the actual model. Check during implementation.

**Step 2: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SocialFusion/Views/Messages/MessageBubble.swift
git commit -m "feat(messages): display media attachments in message bubbles"
```

---

## Task 22: Search Within Conversations — ChatView Search UI

**Files:**
- Modify: `SocialFusion/Views/Messages/ChatView.swift`
- Modify: `SocialFusion/Views/Messages/MessageBubble.swift`

**Step 1: Add search state to ChatView**

```swift
  @State private var isSearching = false
  @State private var searchText = ""
  @State private var currentMatchIndex = 0
```

Add computed property for matching message IDs:

```swift
  private var matchingMessageIds: [String] {
    guard !searchText.isEmpty else { return [] }
    return messages.filter {
      $0.text.localizedCaseInsensitiveContains(searchText)
    }.map(\.id)
  }
```

**Step 2: Add search toolbar button**

Add to toolbar (after the info button):

```swift
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          withAnimation { isSearching.toggle() }
          if !isSearching {
            searchText = ""
            currentMatchIndex = 0
          }
        } label: {
          Image(systemName: isSearching ? "xmark" : "magnifyingglass")
            .foregroundColor(.secondary)
        }
      }
```

**Step 3: Add search bar overlay**

Add above `messagesList` in the VStack:

```swift
      if isSearching {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
            .foregroundColor(.secondary)
          TextField("Search messages...", text: $searchText)
            .textFieldStyle(.plain)

          if !matchingMessageIds.isEmpty {
            Text("\(currentMatchIndex + 1) of \(matchingMessageIds.count)")
              .font(.caption)
              .foregroundColor(.secondary)
              .fixedSize()

            Button {
              currentMatchIndex = max(0, currentMatchIndex - 1)
            } label: {
              Image(systemName: "chevron.up")
                .foregroundColor(.secondary)
            }
            .disabled(currentMatchIndex == 0)

            Button {
              currentMatchIndex = min(matchingMessageIds.count - 1, currentMatchIndex + 1)
            } label: {
              Image(systemName: "chevron.down")
                .foregroundColor(.secondary)
            }
            .disabled(currentMatchIndex >= matchingMessageIds.count - 1)
          }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
      }
```

**Step 4: Add searchHighlight to MessageBubble**

Add enum and parameter:

```swift
  enum SearchHighlight {
    case none, matched, focused
  }

  var searchHighlight: SearchHighlight = .none
```

In the body, wrap the entire HStack with opacity:

```swift
    .opacity(searchHighlight == .none || searchHighlight == .matched || searchHighlight == .focused ? 1 : 1)
```

Actually, apply dimming to non-matching messages. The simplest approach: add an opacity modifier to the entire bubble HStack:

After the closing `}` of the main HStack in the body, but as a modifier on it:

```swift
    .opacity(searchHighlightOpacity)
```

With helper:

```swift
  private var searchHighlightOpacity: Double {
    switch searchHighlight {
    case .none: return 1.0
    case .matched: return 1.0
    case .focused: return 1.0
    }
  }
```

And add a background highlight for matched/focused bubbles on the `messageContent`:

```swift
  private var highlightBackground: Color? {
    switch searchHighlight {
    case .focused: return Color.yellow.opacity(0.3)
    case .matched: return Color.yellow.opacity(0.15)
    case .none: return nil
    }
  }
```

Apply as an overlay on the bubble shape.

**Step 5: Wire in ChatView messageGroupView**

Pass `searchHighlight` based on whether the message matches:

```swift
        let highlight: MessageBubble.SearchHighlight = {
          guard !searchText.isEmpty else { return .none }
          if !matchingMessageIds.contains(message.id) { return .none }
          if matchingMessageIds.indices.contains(currentMatchIndex),
             matchingMessageIds[currentMatchIndex] == message.id {
            return .focused
          }
          return .matched
        }()
```

And if searching, dim non-matching messages by wrapping the MessageBubble:

```swift
        .opacity(!searchText.isEmpty && !matchingMessageIds.contains(message.id) ? 0.3 : 1.0)
```

**Step 6: Scroll to focused match**

In `messagesList`, add an `onChange` of `currentMatchIndex`:

```swift
      .onChange(of: currentMatchIndex) { _, newIndex in
        if matchingMessageIds.indices.contains(newIndex) {
          withAnimation {
            proxy.scrollTo(matchingMessageIds[newIndex], anchor: .center)
          }
        }
      }
```

Note: The `proxy` from `ScrollViewReader` needs to be accessible here. This may require restructuring slightly.

**Step 7: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 8: Commit**

```bash
git add SocialFusion/Views/Messages/ChatView.swift SocialFusion/Views/Messages/MessageBubble.swift
git commit -m "feat(messages): add in-conversation search with highlight and navigation"
```

---

## Task 23: Group Conversations — Model Refactor

**Files:**
- Modify: `SocialFusion/Models/Post.swift` (DMConversation)
- Modify: `SocialFusion/Services/SocialServiceManager.swift` (all DMConversation initializations)
- Modify: `SocialFusion/ViewModels/MessagesViewModel.swift` (DMConversation initializations)

**Step 1: Replace participant with participants in DMConversation**

```swift
public struct DMConversation: Identifiable, Codable, Sendable {
    public let id: String
    public let participants: [NotificationAccount]
    public let lastMessage: DirectMessage
    public let unreadCount: Int
    public let platform: SocialPlatform
    public let isMuted: Bool

    /// Convenience for 1-on-1 conversations
    public var participant: NotificationAccount {
      participants.first ?? NotificationAccount(
        id: "", username: "unknown", displayName: "Unknown", avatarURL: nil
      )
    }

    public var isGroup: Bool { participants.count > 1 }

    public var title: String? {
      guard isGroup else { return nil }
      let names = participants.compactMap(\.displayName).prefix(3)
      if names.isEmpty { return participants.map(\.username).prefix(3).joined(separator: ", ") }
      return names.joined(separator: ", ")
    }

    public init(
        id: String, participants: [NotificationAccount], lastMessage: DirectMessage, unreadCount: Int,
        platform: SocialPlatform, isMuted: Bool = false
    ) {
        self.id = id
        self.participants = participants
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
        self.platform = platform
        self.isMuted = isMuted
    }

    /// Convenience init for backward compatibility with single participant
    public init(
        id: String, participant: NotificationAccount, lastMessage: DirectMessage, unreadCount: Int,
        platform: SocialPlatform, isMuted: Bool = false
    ) {
        self.init(
          id: id, participants: [participant], lastMessage: lastMessage,
          unreadCount: unreadCount, platform: platform, isMuted: isMuted
        )
    }
}
```

**Step 2: Update SocialServiceManager Bluesky mapping**

In `fetchDirectMessages()`, for Bluesky convos, pass all other members:

```swift
  let otherParticipants = convo.members
    .filter { $0.did != account.platformSpecificId }
    .map { member in
      NotificationAccount(
        id: member.did,
        username: member.handle,
        displayName: member.displayName,
        avatarURL: member.avatar
      )
    }
```

Use the `participants:` initializer:

```swift
  DMConversation(
    id: convo.id,
    participants: otherParticipants,
    lastMessage: lastMsg,
    unreadCount: convo.unreadCount,
    platform: .bluesky,
    isMuted: convo.muted
  )
```

**Step 3: Update all other DMConversation inits to use participant: convenience init**

Existing code using `participant:` should still compile thanks to the convenience init. Verify by building.

**Step 4: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED (the backward-compatible convenience init should prevent breakage)

**Step 5: Commit**

```bash
git add SocialFusion/Models/Post.swift SocialFusion/Services/SocialServiceManager.swift
git commit -m "refactor(messages): replace participant with participants array in DMConversation"
```

---

## Task 24: Group Conversations — GroupAvatarStack Component

**Files:**
- Create: `SocialFusion/Views/Messages/GroupAvatarStack.swift`

**Step 1: Create overlapping avatar component**

```swift
import SwiftUI

struct GroupAvatarStack: View {
  let avatarURLs: [String?]
  let size: CGFloat

  init(participants: [NotificationAccount], size: CGFloat = 40) {
    self.avatarURLs = participants.prefix(3).map(\.avatarURL)
    self.size = size
  }

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      ForEach(Array(avatarURLs.prefix(3).enumerated()), id: \.offset) { index, urlString in
        avatarImage(urlString: urlString)
          .frame(width: avatarSize(for: index), height: avatarSize(for: index))
          .clipShape(Circle())
          .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
          .offset(x: xOffset(for: index), y: yOffset(for: index))
      }
    }
    .frame(width: size, height: size)
  }

  @ViewBuilder
  private func avatarImage(urlString: String?) -> some View {
    if let urlString, let url = URL(string: urlString) {
      CachedAsyncImage(url: url, priority: .low) { image in
        image.resizable().aspectRatio(contentMode: .fill)
      } placeholder: {
        Circle().fill(Color.gray.opacity(0.3))
      }
    } else {
      Circle().fill(Color.gray.opacity(0.3))
    }
  }

  private func avatarSize(for index: Int) -> CGFloat {
    avatarURLs.count == 1 ? size : size * 0.65
  }

  private func xOffset(for index: Int) -> CGFloat {
    guard avatarURLs.count > 1 else { return 0 }
    switch index {
    case 0: return -size * 0.15
    case 1: return size * 0.15
    case 2: return 0
    default: return 0
    }
  }

  private func yOffset(for index: Int) -> CGFloat {
    guard avatarURLs.count > 2 else { return 0 }
    switch index {
    case 0: return -size * 0.1
    case 1: return -size * 0.1
    case 2: return size * 0.15
    default: return 0
    }
  }
}
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SocialFusion/Views/Messages/GroupAvatarStack.swift SocialFusion.xcodeproj/project.pbxproj
git commit -m "feat(messages): add GroupAvatarStack overlapping avatar component"
```

---

## Task 25: Group Conversations — DMConversationRow and ChatView Updates

**Files:**
- Modify: `SocialFusion/Views/Messages/DMConversationRow.swift`
- Modify: `SocialFusion/Views/Messages/ChatView.swift`

**Step 1: Update DMConversationRow for groups**

In `DMConversationRow`, conditionally show `GroupAvatarStack` when `conversation.isGroup`:
- Replace the single avatar with: `if conversation.isGroup { GroupAvatarStack(...) } else { /* existing avatar */ }`
- Show group title instead of single participant name
- Prefix last message with sender name for groups

**Step 2: Update ChatView for groups**

- Show sender name above first bubble in a message group from non-self sender
- Use group title in nav bar
- Add `senderName` parameter to `MessageBubble`

Add to `MessageBubble`:

```swift
  var senderName: String?
```

In the bubble VStack, before `messageContent`:

```swift
        if let name = senderName, isFirstInGroup {
          Text(name)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
        }
```

In ChatView's `messageGroupView`, pass the sender name for group conversations:

```swift
        let senderName: String? = conversation.isGroup && !group.isFromMe
          ? group.messages.first.flatMap { msg -> String? in
              // Get display name for the author
              conversation.participants.first { $0.id == msg.authorId }?.displayName
            }
          : nil
```

**Step 3: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add SocialFusion/Views/Messages/DMConversationRow.swift SocialFusion/Views/Messages/ChatView.swift SocialFusion/Views/Messages/MessageBubble.swift
git commit -m "feat(messages): update conversation row and chat view for group conversations"
```

---

## Task 26: Group Conversations — NewConversationView Multi-Select

**Files:**
- Modify: `SocialFusion/Views/Messages/NewConversationView.swift`

**Step 1: Add multi-select state**

```swift
  @State private var selectedParticipants: [BlueskyActor] = []
```

**Step 2: Add token/chip bar above search**

When `selectedParticipants` is non-empty, show a horizontal scroll of selected users as removable chips above the search results. Each chip shows the user's display name with an "x" button.

**Step 3: Change Bluesky row behavior**

Instead of immediately starting a conversation on tap, toggle selection. Add/remove from `selectedParticipants`.

**Step 4: Add "Create Group" button**

When `selectedParticipants.count >= 2`, show a prominent "Create Group" button that calls `getConvoForMembers` with all selected DIDs.

When `selectedParticipants.count == 1`, show "Start Conversation" (existing 1-on-1 flow).

**Step 5: Build to verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add SocialFusion/Views/Messages/NewConversationView.swift
git commit -m "feat(messages): add multi-select for group conversation creation (Bluesky)"
```

---

## Task 27: Final Build Verification and Install

**Step 1: Full clean build**

Run: `xcodebuild clean build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1`
Expected: BUILD SUCCEEDED with zero errors

**Step 2: Install and launch in simulator**

```bash
xcrun simctl install booted <path-to-app>
xcrun simctl launch booted com.socialfusionapp.app
```

**Step 3: Manual smoke test**

- Open Messages tab
- Verify conversation list loads
- Open a Bluesky conversation
- Long-press a message — verify context menu shows reactions (Bluesky) or edit/delete (Mastodon)
- Check for "Seen" indicator on sent messages
- Tap search icon — verify search bar appears
- Tap info icon — verify settings sheet opens

---

## Summary

| Task | Phase | Description |
|------|-------|-------------|
| 1-4 | 1: Read Receipts | API, service, viewmodel, UI |
| 5-8 | 2: Reactions | API, service, component, wiring |
| 9-10 | 3: Edit/Delete | API, context menu, editing UI |
| 11-13 | 4: Typing Indicators | Models, component, wiring |
| 14-17 | 5: Conversation Settings | Model, APIs, settings view, swipe actions |
| 18-21 | 6: Media Attachments | Model, picker, display |
| 22 | 7: Search | Search bar, highlighting, navigation |
| 23-26 | 8: Group Conversations | Model refactor, avatar stack, multi-select |
| 27 | — | Final build verification |

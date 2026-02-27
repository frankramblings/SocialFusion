# Messages Tab Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild the Messages tab UI from scratch — new file structure, ViewModel, iMessage-style chat, platform badges, new-conversation flow — on the existing production backend.

**Architecture:** Extract all messages UI into `SocialFusion/Views/Messages/` with a dedicated `MessagesViewModel`. ChatView keeps local state for one conversation. Backend services (ChatStreamService, API clients) are untouched except for a small Bluesky `getConvoForMembers` addition.

**Tech Stack:** SwiftUI, existing SocialServiceManager/ChatStreamService/BlueskyService/MastodonService

---

### Task 1: Create MessagesViewModel

**Files:**
- Create: `SocialFusion/ViewModels/MessagesViewModel.swift`

**Step 1: Create the ViewModel**

```swift
import SwiftUI
import Combine

@MainActor
class MessagesViewModel: ObservableObject {
  @Published var conversations: [DMConversation] = []
  @Published var isLoading = false
  @Published var errorMessage: String?
  @Published var showNewConversation = false

  private var cancellables = Set<AnyCancellable>()

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
              avatarURL: conv.participant.avatarURL,  // FIX: carry forward avatar
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
      case .conversationUpdated(let update) where update.kind == .began:
        Task { await fetchConversations(serviceManager: serviceManager) }
      default:
        break
      }
    }
  }
}
```

**Step 2: Build and verify no compiler errors**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SocialFusion/ViewModels/MessagesViewModel.swift
git commit -m "feat(messages): add MessagesViewModel with conversation state management"
```

---

### Task 2: Create DMConversationRow

**Files:**
- Create: `SocialFusion/Views/Messages/DMConversationRow.swift`

**Step 1: Create the conversation row view**

```swift
import SwiftUI

struct DMConversationRow: View {
  let conversation: DMConversation

  var body: some View {
    HStack(spacing: 12) {
      // Avatar
      avatarView

      // Content
      VStack(alignment: .leading, spacing: 4) {
        // Row 1: Display name + platform badge
        HStack {
          EmojiDisplayNameText(
            conversation.participant.displayName ?? conversation.participant.username,
            emojiMap: conversation.participant.displayNameEmojiMap,
            font: .headline,
            fontWeight: .semibold,
            foregroundColor: .primary,
            lineLimit: 1
          )

          Spacer()

          PostPlatformBadge(platform: conversation.platform)
            .scaleEffect(0.85)
        }

        // Row 2: @username · relative time
        HStack(spacing: 4) {
          Text("@\(conversation.participant.username)")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .lineLimit(1)

          Text("\u{00B7}")
            .font(.subheadline)
            .foregroundColor(.secondary)

          Text(conversation.lastMessage.createdAt, style: .relative)
            .font(.subheadline)
            .foregroundColor(.secondary)
        }

        // Row 3: Last message preview + unread dot
        HStack {
          Text(conversation.lastMessage.content)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .lineLimit(2)

          Spacer()

          if conversation.unreadCount > 0 {
            Circle()
              .fill(Color.blue)
              .frame(width: 10, height: 10)
          }
        }
      }
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private var avatarView: some View {
    if let avatarURL = conversation.participant.avatarURL,
       let url = URL(string: avatarURL) {
      CachedAsyncImage(url: url, priority: .high) { image in
        image.resizable()
          .aspectRatio(contentMode: .fill)
      } placeholder: {
        Circle().fill(Color.gray.opacity(0.3))
          .overlay(ProgressView().scaleEffect(0.5))
      }
      .frame(width: 48, height: 48)
      .clipShape(Circle())
    } else {
      Circle().fill(Color.gray.opacity(0.3))
        .frame(width: 48, height: 48)
        .overlay(
          Text(String((conversation.participant.displayName ?? conversation.participant.username).prefix(1)).uppercased())
            .font(.title3.bold())
            .foregroundColor(.gray)
        )
    }
  }
}
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SocialFusion/Views/Messages/DMConversationRow.swift
git commit -m "feat(messages): add DMConversationRow with platform badge and richer layout"
```

---

### Task 3: Create MessageBubble with iMessage-style grouping

**Files:**
- Create: `SocialFusion/Views/Messages/MessageBubble.swift`

**Step 1: Create bubble shape and message bubble view**

The bubble needs:
- A custom `BubbleShape` with an optional tail
- Platform-colored outgoing bubbles (blue for Bluesky, purple for Mastodon)
- Gray incoming bubbles
- Grouping support: the view receives `isFirstInGroup`, `isLastInGroup` flags
- Avatar on incoming messages (only at bottom of group)
- Timestamp only on last message of a group

```swift
import SwiftUI

// MARK: - Bubble Shape

struct BubbleShape: Shape {
  let isFromMe: Bool
  let hasTail: Bool

  func path(in rect: CGRect) -> Path {
    let radius: CGFloat = 18
    let tailSize: CGFloat = 6

    var path = Path()

    if hasTail {
      if isFromMe {
        // Rounded rect with tail nub on bottom-right
        path.addRoundedRect(
          in: CGRect(x: rect.minX, y: rect.minY,
                     width: rect.width - tailSize, height: rect.height),
          cornerSize: CGSize(width: radius, height: radius)
        )
        // Tail
        let tailX = rect.maxX - tailSize
        let tailY = rect.maxY - radius
        path.move(to: CGPoint(x: tailX, y: tailY))
        path.addQuadCurve(
          to: CGPoint(x: rect.maxX, y: rect.maxY),
          control: CGPoint(x: tailX + tailSize * 0.5, y: rect.maxY)
        )
        path.addQuadCurve(
          to: CGPoint(x: tailX, y: rect.maxY),
          control: CGPoint(x: tailX, y: rect.maxY)
        )
      } else {
        // Rounded rect with tail nub on bottom-left
        path.addRoundedRect(
          in: CGRect(x: rect.minX + tailSize, y: rect.minY,
                     width: rect.width - tailSize, height: rect.height),
          cornerSize: CGSize(width: radius, height: radius)
        )
        // Tail
        let tailX = rect.minX + tailSize
        let tailY = rect.maxY - radius
        path.move(to: CGPoint(x: tailX, y: tailY))
        path.addQuadCurve(
          to: CGPoint(x: rect.minX, y: rect.maxY),
          control: CGPoint(x: tailX - tailSize * 0.5, y: rect.maxY)
        )
        path.addQuadCurve(
          to: CGPoint(x: tailX, y: rect.maxY),
          control: CGPoint(x: tailX, y: rect.maxY)
        )
      }
    } else {
      path.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius))
    }

    return path
  }
}

// MARK: - Message Bubble

struct MessageBubble: View {
  let message: UnifiedChatMessage
  let isFromMe: Bool
  let platform: SocialPlatform
  let isFirstInGroup: Bool
  let isLastInGroup: Bool
  let showAvatar: Bool
  let avatarURL: String?

  private var bubbleColor: Color {
    if isFromMe {
      return platform == .bluesky ? .blue : .purple
    }
    return Color(.systemGray5)
  }

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      if !isFromMe {
        // Avatar space — show avatar only at bottom of group
        if showAvatar && isLastInGroup {
          asyncAvatar
        } else {
          Color.clear.frame(width: 28, height: 28)
        }
      }

      if isFromMe { Spacer(minLength: 60) }

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
      }

      if !isFromMe { Spacer(minLength: 60) }
    }
  }

  @ViewBuilder
  private var messageContent: some View {
    if message.text.isEmpty || message.text == "(Empty message)" {
      Text("(Empty message)")
        .italic()
        .foregroundColor(isFromMe ? .white.opacity(0.7) : .secondary)
    } else {
      Text(message.text)
    }
  }

  @ViewBuilder
  private var asyncAvatar: some View {
    if let urlString = avatarURL, let url = URL(string: urlString) {
      CachedAsyncImage(url: url, priority: .low) { image in
        image.resizable().aspectRatio(contentMode: .fill)
      } placeholder: {
        Circle().fill(Color.gray.opacity(0.3))
      }
      .frame(width: 28, height: 28)
      .clipShape(Circle())
    } else {
      Circle().fill(Color.gray.opacity(0.3))
        .frame(width: 28, height: 28)
    }
  }
}
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SocialFusion/Views/Messages/MessageBubble.swift
git commit -m "feat(messages): add iMessage-style MessageBubble with platform colors and grouping"
```

---

### Task 4: Create ChatView with message grouping and improved input

**Files:**
- Create: `SocialFusion/Views/Messages/ChatView.swift`

**Step 1: Create the new ChatView**

Key differences from old ChatView:
- Date headers separating message groups
- Message grouping (same sender within 2 min → grouped)
- Multi-line auto-growing TextField
- Separator above input bar
- Avatar in nav bar
- Platform-colored send button

```swift
import SwiftUI

struct ChatView: View {
  @EnvironmentObject var serviceManager: SocialServiceManager
  @EnvironmentObject var chatStreamService: ChatStreamService
  let conversation: DMConversation

  @State private var messages: [UnifiedChatMessage] = []
  @State private var newMessageText = ""
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var isSending = false

  private var platformColor: Color {
    conversation.platform == .bluesky ? .blue : .purple
  }

  var body: some View {
    VStack(spacing: 0) {
      // Messages
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 0) {
            if isLoading && messages.isEmpty {
              ProgressView().padding(.top, 40)
            } else {
              ForEach(Array(groupedMessages.enumerated()), id: \.offset) { sectionIndex, section in
                // Date header
                dateHeader(for: section.date)

                ForEach(Array(section.groups.enumerated()), id: \.offset) { groupIndex, group in
                  ForEach(Array(group.messages.enumerated()), id: \.element.id) { msgIndex, message in
                    let isFirst = msgIndex == 0
                    let isLast = msgIndex == group.messages.count - 1
                    MessageBubble(
                      message: message,
                      isFromMe: group.isFromMe,
                      platform: conversation.platform,
                      isFirstInGroup: isFirst,
                      isLastInGroup: isLast,
                      showAvatar: !group.isFromMe,
                      avatarURL: conversation.participant.avatarURL
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, isFirst ? 8 : 2)
                    .padding(.bottom, isLast ? 8 : 2)
                    .id(message.id)
                  }
                }
              }
            }
          }
        }
        .onChange(of: messages.count) { _ in
          if let last = messages.last {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
          }
        }
      }

      // Input bar
      VStack(spacing: 0) {
        Divider()
        HStack(spacing: 12) {
          TextField("Message...", text: $newMessageText, axis: .vertical)
            .lineLimit(1...5)
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(20)

          Button(action: sendMessage) {
            if isSending {
              ProgressView()
                .scaleEffect(0.8)
                .foregroundColor(.white)
                .padding(10)
                .background(platformColor)
                .clipShape(Circle())
            } else {
              Image(systemName: "paperplane.fill")
                .foregroundColor(.white)
                .padding(10)
                .background(newMessageText.isEmpty ? Color.gray : platformColor)
                .clipShape(Circle())
            }
          }
          .disabled(newMessageText.isEmpty || isLoading || isSending)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
      }
    }
    .navigationTitle(conversation.participant.displayName ?? conversation.participant.username)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        navAvatar
      }
    }
    .alert("Error", isPresented: .constant(errorMessage != nil)) {
      Button("OK") { errorMessage = nil }
      if errorMessage != nil {
        Button("Retry") {
          errorMessage = nil
          loadMessages()
        }
      }
    } message: {
      if let error = errorMessage { Text(error) }
    }
    .onAppear {
      loadMessages()
      chatStreamService.startConversationStreaming(
        conversation: conversation,
        accounts: serviceManager.accounts
      )
    }
    .onDisappear {
      chatStreamService.stopAllStreaming()
    }
    .onReceive(chatStreamService.$recentEvents) { events in
      for event in events {
        guard event.conversationId == conversation.id else { continue }
        switch event {
        case .newMessage(let msg):
          guard !messages.contains(where: { $0.id == msg.id }) else { continue }
          if let unified = msg.unifiedMessage {
            messages.append(unified)
          }
        case .deletedMessage(let del):
          messages.removeAll { $0.id == del.messageId }
        default:
          break
        }
      }
    }
  }

  // MARK: - Message Grouping

  struct DateSection {
    let date: Date
    let groups: [MessageGroup]
  }

  struct MessageGroup {
    let isFromMe: Bool
    let messages: [UnifiedChatMessage]
  }

  private var groupedMessages: [DateSection] {
    guard !messages.isEmpty else { return [] }

    // Group by calendar day
    let calendar = Calendar.current
    var daySections: [(Date, [UnifiedChatMessage])] = []
    var currentDay: DateComponents?
    var currentDayMessages: [UnifiedChatMessage] = []

    for message in messages {
      let day = calendar.dateComponents([.year, .month, .day], from: message.sentAt)
      if day != currentDay {
        if !currentDayMessages.isEmpty, let prevDay = currentDay {
          let date = calendar.date(from: prevDay) ?? Date()
          daySections.append((date, currentDayMessages))
        }
        currentDay = day
        currentDayMessages = [message]
      } else {
        currentDayMessages.append(message)
      }
    }
    if !currentDayMessages.isEmpty, let lastDay = currentDay {
      let date = calendar.date(from: lastDay) ?? Date()
      daySections.append((date, currentDayMessages))
    }

    // Within each day, group consecutive messages from same sender within 2 min
    return daySections.map { date, dayMessages in
      var groups: [MessageGroup] = []
      var currentGroup: [UnifiedChatMessage] = []
      var currentSenderIsMe: Bool?

      for message in dayMessages {
        let isMe = isFromMe(message)
        let timeToPrev = currentGroup.last.map { message.sentAt.timeIntervalSince($0.sentAt) }

        if isMe == currentSenderIsMe && (timeToPrev ?? 0) < 120 {
          currentGroup.append(message)
        } else {
          if !currentGroup.isEmpty, let senderIsMe = currentSenderIsMe {
            groups.append(MessageGroup(isFromMe: senderIsMe, messages: currentGroup))
          }
          currentGroup = [message]
          currentSenderIsMe = isMe
        }
      }
      if !currentGroup.isEmpty, let senderIsMe = currentSenderIsMe {
        groups.append(MessageGroup(isFromMe: senderIsMe, messages: currentGroup))
      }

      return DateSection(date: date, groups: groups)
    }
  }

  // MARK: - Helpers

  @ViewBuilder
  private func dateHeader(for date: Date) -> some View {
    let calendar = Calendar.current
    let text: String = {
      if calendar.isDateInToday(date) { return "Today" }
      if calendar.isDateInYesterday(date) { return "Yesterday" }
      let formatter = DateFormatter()
      formatter.dateStyle = .medium
      formatter.timeStyle = .none
      return formatter.string(from: date)
    }()

    Text(text)
      .font(.caption)
      .fontWeight(.semibold)
      .foregroundColor(.secondary)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private var navAvatar: some View {
    if let urlString = conversation.participant.avatarURL,
       let url = URL(string: urlString) {
      CachedAsyncImage(url: url, priority: .high) { image in
        image.resizable().aspectRatio(contentMode: .fill)
      } placeholder: {
        Circle().fill(Color.gray.opacity(0.3))
      }
      .frame(width: 28, height: 28)
      .clipShape(Circle())
    }
  }

  private func isFromMe(_ message: UnifiedChatMessage) -> Bool {
    serviceManager.accounts.contains { $0.platformSpecificId == message.authorId }
  }

  private func loadMessages() {
    isLoading = true
    errorMessage = nil
    Task {
      do {
        let fetched = try await serviceManager.fetchConversationMessages(conversation: conversation)
        self.messages = fetched.reversed()
        self.isLoading = false
      } catch {
        self.errorMessage = "Failed to load messages: \(error.localizedDescription)"
        self.isLoading = false
      }
    }
  }

  private func sendMessage() {
    guard !newMessageText.isEmpty, !isSending else { return }
    let text = newMessageText
    newMessageText = ""
    isSending = true
    errorMessage = nil
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

**Step 2: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SocialFusion/Views/Messages/ChatView.swift
git commit -m "feat(messages): add ChatView with message grouping, date headers, and auto-growing input"
```

---

### Task 5: Create DirectMessagesView (conversation list)

**Files:**
- Create: `SocialFusion/Views/Messages/DirectMessagesView.swift`

**Step 1: Create the new conversation list view**

This replaces the old `DirectMessagesView` from `NotificationsView.swift`. Key changes:
- Uses `MessagesViewModel` for state
- Large nav title
- New conversation button opens `NewConversationView`
- Richer empty state with CTA

```swift
import SwiftUI

struct DirectMessagesView: View {
  @EnvironmentObject var serviceManager: SocialServiceManager
  @EnvironmentObject var chatStreamService: ChatStreamService
  @StateObject private var viewModel = MessagesViewModel()

  @Binding var showComposeView: Bool
  @Binding var showValidationView: Bool

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        if viewModel.isLoading && viewModel.conversations.isEmpty {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
          .padding(.top, 40)
        } else if viewModel.conversations.isEmpty {
          emptyState
        } else {
          ForEach(viewModel.conversations) { conversation in
            NavigationLink(destination: ChatView(conversation: conversation)) {
              DMConversationRow(conversation: conversation)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(PlainButtonStyle())

            if conversation.id != viewModel.conversations.last?.id {
              Divider()
                .padding(.leading, 78)
                .padding(.trailing, 16)
            }
          }
        }
      }
    }
    .refreshable {
      await viewModel.fetchConversations(serviceManager: serviceManager)
      HapticEngine.tap.trigger()
    }
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          viewModel.showNewConversation = true
        } label: {
          Image(systemName: "square.and.pencil")
            .font(.system(size: 18))
            .foregroundColor(.primary)
        }
        .simultaneousGesture(
          LongPressGesture(minimumDuration: 1.0)
            .onEnded { _ in showValidationView = true }
        )
      }
    }
    .navigationTitle("Messages")
    .navigationBarTitleDisplayMode(.large)
    .sheet(isPresented: $viewModel.showNewConversation) {
      NewConversationView()
        .environmentObject(serviceManager)
    }
    .sheet(isPresented: $showValidationView) {
      TimelineValidationDebugView(serviceManager: serviceManager)
    }
    .onAppear {
      Task {
        await viewModel.fetchConversations(serviceManager: serviceManager)
      }
      chatStreamService.startListStreaming(accounts: serviceManager.accounts)
    }
    .onDisappear {
      chatStreamService.stopAllStreaming()
    }
    .onReceive(chatStreamService.$recentEvents) { events in
      viewModel.handleStreamEvents(events, serviceManager: serviceManager)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      Image(systemName: "bubble.left.and.bubble.right")
        .font(.system(size: 48))
        .foregroundColor(.secondary.opacity(0.4))

      Text("No messages yet")
        .font(.title3)
        .fontWeight(.semibold)
        .foregroundColor(.secondary)

      Button {
        viewModel.showNewConversation = true
      } label: {
        Text("Start a conversation")
          .font(.subheadline)
          .fontWeight(.medium)
          .foregroundColor(.white)
          .padding(.horizontal, 20)
          .padding(.vertical, 10)
          .background(Capsule().fill(Color.blue))
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 100)
  }
}
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -5`
Expected: May get a warning about `NewConversationView` not existing yet — that's fine, we'll create it next. If it errors, add a placeholder:

```swift
// Temporary placeholder — replaced in Task 7
struct NewConversationView: View {
  var body: some View { Text("New Conversation") }
}
```

**Step 3: Commit**

```bash
git add SocialFusion/Views/Messages/DirectMessagesView.swift
git commit -m "feat(messages): add DirectMessagesView with large title, ViewModel, and empty state CTA"
```

---

### Task 6: Wire up ContentView and remove old code

**Files:**
- Modify: `SocialFusion/ContentView.swift:248-256` — update `messagesTabContent` (remove `showComposeView` binding, keep `showValidationView`)
- Modify: `SocialFusion/Views/NotificationsView.swift:403-622` — delete old `DirectMessagesView` and `DMConversationRow`
- Delete: `SocialFusion/Views/ChatView.swift` — old ChatView

**Step 1: Update ContentView's messagesTabContent**

The new `DirectMessagesView` has the same `@Binding` signature, so `ContentView.swift:248-256` should work as-is. Verify the bindings match. If the old view passed `showComposeView` and the new view still accepts it (it does), no change needed in ContentView.

**Step 2: Remove old DirectMessagesView and DMConversationRow from NotificationsView.swift**

Delete lines 403-622 from `SocialFusion/Views/NotificationsView.swift` (the `DirectMessagesView` struct and `DMConversationRow` struct).

**Step 3: Remove old ChatView.swift**

Delete `SocialFusion/Views/ChatView.swift` entirely.

**Step 4: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED (may need to fix any remaining references)

**Step 5: Commit**

```bash
git add -A
git commit -m "refactor(messages): remove old DirectMessagesView, DMConversationRow, and ChatView"
```

---

### Task 7: Add Bluesky getConvoForMembers API

**Files:**
- Modify: `SocialFusion/Services/BlueskyService.swift` — add `getConvoForMembers` method near line ~4453
- Modify: `SocialFusion/Services/SocialServiceManager.swift` — add `startOrFindConversation` method

**Step 1: Add getConvoForMembers to BlueskyService**

Add after the existing `listConversations` method (~line 4453):

```swift
/// Get or create a conversation with specific members
internal func getConvoForMembers(memberDids: [String], for account: SocialAccount) async throws -> BlueskyConvo {
  guard let accessToken = account.accessToken else {
    throw BlueskyTokenError.noAccessToken
  }

  let apiURL = "\(getChatProxyURL(for: account))/chat.bsky.convo.getConvoForMembers"
  var components = URLComponents(string: apiURL)!
  components.queryItems = memberDids.map { URLQueryItem(name: "members", value: $0) }

  guard let url = components.url else {
    throw BlueskyTokenError.invalidServerURL
  }

  var request = URLRequest(url: url)
  request.httpMethod = "GET"
  request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

  let (data, _) = try await session.data(for: request)

  struct Response: Codable {
    let convo: BlueskyConvo
  }
  let response = try JSONDecoder().decode(Response.self, from: data)
  return response.convo
}
```

**Step 2: Add startOrFindBlueskyConversation to SocialServiceManager**

Add near the existing chat methods (~line 3884):

```swift
/// Start or find an existing Bluesky DM conversation with a user
public func startOrFindBlueskyConversation(withDid did: String) async throws -> DMConversation {
  guard let account = accounts.first(where: { $0.platform == .bluesky }) else {
    throw ServiceError.invalidAccount(reason: "No Bluesky account found")
  }

  let convo = try await blueskyService.getConvoForMembers(memberDids: [did], for: account)

  // Convert to DMConversation
  let otherMember = convo.members.first { $0.did != account.platformSpecificId } ?? convo.members.first!
  let participant = NotificationAccount(
    id: otherMember.did,
    username: otherMember.handle,
    displayName: otherMember.displayName,
    avatarURL: otherMember.avatar
  )

  let lastMsg: DirectMessage
  if case .message(let view) = convo.lastMessage {
    let sender = NotificationAccount(
      id: view.sender.did,
      username: view.sender.handle,
      displayName: view.sender.displayName,
      avatarURL: view.sender.avatar
    )
    lastMsg = DirectMessage(
      id: view.id,
      sender: sender,
      recipient: participant,
      content: view.text,
      createdAt: ISO8601DateFormatter().date(from: view.sentAt) ?? Date(),
      platform: .bluesky
    )
  } else {
    lastMsg = DirectMessage(
      id: UUID().uuidString,
      sender: participant,
      recipient: participant,
      content: "",
      createdAt: Date(),
      platform: .bluesky
    )
  }

  return DMConversation(
    id: convo.id,
    participant: participant,
    lastMessage: lastMsg,
    unreadCount: convo.unreadCount,
    platform: .bluesky
  )
}
```

**Step 3: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add SocialFusion/Services/BlueskyService.swift SocialFusion/Services/SocialServiceManager.swift
git commit -m "feat(messages): add Bluesky getConvoForMembers API for new conversation creation"
```

---

### Task 8: Create NewConversationView

**Files:**
- Create (or replace placeholder): `SocialFusion/Views/Messages/NewConversationView.swift`

**Step 1: Create the new conversation view**

Uses Mastodon's `/api/v2/search?type=accounts` and Bluesky's `searchActors` to search users. Tapping a Bluesky user creates/finds a conversation via `startOrFindBlueskyConversation`. Tapping a Mastodon user opens ComposeView with `@mention` and direct visibility.

```swift
import SwiftUI

struct NewConversationView: View {
  @EnvironmentObject var serviceManager: SocialServiceManager
  @Environment(\.dismiss) private var dismiss

  @State private var searchText = ""
  @State private var blueskyResults: [BlueskyActor] = []
  @State private var mastodonResults: [MastodonAccount] = []
  @State private var isSearching = false
  @State private var selectedConversation: DMConversation?
  @State private var showChat = false
  @State private var showCompose = false
  @State private var composeMention = ""
  @State private var searchTask: Task<Void, Never>?

  var body: some View {
    NavigationStack {
      List {
        if isSearching {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        }

        if !blueskyResults.isEmpty {
          Section("Bluesky") {
            ForEach(blueskyResults, id: \.did) { actor in
              Button {
                startBlueskyConversation(with: actor)
              } label: {
                userRow(
                  avatarURL: actor.avatar,
                  displayName: actor.displayName,
                  handle: actor.handle,
                  platform: .bluesky
                )
              }
            }
          }
        }

        if !mastodonResults.isEmpty {
          Section("Mastodon") {
            ForEach(mastodonResults, id: \.id) { account in
              Button {
                startMastodonConversation(with: account)
              } label: {
                userRow(
                  avatarURL: account.avatar,
                  displayName: account.displayName,
                  handle: account.acct,
                  platform: .mastodon
                )
              }
            }
          }
        }

        if !isSearching && searchText.count >= 2
            && blueskyResults.isEmpty && mastodonResults.isEmpty {
          ContentUnavailableView(
            "No results",
            systemImage: "magnifyingglass",
            description: Text("No users found for \"\(searchText)\"")
          )
        }
      }
      .searchable(text: $searchText, prompt: "Search people...")
      .onChange(of: searchText) { _, newValue in
        searchTask?.cancel()
        guard newValue.count >= 2 else {
          blueskyResults = []
          mastodonResults = []
          return
        }
        searchTask = Task {
          try? await Task.sleep(for: .milliseconds(300))
          guard !Task.isCancelled else { return }
          await performSearch(query: newValue)
        }
      }
      .navigationTitle("New Message")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
      .navigationDestination(isPresented: $showChat) {
        if let conversation = selectedConversation {
          ChatView(conversation: conversation)
        }
      }
      .sheet(isPresented: $showCompose) {
        ComposeView(
          initialText: composeMention,
          visibility: .direct
        )
        .environmentObject(serviceManager)
      }
    }
  }

  // MARK: - User Row

  private func userRow(
    avatarURL: String?,
    displayName: String?,
    handle: String,
    platform: SocialPlatform
  ) -> some View {
    HStack(spacing: 12) {
      if let avatarURL, let url = URL(string: avatarURL) {
        CachedAsyncImage(url: url, priority: .high) { image in
          image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
          Circle().fill(Color.gray.opacity(0.3))
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
      } else {
        Circle().fill(Color.gray.opacity(0.3))
          .frame(width: 40, height: 40)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(displayName ?? handle)
          .font(.body)
          .fontWeight(.medium)
          .foregroundColor(.primary)
        Text("@\(handle)")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      Spacer()

      PostPlatformBadge(platform: platform)
        .scaleEffect(0.85)
    }
  }

  // MARK: - Search

  private func performSearch(query: String) async {
    isSearching = true

    // Search both platforms in parallel
    async let blueskySearch: [BlueskyActor] = searchBluesky(query: query)
    async let mastodonSearch: [MastodonAccount] = searchMastodon(query: query)

    let (bsky, masto) = await (blueskySearch, mastodonSearch)
    blueskyResults = bsky
    mastodonResults = masto
    isSearching = false
  }

  private func searchBluesky(query: String) async -> [BlueskyActor] {
    guard let account = serviceManager.accounts.first(where: { $0.platform == .bluesky }) else {
      return []
    }
    do {
      let response = try await serviceManager.blueskyService.searchActors(
        query: query, account: account, limit: 10
      )
      return response.actors
    } catch {
      return []
    }
  }

  private func searchMastodon(query: String) async -> [MastodonAccount] {
    guard let account = serviceManager.accounts.first(where: { $0.platform == .mastodon }) else {
      return []
    }
    do {
      let result = try await serviceManager.mastodonService.search(
        query: query, account: account, type: "accounts", limit: 10
      )
      return result.accounts
    } catch {
      return []
    }
  }

  // MARK: - Conversation Creation

  private func startBlueskyConversation(with actor: BlueskyActor) {
    Task {
      do {
        let conversation = try await serviceManager.startOrFindBlueskyConversation(withDid: actor.did)
        selectedConversation = conversation
        showChat = true
      } catch {
        // Show error — for now just print
        print("Failed to start conversation: \(error)")
      }
    }
  }

  private func startMastodonConversation(with account: MastodonAccount) {
    // Mastodon DMs are posts with visibility: direct
    composeMention = "@\(account.acct) "
    showCompose = true
  }
}
```

**Note:** The `ComposeView(initialText:visibility:)` initializer may need to be verified/adjusted to match the existing `ComposeView` signature. Check `ComposeView.swift` for its init parameters. If it doesn't support `initialText`/`visibility` params, the implementing agent should add simple init params or use the existing init and set state after.

**Step 2: Build and verify**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED (may need minor adjustments to ComposeView init)

**Step 3: Commit**

```bash
git add SocialFusion/Views/Messages/NewConversationView.swift
git commit -m "feat(messages): add NewConversationView with user search and conversation creation"
```

---

### Task 9: Add new files to Xcode project and final integration

**Step 1: Verify all new files are in the Xcode project**

Since SocialFusion uses an `.xcodeproj` (not SPM), new files need to be added to the project. Check if the project uses folder references (auto-includes new files) or file references (requires manual addition).

Run: `grep -c "Views/Messages" SocialFusion.xcodeproj/project.pbxproj`

If 0, the files need to be added to the Xcode project. The implementing agent should open Xcode or use a script to add them. Alternatively, if the project uses the new Xcode "folder reference" style, files are auto-discovered.

**Step 2: Full build verification**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED with 0 errors

**Step 3: Visual smoke test**

Run in simulator and verify:
- Messages tab shows large "Messages" title
- Conversation list renders with platform badges
- Tapping a conversation opens ChatView with grouped messages and date headers
- Input bar has separator, auto-grows on multi-line
- Send button uses platform color
- Empty state shows "Start a conversation" CTA
- New conversation sheet opens and searches users

**Step 4: Commit**

```bash
git add -A
git commit -m "feat(messages): complete messages tab redesign integration"
```

---

### Task Dependencies

```
Task 1 (ViewModel) ─────┐
Task 2 (ConversationRow) ├──► Task 5 (DirectMessagesView) ──► Task 6 (Wire up + cleanup)
Task 3 (MessageBubble) ──┤                                          │
                          └──► Task 4 (ChatView) ───────────────────┘
Task 7 (Bluesky API) ────────► Task 8 (NewConversationView) ────────► Task 9 (Integration)
```

Tasks 1-4 and 7 are independent and can be parallelized. Task 5 depends on 1+2. Task 6 depends on 4+5. Task 8 depends on 7. Task 9 depends on all.

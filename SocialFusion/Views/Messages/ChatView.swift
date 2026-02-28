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
  @State private var lastReadByOther: Date?
  @State private var reactions: [String: [String: Set<String>]] = [:]

  private var platformColor: Color {
    conversation.platform == .bluesky ? .blue : .purple
  }

  private var myAccountIds: Set<String> {
    Set(serviceManager.accounts.map(\.platformSpecificId))
  }

  var body: some View {
    VStack(spacing: 0) {
      messagesList
      inputBar
    }
    .navigationTitle(conversation.participant.displayName ?? conversation.participant.username)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        navAvatar
      }
    }
    .alert("Error", isPresented: Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )) {
      Button("OK") { errorMessage = nil }
      Button("Retry") {
        errorMessage = nil
        loadMessages()
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
      Task { await serviceManager.markConversationRead(conversation: conversation) }
    }
    .onDisappear {
      chatStreamService.stopAllStreaming()
    }
    .onReceive(chatStreamService.$recentEvents) { events in
      handleStreamEvents(events)
    }
  }

  // MARK: - Subviews

  private var messagesList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 0) {
          if isLoading && messages.isEmpty {
            ProgressView().padding(.top, 40)
          } else {
            ForEach(Array(groupedMessages.enumerated()), id: \.offset) { _, section in
              dateHeader(for: section.date)
              ForEach(Array(section.groups.enumerated()), id: \.offset) { _, group in
                messageGroupView(group)
              }
            }
          }
        }
      }
      .onChange(of: messages.count) { _, _ in
        if let last = messages.last {
          withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
      }
    }
  }

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
        onReactionTap: { emoji, isFromMe in
          toggleReaction(messageId: message.id, emoji: emoji, alreadyReacted: isFromMe)
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

  private var inputBar: some View {
    VStack(spacing: 0) {
      Divider()
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

  private var sendButton: some View {
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

  // MARK: - Message Grouping

  private struct DateSection {
    let date: Date
    let groups: [MessageGroup]
  }

  private struct MessageGroup {
    let isFromMe: Bool
    let messages: [UnifiedChatMessage]
  }

  private var groupedMessages: [DateSection] {
    guard !messages.isEmpty else { return [] }

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

  private static let dateSectionFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
  }()

  // MARK: - Helpers

  @ViewBuilder
  private func dateHeader(for date: Date) -> some View {
    let calendar = Calendar.current
    let text: String = {
      if calendar.isDateInToday(date) { return "Today" }
      if calendar.isDateInYesterday(date) { return "Yesterday" }
      return Self.dateSectionFormatter.string(from: date)
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

  private func isSeenMessage(_ message: UnifiedChatMessage) -> Bool {
    guard conversation.platform == .bluesky,
          let readDate = lastReadByOther else { return false }
    return message.sentAt <= readDate
  }

  private func reactionsForMessage(_ messageId: String) -> [MessageReaction] {
    guard let msgReactions = reactions[messageId] else { return [] }
    return msgReactions.map { emoji, senderIds in
      MessageReaction(emoji: emoji, senderIds: senderIds)
    }.sorted { $0.emoji < $1.emoji }
  }

  private func toggleReaction(messageId: String, emoji: String, alreadyReacted: Bool) {
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
        print("[Reactions] Failed to toggle reaction: \(error.localizedDescription)")
      }
    }
  }

  private func handleStreamEvents(_ events: [UnifiedChatEvent]) {
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
      case .readReceipt:
        lastReadByOther = Date()
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
      default:
        break
      }
    }
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

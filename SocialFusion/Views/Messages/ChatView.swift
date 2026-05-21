import SwiftUI
import PhotosUI

struct ChatView: View {
  @EnvironmentObject var serviceManager: SocialServiceManager
  @EnvironmentObject var chatStreamService: ChatStreamService
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let conversation: DMConversation

  @State private var messages: [UnifiedChatMessage] = []
  @State private var newMessageText = ""
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var isSending = false
  @State private var lastReadByOther: Date?
  @State private var reactions: [String: [String: Set<String>]] = [:]
  @State private var editingMessage: UnifiedChatMessage?
  @State private var deleteConfirmMessage: UnifiedChatMessage?
  @State private var isOtherTyping = false
  @State private var typingDismissTask: Task<Void, Never>?
  @State private var showSettings = false
  @State private var selectedMedia: [PhotosPickerItem] = []
  @State private var isSearching = false
  @State private var searchText = ""
  @State private var currentMatchIndex = 0

  /// Brand-tinted color via SocialPlatform.swiftUIColor.
  private var platformColor: Color { conversation.platform.swiftUIColor }

  private var myAccountIds: Set<String> {
    Set(serviceManager.accounts.map(\.platformSpecificId))
  }

  private var matchingMessageIds: [String] {
    guard !searchText.isEmpty else { return [] }
    return messages.filter {
      $0.text.localizedCaseInsensitiveContains(searchText)
    }.map(\.id)
  }

  var body: some View {
    VStack(spacing: 0) {
      if isSearching {
        HStack(spacing: 10) {
          Image(systemName: "magnifyingglass")
            .font(.subheadline)
            .foregroundColor(.secondary)
          TextField("Search messages", text: $searchText)
            .textFieldStyle(.plain)
            .font(.subheadline)
            .submitLabel(.search)
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
            .onChange(of: searchText) { _, _ in
              currentMatchIndex = 0
            }

          if !matchingMessageIds.isEmpty {
            Text("\(currentMatchIndex + 1) of \(matchingMessageIds.count)")
              .font(.caption.weight(.medium).monospacedDigit())
              .foregroundColor(.secondary)
              .fixedSize()
              .contentTransition(.numericText(value: Double(currentMatchIndex)))
              .accessibilityLabel("Match \(currentMatchIndex + 1) of \(matchingMessageIds.count)")

            HStack(spacing: 2) {
              Button {
                HapticEngine.selection.trigger()
                if currentMatchIndex > 0 { currentMatchIndex -= 1 }
              } label: {
                Image(systemName: "chevron.up")
                  .font(.caption.weight(.semibold))
                  .foregroundColor(currentMatchIndex > 0 ? .primary : .secondary.opacity(0.5))
                  .frame(width: 44, height: 44)
                  .contentShape(Rectangle())
              }
              .disabled(currentMatchIndex == 0)
              .accessibilityLabel("Previous match")
              .accessibilityValue("Match \(currentMatchIndex + 1) of \(matchingMessageIds.count)")

              Button {
                HapticEngine.selection.trigger()
                if currentMatchIndex < matchingMessageIds.count - 1 { currentMatchIndex += 1 }
              } label: {
                Image(systemName: "chevron.down")
                  .font(.caption.weight(.semibold))
                  .foregroundColor(currentMatchIndex < matchingMessageIds.count - 1 ? .primary : .secondary.opacity(0.5))
                  .frame(width: 44, height: 44)
                  .contentShape(Rectangle())
              }
              .disabled(currentMatchIndex >= matchingMessageIds.count - 1)
              .accessibilityLabel("Next match")
              .accessibilityValue("Match \(currentMatchIndex + 1) of \(matchingMessageIds.count)")
            }
          } else if !searchText.isEmpty {
            Text("No results")
              .font(.caption.weight(.medium))
              .foregroundColor(.secondary)
              .accessibilityLabel("No matching messages found")
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // Solid fallback for users with Reduce Transparency on —
        // the in-conversation search bar should still read as a
        // distinct strip above the message list when materials
        // are dialed back.
        .background(reduceTransparency ? AnyShapeStyle(Color(.secondarySystemBackground)) : AnyShapeStyle(.ultraThinMaterial))
        .overlay(
          Divider(),
          alignment: .bottom
        )
        .transition(.move(edge: .top).combined(with: .opacity))
      }
      messagesList
      inputBar
    }
    .navigationTitle(conversation.isGroup ? (conversation.title ?? "Group") : (conversation.participant.displayName ?? conversation.participant.username))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        navAvatar
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          HapticEngine.selection.trigger()
          withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.82)) {
            isSearching.toggle()
          }
          if !isSearching {
            searchText = ""
            currentMatchIndex = 0
          }
        } label: {
          Image(systemName: isSearching ? "xmark" : "magnifyingglass")
            .foregroundColor(.secondary)
            .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(isSearching ? "Close search" : "Search messages")
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          HapticEngine.tap.trigger()
          showSettings = true
        } label: {
          Image(systemName: "info.circle")
            .foregroundColor(.secondary)
        }
        .accessibilityLabel("Conversation settings")
      }
    }
    .sheet(isPresented: $showSettings) {
      ConversationSettingsView(conversation: conversation) {
        // onLeave — handled by navigation pop
      }
      .environmentObject(serviceManager)
    }
    .alert("Something Went Wrong", isPresented: Binding(
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
    .alert("Delete Message", isPresented: Binding(
      get: { deleteConfirmMessage != nil },
      set: { if !$0 { deleteConfirmMessage = nil } }
    )) {
      Button("Delete", role: .destructive) {
        HapticEngine.warning.trigger()
        if let msg = deleteConfirmMessage {
          performDelete(msg)
        }
      }
      Button("Cancel", role: .cancel) { deleteConfirmMessage = nil }
    } message: {
      Text("This message will be deleted. This can't be undone.")
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
            ProgressView()
              .padding(.top, 40)
              .accessibilityLabel("Loading messages")
          } else if messages.isEmpty {
            emptyConversationView
          } else {
            ForEach(Array(groupedMessages.enumerated()), id: \.offset) { _, section in
              dateHeader(for: section.date)
              ForEach(Array(section.groups.enumerated()), id: \.offset) { _, group in
                messageGroupView(group)
              }
            }
            if isOtherTyping {
              TypingIndicatorBubble()
            }
          }
        }
      }
      .onChange(of: messages.count) { _, _ in
        if let last = messages.last {
          // New-message scroll uses a springier curve so the latest
          // message arriving feels alive, not just mechanical.
          // Reduce Motion: scroll instantly so the message arrives
          // without the bounce.
          withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82)) {
            proxy.scrollTo(last.id, anchor: .bottom)
          }
        }
      }
      .onChange(of: currentMatchIndex) { _, newIndex in
        if matchingMessageIds.indices.contains(newIndex) {
          // Search nav uses a snappier easeOut so consecutive
          // up/down taps feel responsive.
          withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
            proxy.scrollTo(matchingMessageIds[newIndex], anchor: .center)
          }
        }
      }
      .onChange(of: searchText) { _, _ in
        if let firstMatch = matchingMessageIds.first {
          withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
            proxy.scrollTo(firstMatch, anchor: .center)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func messageGroupView(_ group: MessageGroup) -> some View {
    let senderName: String? = conversation.isGroup && !group.isFromMe
      ? conversation.participants.first(where: { $0.id == group.messages.first?.authorId })?.displayName
        ?? conversation.participants.first(where: { $0.id == group.messages.first?.authorId })?.username
      : nil
    let groupAvatarURL: String? = conversation.isGroup && !group.isFromMe
      ? conversation.participants.first(where: { $0.id == group.messages.first?.authorId })?.avatarURL
      : conversation.participant.avatarURL
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
        avatarURL: groupAvatarURL,
        senderName: isFirst ? senderName : nil,
        showSeenIndicator: showSeen,
        reactions: msgReactions,
        myAccountIds: myAccountIds,
        onReactionTap: { emoji, isFromMe in
          toggleReaction(messageId: message.id, emoji: emoji, alreadyReacted: isFromMe)
        },
        onReactionAdd: { emoji in
          toggleReaction(messageId: message.id, emoji: emoji, alreadyReacted: false)
        },
        onDelete: {
          deleteConfirmMessage = message
        },
        onEdit: {
          editingMessage = message
          newMessageText = message.text
        }
      )
      .opacity(!searchText.isEmpty && !matchingMessageIds.contains(message.id) ? 0.3 : 1.0)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(matchingMessageIds.indices.contains(currentMatchIndex) && matchingMessageIds[currentMatchIndex] == message.id
                ? Color.yellow.opacity(0.22) : Color.clear)
          .padding(.horizontal, 8)
      )
      .animation(.easeInOut(duration: 0.18), value: currentMatchIndex)
      .animation(.easeInOut(duration: 0.2), value: searchText)
      .padding(.horizontal, 12)
      .padding(.top, isFirst ? 8 : 2)
      .padding(.bottom, isLast ? 8 : 2)
      .id(message.id)
    }
  }

  private var inputBar: some View {
    VStack(spacing: 0) {
      Divider()
      if let editing = editingMessage {
        HStack(spacing: 10) {
          Image(systemName: "pencil")
            .font(.caption.weight(.bold))
            .foregroundColor(platformColor)
            .frame(width: 22, height: 22)
            .background(
              Circle()
                .fill(platformColor.opacity(0.14))
            )

          VStack(alignment: .leading, spacing: 1) {
            Text("Editing message")
              .font(.caption.weight(.semibold))
              .foregroundColor(platformColor)
            Text(editing.text)
              .font(.caption)
              .foregroundColor(.secondary)
              .lineLimit(1)
          }

          Spacer()

          Button {
            HapticEngine.tap.trigger()
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)) {
              editingMessage = nil
              newMessageText = ""
            }
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 18))
              .foregroundColor(.secondary)
              .frame(width: 44, height: 44)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Cancel editing")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(platformColor.opacity(0.08))
        .overlay(
          Rectangle()
            .fill(platformColor.opacity(0.18))
            .frame(height: 0.5),
          alignment: .bottom
        )
      }
      ChatMediaPickerBar(selectedItems: $selectedMedia)
      HStack(spacing: 10) {
        PhotosPicker(selection: $selectedMedia, maxSelectionCount: 4, matching: .images) {
          Image(systemName: "plus.circle.fill")
            .font(.system(size: 26))
            .foregroundStyle(.secondary, Color(.systemGray5))
            .symbolRenderingMode(.hierarchical)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .simultaneousGesture(TapGesture().onEnded { HapticEngine.tap.trigger() })
        .accessibilityLabel("Add photos")
        .accessibilityHint("Opens the photo picker to attach up to 4 images")

        TextField("Message", text: $newMessageText, axis: .vertical)
          .lineLimit(1...5)
          .padding(.horizontal, 14)
          .padding(.vertical, 9)
          .background(
            Capsule(style: .continuous)
              .fill(Color(.systemGray6))
              .overlay(
                Capsule(style: .continuous)
                  .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
              )
          )

        sendButton
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(Color(.systemBackground))
    }
  }

  /// Empty-conversation placeholder — matches the tinted-halo
  /// composition Apple uses in Messages, and the rest of this app's
  /// empty states.
  private var emptyConversationView: some View {
    VStack(spacing: 14) {
      ZStack {
        Circle()
          .fill(
            RadialGradient(
              colors: [platformColor.opacity(0.18), platformColor.opacity(0.0)],
              center: .center,
              startRadius: 4,
              endRadius: 60
            )
          )
          .frame(width: 120, height: 120)
        Image(systemName: "bubble.left.and.bubble.right")
          .font(.system(size: 36, weight: .light))
          .foregroundStyle(platformColor.gradient)
          .symbolRenderingMode(.hierarchical)
      }
      VStack(spacing: 6) {
        Text("No messages yet")
          .font(.title3.weight(.semibold))
          .foregroundColor(.primary.opacity(0.85))
        Text("Say hello to start the conversation.")
          .font(.subheadline)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 32)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.top, 80)
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }

  private var sendButton: some View {
    let canSend = !newMessageText.isEmpty && !isLoading && !isSending
    return Button {
      HapticEngine.tap.trigger()
      sendMessage()
    } label: {
      ZStack {
        Circle()
          .fill(canSend ? AnyShapeStyle(platformColor.gradient) : AnyShapeStyle(Color(.systemGray4)))
          .frame(width: 36, height: 36)
          .shadow(color: canSend ? platformColor.opacity(0.3) : .clear, radius: 6, x: 0, y: 2)

        if isSending {
          ProgressView()
            .scaleEffect(0.7)
            .tint(.white)
        } else {
          Image(systemName: "arrow.up")
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .contentTransition(.symbolEffect(.replace))
        }
      }
      .scaleEffect(canSend ? 1.0 : 0.92)
      .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78), value: canSend)
      .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78), value: isSending)
      // The visible button is 36pt; extend hit area to 44pt minimum
      // so the user's thumb has comfortable room to land.
      .frame(width: 44, height: 44)
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(!canSend)
    .accessibilityLabel(isSending ? "Sending" : "Send message")
    .accessibilityHint(canSend
                       ? "Sends your message"
                       : "Type a message to enable")
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
      // Section headers in the messages list — .isHeader lets VoiceOver
      // users navigate between date sections via the rotor, the same
      // way iOS Messages does.
      .accessibilityAddTraits(.isHeader)
  }

  private var navAvatarInitial: String {
    String((conversation.participant.displayName ?? conversation.participant.username).prefix(1)).uppercased()
  }

  @ViewBuilder
  private var navAvatar: some View {
    Group {
      if conversation.isGroup {
        GroupAvatarStack(participants: conversation.participants, size: 28)
      } else if let urlString = conversation.participant.avatarURL,
         let url = URL(string: urlString) {
        CachedAsyncImage(url: url, priority: .high) { image in
          image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
          Circle()
            .fill(Color(.systemGray5))
            .overlay(
              Text(navAvatarInitial)
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(.systemGray))
            )
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
      }
    }
    // Decorative — the conversation title in the toolbar's center
    // already names the person/group. Hiding from VoiceOver avoids
    // an "Image" read with no context after the title is already read.
    .accessibilityHidden(true)
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
    // Capture pre-toggle reaction state so we can roll back on network
    // failure — otherwise an optimistic add/remove would stay even when
    // the server rejected it, leaving the UI out of sync.
    let previousReactions = reactions[messageId]?[emoji]

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
        #if DEBUG
        print("[Reactions] Failed to toggle reaction: \(error.localizedDescription)")
        #endif
        // Roll back the optimistic update + tell the user.
        await MainActor.run {
          if let previousReactions {
            reactions[messageId, default: [:]][emoji] = previousReactions
          } else {
            reactions[messageId]?[emoji] = nil
          }
          HapticEngine.error.trigger()
          ToastManager.shared.show("Couldn't update reaction", severity: .error, duration: 2.0)
        }
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
      case .typingIndicator:
        isOtherTyping = true
        typingDismissTask?.cancel()
        typingDismissTask = Task {
          try? await Task.sleep(for: .seconds(5))
          guard !Task.isCancelled else { return }
          isOtherTyping = false
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
        self.errorMessage = "Couldn't load messages: \(error.localizedDescription)"
        self.isLoading = false
        HapticEngine.error.trigger()
      }
    }
  }

  private func sendMessage() {
    guard !newMessageText.isEmpty, !isSending else { return }
    let text = newMessageText

    // Handle editing mode
    if let editing = editingMessage {
      newMessageText = ""
      editingMessage = nil
      isSending = true
      errorMessage = nil
      Task {
        do {
          try await serviceManager.editChatMessage(
            conversation: conversation, messageId: editing.id, newText: text)
          self.isSending = false
          loadMessages()
        } catch {
          self.errorMessage = "Couldn't edit message: \(error.localizedDescription)"
          self.newMessageText = text
          self.editingMessage = editing
          self.isSending = false
          HapticEngine.error.trigger()
        }
      }
      return
    }

    newMessageText = ""
    isSending = true
    errorMessage = nil
    Task {
      do {
        let sent = try await serviceManager.sendChatMessage(conversation: conversation, text: text)
        self.messages.append(sent)
        self.isSending = false
      } catch {
        self.errorMessage = "Couldn't send message: \(error.localizedDescription)"
        self.newMessageText = text
        self.isSending = false
        HapticEngine.error.trigger()
      }
    }
  }

  private func performDelete(_ message: UnifiedChatMessage) {
    // Message removal — easeOut with a slight bounce response so the
    // bubble feels like it's being lifted out, not just vanishing.
    // Reduce Motion: vanish without the spring envelope.
    withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.82)) {
      messages.removeAll { $0.id == message.id }
    }
    Task {
      do {
        try await serviceManager.deleteChatMessage(conversation: conversation, messageId: message.id)
      } catch {
        loadMessages()
        errorMessage = "Couldn't delete that message"
        HapticEngine.error.trigger()
      }
    }
  }
}

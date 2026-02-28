import Foundation

final class BlueskyPollStreamProvider: ChatStreamProvider, @unchecked Sendable {
  private var continuation: AsyncStream<UnifiedChatEvent>.Continuation?
  private var pollTask: Task<Void, Never>?
  private var lastCursor: String?
  private var isStopped = false
  private var currentConversationId: String?
  private let blueskyService: BlueskyService

  /// Active chat = 3s, list view = 15s
  private(set) var pollInterval: TimeInterval = 15.0

  private(set) var connectionState: ChatConnectionState = .disconnected

  private static let activeChatInterval: TimeInterval = 3.0
  private static let listViewInterval: TimeInterval = 15.0

  init(blueskyService: BlueskyService) {
    self.blueskyService = blueskyService
  }

  func eventStream(for account: SocialAccount, conversationId: String?) -> AsyncStream<UnifiedChatEvent> {
    stop()
    isStopped = false
    currentConversationId = conversationId
    pollInterval = conversationId != nil ? Self.activeChatInterval : Self.listViewInterval

    return AsyncStream { continuation in
      self.continuation = continuation
      continuation.onTermination = { @Sendable _ in
        self.pollTask?.cancel()
      }
      self.pollTask = Task { await self.pollLoop(account: account) }
    }
  }

  func stop() {
    isStopped = true
    pollTask?.cancel()
    pollTask = nil
    continuation?.finish()
    continuation = nil
    lastCursor = nil
    connectionState = .disconnected
  }

  func sendTypingIndicator(conversationId: String, account: SocialAccount) async {
    // No Bluesky API for typing indicators yet
  }

  func updatePollInterval(activeChat: Bool) {
    pollInterval = activeChat ? Self.activeChatInterval : Self.listViewInterval
    currentConversationId = activeChat ? currentConversationId : nil
  }

  // MARK: - Poll Loop

  private func pollLoop(account: SocialAccount) async {
    connectionState = .connecting

    // Initial call to establish baseline cursor
    do {
      let response = try await blueskyService.getChatLog(cursor: nil, for: account)
      lastCursor = response.cursor
      connectionState = .connected
      print("[BlueskyChat] Polling started, baseline cursor: \(response.cursor ?? "nil")")
    } catch {
      connectionState = .error(error.localizedDescription)
      print("[BlueskyChat] Failed to establish baseline: \(error.localizedDescription)")
      return
    }

    var consecutiveErrors = 0

    while !isStopped && !Task.isCancelled {
      do {
        try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
      } catch {
        return // Task cancelled
      }

      guard !isStopped && !Task.isCancelled else { return }

      do {
        let response = try await blueskyService.getChatLog(cursor: lastCursor, for: account)

        if let newCursor = response.cursor {
          lastCursor = newCursor
        }

        consecutiveErrors = 0
        connectionState = .connected

        for logEvent in response.logs {
          if let chatEvent = mapLogEvent(logEvent) {
            // Filter by conversationId if we're in active chat mode
            if let filterConvo = currentConversationId {
              if chatEvent.conversationId == filterConvo {
                continuation?.yield(chatEvent)
              }
            } else {
              continuation?.yield(chatEvent)
            }
          }
        }
      } catch {
        consecutiveErrors += 1
        print("[BlueskyChat] Poll error (\(consecutiveErrors)): \(error.localizedDescription)")
        if consecutiveErrors >= 5 {
          connectionState = .error("Multiple poll failures")
        } else {
          connectionState = .reconnecting(attempt: consecutiveErrors)
        }
      }
    }
  }

  // MARK: - Event Mapping

  private func mapLogEvent(_ logEvent: BlueskyConvoLogEvent) -> UnifiedChatEvent? {
    switch logEvent {
    case .createMessage(let e):
      let sentAt = ISO8601DateFormatter().date(from: e.message.sentAt) ?? Date()
      return .newMessage(ChatEventMessage(
        id: e.message.id,
        conversationId: e.convoId,
        senderDisplayName: e.message.sender.displayName ?? e.message.sender.handle,
        senderId: e.message.sender.did,
        text: e.message.text,
        sentAt: sentAt,
        platform: .bluesky,
        unifiedMessage: .bluesky(.message(e.message))
      ))

    case .deleteMessage(let e):
      return .deletedMessage(ChatEventDeletedMessage(
        messageId: e.message.id,
        conversationId: e.convoId,
        platform: .bluesky
      ))

    case .readMessage(let e):
      return .readReceipt(ChatEventReadReceipt(
        conversationId: e.convoId,
        accountId: "",
        platform: .bluesky
      ))

    case .beginConvo(let e):
      return .conversationUpdated(ChatEventConversationUpdate(
        conversationId: e.convoId,
        kind: .began,
        platform: .bluesky
      ))

    case .acceptConvo(let e):
      return .conversationUpdated(ChatEventConversationUpdate(
        conversationId: e.convoId,
        kind: .accepted,
        platform: .bluesky
      ))

    case .leaveConvo(let e):
      return .conversationUpdated(ChatEventConversationUpdate(
        conversationId: e.convoId,
        kind: .left,
        platform: .bluesky
      ))

    case .muteConvo(let e):
      return .conversationUpdated(ChatEventConversationUpdate(
        conversationId: e.convoId,
        kind: .muted,
        platform: .bluesky
      ))

    case .unmuteConvo(let e):
      return .conversationUpdated(ChatEventConversationUpdate(
        conversationId: e.convoId,
        kind: .unmuted,
        platform: .bluesky
      ))

    case .addReaction(let e):
      return .reactionAdded(ChatEventReaction(
        messageId: e.message?.id ?? "",
        conversationId: e.convoId,
        value: e.value ?? "",
        senderId: e.sender?.did ?? "",
        platform: .bluesky
      ))

    case .removeReaction(let e):
      return .reactionRemoved(ChatEventReaction(
        messageId: e.message?.id ?? "",
        conversationId: e.convoId,
        value: e.value ?? "",
        senderId: e.sender?.did ?? "",
        platform: .bluesky
      ))

    case .unknown(let type):
      print("[BlueskyChat] Unknown log event type: \(type)")
      return nil
    }
  }
}

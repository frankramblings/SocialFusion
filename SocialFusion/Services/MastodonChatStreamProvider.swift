import Foundation

final class MastodonChatStreamProvider: ChatStreamProvider, @unchecked Sendable {
  private var webSocketTask: URLSessionWebSocketTask?
  private var continuation: AsyncStream<UnifiedChatEvent>.Continuation?
  private var reconnectAttempt = 0
  private var isStopped = false
  private var currentAccount: SocialAccount?
  private let mastodonService: MastodonService

  private(set) var connectionState: ChatConnectionState = .disconnected

  init(mastodonService: MastodonService) {
    self.mastodonService = mastodonService
  }

  func eventStream(for account: SocialAccount, conversationId: String?) -> AsyncStream<UnifiedChatEvent> {
    stop()
    isStopped = false
    currentAccount = account
    reconnectAttempt = 0

    return AsyncStream { continuation in
      self.continuation = continuation
      continuation.onTermination = { @Sendable _ in
        self.cleanupWebSocket()
      }
      Task { await self.connect(account: account) }
    }
  }

  func stop() {
    isStopped = true
    cleanupWebSocket()
    continuation?.finish()
    continuation = nil
    connectionState = .disconnected
  }

  // MARK: - WebSocket Connection

  private func connect(account: SocialAccount) async {
    guard !isStopped else { return }
    connectionState = reconnectAttempt == 0 ? .connecting : .reconnecting(attempt: reconnectAttempt)

    let streamingURL = await discoverStreamingURL(account: account)

    guard let url = URL(string: "\(streamingURL)?stream=direct&access_token=\(account.accessToken ?? "")") else {
      connectionState = .error("Invalid streaming URL")
      return
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = 300

    let session = URLSession(configuration: .default)
    let task = session.webSocketTask(with: request)
    webSocketTask = task
    task.resume()

    connectionState = .connected
    reconnectAttempt = 0
    print("[MastodonChat] WebSocket connected to \(streamingURL)")

    await receiveLoop()
  }

  private func receiveLoop() async {
    guard let task = webSocketTask else { return }

    while !isStopped {
      do {
        let message = try await task.receive()
        switch message {
        case .string(let text):
          handleStreamMessage(text)
        case .data(let data):
          if let text = String(data: data, encoding: .utf8) {
            handleStreamMessage(text)
          }
        @unknown default:
          break
        }
      } catch {
        guard !isStopped else { return }
        print("[MastodonChat] WebSocket error: \(error.localizedDescription)")
        await handleDisconnect()
        return
      }
    }
  }

  private func handleStreamMessage(_ text: String) {
    // Mastodon streaming sends JSON: {"stream":["direct"],"event":"conversation","payload":"..."}
    guard let data = text.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let event = json["event"] as? String,
          event == "conversation",
          let payloadString = json["payload"] as? String,
          let payloadData = payloadString.data(using: .utf8)
    else { return }

    // Payload is a Mastodon Conversation object with lastStatus
    guard let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
          let lastStatus = payload["last_status"] as? [String: Any],
          let statusId = lastStatus["id"] as? String,
          let content = lastStatus["content"] as? String,
          let createdAtString = lastStatus["created_at"] as? String,
          let account = lastStatus["account"] as? [String: Any],
          let senderId = account["id"] as? String,
          let senderName = account["display_name"] as? String ?? account["acct"] as? String,
          let conversationId = payload["id"] as? String
    else { return }

    let sentAt = DateParser.parse(createdAtString) ?? Date()
    let plainText = HTMLString(raw: content).plainText

    let chatEvent = UnifiedChatEvent.newMessage(ChatEventMessage(
      id: statusId,
      conversationId: conversationId,
      senderDisplayName: senderName,
      senderId: senderId,
      text: plainText,
      sentAt: sentAt,
      platform: .mastodon,
      unifiedMessage: nil
    ))

    continuation?.yield(chatEvent)
  }

  // MARK: - Reconnection

  private func handleDisconnect() async {
    guard !isStopped, let account = currentAccount else { return }
    reconnectAttempt += 1
    let delay = min(Double(1 << reconnectAttempt), 30.0) // 2, 4, 8, ... max 30s
    connectionState = .reconnecting(attempt: reconnectAttempt)
    print("[MastodonChat] Reconnecting in \(delay)s (attempt \(reconnectAttempt))")

    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    guard !isStopped else { return }

    // REST catch-up: fetch recent conversations to fill the gap
    do {
      let conversations = try await mastodonService.fetchConversations(account: account)
      for convo in conversations {
        let event = UnifiedChatEvent.newMessage(ChatEventMessage(
          id: convo.lastMessage.id,
          conversationId: convo.id,
          senderDisplayName: convo.participant.displayName ?? convo.participant.username,
          senderId: convo.participant.id,
          text: convo.lastMessage.content,
          sentAt: convo.lastMessage.createdAt,
          platform: .mastodon,
          unifiedMessage: nil
        ))
        continuation?.yield(event)
      }
    } catch {
      print("[MastodonChat] REST catch-up failed: \(error.localizedDescription)")
    }

    await connect(account: account)
  }

  // MARK: - Helpers

  private func discoverStreamingURL(account: SocialAccount) async -> String {
    let serverURL = mastodonService.formatServerURL(account.serverURL?.absoluteString ?? "")

    // Try v2 instance endpoint for streaming URL
    if let url = URL(string: "\(serverURL)/api/v2/instance"),
       let (data, _) = try? await URLSession.shared.data(from: url),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let config = json["configuration"] as? [String: Any],
       let urls = config["urls"] as? [String: Any],
       let streaming = urls["streaming"] as? String {
      return streaming
    }

    // Fallback to wss://<host>/api/v1/streaming
    if let host = URL(string: serverURL)?.host {
      return "wss://\(host)/api/v1/streaming"
    }

    return "\(serverURL)/api/v1/streaming"
  }

  private func cleanupWebSocket() {
    webSocketTask?.cancel(with: .goingAway, reason: nil)
    webSocketTask = nil
  }
}

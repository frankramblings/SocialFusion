import Foundation

/// Protocol abstracting real-time chat event delivery.
/// Mastodon uses WebSocket streaming; Bluesky uses cursor-based polling.
protocol ChatStreamProvider {
  func eventStream(for account: SocialAccount, conversationId: String?) -> AsyncStream<UnifiedChatEvent>
  func stop()
  var connectionState: ChatConnectionState { get }
}

import Combine
import Foundation

@MainActor
final class ChatStreamService: ObservableObject {
  @Published var recentEvents: [UnifiedChatEvent] = []
  @Published var connectionStates: [String: ChatConnectionState] = [:]

  private var providers: [String: any ChatStreamProvider] = [:]
  private var activeTasks: [String: Task<Void, Never>] = [:]
  private var seenMessageIds: Set<String> = []

  private var mastodonService: MastodonService?
  private var blueskyService: BlueskyService?

  private let maxEvents = 100
  private let trimTarget = 50

  func configure(mastodonService: MastodonService, blueskyService: BlueskyService) {
    self.mastodonService = mastodonService
    self.blueskyService = blueskyService
  }

  // MARK: - Lifecycle API

  /// Start streaming for all accounts at list-view poll rate (DirectMessagesView)
  func startListStreaming(accounts: [SocialAccount]) {
    stopAllStreaming()
    for account in accounts {
      startProvider(for: account, conversationId: nil)
    }
  }

  /// Start streaming for a specific conversation (ChatView)
  func startConversationStreaming(conversation: DMConversation, accounts: [SocialAccount]) {
    stopAllStreaming()
    // Find the relevant account for this conversation's platform
    if let account = accounts.first(where: { $0.platform == conversation.platform }) {
      startProvider(for: account, conversationId: conversation.id)
    }
  }

  /// Stop all streaming and clean up
  func stopAllStreaming() {
    for (_, task) in activeTasks {
      task.cancel()
    }
    activeTasks.removeAll()
    for (_, provider) in providers {
      provider.stop()
    }
    providers.removeAll()
    connectionStates.removeAll()
    seenMessageIds.removeAll()
    recentEvents.removeAll()
  }

  /// Adjust Bluesky poll rate when navigating between list and chat
  func transitionToConversation(_ conversationId: String) {
    for (key, provider) in providers {
      if let bskyProvider = provider as? BlueskyPollStreamProvider {
        bskyProvider.updatePollInterval(activeChat: true)
        print("[ChatStream] Bluesky provider \(key) → active chat interval")
      }
    }
  }

  func transitionToList() {
    for (key, provider) in providers {
      if let bskyProvider = provider as? BlueskyPollStreamProvider {
        bskyProvider.updatePollInterval(activeChat: false)
        print("[ChatStream] Bluesky provider \(key) → list interval")
      }
    }
  }

  // MARK: - Provider Management

  private func startProvider(for account: SocialAccount, conversationId: String?) {
    let key = account.id

    // Create platform-appropriate provider
    let provider: any ChatStreamProvider
    switch account.platform {
    case .mastodon:
      guard let mastodonService else {
        print("[ChatStream] MastodonService not configured")
        return
      }
      provider = MastodonChatStreamProvider(mastodonService: mastodonService)

    case .bluesky:
      guard let blueskyService else {
        print("[ChatStream] BlueskyService not configured")
        return
      }
      provider = BlueskyPollStreamProvider(blueskyService: blueskyService)
    }

    providers[key] = provider
    connectionStates[key] = .connecting

    let stream = provider.eventStream(for: account, conversationId: conversationId)

    let task = Task { [weak self] in
      for await event in stream {
        guard let self, !Task.isCancelled else { break }
        self.handleEvent(event, providerKey: key)
        self.connectionStates[key] = provider.connectionState
      }
    }

    activeTasks[key] = task
    print("[ChatStream] Started provider for \(account.platform.rawValue) account \(account.username)")
  }

  private func handleEvent(_ event: UnifiedChatEvent, providerKey: String) {
    // Deduplicate new messages
    if case .newMessage(let msg) = event {
      guard !seenMessageIds.contains(msg.id) else { return }
      seenMessageIds.insert(msg.id)
      // Trim seen IDs to prevent unbounded growth
      if seenMessageIds.count > 500 {
        seenMessageIds = Set(seenMessageIds.suffix(250))
      }
    }

    recentEvents.append(event)

    // Trim events buffer
    if recentEvents.count > maxEvents {
      recentEvents = Array(recentEvents.suffix(trimTarget))
    }
  }
}

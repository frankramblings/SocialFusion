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
      case .conversationUpdated(let update) where update.kind == .began:
        Task { await fetchConversations(serviceManager: serviceManager) }
      default:
        break
      }
    }
  }
}

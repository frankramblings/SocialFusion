import SwiftUI

@MainActor
class MessagesViewModel: ObservableObject {
  @Published var conversations: [DMConversation] = []
  @Published var isLoading = false
  @Published var errorMessage: String?
  @Published var showNewConversation = false
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
      case .conversationUpdated(let update):
        switch update.kind {
        case .began, .accepted:
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
        }
      case .readReceipt(let receipt):
        readStates[receipt.conversationId] = Date()
      default:
        break
      }
    }
  }
}

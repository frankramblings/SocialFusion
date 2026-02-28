import Foundation

// MARK: - Connection State

enum ChatConnectionState: Equatable {
  case disconnected
  case connecting
  case connected
  case reconnecting(attempt: Int)
  case error(String)
}

// MARK: - Unified Chat Events

enum UnifiedChatEvent: Identifiable {
  case newMessage(ChatEventMessage)
  case deletedMessage(ChatEventDeletedMessage)
  case conversationUpdated(ChatEventConversationUpdate)
  case readReceipt(ChatEventReadReceipt)
  case reactionAdded(ChatEventReaction)
  case reactionRemoved(ChatEventReaction)
  case typingIndicator(ChatEventTypingIndicator)

  var id: String {
    switch self {
    case .newMessage(let m): return "msg-\(m.id)"
    case .deletedMessage(let d): return "del-\(d.messageId)"
    case .conversationUpdated(let c): return "conv-\(c.conversationId)-\(c.kind)"
    case .readReceipt(let r): return "read-\(r.conversationId)-\(r.accountId)"
    case .reactionAdded(let r): return "react-add-\(r.messageId)-\(r.value)"
    case .reactionRemoved(let r): return "react-rm-\(r.messageId)-\(r.value)"
    case .typingIndicator(let t): return "typing-\(t.conversationId)-\(t.senderId)"
    }
  }

  var conversationId: String {
    switch self {
    case .newMessage(let m): return m.conversationId
    case .deletedMessage(let d): return d.conversationId
    case .conversationUpdated(let c): return c.conversationId
    case .readReceipt(let r): return r.conversationId
    case .reactionAdded(let r): return r.conversationId
    case .reactionRemoved(let r): return r.conversationId
    case .typingIndicator(let t): return t.conversationId
    }
  }
}

// MARK: - Event Payloads

struct ChatEventMessage: Identifiable {
  let id: String
  let conversationId: String
  let senderDisplayName: String
  let senderId: String
  let text: String
  let sentAt: Date
  let platform: SocialPlatform
  /// The raw unified message for direct insertion into ChatView
  let unifiedMessage: UnifiedChatMessage?
}

struct ChatEventDeletedMessage {
  let messageId: String
  let conversationId: String
  let platform: SocialPlatform
}

struct ChatEventConversationUpdate {
  enum Kind: String {
    case began, accepted, left, muted, unmuted
  }
  let conversationId: String
  let kind: Kind
  let platform: SocialPlatform
}

struct ChatEventReadReceipt {
  let conversationId: String
  let accountId: String
  let platform: SocialPlatform
}

struct ChatEventReaction {
  let messageId: String
  let conversationId: String
  let value: String
  let senderId: String
  let platform: SocialPlatform
}

struct ChatEventTypingIndicator {
  let conversationId: String
  let senderId: String
  let platform: SocialPlatform
}

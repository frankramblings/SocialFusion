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
    
    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if isLoading && messages.isEmpty {
                            ProgressView()
                                .padding()
                        } else {
                            ForEach(messages) { message in
                                MessageBubble(message: message, isFromMe: isFromMe(message))
                                    .id(message.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            HStack(spacing: 12) {
                TextField("Message...", text: $newMessageText)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                
                Button(action: sendMessage) {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.8)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.blue)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.white)
                            .padding(10)
                            .background(newMessageText.isEmpty ? Color.gray : Color.blue)
                            .clipShape(Circle())
                    }
                }
                .disabled(newMessageText.isEmpty || isLoading || isSending)
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .navigationTitle(conversation.participant.displayName ?? conversation.participant.username)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { 
                errorMessage = nil 
            }
            if errorMessage != nil {
                Button("Retry") {
                    errorMessage = nil
                    loadMessages()
                }
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
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
                    // Deduplicate by ID
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
    
    private func loadMessages() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let fetchedMessages = try await serviceManager.fetchConversationMessages(conversation: conversation)
                await MainActor.run {
                    self.messages = fetchedMessages.reversed() // Oldest first for chat view
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load messages: \(error.localizedDescription)"
                    self.isLoading = false
                    ErrorHandler.shared.handleError(error) {
                        self.loadMessages()
                    }
                }
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
                let sentMessage = try await serviceManager.sendChatMessage(conversation: conversation, text: text)
                await MainActor.run {
                    self.messages.append(sentMessage)
                    self.isSending = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to send message: \(error.localizedDescription)"
                    self.newMessageText = text // Restore text for retry
                    self.isSending = false
                    ErrorHandler.shared.handleError(error) {
                        self.sendMessage()
                    }
                }
            }
        }
    }
    
    private func isFromMe(_ message: UnifiedChatMessage) -> Bool {
        // Check if sender matches any of our accounts
        let senderId = message.authorId
        return serviceManager.accounts.contains { account in
            account.platformSpecificId == senderId
        }
    }
}

struct MessageBubble: View {
    let message: UnifiedChatMessage
    let isFromMe: Bool
    
    var body: some View {
        HStack {
            if isFromMe { Spacer() }
            
            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {
                messageContentView
                    .padding(12)
                    .background(isFromMe ? Color.blue : Color(.systemGray5))
                    .foregroundColor(isFromMe ? .white : .primary)
                    .cornerRadius(18)
                
                Text(message.sentAt, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !isFromMe { Spacer() }
        }
    }
    
    @ViewBuilder
    private var messageContentView: some View {
        // UnifiedChatMessage.text now handles HTML conversion for Mastodon
        if message.text.isEmpty || message.text == "(Empty message)" {
            Text("(Empty message)")
                .italic()
                .foregroundColor(.secondary)
        } else {
            Text(message.text)
        }
    }
}


import SwiftUI

struct ChatView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    let conversation: DMConversation
    
    @State private var messages: [BlueskyChatMessage] = []
    @State private var newMessageText = ""
    @State private var isLoading = false
    
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
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .padding(10)
                        .background(newMessageText.isEmpty ? Color.gray : Color.blue)
                        .clipShape(Circle())
                }
                .disabled(newMessageText.isEmpty || isLoading)
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .navigationTitle(conversation.participant.displayName ?? conversation.participant.username)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadMessages()
        }
    }
    
    private func loadMessages() {
        guard conversation.platform == .bluesky else { return }
        
        isLoading = true
        Task {
            // Find the account for this conversation
            if let account = serviceManager.blueskyAccounts.first(where: { account in
                // In a real app, you'd track which account owns which conversation
                // For now, we'll try to find an account that has this conversation
                return true 
            }) {
                do {
                    let fetchedMessages = try await serviceManager.blueskyService.fetchMessages(convoId: conversation.id, for: account)
                    await MainActor.run {
                        self.messages = fetchedMessages.reversed() // Oldest first for chat view
                        self.isLoading = false
                    }
                } catch {
                    print("Failed to fetch messages: \(error)")
                    await MainActor.run { self.isLoading = false }
                }
            }
        }
    }
    
    private func sendMessage() {
        guard !newMessageText.isEmpty else { return }
        let text = newMessageText
        newMessageText = ""
        
        guard conversation.platform == .bluesky else { return }
        
        Task {
            if let account = serviceManager.blueskyAccounts.first {
                do {
                    let sentMessage = try await serviceManager.blueskyService.sendMessage(convoId: conversation.id, text: text, for: account)
                    await MainActor.run {
                        self.messages.append(.message(sentMessage))
                    }
                } catch {
                    print("Failed to send message: \(error)")
                }
            }
        }
    }
    
    private func isFromMe(_ message: BlueskyChatMessage) -> Bool {
        // Simple heuristic: if the sender DID matches one of our accounts
        switch message {
        case .message(let view):
            return serviceManager.accounts.contains { $0.platformSpecificId == view.sender.did }
        case .deleted:
            return false
        }
    }
}

struct MessageBubble: View {
    let message: BlueskyChatMessage
    let isFromMe: Bool
    
    var body: some View {
        HStack {
            if isFromMe { Spacer() }
            
            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {
                switch message {
                case .message(let view):
                    Text(view.text)
                        .padding(12)
                        .background(isFromMe ? Color.blue : Color(.systemGray5))
                        .foregroundColor(isFromMe ? .white : .primary)
                        .cornerRadius(18)
                case .deleted:
                    Text("(Deleted Message)")
                        .italic()
                        .padding(12)
                        .background(Color(.systemGray6))
                        .foregroundColor(.secondary)
                        .cornerRadius(18)
                }
            }
            
            if !isFromMe { Spacer() }
        }
    }
}


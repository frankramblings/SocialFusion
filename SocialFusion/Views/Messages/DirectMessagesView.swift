import SwiftUI

struct DirectMessagesView: View {
  @EnvironmentObject var serviceManager: SocialServiceManager
  @EnvironmentObject var chatStreamService: ChatStreamService
  @StateObject private var viewModel = MessagesViewModel()

  @Binding var showComposeView: Bool
  @Binding var showValidationView: Bool

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        if viewModel.isLoading && viewModel.conversations.isEmpty {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
          .padding(.top, 40)
        } else if viewModel.conversations.isEmpty {
          emptyState
        } else {
          ForEach(viewModel.conversations) { conversation in
            NavigationLink(destination: ChatView(conversation: conversation)) {
              DMConversationRow(conversation: conversation)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(PlainButtonStyle())

            if conversation.id != viewModel.conversations.last?.id {
              Divider()
                .padding(.leading, 78)
                .padding(.trailing, 16)
            }
          }
        }
      }
    }
    .refreshable {
      await viewModel.fetchConversations(serviceManager: serviceManager)
      HapticEngine.tap.trigger()
    }
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          viewModel.showNewConversation = true
        } label: {
          Image(systemName: "square.and.pencil")
            .font(.system(size: 18))
            .foregroundColor(.primary)
        }
        .simultaneousGesture(
          LongPressGesture(minimumDuration: 1.0)
            .onEnded { _ in showValidationView = true }
        )
      }
    }
    .navigationTitle("Messages")
    .navigationBarTitleDisplayMode(.large)
    .sheet(isPresented: $viewModel.showNewConversation) {
      NewConversationView()
        .environmentObject(serviceManager)
    }
    .sheet(isPresented: $showValidationView) {
      TimelineValidationDebugView(serviceManager: serviceManager)
    }
    .onAppear {
      Task {
        await viewModel.fetchConversations(serviceManager: serviceManager)
      }
      chatStreamService.startListStreaming(accounts: serviceManager.accounts)
    }
    .onDisappear {
      chatStreamService.stopAllStreaming()
    }
    .onReceive(chatStreamService.$recentEvents) { events in
      viewModel.handleStreamEvents(events, serviceManager: serviceManager)
    }
    .alert("Error", isPresented: Binding(
      get: { viewModel.errorMessage != nil },
      set: { if !$0 { viewModel.errorMessage = nil } }
    )) {
      Button("OK") { viewModel.errorMessage = nil }
      Button("Retry") {
        viewModel.errorMessage = nil
        Task { await viewModel.fetchConversations(serviceManager: serviceManager) }
      }
    } message: {
      if let error = viewModel.errorMessage { Text(error) }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      Image(systemName: "bubble.left.and.bubble.right")
        .font(.system(size: 48))
        .foregroundColor(.secondary.opacity(0.4))

      Text("No messages yet")
        .font(.title3)
        .fontWeight(.semibold)
        .foregroundColor(.secondary)

      Button {
        viewModel.showNewConversation = true
      } label: {
        Text("Start a conversation")
          .font(.subheadline)
          .fontWeight(.medium)
          .foregroundColor(.white)
          .padding(.horizontal, 20)
          .padding(.vertical, 10)
          .background(Capsule().fill(Color.blue))
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 100)
  }
}

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
        #if DEBUG
        .simultaneousGesture(
          LongPressGesture(minimumDuration: 1.0)
            .onEnded { _ in showValidationView = true }
        )
        #endif
      }
    }
    .navigationTitle("Messages")
    .navigationBarTitleDisplayMode(.large)
    .sheet(isPresented: $viewModel.showNewConversation) {
      NewConversationView()
        .environmentObject(serviceManager)
    }
    #if DEBUG
    .sheet(isPresented: $showValidationView) {
      TimelineValidationDebugView(serviceManager: serviceManager)
    }
    #endif
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
    VStack(spacing: 18) {
      ZStack {
        Circle()
          .fill(
            RadialGradient(
              colors: [Color.accentColor.opacity(0.14), Color.accentColor.opacity(0.0)],
              center: .center,
              startRadius: 4,
              endRadius: 70
            )
          )
          .frame(width: 140, height: 140)

        Image(systemName: "bubble.left.and.bubble.right")
          .font(.system(size: 44, weight: .light))
          .foregroundStyle(Color.accentColor.gradient)
          .symbolRenderingMode(.hierarchical)
      }

      VStack(spacing: 6) {
        Text("No messages yet")
          .font(.title3.weight(.semibold))
          .foregroundColor(.primary.opacity(0.85))

        Text("Start a conversation with anyone on Bluesky or Mastodon.")
          .font(.subheadline)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 40)
          .fixedSize(horizontal: false, vertical: true)
      }

      Button {
        HapticEngine.tap.trigger()
        viewModel.showNewConversation = true
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "square.and.pencil")
            .font(.subheadline.weight(.semibold))
          Text("Start a conversation")
            .font(.subheadline.weight(.semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(
          Capsule()
            .fill(Color.accentColor.gradient)
            .shadow(color: Color.accentColor.opacity(0.32), radius: 10, x: 0, y: 4)
        )
      }
      .buttonStyle(MessagesPressStyle())
      .padding(.top, 4)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 80)
    .padding(.bottom, 40)
  }
}

private struct MessagesPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
      .opacity(configuration.isPressed ? 0.9 : 1.0)
      .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
  }
}

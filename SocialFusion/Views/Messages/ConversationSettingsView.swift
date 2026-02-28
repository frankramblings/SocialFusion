import SwiftUI

struct ConversationSettingsView: View {
  @EnvironmentObject var serviceManager: SocialServiceManager
  @Environment(\.dismiss) private var dismiss
  let conversation: DMConversation
  let onLeave: () -> Void

  @State private var isMuted: Bool
  @State private var showLeaveConfirm = false
  @State private var isUpdating = false

  init(conversation: DMConversation, onLeave: @escaping () -> Void) {
    self.conversation = conversation
    self.onLeave = onLeave
    _isMuted = State(initialValue: conversation.isMuted)
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack(spacing: 12) {
            if let urlString = conversation.participant.avatarURL,
               let url = URL(string: urlString) {
              CachedAsyncImage(url: url, priority: .high) { image in
                image.resizable().aspectRatio(contentMode: .fill)
              } placeholder: {
                Circle().fill(Color.gray.opacity(0.3))
              }
              .frame(width: 56, height: 56)
              .clipShape(Circle())
            } else {
              Circle().fill(Color.gray.opacity(0.3))
                .frame(width: 56, height: 56)
            }

            VStack(alignment: .leading, spacing: 4) {
              if let name = conversation.participant.displayName {
                Text(name).font(.headline)
              }
              Text("@\(conversation.participant.username)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            Spacer()
            PostPlatformBadge(platform: conversation.platform)
              .scaleEffect(0.85)
          }
          .listRowBackground(Color.clear)
        }

        if conversation.platform == .bluesky {
          Section {
            Toggle("Mute Conversation", isOn: $isMuted)
              .disabled(isUpdating)
              .onChange(of: isMuted) { _, newValue in
                toggleMute(muted: newValue)
              }
          } footer: {
            Text("Muted conversations won't send notifications.")
          }

          Section {
            Button(role: .destructive) {
              showLeaveConfirm = true
            } label: {
              Label("Leave Conversation", systemImage: "arrow.right.square")
            }
          }
        }
      }
      .navigationTitle("Conversation")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .alert("Leave Conversation", isPresented: $showLeaveConfirm) {
        Button("Leave", role: .destructive) { leaveConversation() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("You'll no longer see this conversation.")
      }
    }
  }

  private func toggleMute(muted: Bool) {
    isUpdating = true
    Task {
      do {
        if muted {
          try await serviceManager.muteConversation(conversation)
        } else {
          try await serviceManager.unmuteConversation(conversation)
        }
      } catch {
        isMuted = !muted
      }
      isUpdating = false
    }
  }

  private func leaveConversation() {
    Task {
      do {
        try await serviceManager.leaveConversation(conversation)
        dismiss()
        onLeave()
      } catch {
        // Silently fail
      }
    }
  }
}

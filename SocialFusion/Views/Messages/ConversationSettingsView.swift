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

  /// Initials derived from the participant's display name or username.
  private var initials: String {
    let name = conversation.participant.displayName ?? conversation.participant.username
    return PostAuthorImageView.generateInitials(from: name)
  }

  /// Stable hue derived from the username so the placeholder isn't a
  /// monotone gray — matches PostAuthorImageView's fallback convention.
  private var placeholderHue: Double {
    let key = conversation.participant.username
    return Double(abs(key.hashValue) % 360) / 360.0
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack(spacing: 14) {
            avatarView
              .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 3) {
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
          .padding(.vertical, 4)
          .listRowBackground(Color.clear)
        }

        if conversation.platform == .bluesky {
          Section {
            Toggle(isOn: $isMuted) {
              Label {
                Text("Mute Conversation")
              } icon: {
                Image(systemName: "speaker.slash")
                  .foregroundStyle(Color.orange.gradient)
                  .symbolRenderingMode(.hierarchical)
              }
            }
            .disabled(isUpdating)
            .onChange(of: isMuted) { _, newValue in
              HapticEngine.selection.trigger()
              toggleMute(muted: newValue)
            }
          } footer: {
            Text("Muted conversations won't send notifications.")
          }

          Section {
            Button(role: .destructive) {
              HapticEngine.warning.trigger()
              showLeaveConfirm = true
            } label: {
              Label {
                Text("Leave Conversation")
              } icon: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                  .foregroundStyle(Color.red.gradient)
                  .symbolRenderingMode(.hierarchical)
              }
            }
          }
        }
      }
      .navigationTitle("Conversation")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            HapticEngine.tap.trigger()
            dismiss()
          }
          .fontWeight(.semibold)
        }
      }
      .alert("Leave Conversation", isPresented: $showLeaveConfirm) {
        Button("Leave", role: .destructive) {
          HapticEngine.warning.trigger()
          leaveConversation()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("You'll no longer see this conversation.")
      }
    }
  }

  /// Avatar with initials fallback and stable per-username hue — matches
  /// the avatar treatment used everywhere else in the app.
  @ViewBuilder
  private var avatarView: some View {
    Group {
      if let urlString = conversation.participant.avatarURL,
         let url = URL(string: urlString) {
        CachedAsyncImage(url: url, priority: .high) { image in
          image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
          initialsPlaceholder
        }
      } else {
        initialsPlaceholder
      }
    }
    .clipShape(Circle())
  }

  private var initialsPlaceholder: some View {
    Circle()
      .fill(
        LinearGradient(
          colors: [
            Color(hue: placeholderHue, saturation: 0.55, brightness: 0.78),
            Color(hue: placeholderHue, saturation: 0.75, brightness: 0.6),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .overlay(
        Group {
          if !initials.isEmpty {
            Text(initials)
              .font(.title3.weight(.semibold).monospacedDigit())
              .foregroundColor(.white)
          } else {
            Image(systemName: "person.fill")
              .foregroundColor(.white.opacity(0.85))
              .font(.title3)
          }
        }
      )
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

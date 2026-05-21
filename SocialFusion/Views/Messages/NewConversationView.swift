import SwiftUI

struct NewConversationView: View {
  @EnvironmentObject var serviceManager: SocialServiceManager
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var searchText = ""
  @State private var blueskyResults: [BlueskyActor] = []
  @State private var mastodonResults: [MastodonAccount] = []
  @State private var isSearching = false
  @State private var selectedConversation: DMConversation?
  @State private var navigateToChat = false
  @State private var searchTask: Task<Void, Never>?
  @State private var errorMessage: String?
  @State private var selectedParticipants: [BlueskyActor] = []

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if !selectedParticipants.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(selectedParticipants, id: \.did) { actor in
                HStack(spacing: 5) {
                  Text(actor.displayName ?? actor.handle)
                    .font(.caption.weight(.semibold))
                  Button {
                    HapticEngine.tap.trigger()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
                      selectedParticipants.removeAll { $0.did == actor.did }
                    }
                  } label: {
                    Image(systemName: "xmark.circle.fill")
                      .font(.caption)
                      .foregroundStyle(Color.accentColor.opacity(0.85), Color.accentColor.opacity(0.16))
                      .symbolRenderingMode(.palette)
                  }
                  .buttonStyle(.plain)
                  .accessibilityLabel("Remove \(actor.displayName ?? actor.handle)")
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                  Capsule()
                    .fill(Color.accentColor.opacity(0.14))
                    .overlay(
                      Capsule()
                        .strokeBorder(Color.accentColor.opacity(0.24), lineWidth: 0.5)
                    )
                )
                .transition(
                  reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .scale(scale: 0.7).combined(with: .opacity),
                        removal: .scale(scale: 0.7).combined(with: .opacity)
                      )
                )
              }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
          }
          .overlay(
            Divider(),
            alignment: .bottom
          )
        }

        List {
          if isSearching {
            HStack {
              Spacer()
              ProgressView()
              Spacer()
            }
            .listRowBackground(Color.clear)
          }

          if !blueskyResults.isEmpty {
            Section("Bluesky") {
              ForEach(blueskyResults, id: \.did) { actor in
                Button {
                  HapticEngine.selection.trigger()
                  withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    toggleBlueskySelection(actor)
                  }
                } label: {
                  HStack {
                    userRow(
                      avatarURL: actor.avatar,
                      displayName: actor.displayName,
                      handle: actor.handle,
                      platform: .bluesky
                    )
                    if selectedParticipants.contains(where: { $0.did == actor.did }) {
                      // Brand checkmark via SocialPlatform.swiftUIColor
                      // — was a hand-rolled RGB tuple for Bluesky blue.
                      Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, SocialPlatform.bluesky.swiftUIColor)
                        .symbolRenderingMode(.palette)
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                    }
                  }
                }
              }
            }
          }

          if !mastodonResults.isEmpty {
            Section("Mastodon") {
              ForEach(mastodonResults, id: \.id) { account in
                Button {
                  // Mastodon DMs are posts with direct visibility
                  // For now, just dismiss — user can use compose
                  dismiss()
                } label: {
                  userRow(
                    avatarURL: account.avatar,
                    displayName: account.displayName,
                    handle: account.acct,
                    platform: .mastodon
                  )
                }
              }
            }
          }

          if !isSearching && searchText.count >= 2
              && blueskyResults.isEmpty && mastodonResults.isEmpty {
            ContentUnavailableView(
              "No results",
              systemImage: "magnifyingglass",
              description: Text("No users found for \"\(searchText)\"")
            )
          }
        }
      }
      .searchable(text: $searchText, prompt: "Search people...")
      // Drop the keyboard the moment the list scrolls — feels right
      // when the user is browsing results, no need to keep typing space.
      .scrollDismissesKeyboard(.immediately)
      .onChange(of: searchText) { _, newValue in
        searchTask?.cancel()
        guard newValue.count >= 2 else {
          blueskyResults = []
          mastodonResults = []
          return
        }
        searchTask = Task {
          try? await Task.sleep(for: .milliseconds(300))
          guard !Task.isCancelled else { return }
          await performSearch(query: newValue)
        }
      }
      .navigationTitle("New Message")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            HapticEngine.tap.trigger()
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          if !selectedParticipants.isEmpty {
            Button(selectedParticipants.count > 1 ? "Create Group" : "Start Chat") {
              HapticEngine.tap.trigger()
              startConversationWithSelected()
            }
            .fontWeight(.semibold)
          }
        }
      }
      .navigationDestination(isPresented: $navigateToChat) {
        if let conversation = selectedConversation {
          ChatView(conversation: conversation)
        }
      }
      .alert("Couldn't Start Conversation", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK") { errorMessage = nil }
      } message: {
        if let error = errorMessage { Text(error) }
      }
    }
  }

  // MARK: - User Row

  /// Initials-fallback avatar — circle with the first letter of the
  /// display name (or handle) when no avatar URL is available, or as
  /// the placeholder while the AsyncImage is loading. Gives every
  /// account a recognizable identity even before the network resolves.
  private func avatarPlaceholder(initial: String) -> some View {
    Circle()
      .fill(Color(.systemGray5))
      .overlay(
        Text(initial.uppercased())
          .font(.subheadline.weight(.semibold))
          .foregroundColor(Color(.systemGray))
      )
  }

  private func userRow(
    avatarURL: String?,
    displayName: String?,
    handle: String,
    platform: SocialPlatform
  ) -> some View {
    HStack(spacing: 12) {
      if let avatarURL, let url = URL(string: avatarURL) {
        CachedAsyncImage(url: url, priority: .high) { image in
          image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
          avatarPlaceholder(initial: (displayName ?? handle).first.map { String($0) } ?? "?")
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
      } else {
        avatarPlaceholder(initial: (displayName ?? handle).first.map { String($0) } ?? "?")
          .frame(width: 40, height: 40)
      }

      VStack(alignment: .leading, spacing: 2) {
        // Decode HTML entities — Mastodon API ships display names
        // with raw entities (e.g. "Frank&#8217;s"). Same boundary fix
        // as the canonical EmojiDisplayNameText (afcbaa9). This view
        // builds plain Text directly, so it needs its own decode pass.
        Text((displayName ?? handle).decodingHTMLEntities)
          .font(.body)
          .fontWeight(.medium)
          .foregroundColor(.primary)
        Text("@\(handle)")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      Spacer()

      PostPlatformBadge(platform: platform)
        .scaleEffect(0.85)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(displayName ?? handle), @\(handle), on \(platform.rawValue.capitalized)")
  }

  // MARK: - Search

  private func performSearch(query: String) async {
    isSearching = true

    async let blueskySearch: [BlueskyActor] = searchBluesky(query: query)
    async let mastodonSearch: [MastodonAccount] = searchMastodon(query: query)

    let (bsky, masto) = await (blueskySearch, mastodonSearch)
    blueskyResults = bsky
    mastodonResults = masto
    isSearching = false
  }

  private func searchBluesky(query: String) async -> [BlueskyActor] {
    guard let account = serviceManager.accounts.first(where: { $0.platform == .bluesky }) else {
      return []
    }
    do {
      let response = try await serviceManager.blueskyService.searchActors(
        query: query, account: account, limit: 10
      )
      return response.actors
    } catch {
      return []
    }
  }

  private func searchMastodon(query: String) async -> [MastodonAccount] {
    guard let account = serviceManager.accounts.first(where: { $0.platform == .mastodon }) else {
      return []
    }
    do {
      let result = try await serviceManager.mastodonService.search(
        query: query, account: account, type: "accounts", limit: 10
      )
      return result.accounts
    } catch {
      return []
    }
  }

  // MARK: - Selection

  private func toggleBlueskySelection(_ actor: BlueskyActor) {
    // Selection haptic on add or remove — feels like every other iOS
    // selection toggle (Mail's recipient picker, Photos' multi-select).
    HapticEngine.selection.trigger()
    if selectedParticipants.contains(where: { $0.did == actor.did }) {
      selectedParticipants.removeAll { $0.did == actor.did }
    } else {
      selectedParticipants.append(actor)
    }
  }

  // MARK: - Conversation Creation

  private func startConversationWithSelected() {
    Task {
      do {
        let dids = selectedParticipants.map(\.did)
        let conversation = try await serviceManager.startOrFindBlueskyConversation(withDids: dids)
        await MainActor.run {
          HapticEngine.success.trigger()
          selectedConversation = conversation
          navigateToChat = true
        }
      } catch {
        await MainActor.run {
          HapticEngine.error.trigger()
          errorMessage = "Couldn't start the conversation: \(error.localizedDescription)"
        }
      }
    }
  }
}

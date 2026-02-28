import SwiftUI

struct NewConversationView: View {
  @EnvironmentObject var serviceManager: SocialServiceManager
  @Environment(\.dismiss) private var dismiss

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
                HStack(spacing: 4) {
                  Text(actor.displayName ?? actor.handle)
                    .font(.caption)
                    .fontWeight(.medium)
                  Button {
                    selectedParticipants.removeAll { $0.did == actor.did }
                  } label: {
                    Image(systemName: "xmark.circle.fill")
                      .font(.caption)
                      .foregroundColor(.secondary)
                  }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(.systemGray5)))
              }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
          }
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
                  toggleBlueskySelection(actor)
                } label: {
                  HStack {
                    userRow(
                      avatarURL: actor.avatar,
                      displayName: actor.displayName,
                      handle: actor.handle,
                      platform: .bluesky
                    )
                    if selectedParticipants.contains(where: { $0.did == actor.did }) {
                      Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
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
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          if !selectedParticipants.isEmpty {
            Button(selectedParticipants.count > 1 ? "Create Group" : "Start Chat") {
              startConversationWithSelected()
            }
          }
        }
      }
      .navigationDestination(isPresented: $navigateToChat) {
        if let conversation = selectedConversation {
          ChatView(conversation: conversation)
        }
      }
      .alert("Error", isPresented: Binding(
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
          Circle().fill(Color.gray.opacity(0.3))
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
      } else {
        Circle().fill(Color.gray.opacity(0.3))
          .frame(width: 40, height: 40)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(displayName ?? handle)
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
        selectedConversation = conversation
        navigateToChat = true
      } catch {
        errorMessage = "Failed to start conversation: \(error.localizedDescription)"
      }
    }
  }
}

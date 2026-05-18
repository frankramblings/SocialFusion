import SwiftUI

/// Sheet presented from a non-merged profile that lets the user manually bind
/// the current profile to its twin on the opposite network.
///
/// The heuristic matcher only auto-suggests merges when handles align by
/// convention (shared local-part, conventional or shared domains). For
/// everyone else — custom Bluesky domains, mismatched local-parts — the user
/// needs to be able to manually find and bind any two cross-network profiles
/// they know are the same person. That's what this sheet is for.
public struct ManualMergeSheet: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @Environment(\.dismiss) private var dismiss

    /// The profile we're matching FROM.
    public let sourceProfile: UserProfile
    /// The platform of the side we're searching ON (opposite of sourceProfile.platform).
    public let targetPlatform: SocialPlatform
    /// Called with the chosen twin once the user taps Confirm.
    public let onConfirm: (SearchUser, UserProfile) async -> Void

    @State private var query: String = ""
    @State private var results: [SearchUser] = []
    @State private var isSearching = false
    @State private var selectedCandidate: SearchUser?
    @State private var resolvedTwinProfile: UserProfile?
    @State private var searchTask: Task<Void, Never>?

    public init(
        sourceProfile: UserProfile,
        targetPlatform: SocialPlatform,
        onConfirm: @escaping (SearchUser, UserProfile) async -> Void
    ) {
        self.sourceProfile = sourceProfile
        self.targetPlatform = targetPlatform
        self.onConfirm = onConfirm
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                content
            }
            .navigationTitle("Mark as same person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(
                "Confirm merged identity",
                isPresented: Binding(
                    get: { selectedCandidate != nil },
                    set: { if !$0 { selectedCandidate = nil; resolvedTwinProfile = nil } }
                ),
                presenting: selectedCandidate
            ) { candidate in
                Button("Confirm", role: .none) {
                    if let twin = resolvedTwinProfile {
                        Task {
                            await onConfirm(candidate, twin)
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    selectedCandidate = nil
                    resolvedTwinProfile = nil
                }
            } message: { candidate in
                Text("@\(candidate.username) is the same person as @\(sourceProfile.username)? This will merge their profiles in SocialFusion.")
            }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search \(targetPlatform == .mastodon ? "Mastodon" : "Bluesky")", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: query) { _, newValue in
                    debouncedSearch(query: newValue)
                }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if isSearching {
            VStack { Spacer(); ProgressView(); Spacer() }
        } else if query.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "person.2.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Search for their account on \(targetPlatform == .mastodon ? "Mastodon" : "Bluesky")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
        } else if results.isEmpty {
            VStack { Spacer(); Text("No results").foregroundStyle(.secondary); Spacer() }
        } else {
            List(results) { user in
                Button {
                    selectCandidate(user)
                } label: {
                    HStack(spacing: 12) {
                        avatarView(for: user)
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName ?? user.username)
                                .font(.subheadline.weight(.semibold))
                            Text("@\(user.username)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        PlatformLogoBadge(platform: user.platform, size: 18)
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func avatarView(for user: SearchUser) -> some View {
        if let urlString = user.avatarURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle().fill(Color(.secondarySystemBackground))
            }
        } else {
            Circle().fill(Color(.secondarySystemBackground))
        }
    }

    private func debouncedSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            await runSearch(query: trimmed)
        }
    }

    private func runSearch(query: String) async {
        guard let account = serviceManager.accounts.first(where: { $0.platform == targetPlatform }) else {
            results = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            let users = try await serviceManager.searchUsers(query: query, account: account, limit: 10)
            results = users
        } catch {
            results = []
        }
    }

    private func selectCandidate(_ candidate: SearchUser) {
        Task {
            guard let account = serviceManager.accounts.first(where: { $0.platform == targetPlatform }) else { return }
            do {
                let twin = try await serviceManager.fetchUserProfile(user: candidate, account: account)
                resolvedTwinProfile = twin
                selectedCandidate = candidate
            } catch {
                // Surface a brief failure — for v1.0 just silently log/skip.
            }
        }
    }
}

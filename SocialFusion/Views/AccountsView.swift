import SwiftUI
import UIKit

struct AccountsView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingAddAccount = false
    @State private var selectedPlatform: SocialPlatform = .mastodon

    @State private var accountToDelete: SocialAccount? = nil
    @State private var showDeleteConfirmation = false
    @State private var showDebugInfo = false

    var body: some View {
        NavigationStack {
            List {
                // "All" selection option
                Section {
                    Button(action: {
                        toggleSelection(id: "all")
                    }) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.16))
                                    .frame(width: 32, height: 32)

                                Text("All")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.accentColor)
                            }

                            let isActive = serviceManager.selectedAccountIds.contains("all")
                            Text("All Accounts")
                                .font(.headline)
                                .fontWeight(isActive ? .semibold : .regular)

                            Spacer()

                            if isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white, Color.accentColor)
                                    .symbolRenderingMode(.palette)
                                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("All Accounts")
                    .accessibilityHint(
                        serviceManager.selectedAccountIds.contains("all")
                            ? "Currently selected. Tap to deselect"
                            : "Tap to select all accounts"
                    )
                    .accessibilityAddTraits(
                        serviceManager.selectedAccountIds.contains("all") ? .isSelected : []
                    )
                }

                // Accounts needing re-authentication section
                if let tokenRefreshService = serviceManager.automaticTokenRefreshService,
                    !tokenRefreshService.accountsNeedingReauth.isEmpty
                {
                    Section(
                        header: HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.orange.gradient)
                                .symbolRenderingMode(.hierarchical)
                            Text("Authentication Required")
                                .foregroundColor(.orange)
                        }
                    ) {
                        ForEach(tokenRefreshService.accountsNeedingReauth) { account in
                            reauthenticationRow(account, tokenRefreshService: tokenRefreshService)
                        }
                    }
                }

                // Mastodon accounts section
                Section(header: Text("Mastodon")) {
                    if serviceManager.mastodonAccounts.isEmpty {
                        addAccountButton(platform: .mastodon, label: "Add Mastodon Account")
                    } else {
                        ForEach(serviceManager.mastodonAccounts) { account in
                            accountSelectionRow(account)
                        }
                        addAccountButton(platform: .mastodon, label: "Add Another Mastodon Account")
                    }
                }

                // Bluesky accounts section
                Section(header: Text("Bluesky")) {
                    if serviceManager.blueskyAccounts.isEmpty {
                        addAccountButton(platform: .bluesky, label: "Add Bluesky Account")
                    } else {
                        ForEach(serviceManager.blueskyAccounts) { account in
                            accountSelectionRow(account)
                        }
                        addAccountButton(platform: .bluesky, label: "Add Another Bluesky Account")
                    }
                }

                Section(header: Text("Settings")) {
                    NavigationLink(destination: SettingsView()) {
                        HStack(spacing: 12) {
                            tintedTile(symbol: "gear", tint: .gray)
                            Text("Settings")
                        }
                    }

                    // Hidden debug toggle
                    Button {
                        HapticEngine.tap.trigger()
                        showDebugInfo.toggle()
                    } label: {
                        HStack(spacing: 12) {
                            tintedTile(symbol: "ladybug.fill", tint: .green)
                            Text("Debug Info")
                                .foregroundColor(.primary)
                        }
                    }
                    .accessibilityHint(showDebugInfo ? "Hides debug information" : "Shows debug information")
                }
            }

            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showingAddAccount) {
                AddAccountView()
                    .environmentObject(serviceManager)
            }
            .alert("Remove Account", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    accountToDelete = nil
                }
                Button("Remove", role: .destructive) {
                    HapticEngine.warning.trigger()
                    if let account = accountToDelete {
                        let removedName = account.displayName ?? "@\(account.username)"
                        Task {
                            await serviceManager.removeAccount(account)
                            // Remove account from selected IDs if it was selected
                            serviceManager.selectedAccountIds.remove(account.id)

                            // If no accounts remain, select "all"
                            if serviceManager.mastodonAccounts.isEmpty
                                && serviceManager.blueskyAccounts.isEmpty
                            {
                                serviceManager.selectedAccountIds = ["all"]
                            } else if serviceManager.selectedAccountIds.isEmpty {
                                serviceManager.selectedAccountIds.insert("all")
                            }

                            // Update service manager's selection
                            serviceManager.selectedAccountIds = serviceManager.selectedAccountIds

                            await MainActor.run {
                                ToastManager.shared.show("Removed \(removedName)", severity: .success, duration: 1.6)
                            }
                        }
                    }
                }
            } message: {
                let name = accountToDelete?.displayName ?? accountToDelete?.username ?? "this account"
                Text(
                    "Remove \(name) from this device? You can add it again later."
                )
            }
            .onAppear {
                // Small delay to prevent rapid successive calls
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    refreshAccountSelections()
                }
                #if DEBUG
                print(
                    "AccountsView appeared. Mastodon accounts: \(serviceManager.mastodonAccounts.count), Bluesky accounts: \(serviceManager.blueskyAccounts.count)"
                )
                #endif
            }
        }
    }

    // Account row with selection toggle
    /// Colored leading-icon tile matching SettingsView's SettingsIcon
    /// pattern. Mirrors ContentView's tintedTile (same dimensions and
    /// styling) for visual consistency across the Settings entry points.
    @ViewBuilder
    private func tintedTile(symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.gradient)
            )
            .accessibilityHidden(true)
    }

    /// 'Add Account' row button with haptic + a11y. Used by both Mastodon
    /// and Bluesky sections, in both empty and non-empty states, so the
    /// behavior is consistent across all four call sites.
    private func addAccountButton(platform: SocialPlatform, label: String) -> some View {
        Button {
            HapticEngine.tap.trigger()
            selectedPlatform = platform
            showingAddAccount = true
        } label: {
            Label(label, systemImage: "plus.circle")
        }
        .accessibilityLabel(label)
        .accessibilityHint("Opens the account sign-in flow")
    }

    private func accountSelectionRow(_ account: SocialAccount) -> some View {
        VStack(spacing: 8) {
            HStack {
                if account.platform.usesSFSymbol {
                    Image(systemName: account.platform.sfSymbol)
                        .foregroundColor(
                            platformColor(for: account.platform)
                        )
                        .font(.system(size: 24))
                        .frame(width: 32, height: 32)
                } else {
                    Image(account.platform.icon)
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(
                            platformColor(for: account.platform)
                        )
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .padding(2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    EmojiDisplayNameText(
                        account.displayName ?? account.username,
                        emojiMap: account.displayNameEmojiMap,
                        font: .headline,
                        fontWeight: .regular,
                        foregroundColor: .primary,
                        lineLimit: 1
                    )

                    Text("@\(account.username)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    toggleSelection(id: account.id)
                }) {
                    let isSelected = serviceManager.selectedAccountIds.contains(account.id)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            isSelected ? Color.white : Color.secondary.opacity(0.5),
                            isSelected ? platformColor(for: account.platform) : Color.clear
                        )
                        .symbolRenderingMode(.palette)
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityLabel(isSelected ? "Selected" : "Not selected")
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleSelection(id: account.id)
            }
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            // The whole row toggles selection — combine into one a11y
            // unit so VoiceOver reads it as a single named toggle rather
            // than stepping through icon, name, handle, checkmark
            // separately.
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(account.displayName ?? account.username), @\(account.username)")
            .accessibilityHint(
                serviceManager.selectedAccountIds.contains(account.id)
                    ? "Currently included. Tap to exclude from the timeline"
                    : "Tap to include in the timeline"
            )
            .accessibilityAddTraits(serviceManager.selectedAccountIds.contains(account.id) ? .isSelected : [])

            // Delete button row - more subtle design
            HStack {
                Spacer()

                Button(action: {
                    confirmDelete(account: account)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                        Text("Delete")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.red)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .padding(.top, 2)
            .padding(.bottom, 4)
            .padding(.trailing, 4)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
        .padding(.vertical, 4)
    }

    // Toggle selection for an account
    private func toggleSelection(id: String) {
        // Add haptic feedback
        HapticEngine.selection.trigger()

        if id == "all" {
            // If "all" is selected, clear other selections
            if serviceManager.selectedAccountIds.contains("all") {
                serviceManager.selectedAccountIds.remove("all")
            } else {
                serviceManager.selectedAccountIds = ["all"]
            }
        } else {
            // If a specific account is selected, remove "all"
            if serviceManager.selectedAccountIds.contains(id) {
                serviceManager.selectedAccountIds.remove(id)
            } else {
                serviceManager.selectedAccountIds.insert(id)
                serviceManager.selectedAccountIds.remove("all")
            }

            // If no accounts are selected, select "all"
            if serviceManager.selectedAccountIds.isEmpty {
                serviceManager.selectedAccountIds.insert("all")
            }
        }

        #if DEBUG
        print("Account selection changed to: \(serviceManager.selectedAccountIds)")
        #endif

        // REMOVED: automatic timeline refresh to prevent spam
        // Timeline will refresh automatically when user returns to main view
    }

    // Initialize or refresh account selections
    private func refreshAccountSelections() {
        // If we have accounts but nothing is selected, select "all"
        if (!serviceManager.mastodonAccounts.isEmpty || !serviceManager.blueskyAccounts.isEmpty)
            && serviceManager.selectedAccountIds.isEmpty
        {
            serviceManager.selectedAccountIds = ["all"]
        }
    }

    private func confirmDelete(account: SocialAccount) {
        // Store the account to delete and show confirmation dialog
        accountToDelete = account
        showDeleteConfirmation = true
    }

    // Helper function to get platform color
    private func platformColor(for platform: SocialPlatform) -> Color {
        switch platform {
        case .mastodon:
            return Color(hex: "6364FF")
        case .bluesky:
            return Color(hex: "0085FF")
        }
    }


    // Row for accounts needing re-authentication
    private func reauthenticationRow(
        _ account: SocialAccount, tokenRefreshService: AutomaticTokenRefreshService
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if account.platform.usesSFSymbol {
                    Image(systemName: account.platform.sfSymbol)
                        .foregroundColor(platformColor(for: account.platform))
                        .font(.system(size: 24))
                        .frame(width: 32, height: 32)
                } else {
                    Image(account.platform.icon)
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(platformColor(for: account.platform))
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .padding(2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    EmojiDisplayNameText(
                        account.displayName ?? account.username,
                        emojiMap: account.displayNameEmojiMap,
                        font: .headline,
                        fontWeight: .regular,
                        foregroundColor: .primary,
                        lineLimit: 1
                    )

                    Text("@\(account.username)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange.gradient)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 22))
            }

            // Guidance text
            Text(tokenRefreshService.getTokenRefreshGuidance(for: account))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Action buttons
            HStack(spacing: 10) {
                Button {
                    HapticEngine.warning.trigger()
                    let removedName = account.displayName ?? "@\(account.username)"
                    Task {
                        await serviceManager.removeAccount(account)
                        tokenRefreshService.clearReauthNotification(for: account)
                        await MainActor.run {
                            ToastManager.shared.show("Removed \(removedName)", severity: .success, duration: 1.6)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.caption.weight(.semibold))
                        Text("Remove")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(.red)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.red.opacity(0.12))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.red.opacity(0.22), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(ReauthButtonPressStyle())
                .accessibilityLabel("Remove account")
                .accessibilityHint("Deletes \(account.username) from this device")

                Button {
                    HapticEngine.tap.trigger()
                    selectedPlatform = account.platform
                    showingAddAccount = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                        Text("Re-authenticate")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 14)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.gradient)
                            .shadow(color: Color.accentColor.opacity(0.28), radius: 6, x: 0, y: 2)
                    )
                }
                .buttonStyle(ReauthButtonPressStyle())
                .accessibilityLabel("Re-authenticate")
                .accessibilityHint("Adds \(account.username) again with fresh credentials")

                Spacer()
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.28), lineWidth: 0.5)
        )
    }
}

/// Subtle press feedback for the re-auth row buttons — small scale + dim.
private struct ReauthButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

struct AccountRow: View {
    let account: SocialAccount
    @State private var showingAccountDetails = false

    var body: some View {
        Button(action: {
            showingAccountDetails = true
        }) {
            HStack {
                if account.platform.usesSFSymbol {
                    Image(systemName: account.platform.sfSymbol)
                        .foregroundColor(
                            platformColor(for: account.platform)
                        )
                        .font(.system(size: 24))
                        .frame(width: 32, height: 32)
                } else {
                    Image(account.platform.icon)
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(
                            platformColor(for: account.platform)
                        )
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .padding(2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    EmojiDisplayNameText(
                        account.displayName ?? account.username,
                        emojiMap: account.displayNameEmojiMap,
                        font: .headline,
                        fontWeight: .regular,
                        foregroundColor: .primary,
                        lineLimit: 1
                    )

                    Text("@\(account.username)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .sheet(isPresented: $showingAccountDetails) {
            AccountDetailView(account: account)
        }
    }

    // Helper function to get platform color
    private func platformColor(for platform: SocialPlatform) -> Color {
        switch platform {
        case .mastodon:
            return Color(hex: "6364FF")
        case .bluesky:
            return Color(hex: "0085FF")
        }
    }
}

struct AccountDetailView: View {
    let account: SocialAccount
    @State private var showingDeleteConfirmation = false
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var serviceManager: SocialServiceManager

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Account Information")) {
                    detailRow(label: "Platform", value: account.platform.rawValue.capitalized)
                    detailRow(label: "Username", value: "@\(account.username)")
                    if let server = account.serverURL?.host ?? account.serverURL?.absoluteString {
                        detailRow(label: "Server", value: server)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        HapticEngine.warning.trigger()
                        showingDeleteConfirmation = true
                    } label: {
                        Label {
                            Text("Remove Account")
                        } icon: {
                            Image(systemName: "trash")
                                .foregroundStyle(Color.red.gradient)
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                }
            }
            .navigationTitle("Account Details")
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
            .alert("Remove Account", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    // Do nothing
                }
                Button("Remove", role: .destructive) {
                    HapticEngine.warning.trigger()
                    let removedName = account.displayName ?? "@\(account.username)"
                    Task {
                        await serviceManager.removeAccount(account)
                        await MainActor.run {
                            ToastManager.shared.show("Removed \(removedName)", severity: .success, duration: 1.6)
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("Remove this account from your device? You can add it again later.")
            }
        }
    }

    /// A consistent label/value row for the account-info section.
    /// Value uses .monospacedDigit so usernames + server addresses
    /// stay aligned column-wise when stacked.
    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
        // Combine the two Texts so VoiceOver reads 'Platform: Mastodon'
        // rather than 'Platform' and 'Mastodon' as separate stops.
        // Keep .textSelection on the value text so iPad+keyboard users
        // can still long-press to copy.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct AccountsView_Previews: PreviewProvider {
    static var previews: some View {
        AccountsView()
    }
}

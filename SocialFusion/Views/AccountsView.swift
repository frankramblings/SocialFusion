import SwiftUI
import UIKit

struct AccountsView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @State private var showingAddAccount = false
    @State private var selectedPlatform: SocialPlatform = .mastodon

    @State private var accountToDelete: SocialAccount? = nil
    @State private var showDeleteConfirmation = false
    @State private var showDebugInfo = false

    var body: some View {
        NavigationView {
            List {
                // "All" selection option
                Section {
                    Button(action: {
                        toggleSelection(id: "all")
                    }) {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(Color.purple.opacity(0.2))
                                    .frame(width: 32, height: 32)

                                Text("All")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.purple)
                            }

                            Text("All Accounts")
                                .font(.headline)

                            Spacer()

                            if serviceManager.selectedAccountIds.contains("all") {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // Accounts needing re-authentication section
                if let tokenRefreshService = serviceManager.automaticTokenRefreshService,
                    !tokenRefreshService.accountsNeedingReauth.isEmpty
                {
                    Section(
                        header: HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
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
                        Button(action: {
                            selectedPlatform = .mastodon
                            showingAddAccount = true
                        }) {
                            Label("Add Mastodon Account", systemImage: "plus.circle")
                        }
                    } else {
                        ForEach(serviceManager.mastodonAccounts) { account in
                            accountSelectionRow(account)
                        }

                        Button(action: {
                            selectedPlatform = .mastodon
                            showingAddAccount = true
                        }) {
                            Label("Add Another Mastodon Account", systemImage: "plus.circle")
                        }
                    }
                }

                // Bluesky accounts section
                Section(header: Text("Bluesky")) {
                    if serviceManager.blueskyAccounts.isEmpty {
                        Button(action: {
                            selectedPlatform = .bluesky
                            showingAddAccount = true
                        }) {
                            Label("Add Bluesky Account", systemImage: "plus.circle")
                        }
                    } else {
                        ForEach(serviceManager.blueskyAccounts) { account in
                            accountSelectionRow(account)
                        }

                        Button(action: {
                            selectedPlatform = .bluesky
                            showingAddAccount = true
                        }) {
                            Label("Add Another Bluesky Account", systemImage: "plus.circle")
                        }
                    }
                }

                Section(header: Text("Settings")) {
                    NavigationLink(destination: SettingsView()) {
                        HStack {
                            Image(systemName: "gear")
                                .frame(width: 32, height: 32)
                            Text("Settings")
                        }
                    }

                    // Hidden debug toggle
                    Button(action: {
                        showDebugInfo.toggle()
                    }) {
                        HStack {
                            Image(systemName: "ladybug")
                                .frame(width: 32, height: 32)
                            Text("Debug Info")
                        }
                    }
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
                    if let account = accountToDelete {
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
                        }
                    }
                }
            } message: {
                Text(
                    "Are you sure you want to remove \(accountToDelete?.displayName ?? accountToDelete?.username ?? "this account")? This action cannot be undone."
                )
            }
            .onAppear {
                // Small delay to prevent rapid successive calls
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    refreshAccountSelections()
                }
                print(
                    "AccountsView appeared. Mastodon accounts: \(serviceManager.mastodonAccounts.count), Bluesky accounts: \(serviceManager.blueskyAccounts.count)"
                )
            }
        }
    }

    // Account row with selection toggle
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
                    Text(account.displayName ?? account.username)
                        .font(.headline)

                    Text("@\(account.username)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    toggleSelection(id: account.id)
                }) {
                    if serviceManager.selectedAccountIds.contains(account.id) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 24))
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.gray)
                            .font(.system(size: 24))
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleSelection(id: account.id)
            }
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(8)

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
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        .padding(.vertical, 4)
    }

    // Toggle selection for an account
    private func toggleSelection(id: String) {
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

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

        print("Account selection changed to: \(serviceManager.selectedAccountIds)")

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
                    Text(account.displayName ?? account.username)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("@\(account.username)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 20))
            }

            // Guidance text
            Text(tokenRefreshService.getTokenRefreshGuidance(for: account))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    // Remove the account
                    Task {
                        await serviceManager.removeAccount(account)
                        tokenRefreshService.clearReauthNotification(for: account)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                        Text("Remove")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.red)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                }

                Button(action: {
                    // Show add account flow for this platform
                    selectedPlatform = account.platform
                    showingAddAccount = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 12))
                        Text("Re-add Account")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.blue)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }

                Spacer()
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
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
                    Text(account.displayName ?? account.username)
                        .font(.headline)

                    Text("@\(account.username)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
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

struct LegacyAddAccountView: View {
    let platform: SocialPlatform
    let onAccountAdded: (SocialAccount) -> Void

    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Account Information")) {
                    if platform == .mastodon {
                        TextField("Server (e.g., mastodon.social)", text: $server)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                    }

                    TextField("Username", text: $username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    SecureField("Password", text: $password)
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Button(action: addAccount) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Add Account")
                        }
                    }
                    .disabled(isLoading || !isFormValid)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            .navigationBarItems(
                trailing: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                })
        }
    }

    private var isFormValid: Bool {
        if platform == .mastodon {
            return !server.isEmpty && !username.isEmpty && !password.isEmpty
        } else {
            return !username.isEmpty && !password.isEmpty
        }
    }

    private func addAccount() {
        isLoading = true
        errorMessage = ""

        if platform == .mastodon {
            Task {
                do {
                    // Use the MastodonService to authenticate
                    let mastodonService = MastodonService()
                    let newAccount = try await mastodonService.authenticate(
                        server: URL(string: server),
                        username: username,
                        password: password
                    )

                    // Handle successful authentication
                    DispatchQueue.main.async {
                        self.onAccountAdded(newAccount)
                        self.isLoading = false
                        self.presentationMode.wrappedValue.dismiss()
                    }
                } catch {
                    // Handle authentication error
                    DispatchQueue.main.async {
                        self.errorMessage = "Authentication failed: \(error.localizedDescription)"
                        self.isLoading = false
                    }
                }
            }
        } else if platform == .bluesky {
            Task {
                do {
                    // Use the BlueskyService to authenticate
                    let blueskyService = BlueskyService()
                    let newAccount = try await blueskyService.authenticate(
                        server: URL(string: "bsky.social"),
                        username: username,
                        password: password
                    )

                    // Handle successful authentication
                    DispatchQueue.main.async {
                        self.onAccountAdded(newAccount)
                        self.isLoading = false
                        self.presentationMode.wrappedValue.dismiss()
                    }
                } catch {
                    // Handle authentication error
                    DispatchQueue.main.async {
                        self.errorMessage = "Authentication failed: \(error.localizedDescription)"
                        self.isLoading = false
                    }
                }
            }
        }
    }
}

struct AccountDetailView: View {
    let account: SocialAccount
    @State private var showingDeleteConfirmation = false
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var serviceManager: SocialServiceManager

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Account Information")) {
                    HStack {
                        Text("Platform")
                        Spacer()
                        Text(account.platform.rawValue)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Username")
                        Spacer()
                        Text("@\(account.username)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Server")
                        Spacer()
                        Text(account.serverURL?.absoluteString ?? "")
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button(action: {
                        showingDeleteConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                                .font(.system(size: 15))
                            Text("Delete Account")
                                .font(.system(size: 16))
                            Spacer()
                        }
                        .foregroundColor(.red)
                    }
                }
            }

            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .alert("Remove Account", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    // Do nothing
                }
                Button("Remove", role: .destructive) {
                    Task {
                        await serviceManager.removeAccount(account)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            } message: {
                Text("Are you sure you want to remove this account? This action cannot be undone.")
            }
        }
    }
}

struct AccountsView_Previews: PreviewProvider {
    static var previews: some View {
        AccountsView()
    }
}

import SwiftUI
import UIKit

struct AccountsView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @State private var selectedAccountIds: Set<String> = ["all"]  // Default to "all" selected
    @State private var showingAddAccount = false
    @State private var selectedPlatform: SocialPlatform = .mastodon
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

                            if selectedAccountIds.contains("all") {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // Debug info (hidden by default)
                if showDebugInfo {
                    Section(header: Text("Debug Info")) {
                        Text("Mastodon Accounts: \(serviceManager.mastodonAccounts.count)")
                        Text("Bluesky Accounts: \(serviceManager.blueskyAccounts.count)")
                        Text("Selected IDs: \(selectedAccountIds.joined(separator: ", "))")

                        Button("Toggle Debug") {
                            showDebugInfo.toggle()
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
                        .onDelete { indexSet in
                            deleteAccounts(
                                at: indexSet, from: serviceManager.mastodonAccounts,
                                platform: .mastodon)
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
                        .onDelete { indexSet in
                            deleteAccounts(
                                at: indexSet, from: serviceManager.blueskyAccounts,
                                platform: .bluesky)
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
            .navigationTitle("Accounts")
            .sheet(isPresented: $showingAddAccount) {
                AddAccountView()
                    .environmentObject(serviceManager)
            }
            .onAppear {
                // Auto-refresh account lists when view appears
                refreshAccountSelections()
                print(
                    "AccountsView appeared. Mastodon accounts: \(serviceManager.mastodonAccounts.count), Bluesky accounts: \(serviceManager.blueskyAccounts.count)"
                )
            }
        }
    }

    // Account row with selection toggle
    private func accountSelectionRow(_ account: SocialAccount) -> some View {
        Button(action: {
            toggleSelection(id: account.id)
        }) {
            HStack {
                if account.platform.usesSFSymbol {
                    Image(systemName: account.platform.sfSymbol)
                        .foregroundColor(Color(account.platform.color))
                        .font(.system(size: 24))
                        .frame(width: 32, height: 32)
                } else {
                    Image(account.platform.icon)
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(Color(account.platform.color))
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

                if selectedAccountIds.contains(account.id) {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // Toggle selection for an account
    private func toggleSelection(id: String) {
        if id == "all" {
            // If "all" is selected, clear other selections
            if selectedAccountIds.contains("all") {
                selectedAccountIds.remove("all")
            } else {
                selectedAccountIds = ["all"]
            }
        } else {
            // If a specific account is selected, remove "all"
            if selectedAccountIds.contains(id) {
                selectedAccountIds.remove(id)
            } else {
                selectedAccountIds.insert(id)
                selectedAccountIds.remove("all")
            }

            // If no accounts are selected, select "all"
            if selectedAccountIds.isEmpty {
                selectedAccountIds.insert("all")
            }
        }

        // Sync with service manager
        serviceManager.selectedAccountIds = selectedAccountIds

        print("Account selection changed to: \(selectedAccountIds)")

        // Refresh timeline based on selection
        Task {
            await serviceManager.refreshTimeline()
        }
    }

    // Initialize or refresh account selections
    private func refreshAccountSelections() {
        // If we're opening the view, sync with service manager first
        selectedAccountIds = serviceManager.selectedAccountIds

        // If we have accounts but nothing is selected, select "all"
        if (!serviceManager.mastodonAccounts.isEmpty || !serviceManager.blueskyAccounts.isEmpty)
            && selectedAccountIds.isEmpty
        {
            selectedAccountIds = ["all"]
            serviceManager.selectedAccountIds = selectedAccountIds
        }
    }

    private func deleteAccounts(
        at offsets: IndexSet, from accounts: [SocialAccount], platform: SocialPlatform
    ) {
        for index in offsets {
            let accountToRemove = accounts[index]
            serviceManager.removeAccount(accountToRemove)
            selectedAccountIds.remove(accountToRemove.id)
        }

        // If no accounts remain, select "all"
        if serviceManager.mastodonAccounts.isEmpty && serviceManager.blueskyAccounts.isEmpty {
            selectedAccountIds = ["all"]
        } else if selectedAccountIds.isEmpty {
            selectedAccountIds.insert("all")
        }

        // Refresh timeline after account removal
        Task {
            await serviceManager.refreshTimeline()
        }
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
                        .foregroundColor(Color(account.platform.color))
                        .font(.system(size: 24))
                        .frame(width: 32, height: 32)
                } else {
                    Image(account.platform.icon)
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(Color(account.platform.color))
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
            .navigationTitle("Add \(platform.rawValue) Account")
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
                        Text("Remove Account")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(account.displayName ?? account.username)
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .alert(isPresented: $showingDeleteConfirmation) {
                Alert(
                    title: Text("Remove Account"),
                    message: Text(
                        "Are you sure you want to remove this account? This action cannot be undone."
                    ),
                    primaryButton: .destructive(Text("Remove")) {
                        // This would be replaced with actual account removal
                        presentationMode.wrappedValue.dismiss()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }
}

struct AccountsView_Previews: PreviewProvider {
    static var previews: some View {
        AccountsView()
    }
}

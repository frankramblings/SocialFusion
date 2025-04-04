import SwiftUI

struct AccountPickerView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @Binding var selectedAccountId: String?
    @Binding var isPresented: Bool
    @State private var showSettingsView = false
    @State private var showAccountsView = false
    @State private var showAddAccountSheet = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    // "All" option (unified timeline)
                    Button(action: {
                        selectedAccountId = nil
                        serviceManager.selectedAccountIds = ["all"]
                        Task {
                            await serviceManager.refreshTimeline(force: true)
                        }
                        isPresented = false
                    }) {
                        HStack {
                            UnifiedAccountsIcon(
                                mastodonAccounts: serviceManager.mastodonAccounts,
                                blueskyAccounts: serviceManager.blueskyAccounts
                            )
                            .frame(width: 40, height: 40)

                            Text("All")
                                .font(.headline)

                            Spacer()

                            if selectedAccountId == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.vertical, 4)
                }

                // Mastodon accounts
                if !serviceManager.mastodonAccounts.isEmpty {
                    Section(header: Text("Mastodon")) {
                        ForEach(serviceManager.mastodonAccounts) { account in
                            accountRow(account)
                        }
                    }
                }

                // Bluesky accounts
                if !serviceManager.blueskyAccounts.isEmpty {
                    Section(header: Text("Bluesky")) {
                        ForEach(serviceManager.blueskyAccounts) { account in
                            accountRow(account)
                        }
                    }
                }

                // Account Management
                Section(header: Text("Account Management")) {
                    // Add Account Button
                    Button(action: {
                        showAddAccountSheet = true
                    }) {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.1))
                                    .frame(width: 40, height: 40)

                                Image(systemName: "plus")
                                    .font(.system(size: 18))
                                    .foregroundColor(.blue)
                            }

                            Text("Add Account")
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.vertical, 4)

                    // Manage Accounts Button (takes you to the old accounts view)
                    Button(action: {
                        showAccountsView = true
                    }) {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(width: 40, height: 40)

                                Image(systemName: "person.2")
                                    .font(.system(size: 16))
                                    .foregroundColor(.gray)
                            }

                            Text("Manage Accounts")
                                .font(.headline)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.vertical, 4)

                    // Settings Button
                    Button(action: {
                        showSettingsView = true
                    }) {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(width: 40, height: 40)

                                Image(systemName: "gear")
                                    .font(.system(size: 18))
                                    .foregroundColor(.gray)
                            }

                            Text("Settings")
                                .font(.headline)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.vertical, 4)
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
            .sheet(isPresented: $showSettingsView) {
                SettingsView()
            }
            .sheet(isPresented: $showAccountsView) {
                AccountsView()
                    .environmentObject(serviceManager)
            }
            .sheet(isPresented: $showAddAccountSheet) {
                AddAccountView()
                    .environmentObject(serviceManager)
            }
        }
    }

    // Helper for rendering an account row
    private func accountRow(_ account: SocialAccount) -> some View {
        Button(action: {
            selectedAccountId = account.id
            serviceManager.selectedAccountIds = [account.id]
            Task {
                await serviceManager.refreshTimeline(force: true)
            }
            isPresented = false
        }) {
            HStack {
                ProfileImageView(account: account)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName)
                        .font(.headline)

                    Text("@\(account.username)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                Spacer()

                if selectedAccountId == account.id {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.vertical, 4)
    }
}

// A simple view to add a new account
struct AddAccountView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedPlatform: SocialPlatform = .mastodon

    // Mastodon fields
    @State private var mastodonServer = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var error: Error? = nil

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Select Platform")) {
                    Picker("Platform", selection: $selectedPlatform) {
                        ForEach(SocialPlatform.allCases, id: \.self) { platform in
                            HStack {
                                Image(systemName: platform.icon)
                                Text(platform.rawValue)
                            }
                            .tag(platform)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                if selectedPlatform == .mastodon {
                    Section(header: Text("Mastodon Account Details")) {
                        TextField("Server (e.g. mastodon.social)", text: $mastodonServer)
                            .autocapitalization(.none)
                            .keyboardType(.URL)

                        TextField("Username", text: $username)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)

                        SecureField("Password", text: $password)
                    }
                } else {
                    Section(header: Text("Bluesky Account Details")) {
                        TextField("Username", text: $username)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)

                        SecureField("Password", text: $password)
                    }
                }

                if let error = error {
                    Section {
                        Text(error.localizedDescription)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button(action: addAccount) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Add Account")
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                    .disabled(isLoading || !isFormValid)
                }
            }
            .navigationTitle("Add Account")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    private var isFormValid: Bool {
        if selectedPlatform == .mastodon {
            return !mastodonServer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !password.isEmpty
        } else {
            return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !password.isEmpty
        }
    }

    private func addAccount() {
        isLoading = true
        error = nil

        Task {
            do {
                if selectedPlatform == .mastodon {
                    // Use simplified implementation for now
                    let account = try await serviceManager.addMastodonAccount(
                        server: mastodonServer,
                        username: username,
                        password: password
                    )

                    DispatchQueue.main.async {
                        isLoading = false
                        presentationMode.wrappedValue.dismiss()
                    }
                } else {
                    let account = try await serviceManager.addBlueskyAccount(
                        username: username,
                        password: password
                    )

                    DispatchQueue.main.async {
                        isLoading = false
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error
                    isLoading = false
                }
            }
        }
    }
}

struct AccountPickerView_Previews: PreviewProvider {
    static var previews: some View {
        AccountPickerView(
            selectedAccountId: .constant(nil),
            isPresented: .constant(true)
        )
        .environmentObject(SocialServiceManager())
    }
}

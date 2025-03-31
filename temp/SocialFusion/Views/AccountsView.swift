import SwiftUI

struct AccountsView: View {
    @State private var mastodonAccounts: [SocialAccount] = []
    @State private var blueskyAccounts: [SocialAccount] = []
    @State private var showingAddAccount = false
    @State private var selectedPlatform: SocialPlatform = .mastodon
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Mastodon")) {
                    if mastodonAccounts.isEmpty {
                        Button(action: {
                            selectedPlatform = .mastodon
                            showingAddAccount = true
                        }) {
                            Label("Add Mastodon Account", systemImage: "plus.circle")
                        }
                    } else {
                        ForEach(mastodonAccounts) { account in
                            AccountRow(account: account)
                        }
                        .onDelete { indexSet in
                            mastodonAccounts.remove(atOffsets: indexSet)
                        }
                        
                        Button(action: {
                            selectedPlatform = .mastodon
                            showingAddAccount = true
                        }) {
                            Label("Add Another Mastodon Account", systemImage: "plus.circle")
                        }
                    }
                }
                
                Section(header: Text("Bluesky")) {
                    if blueskyAccounts.isEmpty {
                        Button(action: {
                            selectedPlatform = .bluesky
                            showingAddAccount = true
                        }) {
                            Label("Add Bluesky Account", systemImage: "plus.circle")
                        }
                    } else {
                        ForEach(blueskyAccounts) { account in
                            AccountRow(account: account)
                        }
                        .onDelete { indexSet in
                            blueskyAccounts.remove(atOffsets: indexSet)
                        }
                        
                        Button(action: {
                            selectedPlatform = .bluesky
                            showingAddAccount = true
                        }) {
                            Label("Add Another Bluesky Account", systemImage: "plus.circle")
                        }
                    }
                }
            }
            .navigationTitle("Accounts")
            .sheet(isPresented: $showingAddAccount) {
                AddAccountView(platform: selectedPlatform, onAccountAdded: { account in
                    if account.platform == .mastodon {
                        mastodonAccounts.append(account)
                    } else {
                        blueskyAccounts.append(account)
                    }
                })
            }
            .onAppear {
                // Load saved accounts
                loadAccounts()
            }
        }
    }
    
    private func loadAccounts() {
        // This would be replaced with actual account loading from secure storage
        // For now, we'll just use sample data
        mastodonAccounts = [
            SocialAccount(id: "1", username: "user1", displayName: "User One", serverURL: "mastodon.social", platform: .mastodon),
        ]
        
        blueskyAccounts = [
            SocialAccount(id: "2", username: "user2.bsky.social", displayName: "User Two", serverURL: "bsky.social", platform: .bluesky),
        ]
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
                Image(systemName: account.platform.icon)
                    .foregroundColor(Color(account.platform.color))
                    .font(.system(size: 24))
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName)
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

struct AddAccountView: View {
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
            .navigationBarItems(trailing: Button("Cancel") {
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
        
        // This would be replaced with actual authentication API calls
        // For now, we'll just simulate authentication with a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // Simulate successful authentication
            let newAccount = SocialAccount(
                id: UUID().uuidString,
                username: username,
                displayName: username.components(separatedBy: "@").first ?? username,
                serverURL: platform == .mastodon ? server : "bsky.social",
                platform: platform
            )
            
            onAccountAdded(newAccount)
            isLoading = false
            presentationMode.wrappedValue.dismiss()
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
                        Text(account.serverURL)
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
            .navigationTitle(account.displayName)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
            .alert(isPresented: $showingDeleteConfirmation) {
                Alert(
                    title: Text("Remove Account"),
                    message: Text("Are you sure you want to remove this account? This action cannot be undone."),
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
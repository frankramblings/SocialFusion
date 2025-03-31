import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @State private var selectedAccountId: String? = nil
    @State private var showAccountPicker = false
    @State private var showComposeView = false
    @State private var selectedTab = 0
    @State private var selectedAccount: SocialAccount? = nil
    @State private var showSettings = false

    var body: some View {
        TabView(selection: $selectedTab) {
            // Home Tab
            NavigationView {
                ZStack {
                    // Main content area - will show either the unified timeline or a specific account timeline
                    if selectedAccountId == nil {
                        // Show unified timeline
                        UnifiedTimelineView()
                    } else {
                        // For now, use UnifiedTimelineView for both unified and individual timelines
                        // In a future update, we'd replace this with individual account timeline views
                        UnifiedTimelineView()
                    }

                    // FAB for compose
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                showComposeView = true
                            }) {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                                    .frame(width: 60, height: 60)
                                    .contentShape(Circle())
                                    .background(
                                        Circle()
                                            .fill(Color.blue)
                                    )
                                    .shadow(radius: 4)
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
                .navigationTitle(navigationTitle)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            showAccountPicker = true
                        }) {
                            getCurrentAccountImage()
                                .frame(width: 30, height: 30)
                                .clipShape(Circle())
                        }
                        .sheet(isPresented: $showAccountPicker) {
                            AccountPickerSheet(
                                selectedAccountId: $selectedAccountId,
                                isPresented: $showAccountPicker
                            )
                        }
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            Task {
                                await serviceManager.refreshTimeline()
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .sheet(isPresented: $showComposeView) {
                    ComposeView()
                        .environmentObject(serviceManager)
                }
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .tag(0)

            // Notifications Tab
            NavigationView {
                VStack {
                    Text("Notifications will appear here")
                        .font(.headline)
                }
                .navigationTitle("Notifications")
            }
            .tabItem {
                Label("Notifications", systemImage: "bell")
            }
            .tag(1)

            // Search Tab
            NavigationView {
                VStack {
                    Text("Search functionality will appear here")
                        .font(.headline)
                }
                .navigationTitle("Search")
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            .tag(2)

            // Profile Tab
            NavigationView {
                VStack {
                    if let account = getCurrentAccount() {
                        Text("Profile for \(account.displayName)")
                            .font(.headline)
                    } else {
                        Text("Select an account to view profile")
                            .font(.headline)
                    }
                }
                .navigationTitle("Profile")
            }
            .tabItem {
                Label("Profile", systemImage: "person")
            }
            .tag(3)
        }
        .accentColor(Color("PrimaryColor"))
    }

    // Helper function to get the current account
    private func getCurrentAccount() -> SocialAccount? {
        guard let selectedId = selectedAccountId else { return nil }

        return serviceManager.mastodonAccounts.first(where: { $0.id == selectedId })
            ?? serviceManager.blueskyAccounts.first(where: { $0.id == selectedId })
    }

    // Helper to get account image for the picker button
    @ViewBuilder
    private func getCurrentAccountImage() -> some View {
        if selectedAccountId != nil, let account = getCurrentAccount() {
            // Show the selected account avatar
            ProfileImageView(account: account)
        } else {
            // Show the "All" icon (unified view)
            UnifiedAccountsIcon(
                mastodonAccounts: serviceManager.mastodonAccounts,
                blueskyAccounts: serviceManager.blueskyAccounts
            )
            .frame(width: 36, height: 36)
        }
    }

    // Dynamic navigation title based on selection
    private var navigationTitle: String {
        if selectedAccountId == nil {
            return "Home"
        } else if let account = getCurrentAccount() {
            return account.displayName ?? account.username
        } else {
            return "Home"
        }
    }
}

// View for profile image (used in multiple places)
struct ProfileImageView: View {
    let account: SocialAccount

    var body: some View {
        // For now just use a placeholder, in the real app you'd load the actual avatar
        ZStack {
            Circle()
                .fill(
                    account.platform == .mastodon ? Color("PrimaryColor") : Color("SecondaryColor"))

            Text(String((account.displayName ?? "?").prefix(1)))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            // Platform badge
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    PlatformBadge(platform: account.platform)
                }
            }
            .padding(2)
        }
    }
}

// Unified icon showing overlapping accounts
struct UnifiedAccountsIcon: View {
    let mastodonAccounts: [SocialAccount]
    let blueskyAccounts: [SocialAccount]

    var body: some View {
        ZStack {
            // Background
            Circle()
                .fill(Color.gray.opacity(0.1))

            if mastodonAccounts.isEmpty && blueskyAccounts.isEmpty {
                // No accounts, show a placeholder
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 20))
                    .foregroundColor(.gray)
            } else {
                // Show overlapping icons for the accounts
                ZStack {
                    // Bluesky account (if any)
                    if !blueskyAccounts.isEmpty {
                        Circle()
                            .fill(Color("SecondaryColor"))
                            .frame(width: 24, height: 24)
                            .offset(x: 5, y: 5)
                    }

                    // Mastodon account (if any)
                    if !mastodonAccounts.isEmpty {
                        Circle()
                            .fill(Color("PrimaryColor"))
                            .frame(width: 24, height: 24)
                            .offset(x: -5, y: -5)
                    }
                }
            }
        }
    }
}

// Platform badge to show on account avatars
struct PlatformBadge: View {
    let platform: SocialPlatform

    private func getLogoName(for platform: SocialPlatform) -> String {
        switch platform {
        case .mastodon:
            return "MastodonLogo"
        case .bluesky:
            return "BlueskyLogo"
        }
    }

    private func getPlatformColor() -> Color {
        switch platform {
        case .mastodon:
            return Color("PrimaryColor")
        case .bluesky:
            return Color("SecondaryColor")
        }
    }

    var body: some View {
        ZStack {
            // Remove the white circle background
            // Just show the platform logo with a slight shadow for visibility
            Image(getLogoName(for: platform))
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
                .foregroundColor(getPlatformColor())
                .shadow(color: Color.black.opacity(0.3), radius: 1.5, x: 0, y: 0)
        }
        .frame(width: 16, height: 16)
    }
}

// This is a temporary replacement for the AccountPickerView until we implement it fully
struct AccountPickerSheet: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @Binding var selectedAccountId: String?
    @Binding var isPresented: Bool
    @State private var showSettingsView = false
    @State private var showAddAccountView = false

    var body: some View {
        NavigationView {
            List {
                // Add Account Button
                Section {
                    Button(action: {
                        showAddAccountView = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(Color("PrimaryColor"))

                            Text("Add Account")
                                .font(.headline)
                        }
                    }
                }

                // All option
                Section {
                    Button(action: {
                        selectedAccountId = nil
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
                    }
                }

                // Settings option
                Section {
                    Button(action: {
                        showSettingsView = true
                    }) {
                        HStack {
                            Image(systemName: "gear")
                                .font(.system(size: 22))
                                .foregroundColor(.gray)

                            Text("Settings")
                                .font(.headline)
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
            .sheet(isPresented: $showSettingsView) {
                SettingsView()
            }
            .sheet(isPresented: $showAddAccountView) {
                AddAccountView()
                    .environmentObject(serviceManager)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(SocialServiceManager())
    }
}

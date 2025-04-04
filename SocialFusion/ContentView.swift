import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @State private var selectedAccountId: String? = nil
    @State private var previousAccountId: String? = nil  // Track previous account
    @State private var showAccountPicker = false
    @State private var showAccountDropdown = false  // Control for dropdown visibility
    @State private var showComposeView = false
    @State private var selectedTab = 0
    @State private var selectedAccount: SocialAccount? = nil
    @State private var showSettings = false
    @State private var longPressLocation: CGPoint = .zero  // Track long press location
    @Environment(\.colorScheme) private var colorScheme

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

                    // Account dropdown overlay when visible
                    if showAccountDropdown {
                        AccountDropdownView(
                            selectedAccountId: $selectedAccountId,
                            previousAccountId: $previousAccountId,
                            isVisible: $showAccountDropdown,
                            position: longPressLocation
                        )
                        .zIndex(10)  // Ensure it appears above other content
                    }

                    // Floating action button (FAB) for compose
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                showComposeView = true
                            }) {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                                    .frame(width: 56, height: 56)
                                    .background(
                                        Circle()
                                            .fill(Color.blue)
                                            .shadow(
                                                color: Color.black.opacity(0.15), radius: 4, x: 0,
                                                y: 2)
                                    )
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 16)
                        }
                    }
                }
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        // Account icon with gestures
                        HStack(spacing: 6) {
                            getCurrentAccountImage()
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                                .background(
                                    // Use GeometryReader to get precise position
                                    GeometryReader { geometry -> Color in
                                        let frame = geometry.frame(in: .global)
                                        // Store the center of the account icon for dropdown positioning
                                        longPressLocation = CGPoint(
                                            x: frame.midX,
                                            y: frame.maxY + 8  // Position dropdown slightly below the icon
                                        )
                                        return Color.clear
                                    }
                                )

                            // Dropdown indicator
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(6)
                        .background(
                            Capsule()
                                .fill(
                                    colorScheme == .dark
                                        ? Color(UIColor.tertiarySystemBackground)
                                        : Color(UIColor.secondarySystemBackground)
                                )
                                .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
                        )
                        // Combined gesture for both actions
                        .onTapGesture {
                            // Toggle dropdown on tap
                            showAccountDropdown.toggle()
                        }
                        .gesture(
                            LongPressGesture(minimumDuration: 0.3)
                                .onEnded { _ in
                                    // Show full account picker on long press
                                    showAccountPicker = true
                                }
                        )
                        .sheet(isPresented: $showAccountPicker) {
                            AccountPickerSheet(
                                selectedAccountId: $selectedAccountId,
                                previousAccountId: $previousAccountId,
                                isPresented: $showAccountPicker
                            )
                        }
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            showSettings = true
                        }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                        }
                        .sheet(isPresented: $showSettings) {
                            SettingsView()
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

            // Notifications Tab - with a modern design
            NavigationView {
                ZStack {
                    Color(UIColor.systemBackground)
                        .ignoresSafeArea()

                    VStack(spacing: 20) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.gray.opacity(0.3))

                        Text("Notifications")
                            .font(.title3)
                            .fontWeight(.medium)

                        Text("Notifications will appear here")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
                .navigationTitle("Notifications")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Notifications", systemImage: "bell")
            }
            .tag(1)

            // Search Tab - with a modern design
            NavigationView {
                ZStack {
                    Color(UIColor.systemBackground)
                        .ignoresSafeArea()

                    VStack(spacing: 20) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 50))
                            .foregroundColor(.gray.opacity(0.3))

                        Text("Search")
                            .font(.title3)
                            .fontWeight(.medium)

                        Text("Search for people, posts, and hashtags")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
                .navigationTitle("Search")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            .tag(2)

            // Profile Tab - with a modern design
            NavigationView {
                ZStack {
                    Color(UIColor.systemBackground)
                        .ignoresSafeArea()

                    if let account = getCurrentAccount() {
                        ScrollView {
                            VStack(spacing: 0) {
                                // Profile header
                                VStack(spacing: 16) {
                                    // Profile image
                                    ProfileImageView(account: account)
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                        )
                                        .padding(.top, 20)

                                    // Account name and username
                                    VStack(spacing: 4) {
                                        Text(account.displayName ?? account.username)
                                            .font(.title2)
                                            .fontWeight(.bold)

                                        Text("@\(account.username)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }

                                    // Platform badge
                                    HStack {
                                        PlatformBadge(platform: account.platform)
                                    }
                                    .padding(.bottom, 10)
                                }
                                .frame(maxWidth: .infinity)
                                .background(
                                    colorScheme == .dark
                                        ? Color(UIColor.secondarySystemBackground) : Color.white)

                                // Profile content placeholder
                                VStack(spacing: 20) {
                                    Text("Profile content will appear here")
                                        .font(.headline)
                                        .padding(.top, 40)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    } else {
                        VStack(spacing: 20) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 50))
                                .foregroundColor(.gray.opacity(0.3))

                            Text("No Account Selected")
                                .font(.title3)
                                .fontWeight(.medium)

                            Text("Select an account to view profile")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)

                            Button(action: {
                                // Show account picker
                                showAccountPicker = true
                            }) {
                                Text("Select Account")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(Color.blue)
                                    .cornerRadius(25)
                            }
                            .padding(.top, 10)
                            .sheet(isPresented: $showAccountPicker) {
                                AccountPickerSheet(
                                    selectedAccountId: $selectedAccountId,
                                    previousAccountId: $previousAccountId,
                                    isPresented: $showAccountPicker
                                )
                            }
                        }
                    }
                }
                .navigationTitle("Profile")
                .navigationBarTitleDisplayMode(.inline)
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

    // Helper function to switch to the previous account
    private func switchToPreviousAccount() {
        if let prevId = previousAccountId {
            // Store current account before switching
            let currentId = selectedAccountId
            // Switch to previous account
            switchToAccount(id: prevId)
            // Update previous account to be the one we just left
            previousAccountId = currentId
        }
    }

    // Helper function to switch accounts and track previous selection
    private func switchToAccount(id: String?) {
        // Store current selection as previous
        previousAccountId = selectedAccountId
        // Update to new selection
        selectedAccountId = id

        // Update the selected account IDs in the service manager
        if let id = id {
            // Add the selected account to the service manager's selectedAccountIds
            serviceManager.selectedAccountIds = [id]
        } else {
            // If nil (all accounts selected), use "all"
            serviceManager.selectedAccountIds = ["all"]
        }

        // Refresh timeline with new account selection
        Task {
            try? await serviceManager.refreshTimeline(force: true)
        }
    }
}

// Account dropdown overlay with improved design
struct AccountDropdownView: View {
    @Binding var selectedAccountId: String?
    @Binding var previousAccountId: String?
    @Binding var isVisible: Bool
    @EnvironmentObject var serviceManager: SocialServiceManager
    @Environment(\.colorScheme) var colorScheme

    let position: CGPoint

    var body: some View {
        ZStack {
            // Dismiss when tapping outside the dropdown
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    isVisible = false
                }

            VStack(spacing: 0) {
                // Dropdown arrow at the top
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 16))
                    .foregroundColor(
                        colorScheme == .dark
                            ? Color(UIColor.secondarySystemBackground) : Color.white
                    )
                    .offset(y: 7)
                    .zIndex(1)

                // Main dropdown content
                VStack(spacing: 0) {
                    // "All Accounts" option
                    accountOptionView(account: nil)

                    Divider()
                        .padding(.horizontal, 8)

                    // Individual accounts
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(serviceManager.mastodonAccounts) { account in
                                accountOptionView(account: account)

                                if account.id != serviceManager.mastodonAccounts.last?.id
                                    || !serviceManager.blueskyAccounts.isEmpty
                                {
                                    Divider()
                                        .padding(.horizontal, 8)
                                }
                            }

                            ForEach(serviceManager.blueskyAccounts) { account in
                                accountOptionView(account: account)

                                if account.id != serviceManager.blueskyAccounts.last?.id {
                                    Divider()
                                        .padding(.horizontal, 8)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 240)

                    Divider()
                        .padding(.horizontal, 8)

                    // "Add Account" option
                    Button(action: {
                        // Here you would show the account adding interface
                        isVisible = false
                    }) {
                        HStack {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 16))
                                .foregroundColor(.blue)

                            Text("Add Account")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .background(
                    colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color.white
                )
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
            }
            .position(x: position.x, y: position.y)
            .frame(width: 220)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func accountOptionView(account: SocialAccount?) -> some View {
        Button(action: {
            // Switch to this account
            if let account = account {
                if selectedAccountId != account.id {
                    previousAccountId = selectedAccountId
                    selectedAccountId = account.id

                    // Update selected accounts in service manager
                    serviceManager.selectedAccountIds = [account.id]
                }
            } else {
                previousAccountId = selectedAccountId
                selectedAccountId = nil

                // Update selected accounts in service manager
                serviceManager.selectedAccountIds = ["all"]
            }

            // Hide the dropdown
            isVisible = false

            // Refresh the timeline
            Task {
                try? await serviceManager.refreshTimeline(force: true)
            }
        }) {
            HStack(spacing: 12) {
                // Account image
                if let account = account {
                    ProfileImageView(account: account)
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                } else {
                    UnifiedAccountsIcon(
                        mastodonAccounts: serviceManager.mastodonAccounts,
                        blueskyAccounts: serviceManager.blueskyAccounts
                    )
                    .frame(width: 32, height: 32)
                }

                // Account name and platform
                VStack(alignment: .leading, spacing: 2) {
                    Text(account?.displayName ?? account?.username ?? "All Accounts")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    if let account = account {
                        Text("@\(account.username)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Unified Timeline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Selected indicator
                if (account == nil && selectedAccountId == nil)
                    || (account != nil && selectedAccountId == account?.id)
                {
                    Image(systemName: "checkmark")
                        .font(.footnote)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                (account == nil && selectedAccountId == nil)
                    || (account != nil && selectedAccountId == account?.id)
                    ? Color.blue.opacity(0.1)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Account picker sheet view
struct AccountPickerSheet: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @Binding var selectedAccountId: String?
    @Binding var previousAccountId: String?  // Add binding for previous account
    @Binding var isPresented: Bool
    @State private var showSettingsView = false
    @State private var showAddAccountView = false

    var body: some View {
        NavigationView {
            List {
                // Account section - show all accounts
                Section(header: Text("Accounts")) {
                    // All accounts option
                    Button(action: {
                        switchToAccount(id: nil)
                        isPresented = false
                    }) {
                        HStack {
                            UnifiedAccountsIcon(
                                mastodonAccounts: serviceManager.mastodonAccounts,
                                blueskyAccounts: serviceManager.blueskyAccounts
                            )
                            .frame(width: 44, height: 44)

                            Text("All Accounts")
                                .font(.headline)

                            Spacer()

                            if selectedAccountId == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    // Mastodon accounts
                    ForEach(serviceManager.mastodonAccounts) { account in
                        Button(action: {
                            switchToAccount(id: account.id)
                            isPresented = false
                        }) {
                            HStack {
                                ProfileImageView(account: account)
                                    .frame(width: 40, height: 40)

                                VStack(alignment: .leading) {
                                    Text(account.displayName ?? "")
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
                        }
                    }

                    // Bluesky accounts
                    ForEach(serviceManager.blueskyAccounts) { account in
                        Button(action: {
                            switchToAccount(id: account.id)
                            isPresented = false
                        }) {
                            HStack {
                                ProfileImageView(account: account)
                                    .frame(width: 40, height: 40)

                                VStack(alignment: .leading) {
                                    Text(account.displayName ?? "")
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
                        }
                    }
                }

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

                // Manage Accounts Button
                Section {
                    NavigationLink(destination: AccountsView()) {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.minus")
                                .font(.system(size: 22))
                                .foregroundColor(.red)

                            Text("Manage Accounts")
                                .font(.headline)
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

    // Helper function to switch accounts and track previous selection
    private func switchToAccount(id: String?) {
        // Store current selection as previous
        previousAccountId = selectedAccountId
        // Update to new selection
        selectedAccountId = id
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(SocialServiceManager())
    }
}

// MARK: - Supporting Components

/// ProfileImageView displays a user's profile image with appropriate styling
/// based on their account type.
struct ProfileImageView: View {
    let account: SocialAccount

    @State private var refreshTrigger = false

    var body: some View {
        ZStack {
            // Colored circle for outline based on platform
            Circle()
                .fill(
                    account.platform == .mastodon ? Color("PrimaryColor") : Color("SecondaryColor")
                )
                .frame(width: 34, height: 34)

            // Profile image or initial
            if let imageURL = account.profileImageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 30, height: 30)
                            .clipShape(Circle())
                    } else if phase.error != nil {
                        // Show initial on error
                        InitialView(account: account)
                    } else {
                        // Show loading placeholder
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 30, height: 30)
                    }
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                .onAppear {
                    print("Refreshing ProfileImageView for account: \(account.username)")
                }
                .onReceive(NotificationCenter.default.publisher(for: .profileImageUpdated)) {
                    notification in
                    if let accountId = notification.object as? String, accountId == account.id {
                        print("Received profile image update for \(account.username)")
                        refreshTrigger.toggle()
                    }
                }
            } else {
                // No URL, show initial
                InitialView(account: account)
            }
        }
        .id(refreshTrigger)  // Force view refresh when trigger changes
    }
}

/// Displays the user's initial when no profile image is available
struct InitialView: View {
    let account: SocialAccount

    var body: some View {
        Text(String((account.displayName ?? account.username).prefix(1)))
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(
                account.platform == .mastodon ? Color("PrimaryColor") : Color("SecondaryColor")
            )
            .frame(width: 30, height: 30)
            .background(Circle().fill(Color.white))
    }
}

struct UnifiedAccountsIcon: View {
    let mastodonAccounts: [SocialAccount]
    let blueskyAccounts: [SocialAccount]

    @State private var refreshTrigger = false

    var body: some View {
        ZStack {
            // Background circle (gray)
            Circle()
                .fill(Color.gray.opacity(0.1))
                .frame(width: 36, height: 36)
                .onAppear {
                    print(
                        "UnifiedAccountsIcon appeared with \(mastodonAccounts.count) Mastodon accounts and \(blueskyAccounts.count) Bluesky accounts"
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: .profileImageUpdated)) {
                    notification in
                    if let accountId = notification.object as? String {
                        // Check if the updated account is one of ours
                        let isOurAccount =
                            mastodonAccounts.contains { $0.id == accountId }
                            || blueskyAccounts.contains { $0.id == accountId }
                        if isOurAccount {
                            print("Refreshing UnifiedAccountsIcon for account update: \(accountId)")
                            refreshTrigger.toggle()
                        }
                    }
                }

            if mastodonAccounts.isEmpty && blueskyAccounts.isEmpty {
                // No accounts, show a placeholder
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 20))
                    .foregroundColor(.gray)
            } else {
                // Show account profiles with colored outlines
                ZStack {
                    // First profile (if any Mastodon accounts)
                    if let firstMastodonAccount = mastodonAccounts.first {
                        ProfileImageView(account: firstMastodonAccount)
                            .offset(x: -6, y: -6)
                    }

                    // Second profile (if any Bluesky accounts)
                    if let firstBlueskyAccount = blueskyAccounts.first {
                        ProfileImageView(account: firstBlueskyAccount)
                            .offset(x: 6, y: 6)
                    }
                }
            }
        }
        .id(refreshTrigger)  // Force view refresh when trigger changes
    }
}

/// Platform badge to show on account avatars
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
                .frame(width: 16, height: 16)
                .foregroundColor(getPlatformColor())
                .shadow(color: Color.black.opacity(0.4), radius: 1.5, x: 0, y: 0)
        }
        .frame(width: 20, height: 20)
    }
}

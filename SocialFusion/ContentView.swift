import SwiftUI

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
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        // Account icon with gestures
                        getCurrentAccountImage()
                            .frame(width: 34, height: 34)
                            .clipShape(Circle())
                            .onTapGesture(count: 2) {
                                // Double tap - switch to previous account
                                switchToPreviousAccount()
                            }
                            .onTapGesture(count: 1) {
                                // Single tap - show full account picker sheet
                                showAccountPicker = true
                            }
                            .background(
                                // Use GeometryReader to get precise position
                                GeometryReader { geometry -> Color in
                                    let frame = geometry.frame(in: .global)
                                    // Store the center of the account icon for dropdown positioning
                                    longPressLocation = CGPoint(
                                        x: frame.midX,
                                        y: frame.maxY  // Use bottom edge of icon instead of center + offset
                                    )
                                    return Color.clear
                                }
                            )
                            .gesture(
                                LongPressGesture(minimumDuration: 0.3)  // Slightly quicker response
                                    .onEnded { _ in
                                        // Show dropdown when long press ends
                                        showAccountDropdown = true
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
                .navigationBarTitleDisplayMode(.inline)
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
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            .tag(2)

            // Profile Tab
            NavigationView {
                VStack {
                    if let account = getCurrentAccount() {
                        Text("Profile for \(account.displayName ?? account.username)")
                            .font(.headline)
                    } else {
                        Text("Select an account to view profile")
                            .font(.headline)
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
            .frame(width: 44, height: 44)  // Increased size for more spacing
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
            await serviceManager.refreshTimeline(force: true)
        }
    }
}

// View for profile image (used in multiple places)
struct ProfileImageView: View {
    let account: SocialAccount

    var body: some View {
        ZStack {
            // Colored circle background based on platform type
            Circle()
                .fill(
                    account.platform == .mastodon ? Color("PrimaryColor") : Color("SecondaryColor")
                )
                .frame(width: 36, height: 36)

            // Profile image
            AsyncImage(url: account.profileImageURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                } else {
                    // Fallback to initial if image can't be loaded
                    Circle()
                        .fill(Color.white)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(String((account.displayName ?? "?").prefix(1)))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(
                                    account.platform == .mastodon
                                        ? Color("PrimaryColor") : Color("SecondaryColor"))
                        )
                }
            }

            // Platform badge in corner
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    PlatformBadge(platform: account.platform)
                        .offset(x: 1, y: 1)  // Adjust placement to be more visible
                }
            }
            .padding(3)
        }
    }
}

// Unified icon showing overlapping accounts
struct UnifiedAccountsIcon: View {
    let mastodonAccounts: [SocialAccount]
    let blueskyAccounts: [SocialAccount]

    var body: some View {
        ZStack {
            // Transparent background container
            Circle()
                .fill(Color.clear)
                .frame(width: 44, height: 44)
                .onAppear {
                    if let firstMastodonAccount = mastodonAccounts.first {
                        print(
                            "First Mastodon account profile image URL: \(String(describing: firstMastodonAccount.profileImageURL))"
                        )
                    }
                    if let firstBlueskyAccount = blueskyAccounts.first {
                        print(
                            "First Bluesky account profile image URL: \(String(describing: firstBlueskyAccount.profileImageURL))"
                        )
                    }
                }

            // Background circle (gray)
            Circle()
                .fill(Color.gray.opacity(0.1))
                .frame(width: 36, height: 36)

            if mastodonAccounts.isEmpty && blueskyAccounts.isEmpty {
                // No accounts, show a placeholder
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 20))
                    .foregroundColor(.gray)
            } else {
                // Show account profiles with colored outlines
                ZStack {
                    // First profile (if any Mastodon accounts)
                    if !mastodonAccounts.isEmpty, let firstMastodonAccount = mastodonAccounts.first
                    {
                        // Colored circle for outline
                        Circle()
                            .fill(Color("PrimaryColor"))
                            .frame(width: 24, height: 24)
                            .offset(x: -6, y: -6)

                        // Profile image
                        AsyncImage(url: firstMastodonAccount.profileImageURL) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                // Fallback to initial if image can't be loaded
                                Text(String((firstMastodonAccount.displayName ?? "?").prefix(1)))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(Color("PrimaryColor"))
                            }
                        }
                        .frame(width: 20, height: 20)
                        .clipShape(Circle())
                        .offset(x: -6, y: -6)
                    }

                    // Second profile (if any Bluesky accounts)
                    if !blueskyAccounts.isEmpty, let firstBlueskyAccount = blueskyAccounts.first {
                        // Colored circle for outline
                        Circle()
                            .fill(Color("SecondaryColor"))
                            .frame(width: 24, height: 24)
                            .offset(x: 6, y: 6)

                        // Profile image
                        AsyncImage(url: firstBlueskyAccount.profileImageURL) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                // Fallback to initial if image can't be loaded
                                Text(String((firstBlueskyAccount.displayName ?? "?").prefix(1)))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(Color("SecondaryColor"))
                            }
                        }
                        .frame(width: 20, height: 20)
                        .clipShape(Circle())
                        .offset(x: 6, y: 6)
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

// Account dropdown view for quick account switching
struct AccountDropdownView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @Binding var selectedAccountId: String?
    @Binding var previousAccountId: String?
    @Binding var isVisible: Bool
    var position: CGPoint

    // Detect drag motion for account selection
    @GestureState private var dragLocation: CGPoint = .zero
    @State private var highlightedIndex: Int? = nil

    var body: some View {
        // Generate combined list of accounts
        let accounts: [AccountOption] =
            [
                AccountOption(
                    id: "all", name: "All Accounts",
                    icon: {
                        UnifiedAccountsIcon(
                            mastodonAccounts: serviceManager.mastodonAccounts,
                            blueskyAccounts: serviceManager.blueskyAccounts
                        )
                    })
            ]
            + serviceManager.mastodonAccounts.map { account in
                AccountOption(
                    id: account.id, name: account.displayName ?? account.username,
                    icon: {
                        ProfileImageView(account: account)
                    })
            }
            + serviceManager.blueskyAccounts.map { account in
                AccountOption(
                    id: account.id, name: account.displayName ?? account.username,
                    icon: {
                        ProfileImageView(account: account)
                    })
            }

        let dropdownHeight = CGFloat(accounts.count * 50)  // Each row is approx 50 points high

        ZStack {
            // Semi-transparent overlay to detect taps outside
            Color.black.opacity(0.001)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    isVisible = false
                }

            // Dropdown container
            VStack(spacing: 0) {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                    accountRow(account, index: index, isHighlighted: highlightedIndex == index)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectAccountAndClose(account.id)
                        }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.systemBackground))
                    .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
            )
            .frame(width: 250)
            // Position the dropdown below the profile icon
            // Use geometry reader for screen-aware positioning
            .position(
                // Horizontal position - keep within screen bounds, near the tap
                x: min(max(position.x, 140), UIScreen.main.bounds.width - 140),
                // Vertical position - much closer to the tap position, with minimal offset
                y: position.y + (dropdownHeight / 2) + 10  // Just 10 points below the icon
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($dragLocation) { value, state, _ in
                        state = value.location
                        // Find which account is under the finger
                        let rowHeight: CGFloat = 50
                        let yOffset = value.location.y - (position.y - (dropdownHeight / 2))
                        let index = Int(yOffset / rowHeight)

                        if index >= 0 && index < accounts.count {
                            highlightedIndex = index
                        }
                    }
                    .onEnded { value in
                        // Select account when drag ends
                        if let index = highlightedIndex, index < accounts.count {
                            selectAccountAndClose(accounts[index].id)
                        }
                        highlightedIndex = nil
                    }
            )
        }
    }

    private func accountRow(_ account: AccountOption, index: Int, isHighlighted: Bool) -> some View
    {
        HStack(spacing: 12) {
            account.icon()
                .frame(width: 30, height: 30)

            Text(account.name)
                .lineLimit(1)
                .font(.system(size: 14, weight: account.id == selectedAccountId ? .bold : .regular))

            Spacer()

            if account.id == selectedAccountId {
                Image(systemName: "checkmark")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isHighlighted ? Color.gray.opacity(0.2) : Color.clear)
    }

    private func selectAccountAndClose(_ id: String) {
        // Store current as previous before changing
        previousAccountId = selectedAccountId

        // If selecting "all", set to nil
        selectedAccountId = id == "all" ? nil : id

        // Close dropdown
        isVisible = false
    }
}

// Helper struct for account options in dropdown
struct AccountOption: Identifiable {
    let id: String
    let name: String
    let icon: () -> AnyView

    init(id: String, name: String, icon: @escaping () -> some View) {
        self.id = id
        self.name = name
        self.icon = { AnyView(icon()) }
    }
}

// This is a temporary replacement for the AccountPickerView until we implement it fully
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

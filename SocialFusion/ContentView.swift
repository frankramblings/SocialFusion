import SwiftUI
import UIKit
import UserNotifications

struct ContentView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @EnvironmentObject var appVersionManager: AppVersionManager
    @State private var selectedTab = 0

    // Account selection state
    @State private var selectedAccountId: String? = nil  // nil means showing unified view
    @State private var previousAccountId: String? = nil  // For back/forth navigation between accounts

    // UI control states
    @State private var showAccountPicker = false
    @State private var showAccountDropdown = false

    @State private var showComposeView = false

    @Environment(\.colorScheme) var colorScheme

    // Double-tap state for scroll functionality
    @State private var lastHomeTapTime: Date = Date()
    @State private var isAtTopOfFeed = true
    @State private var tabBarDelegate: TabBarDelegate?

    // Migration manager for architecture switching
    @StateObject private var migrationManager = GradualMigrationManager.shared

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                // Home Tab - Timeline implementation
                NavigationView {
                    ZStack {
                        // Use the single, consolidated timeline view
                        ConsolidatedTimelineView(serviceManager: serviceManager)

                        // Dropdown overlay positioned correctly
                        if showAccountDropdown {
                            ZStack {
                                // Backdrop to dismiss dropdown
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showAccountDropdown = false
                                        }
                                    }

                                VStack {
                                    HStack {
                                        SimpleAccountDropdown(
                                            selectedAccountId: $selectedAccountId,
                                            previousAccountId: $previousAccountId,
                                            isVisible: $showAccountDropdown
                                        )
                                        .environmentObject(serviceManager)
                                        Spacer()
                                    }
                                    .padding(.leading, 16)
                                    .padding(.top, 8)
                                    Spacer()
                                }
                            }
                            .zIndex(1000)
                        }
                    }
                    .navigationTitle(navigationTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.clear, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            HStack {
                                Text(navigationTitle)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.primary)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .advancedLiquidGlass(
                                variant: .floating,
                                intensity: 0.9,
                                morphingState: .floating
                            )
                            .clipShape(Capsule())
                        }
                    }
                    .navigationBarItems(
                        leading: HStack {
                            // Account selector button
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showAccountDropdown.toggle()
                                }
                            }) {
                                HStack(spacing: 8) {
                                    // Show current account image or unified icon
                                    getCurrentAccountImage()
                                        .frame(width: 30, height: 30)
                                        .clipShape(Circle())

                                    // Dropdown indicator with rotation animation
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.primary)
                                        .rotationEffect(
                                            .degrees(showAccountDropdown ? 180 : 0)
                                        )
                                        .animation(
                                            .easeInOut(duration: 0.2),
                                            value: showAccountDropdown)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    Group {
                                        if showAccountDropdown {
                                            RoundedRectangle(cornerRadius: 22)
                                                .foregroundColor(Color.primary.opacity(0.08))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 22)
                                                        .stroke(
                                                            Color.primary.opacity(0.15),
                                                            lineWidth: 0.5)
                                                )
                                        } else {
                                            Color.clear
                                        }
                                    }
                                )
                            }
                            // Debug: Triple tap to show launch animation
                            .onTapGesture(count: 3) {
                                #if DEBUG
                                    appVersionManager.forceShowLaunchAnimation()
                                #endif
                            }
                        },
                        trailing: Button(action: {
                            showComposeView = true
                        }) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                        }
                    )
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
                    .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
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
                    .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
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

                                        // Platform badge - Enhanced with Liquid Glass
                                        HStack {
                                            PostPlatformBadge(platform: account.platform)
                                        }
                                        .padding(.bottom, 10)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        colorScheme == .dark
                                            ? Color(UIColor.secondarySystemBackground) : Color.white
                                    )

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
                    .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                }
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
                .tag(3)
            }
            .accentColor(Color("PrimaryColor"))
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .onAppear {
                setupTabBarDelegate()

                print("🔧 ContentView: onAppear called")
                print(
                    "🔧 ContentView: serviceManager.accounts.count = \(serviceManager.accounts.count)"
                )
                print(
                    "🔧 ContentView: serviceManager.unifiedTimeline.count = \(serviceManager.unifiedTimeline.count)"
                )
                print(
                    "🔧 ContentView: serviceManager.selectedAccountIds = \(serviceManager.selectedAccountIds)"
                )

                // Ensure account selection is properly initialized
                if selectedAccountId == nil && !serviceManager.accounts.isEmpty {
                    print(
                        "🔧 ContentView: No account selected but accounts exist - setting to unified view"
                    )
                    selectedAccountId = nil  // This represents "All" accounts
                    serviceManager.selectedAccountIds = ["all"]
                } else if let selectedId = selectedAccountId {
                    print("🔧 ContentView: Account selection already set to: \(selectedId)")
                    // Ensure service manager is in sync
                    if !serviceManager.selectedAccountIds.contains(selectedId)
                        && selectedId != "all"
                    {
                        serviceManager.selectedAccountIds = [selectedId]
                        print(
                            "🔧 ContentView: Updated serviceManager.selectedAccountIds to match UI selection"
                        )
                    }
                } else {
                    print("🔧 ContentView: Account selections are already in sync")
                }

                // Ensure timeline is refreshed when app opens
                Task {
                    await serviceManager.ensureTimelineRefresh()
                }

                // Request notification permissions for showing token refresh alerts
                requestNotificationPermissions()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.willEnterForegroundNotification)
            ) { _ in
                serviceManager.automaticTokenRefreshService?.handleAppWillEnterForeground()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didEnterBackgroundNotification)
            ) { _ in
                serviceManager.automaticTokenRefreshService?.handleAppDidEnterBackground()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: Notification.Name.homeTabDoubleTapped)
            ) { _ in
                handleHomeTabDoubleTap()
            }

            // Launch Animation Overlay
            if appVersionManager.shouldShowLaunchAnimation {
                LaunchAnimationView {
                    // Animation completed, hide with smooth transition
                    withAnimation(.easeOut(duration: 0.5)) {
                        appVersionManager.markLaunchAnimationCompleted()
                    }
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.5)))
                .zIndex(1)
            }
        }
    }

    /// Request notification permissions for showing token refresh alerts
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
            granted, error in
            if let error = error {
                print("Failed to request notification permissions: \(error.localizedDescription)")
            } else if granted {
                print("Notification permissions granted")
            } else {
                print("Notification permissions denied")
            }
        }

        // Set up notification categories for better user experience
        let reauthCategory = UNNotificationCategory(
            identifier: "REAUTH_NEEDED",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        let multipleReauthCategory = UNNotificationCategory(
            identifier: "MULTIPLE_REAUTH_NEEDED",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            reauthCategory, multipleReauthCategory,
        ])
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
            return "All Accounts"
        } else if let account = getCurrentAccount() {
            return "@\(account.username)"
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

    // Setup tab bar delegate to detect double-taps
    private func setupTabBarDelegate() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first,
            let tabBarController = findTabBarController(in: window.rootViewController)
        else {
            return
        }

        // Create and store a strong reference to the delegate
        let delegate = TabBarDelegate { [self] in
            handleHomeTap()
        }
        tabBarDelegate = delegate
        tabBarController.delegate = delegate
    }

    // Handle Home tab double-tap
    private func handleHomeTap() {
        guard selectedTab == 0 else { return }  // Only handle when on Home tab

        let now = Date()
        let timeSinceLastTap = now.timeIntervalSince(lastHomeTapTime)

        if timeSinceLastTap < 0.3 {  // Double-tap detected within 300ms
            // Trigger scroll action
            NotificationCenter.default.post(name: .homeTabDoubleTapped, object: nil)
        }

        lastHomeTapTime = now
    }

    // Helper to find UITabBarController
    private func findTabBarController(in viewController: UIViewController?) -> UITabBarController? {
        if let tabBarController = viewController as? UITabBarController {
            return tabBarController
        }

        for child in viewController?.children ?? [] {
            if let found = findTabBarController(in: child) {
                return found
            }
        }

        return nil
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
            try? await serviceManager.refreshTimeline(force: false)
        }
    }

    private var timelineAccounts: [SocialAccount] {
        if let selectedId = selectedAccountId {
            if let account = serviceManager.mastodonAccounts.first(where: { $0.id == selectedId }) {
                return [account]
            } else if let account = serviceManager.blueskyAccounts.first(where: {
                $0.id == selectedId
            }) {
                return [account]
            } else {
                return []
            }
        } else {
            return serviceManager.mastodonAccounts + serviceManager.blueskyAccounts
        }
    }

    private func handleHomeTabDoubleTap() {
        // Implementation of handleHomeTabDoubleTap method
    }
}

// Simple account dropdown using SwiftUI's natural layout
struct SimpleAccountDropdown: View {
    @Binding var selectedAccountId: String?
    @Binding var previousAccountId: String?
    @Binding var isVisible: Bool
    @EnvironmentObject var serviceManager: SocialServiceManager
    @Environment(\.colorScheme) var colorScheme
    @State private var showAddAccountView = false

    var body: some View {
        VStack(spacing: 0) {
            // "All Accounts" option
            Button(action: {
                previousAccountId = selectedAccountId
                selectedAccountId = nil
                serviceManager.selectedAccountIds = ["all"]

                // Clear timeline immediately for better UX
                serviceManager.unifiedTimeline = []
                serviceManager.resetPagination()

                isVisible = false
                Task {
                    try? await serviceManager.refreshTimeline(force: true)
                }
            }) {
                HStack {
                    Text("All Accounts")
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                    Spacer()
                    if selectedAccountId == nil {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            if !serviceManager.mastodonAccounts.isEmpty || !serviceManager.blueskyAccounts.isEmpty {
                Divider().padding(.horizontal, 8)
            }

            // Individual accounts
            ForEach(serviceManager.mastodonAccounts + serviceManager.blueskyAccounts, id: \.id) {
                account in
                Button(action: {
                    previousAccountId = selectedAccountId
                    selectedAccountId = account.id
                    serviceManager.selectedAccountIds = [account.id]

                    // Clear timeline immediately for better UX
                    serviceManager.unifiedTimeline = []
                    serviceManager.resetPagination()

                    isVisible = false
                    Task {
                        try? await serviceManager.refreshTimeline(force: true)
                    }
                }) {
                    HStack {
                        ProfileImageView(account: account)
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.displayName ?? account.username)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Text("@\(account.username)")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if selectedAccountId == account.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())

                if account.id
                    != (serviceManager.mastodonAccounts + serviceManager.blueskyAccounts).last?.id
                {
                    Divider().padding(.horizontal, 8)
                }
            }

            if !serviceManager.mastodonAccounts.isEmpty || !serviceManager.blueskyAccounts.isEmpty {
                Divider().padding(.horizontal, 8)
            }

            // "Add Account" option
            Button(action: {
                showAddAccountView = true
                isVisible = false
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                        .padding(.trailing, 4)
                    Text("Add Account")
                        .font(.system(size: 16))
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
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .frame(width: 220)
        .scaleEffect(isVisible ? 1.0 : 0.8)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isVisible)
        .sheet(isPresented: $showAddAccountView) {
            AddAccountView()
                .environmentObject(serviceManager)
        }
    }
}

// Account dropdown overlay with improved design (DEPRECATED - keeping for reference)
struct AccountDropdownView: View {
    @Binding var selectedAccountId: String?
    @Binding var previousAccountId: String?
    @Binding var isVisible: Bool
    @EnvironmentObject var serviceManager: SocialServiceManager
    @Environment(\.colorScheme) var colorScheme
    @State private var showAddAccountView = false

    let position: CGPoint
    @State private var dropdownSize: CGSize = .zero

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
                    .font(.system(size: 12))
                    .foregroundColor(
                        colorScheme == .dark
                            ? Color(UIColor.secondarySystemBackground) : Color.white
                    )
                    .offset(y: 5)
                    .zIndex(1)

                // Main dropdown content
                VStack(spacing: 0) {
                    // "All Accounts" option with checkmark
                    Button(action: {
                        // Switch to All Accounts
                        previousAccountId = selectedAccountId
                        selectedAccountId = nil

                        // Update selected accounts in service manager
                        serviceManager.selectedAccountIds = ["all"]

                        // Hide the dropdown
                        isVisible = false

                        // Refresh the timeline
                        Task {
                            try? await serviceManager.refreshTimeline(force: false)
                        }
                    }) {
                        HStack {
                            Text("All Accounts")
                                .font(.system(size: 16))
                                .foregroundColor(.primary)

                            Spacer()

                            // Show checkmark if selected
                            if selectedAccountId == nil {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14))
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())

                    Divider()
                        .padding(.horizontal, 8)

                    // Individual accounts
                    ForEach(
                        serviceManager.mastodonAccounts + serviceManager.blueskyAccounts, id: \.id
                    ) { account in
                        Button(action: {
                            // Switch to specific account
                            previousAccountId = selectedAccountId
                            selectedAccountId = account.id

                            // Update selected accounts in service manager
                            serviceManager.selectedAccountIds = [account.id]

                            // Hide the dropdown
                            isVisible = false

                            // Refresh the timeline
                            Task {
                                try? await serviceManager.refreshTimeline(force: false)
                            }
                        }) {
                            HStack {
                                ProfileImageView(account: account)
                                    .frame(width: 24, height: 24)
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.displayName ?? account.username)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    Text("@\(account.username)")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                // Show checkmark if selected
                                if selectedAccountId == account.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14))
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())

                        if account.id
                            != (serviceManager.mastodonAccounts + serviceManager.blueskyAccounts)
                            .last?.id
                        {
                            Divider()
                                .padding(.horizontal, 8)
                        }
                    }

                    if !serviceManager.mastodonAccounts.isEmpty
                        || !serviceManager.blueskyAccounts.isEmpty
                    {
                        Divider()
                            .padding(.horizontal, 8)
                    }

                    // "Add Account" option
                    Button(action: {
                        showAddAccountView = true
                        isVisible = false
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.blue)
                                .padding(.trailing, 4)

                            Text("Add Account")
                                .font(.system(size: 16))
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
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear {
                            dropdownSize = geo.size
                        }
                    }
                )
            }
            .position(adjustedPosition)
            .frame(width: 220)
            .scaleEffect(isVisible ? 1.0 : 0.8)
            .opacity(isVisible ? 1.0 : 0.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isVisible)
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showAddAccountView) {
            AddAccountView()
                .environmentObject(serviceManager)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name("shouldRepresentAddAccount"))
        ) { notification in
            // PHASE 3+: Removed notification handler to prevent AttributeGraph cycles
            // Account management will be handled through normal UI flow instead
        }
    }

    // Calculate position that keeps the dropdown on screen
    private var adjustedPosition: CGPoint {
        let screenWidth = UIScreen.main.bounds.width
        let safeAreaInsets: UIEdgeInsets

        // Get safe area insets using modern approach
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first
        {
            safeAreaInsets = window.safeAreaInsets
        } else {
            safeAreaInsets = .zero
        }

        // Get dropdown dimensions - use fixed values if geometry hasn't calculated yet
        let dropdownWidth: CGFloat = 220

        // Position dropdown below the button, accounting for navigation bar
        let buttonX: CGFloat = 80  // Approximate button position from left
        let buttonY: CGFloat = safeAreaInsets.top + 44 + 30  // Below navigation bar

        var x = buttonX
        var y = buttonY

        // Center horizontally on the button
        x = max(dropdownWidth / 2 + 16, min(screenWidth - dropdownWidth / 2 - 16, x))

        // Position below the button with some padding
        y = buttonY + 20

        return CGPoint(x: x, y: y)
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
            .onReceive(
                NotificationCenter.default.publisher(
                    for: Notification.Name("shouldRepresentAddAccount"))
            ) { notification in
                // PHASE 3+: Removed notification handler to prevent AttributeGraph cycles
                // Account management will be handled through normal UI flow instead
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

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Profile image (real avatar or placeholder)
            if let profileURL = account.profileImageURL {
                AsyncImage(url: profileURL) { phase in
                    if let image = phase.image {
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if phase.error != nil {
                        // Error placeholder
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundColor(.gray)
                    } else {
                        // Loading placeholder
                        Color.gray.opacity(0.3)
                    }
                }
                .clipShape(Circle())
            } else {
                // Default placeholder
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundColor(.gray)
                    .clipShape(Circle())
            }

            // Platform badge in bottom-right
            PlatformBadge(platform: account.platform)
                .offset(x: 2, y: 2)
        }
    }
}

/// UnifiedAccountsIcon displays a visually appealing representation
/// of all accounts when no specific account is selected
struct UnifiedAccountsIcon: View {
    let mastodonAccounts: [SocialAccount]
    let blueskyAccounts: [SocialAccount]

    // Compute accounts without causing side effects
    private var allAccounts: [SocialAccount] {
        mastodonAccounts + blueskyAccounts
    }

    var body: some View {
        if allAccounts.isEmpty {
            // Show placeholder if no accounts
            Image(systemName: "person.3.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
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
}

/// Platform badge to show on account avatars (temporary duplicate to fix build)
struct PlatformBadge: View {
    let platform: SocialPlatform

    private func getLogoSystemName(for platform: SocialPlatform) -> String {
        switch platform {
        case .mastodon:
            return "message.fill"
        case .bluesky:
            return "cloud.fill"
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
            Image(systemName: getLogoSystemName(for: platform))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(getPlatformColor())
                .shadow(color: Color.black.opacity(0.4), radius: 1.5, x: 0, y: 0)
        }
        .frame(width: 20, height: 20)
    }
}

// MARK: - Tab Bar Delegate for Double-Tap Detection
class TabBarDelegate: NSObject, UITabBarControllerDelegate {
    private let onHomeTap: () -> Void

    init(onHomeTap: @escaping () -> Void) {
        self.onHomeTap = onHomeTap
    }

    func tabBarController(
        _ tabBarController: UITabBarController, shouldSelect viewController: UIViewController
    ) -> Bool {
        // If the Home tab (index 0) is selected while already on Home tab, trigger our handler
        if tabBarController.selectedIndex == 0
            && viewController == tabBarController.viewControllers?[0]
        {
            onHomeTap()
        }
        return true
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let homeTabDoubleTapped = Notification.Name("homeTabDoubleTapped")
}

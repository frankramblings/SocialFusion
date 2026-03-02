import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @Binding var showComposeView: Bool
    @Binding var showValidationView: Bool
    
    @State private var notifications: [AppNotification] = []
    @State private var isLoading = false
    @State private var selectedFilter: AppNotification.NotificationType? = nil
    @State private var showFilterDropdown = false
    @State private var scrollOffset: CGFloat = 0
    @State private var showAddAccountView = false
    
    var filteredNotifications: [AppNotification] {
        if let filter = selectedFilter {
            return notifications.filter { $0.type == filter }
        }
        return notifications
    }
    
    // Current filter display title
    private var filterTitle: String {
        if let filter = selectedFilter {
            return filter.displayName
        }
        return "All"
    }
    
    // Dismiss dropdown on scroll
    private func handleScrollChange(offset: CGFloat) {
        let previousOffset = scrollOffset
        scrollOffset = offset
        
        // Dismiss dropdown if scrolling
        if showFilterDropdown && abs(offset - previousOffset) > 5 {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showFilterDropdown = false
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Scroll offset tracking
                        GeometryReader { scrollGeometry in
                            Color.clear
                                .preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: scrollGeometry.frame(in: .named("notificationsScroll")).minY
                                )
                        }
                        .frame(height: 0)
                        
                        // Notifications content
                        if isLoading && notifications.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding(.top, 40)
                        } else if filteredNotifications.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "bell.slash")
                                    .font(.system(size: 50))
                                    .foregroundColor(.gray.opacity(0.3))
                                Text(selectedFilter == nil ? "No notifications yet" : "No \(selectedFilter!.displayName.lowercased()) notifications")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                        } else {
                            ForEach(filteredNotifications) { notification in
                                if let post = notification.post {
                                    NavigationLink(destination: PostDetailView(viewModel: PostViewModel(post: post, serviceManager: serviceManager))) {
                                        NotificationRow(notification: notification)
                                            .padding(.horizontal, 16)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                } else if notification.type == .follow {
                                    NavigationLink(destination: ProfileView(user: SearchUser(id: notification.fromAccount.id, username: notification.fromAccount.username, displayName: notification.fromAccount.displayName, avatarURL: notification.fromAccount.avatarURL, platform: notification.account.platform), serviceManager: serviceManager).environmentObject(serviceManager)) {
                                        NotificationRow(notification: notification)
                                            .padding(.horizontal, 16)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                } else {
                                    NotificationRow(notification: notification)
                                        .padding(.horizontal, 16)
                                }
                                
                                if notification.id != filteredNotifications.last?.id {
                                    Divider()
                                        .padding(.leading, 56)
                                        .padding(.trailing, 16)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .coordinateSpace(name: "notificationsScroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                    handleScrollChange(offset: -offset)
                }
                .refreshable {
                    await fetchNotifications()
                    HapticEngine.tap.trigger()
                }
            }
        }
        .overlay(alignment: .top) {
            // Dropdown overlay positioned just below the toolbar
            if showFilterDropdown {
                ZStack {
                    // Tap outside to dismiss - full screen overlay
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showFilterDropdown = false
                            }
                        }
                    
                    // Dropdown content positioned below toolbar
                    VStack {
                        HStack {
                            Spacer()
                            
                            // Dropdown content
                            NavBarPillDropdown(
                                sections: [
                                    NavBarPillDropdownSection(
                                        id: "notifications-filter",
                                        header: nil,
                                        items: ([nil] + [AppNotification.NotificationType.mention, .repost, .like, .follow] as [AppNotification.NotificationType?]).map { filter in
                                            NavBarPillDropdownItem(
                                                id: filter?.rawValue ?? "all",
                                                title: filter?.displayName ?? "All",
                                                isSelected: selectedFilter == filter,
                                                action: {
                                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                        selectedFilter = filter
                                                        showFilterDropdown = false
                                                    }
                                                }
                                            )
                                        }
                                    )
                                ],
                                width: 200
                            )
                            
                            Spacer()
                        }
                        .padding(.top, 2)
                        
                        Spacer()
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .background(Color(.systemBackground))
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavBarPillSelector(
                    title: filterTitle,
                    isExpanded: showFilterDropdown,
                    action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showFilterDropdown.toggle()
                        }
                    }
                )
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                composeButton
            }
        }
        .onAppear {
            Task {
                await fetchNotifications()
            }
        }
        .sheet(isPresented: $showAddAccountView) {
            AddAccountView()
                .environmentObject(serviceManager)
        }
    }

    private var composeButton: some View {
        Button {
            showComposeView = true
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Compose")
        .accessibilityHint("Create a new post")
        .accessibilityIdentifier("ComposeToolbarButton")
        .onLongPressGesture(minimumDuration: 1.0) {
            showValidationView = true
        }
    }
    
    private func fetchNotifications() async {
        isLoading = true
        let previousNotifications = notifications
        let previousCount = notifications.count
        
        do {
            let fetchedNotifications = try await serviceManager.fetchNotifications()
            let fetchedCount = fetchedNotifications.count
            
            DebugLog.verbose(
                "NotificationsView fetched \(fetchedCount) notifications (previous \(previousCount))")
            
            // Only update if we got results, or if both are empty (to show empty state when there really are none)
            // This prevents clearing existing notifications if fetch returns empty due to cancellation
            if !fetchedNotifications.isEmpty {
                // Got new results, update
                notifications = fetchedNotifications
            } else if previousNotifications.isEmpty {
                // Both are empty, show empty state
                notifications = fetchedNotifications
            } else {
                // Fetch returned empty but we had notifications - likely cancelled, preserve existing
                DebugLog.verbose(
                    "NotificationsView fetch returned empty; preserving \(previousCount) existing notifications")
                notifications = previousNotifications
            }
        } catch {
            // Check if this is a cancellation error
            let isCancellation = (error as NSError).domain == NSURLErrorDomain && 
                                (error as NSError).code == NSURLErrorCancelled
            
            if isCancellation {
                DebugLog.verbose(
                    "NotificationsView request cancelled; preserving \(previousCount) existing notifications")
            } else {
                DebugLog.verbose("NotificationsView failed to fetch notifications: \(error)")
            }
            
            // Preserve existing notifications on error to prevent blank screen
            notifications = previousNotifications
        }
        isLoading = false
    }
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let opacity: Double
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
                .foregroundColor(isSelected ? .blue : .secondary)
                .opacity(opacity)
                .cornerRadius(20)
                .conditionalLiquidGlass(enabled: isSelected, prominence: .thin)
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
    }
}

extension AppNotification.NotificationType {
    var displayName: String {
        switch self {
        case .like: return "Likes"
        case .repost: return "Reposts"
        case .mention: return "Mentions"
        case .follow: return "Follows"
        case .poll: return "Polls"
        case .update: return "Updates"
        }
    }
}

struct NotificationRow: View {
    let notification: AppNotification
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                notificationIcon
                    .font(.system(size: 18))
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let avatarURL = notification.fromAccount.avatarURL, let url = URL(string: avatarURL) {
                            CachedAsyncImage(url: url, priority: .high) { image in
                                image.resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Circle().fill(Color.gray.opacity(0.3))
                                    .overlay(
                                        ProgressView()
                                            .scaleEffect(0.5)
                                    )
                            }
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                        } else {
                            Circle().fill(Color.gray.opacity(0.3))
                                .frame(width: 32, height: 32)
                        }
                        
                        VStack(alignment: .leading) {
                            EmojiDisplayNameText(
                                notification.fromAccount.displayName ?? notification.fromAccount.username,
                                emojiMap: notification.fromAccount.displayNameEmojiMap,
                                font: .subheadline,
                                fontWeight: .bold,
                                foregroundColor: .primary,
                                lineLimit: 1
                            )
                            Text(notificationText)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(notification.createdAt, style: .relative)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if let post = notification.post {
                        Text(PostNormalizerImpl.shared.normalizeContent(post.content))
                            .font(.system(size: 14))
                            .lineLimit(2)
                            .foregroundColor(.primary.opacity(0.8))
                            .padding(.leading, 4)
                            .overlay(
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 2)
                                    .padding(.leading, -4),
                                alignment: .leading
                            )
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var notificationIcon: some View {
        switch notification.type {
        case .like:
            Image(systemName: "heart.fill").foregroundColor(.red)
        case .repost:
            Image(systemName: "arrow.2.squarepath").foregroundColor(.green)
        case .mention:
            Image(systemName: "at").foregroundColor(.blue)
        case .follow:
            Image(systemName: "person.badge.plus.fill").foregroundColor(.purple)
        case .poll:
            Image(systemName: "chart.bar.fill").foregroundColor(.orange)
        case .update:
            Image(systemName: "pencil").foregroundColor(.gray)
        }
    }
    
    private var notificationText: String {
        switch notification.type {
        case .like: return "liked your post"
        case .repost: return "reposted your post"
        case .mention: return "mentioned you"
        case .follow: return "followed you"
        case .poll: return "a poll you voted in has ended"
        case .update: return "edited a post"
        }
    }
}

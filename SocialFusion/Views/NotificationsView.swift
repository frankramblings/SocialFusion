import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @Binding var showAccountDropdown: Bool
    @Binding var showComposeView: Bool
    @Binding var showValidationView: Bool
    @Binding var selectedAccountId: String?
    @Binding var previousAccountId: String?
    
    @State private var notifications: [AppNotification] = []
    @State private var isLoading = false
    @State private var selectedFilter: AppNotification.NotificationType? = nil
    @State private var showFilterDropdown = false
    @State private var scrollOffset: CGFloat = 0
    
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
                                    NavigationLink(destination: UserDetailView(user: SearchUser(id: notification.fromAccount.id, username: notification.fromAccount.username, displayName: notification.fromAccount.displayName, avatarURL: notification.fromAccount.avatarURL, platform: notification.account.platform))) {
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
                            VStack(spacing: 0) {
                                ForEach([nil] + [AppNotification.NotificationType.mention, .repost, .like, .follow] as [AppNotification.NotificationType?], id: \.self) { filter in
                                    FilterDropdownRow(
                                        title: filter?.displayName ?? "All",
                                        isSelected: selectedFilter == filter,
                                        action: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                selectedFilter = filter
                                                showFilterDropdown = false
                                            }
                                        }
                                    )
                                    
                                    if filter != AppNotification.NotificationType.follow {
                                        Divider()
                                            .padding(.horizontal, 12)
                                    }
                                }
                            }
                            .frame(width: 200)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 4)
                                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                            )
                            .frame(maxHeight: 300)
                            
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
            ToolbarItem(placement: .navigationBarLeading) {
                accountButton
            }
            ToolbarItem(placement: .principal) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showFilterDropdown.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(filterTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .rotationEffect(.degrees(showFilterDropdown ? 180 : 0))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
                            .shadow(color: .black.opacity(0.02), radius: 2, x: 0, y: 0.5)
                    )
                }
                .buttonStyle(PlainButtonStyle())
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
        .overlay(alignment: .topLeading) {
            if showAccountDropdown {
                accountDropdownOverlay
            }
        }
        .sheet(isPresented: $showComposeView) {
            ComposeView().environmentObject(serviceManager)
        }
        .sheet(isPresented: $showValidationView) {
            TimelineValidationDebugView(serviceManager: serviceManager)
        }
    }
    
    private var accountButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                showAccountDropdown.toggle()
            }
        }) {
            getCurrentAccountImage()
                .frame(width: 24, height: 24)
        }
        .accessibilityLabel("Account selector")
    }
    
    private var composeButton: some View {
        Image(systemName: "square.and.pencil")
            .font(.system(size: 18))
            .foregroundColor(.primary)
            .onTapGesture {
                showComposeView = true
            }
            .onLongPressGesture(minimumDuration: 1.0) {
                showValidationView = true
            }
    }
    
    private var accountDropdownOverlay: some View {
        ZStack {
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
    
    private func getCurrentAccount() -> SocialAccount? {
        guard let selectedId = selectedAccountId else { return nil }
        return serviceManager.mastodonAccounts.first(where: { $0.id == selectedId })
            ?? serviceManager.blueskyAccounts.first(where: { $0.id == selectedId })
    }
    
    @ViewBuilder
    private func getCurrentAccountImage() -> some View {
        if selectedAccountId != nil, let account = getCurrentAccount() {
            ProfileImageView(account: account)
        } else {
            UnifiedAccountsIcon(
                mastodonAccounts: serviceManager.mastodonAccounts,
                blueskyAccounts: serviceManager.blueskyAccounts
            )
        }
    }
    
    private func fetchNotifications() async {
        isLoading = true
        do {
            notifications = try await serviceManager.fetchNotifications()
        } catch {
            print("Failed to fetch notifications: \(error)")
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

// Filter dropdown row
struct FilterDropdownRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
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
                            AsyncImage(url: url) { image in
                                image.resizable()
                            } placeholder: {
                                Circle().fill(Color.gray.opacity(0.3))
                            }
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                        } else {
                            Circle().fill(Color.gray.opacity(0.3))
                                .frame(width: 32, height: 32)
                        }
                        
                        VStack(alignment: .leading) {
                            Text(notification.fromAccount.displayName ?? notification.fromAccount.username)
                                .font(.subheadline)
                                .fontWeight(.bold)
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
                        Text(post.content)
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


struct DirectMessagesView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @Binding var showAccountDropdown: Bool
    @Binding var showComposeView: Bool
    @Binding var showValidationView: Bool
    @Binding var selectedAccountId: String?
    @Binding var previousAccountId: String?
    
    @State private var conversations: [DMConversation] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isLoading && conversations.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.top, 40)
                } else if conversations.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 50))
                            .foregroundColor(.gray.opacity(0.3))
                        Text("No messages yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else {
                    ForEach(conversations) { conversation in
                        NavigationLink(destination: ChatView(conversation: conversation)) {
                            DMConversationRow(conversation: conversation)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        if conversation.id != conversations.last?.id {
                            Divider()
                                .padding(.leading, 78)
                                .padding(.trailing, 16)
                        }
                    }
                }
            }
        }
        .refreshable {
            await fetchConversations()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { 
                errorMessage = nil 
            }
            if errorMessage != nil {
                Button("Retry") {
                    errorMessage = nil
                    Task {
                        await fetchConversations()
                    }
                }
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                accountButton
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                composeButton
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .topLeading) {
            if showAccountDropdown {
                accountDropdownOverlay
            }
        }
        .sheet(isPresented: $showComposeView) {
            ComposeView().environmentObject(serviceManager)
        }
        .sheet(isPresented: $showValidationView) {
            TimelineValidationDebugView(serviceManager: serviceManager)
        }
        .onAppear {
            Task {
                await fetchConversations()
            }
        }
    }
    
    private var accountButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                showAccountDropdown.toggle()
            }
        }) {
            getCurrentAccountImage()
                .frame(width: 24, height: 24)
        }
        .accessibilityLabel("Account selector")
    }
    
    private var composeButton: some View {
        Image(systemName: "square.and.pencil")
            .font(.system(size: 18))
            .foregroundColor(.primary)
            .onTapGesture {
                showComposeView = true
            }
            .onLongPressGesture(minimumDuration: 1.0) {
                showValidationView = true
            }
    }
    
    private var accountDropdownOverlay: some View {
        ZStack {
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
    
    private func getCurrentAccount() -> SocialAccount? {
        guard let selectedId = selectedAccountId else { return nil }
        return serviceManager.mastodonAccounts.first(where: { $0.id == selectedId })
            ?? serviceManager.blueskyAccounts.first(where: { $0.id == selectedId })
    }
    
    @ViewBuilder
    private func getCurrentAccountImage() -> some View {
        if selectedAccountId != nil, let account = getCurrentAccount() {
            ProfileImageView(account: account)
        } else {
            UnifiedAccountsIcon(
                mastodonAccounts: serviceManager.mastodonAccounts,
                blueskyAccounts: serviceManager.blueskyAccounts
            )
        }
    }
    
    private func fetchConversations() async {
        isLoading = true
        errorMessage = nil
        do {
            conversations = try await serviceManager.fetchDirectMessages()
        } catch {
            errorMessage = "Failed to load conversations: \(error.localizedDescription)"
            ErrorHandler.shared.handleError(error) {
                Task {
                    await fetchConversations()
                }
            }
        }
        isLoading = false
    }
}

struct DMConversationRow: View {
    let conversation: DMConversation
    
    var body: some View {
        HStack(spacing: 12) {
            if let avatarURL = conversation.participant.avatarURL, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { image in
                    image.resizable()
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.3))
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Circle().fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.participant.displayName ?? conversation.participant.username)
                        .font(.headline)
                    
                    Spacer()
                    
                    Text(conversation.lastMessage.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Text(conversation.lastMessage.content)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            if conversation.unreadCount > 0 {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 10, height: 10)
            }
        }
        .padding(.vertical, 4)
    }
}


import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showComposeView: Bool
    @Binding var showValidationView: Bool
    
    @State private var notifications: [AppNotification] = []
    @State private var isLoading = false
    @State private var selectedFilter: AppNotification.NotificationType? = nil
    @State private var showFilterDropdown = false
    /// Scroll offset captured when the filter dropdown opens, used only to
    /// dismiss it on scroll. nil while the dropdown is closed so we don't write
    /// @State on every scroll frame (that per-frame write invalidated the whole
    /// view — the AttributeGraph-cycle pattern that was removed from the timeline).
    @State private var dropdownScrollBaseline: CGFloat?
    @State private var showAddAccountView = false
    /// Set when a (non-cancellation) fetch fails with no notifications to show,
    /// so a first-load failure surfaces a retryable error instead of the
    /// indistinguishable "All quiet" empty state.
    @State private var fetchError: Error?

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
    
    // Dismiss dropdown on scroll. Only does work while the dropdown is open, so
    // the common case (just scrolling the list) performs no @State writes.
    private func handleScrollChange(offset: CGFloat) {
        guard showFilterDropdown else { return }

        // First frame after opening: establish the baseline without dismissing.
        guard let baseline = dropdownScrollBaseline else {
            dropdownScrollBaseline = offset
            return
        }

        if abs(offset - baseline) > 5 {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
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
                                    .accessibilityLabel("Loading notifications")
                                Spacer()
                            }
                            .padding(.top, 40)
                        } else if fetchError != nil && notifications.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 44, weight: .light))
                                    .foregroundStyle(Color.secondary.gradient)
                                    .symbolRenderingMode(.hierarchical)

                                VStack(spacing: 6) {
                                    Text("Couldn't load notifications")
                                        .font(.title3.weight(.semibold))
                                        .foregroundColor(.primary.opacity(0.8))

                                    Text("Check your connection and try again.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 40)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Button {
                                    Task {
                                        await fetchNotifications()
                                        HapticEngine.tap.trigger()
                                    }
                                } label: {
                                    Text("Retry")
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.borderedProminent)
                                .accessibilityHint("Reload notifications")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                            .padding(.bottom, 40)
                            .accessibilityElement(children: .combine)
                        } else if filteredNotifications.isEmpty {
                            VStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            RadialGradient(
                                                colors: [
                                                    Color.accentColor.opacity(0.14),
                                                    Color.accentColor.opacity(0.0),
                                                ],
                                                center: .center,
                                                startRadius: 4,
                                                endRadius: 70
                                            )
                                        )
                                        .frame(width: 140, height: 140)

                                    Image(systemName: selectedFilter == nil ? "bell.slash" : "tray")
                                        .font(.system(size: 44, weight: .light))
                                        .foregroundStyle(Color.secondary.gradient)
                                        .symbolRenderingMode(.hierarchical)
                                        .contentTransition(.symbolEffect(.replace))
                                }

                                VStack(spacing: 6) {
                                    Text(selectedFilter == nil ? "All quiet" : "No \(selectedFilter!.displayName.lowercased())")
                                        .font(.title3.weight(.semibold))
                                        .foregroundColor(.primary.opacity(0.8))

                                    Text(selectedFilter == nil
                                         ? "When someone interacts with your posts, you'll see it here."
                                         : "Try switching filters to see other notifications.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 40)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                            .padding(.bottom, 40)
                            // Combined element + header trait so the
                            // empty state lands on the headings rotor
                            // — matches the rotor-anchor pass across
                            // other primary empty states.
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isHeader)
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
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
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
                                                    // NavBarPillDropdownRow fires .selection internally.
                                                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
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
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .background(Color(.systemBackground))
        .background(notificationsKeyboardShortcut)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavBarPillSelector(
                    title: filterTitle,
                    isExpanded: showFilterDropdown,
                    action: {
                        // NavBarPillSelector fires .tap internally; no need
                        // to duplicate it here.
                        // Re-establish the scroll baseline each time the dropdown
                        // opens so it dismisses on the *next* scroll, not stale movement.
                        dropdownScrollBaseline = nil
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
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
            HapticEngine.tap.trigger()
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
        .accessibilityHint("Opens the post composer")
        .accessibilityIdentifier("ComposeToolbarButton")
        #if DEBUG
        .onLongPressGesture(minimumDuration: 1.0) {
            showValidationView = true
        }
        #endif
    }
    
    /// ⌘R refreshes notifications, mirroring the timeline shortcut so
    /// iPadOS users have a consistent "refresh active surface" gesture
    /// across the app.
    private var notificationsKeyboardShortcut: some View {
        Button("Refresh Notifications") {
            Task {
                await fetchNotifications()
                HapticEngine.tap.trigger()
            }
        }
        .keyboardShortcut("r", modifiers: .command)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
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
            
            // A successful fetch clears any prior error state.
            fetchError = nil

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
                // Surface a retryable error only when there's nothing to show;
                // if we still have notifications, keep them and stay silent.
                if previousNotifications.isEmpty {
                    fetchError = error
                }
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
                // Selected-state tint = accentColor so the filter
                // chip respects the user's app-level tint (and
                // matches whatever the rest of the system is doing
                // for selection). Was hard-coded .blue, which broke
                // alignment with non-blue accents.
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .opacity(opacity)
                .cornerRadius(20)
                .conditionalLiquidGlass(enabled: isSelected, prominence: .thin)
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color(.systemGray4), lineWidth: 1)
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
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        let initial = String((notification.fromAccount.displayName ?? notification.fromAccount.username).prefix(1)).uppercased()
                        if let avatarURL = notification.fromAccount.avatarURL, let url = URL(string: avatarURL) {
                            CachedAsyncImage(url: url, priority: .high) { image in
                                image.resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Circle().fill(Color(.systemGray5))
                                    .overlay(
                                        Text(initial)
                                            .font(.footnote.weight(.semibold))
                                            .foregroundColor(Color(.systemGray))
                                    )
                            }
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                        } else {
                            Circle().fill(Color(.systemGray5))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(initial)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundColor(Color(.systemGray))
                                )
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
                            .monospacedDigit()
                    }

                    if let post = notification.post {
                        // Quoted-post snippet — the side bar tints to the
                        // notification type's color so the row tells a tiny
                        // visual story (which post got which kind of love).
                        HStack(alignment: .top, spacing: 8) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(notificationAccentColor.opacity(0.4))
                                .frame(width: 2.5)

                            Text(PostNormalizerImpl.shared.normalizeContent(post.content))
                                .font(.footnote)
                                .lineLimit(2)
                                .foregroundColor(.primary.opacity(0.78))
                        }
                        .padding(.leading, 2)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var notificationIcon: some View {
        Group {
            switch notification.type {
            case .like:
                Image(systemName: "heart.fill").foregroundStyle(Color.red.gradient)
            case .repost:
                Image(systemName: "arrow.2.squarepath").foregroundStyle(Color.green.gradient)
            case .mention:
                Image(systemName: "at").foregroundStyle(Color.blue.gradient)
            case .follow:
                Image(systemName: "person.badge.plus.fill").foregroundStyle(Color.purple.gradient)
            case .poll:
                Image(systemName: "chart.bar.fill").foregroundStyle(Color.orange.gradient)
            case .update:
                Image(systemName: "pencil").foregroundStyle(Color(.systemGray).gradient)
            }
        }
        // Hierarchical rendering gives all the notification glyphs the
        // same depth language used throughout the polished surfaces.
        // .gray → systemGray for the same dark-mode-adaptive reasons
        // we converted elsewhere.
        .symbolRenderingMode(.hierarchical)
    }

    /// The accent color used for the quoted-post side bar — picks up the
    /// type's identity so the row tells a coherent story end-to-end.
    private var notificationAccentColor: Color {
        switch notification.type {
        case .like: return .red
        case .repost: return .green
        case .mention: return .blue
        case .follow: return .purple
        case .poll: return .orange
        case .update: return .gray
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

    private var accessibilityLabel: String {
        // Decode entities — Mastodon displayName can carry raw HTML
        // entities ("Frank&#8217;s"), which VoiceOver would read as
        // "Frank ampersand pound 8217 semicolon s." The adjacent visible
        // chip already routes through EmojiDisplayNameText (decoded);
        // this brings the a11y label in line.
        let name = (notification.fromAccount.displayName ?? notification.fromAccount.username).decodingHTMLEntities
        var label = "\(name) \(notificationText)"

        // Append the post snippet so VoiceOver can hear which post got
        // the interaction — visually present in the row, but invisible
        // to VoiceOver without this.
        if let post = notification.post {
            let snippet = PostNormalizerImpl.shared.normalizeContent(post.content)
            if !snippet.isEmpty {
                label += ". \(snippet)"
            }
        }

        // Append a natural-language timestamp ('5 minutes ago') rather
        // than relying on the visible '5m' shorthand — same readability
        // treatment we apply elsewhere.
        label += ". \(SharedFormatters.relativeFull.localizedString(for: notification.createdAt, relativeTo: Date()))"

        return label
    }
}

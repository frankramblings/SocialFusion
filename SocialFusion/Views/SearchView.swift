import SwiftUI

// MARK: - Search Store Wrapper

/// Wrapper to ensure SwiftUI properly observes SearchStore changes
private struct SearchStoreWrapper<Content: View>: View {
    @ObservedObject var store: SearchStore
    let content: (SearchStore) -> Content
    
    init(store: SearchStore, @ViewBuilder content: @escaping (SearchStore) -> Content) {
        self.store = store
        self.content = content
    }
    
    var body: some View {
        content(store)
    }
}

struct SearchView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @Binding var showComposeView: Bool
    @Binding var showValidationView: Bool

    @StateObject private var navigationEnvironment = PostNavigationEnvironment()
    @State private var searchStore: SearchStore?

    @State private var showAddAccountView = false
    @State private var trendingTags: [SearchTag] = []
    @State private var isLoadingTrending = false
    @State private var replyingToPost: Post? = nil
    @State private var quotingToPost: Post? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            if let store = searchStore {
                SearchStoreWrapper(store: store) { observedStore in
                // Chip Row (when results are available)
                if let chipModel = observedStore.chipRowModel, !observedStore.text.isEmpty {
                    SearchChipRow(
                        model: chipModel,
                        onNetworkChange: { selection in
                            let accountId = serviceManager.selectedAccountIds.first ?? "all"
                            let oldText = observedStore.text
                            let oldScope = observedStore.scope
                            let oldSort = observedStore.sort
                            searchStore = serviceManager.createSearchStore(
                                networkSelection: selection,
                                accountId: accountId
                            )
                            searchStore?.text = oldText
                            searchStore?.scope = oldScope
                            searchStore?.sort = oldSort
                            searchStore?.performSearch()
                        },
                        onSortChange: { sort in
                            observedStore.updateSort(sort)
                        }
                    )
                    .padding(.vertical, 8)
                }

                // Direct Open Target (if detected)
                if let directTarget = observedStore.directOpenTarget {
                    DirectOpenRow(target: directTarget) {
                        handleDirectOpen(directTarget)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                // Scope Picker
                if !observedStore.text.isEmpty || observedStore.phase.hasResults {
                    Picker("Search Scope", selection: Binding(
                        get: { observedStore.scope },
                        set: { observedStore.scope = $0 }
                    )) {
                        Text("Posts").tag(SearchScope.posts)
                        Text("Users").tag(SearchScope.users)
                        Text("Tags").tag(SearchScope.tags)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding()
                }

                // Results or Empty State
                if observedStore.phase.isLoading && observedStore.results.isEmpty {
                    Spacer()
                    ProgressView("Searching...")
                    Spacer()
                } else if case .error(let message) = observedStore.phase {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("Search Error")
                            .font(.headline)
                        Text(message)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Spacer()
                } else if observedStore.phase == .empty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No Results")
                            .font(.headline)
                        Text("Try a different search term")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else if observedStore.phase.hasResults {
                    resultsList(store: observedStore)
                } else {
                    emptyStateView(store: observedStore)
                }
                }
            } else {
                Spacer()
                ProgressView("Initializing...")
                Spacer()
            }
        }
        .searchable(
            text: Binding(
                get: { searchStore?.text ?? "" },
                set: { searchStore?.text = $0 }
            ),
            prompt: "People, posts, and hashtags"
        ) {
            if let store = searchStore {
                let suggestions = store.suggestions(for: store.text)
                ForEach(suggestions, id: \.self) { suggestion in
                    Text(suggestion)
                        .searchCompletion(suggestion)
                }
            }
        }
        .onSubmit(of: .search) {
            searchStore?.performSearch()
        }
        .navigationDestination(
            isPresented: Binding(
                get: { navigationEnvironment.selectedUser != nil },
                set: { if !$0 { navigationEnvironment.clearNavigation() } }
            )
        ) {
            if let user = navigationEnvironment.selectedUser {
                UserDetailView(user: user)
                    .environmentObject(serviceManager)
            }
        }
        .navigationDestination(
            isPresented: Binding(
                get: { navigationEnvironment.selectedPost != nil },
                set: { if !$0 { navigationEnvironment.clearNavigation() } }
            )
        ) {
            if let post = navigationEnvironment.selectedPost {
                PostDetailView(
                    viewModel: PostViewModel(post: post, serviceManager: serviceManager)
                )
                .environmentObject(serviceManager)
                .environmentObject(navigationEnvironment)
            }
        }
        .navigationDestination(
            isPresented: Binding(
                get: { navigationEnvironment.selectedTag != nil },
                set: { if !$0 { navigationEnvironment.clearNavigation() } }
            )
        ) {
            if let tag = navigationEnvironment.selectedTag {
                TagDetailView(tag: tag)
                    .environmentObject(serviceManager)
            }
        }
        .navigationTitle("Search")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                composeButton
            }
        }
        .navigationBarTitleDisplayMode(.large)
        .task {
            // Initialize SearchStore with proper provider
            let accountId = serviceManager.selectedAccountIds.first ?? "all"
            let networkSelection = determineNetworkSelection()
            searchStore = serviceManager.createSearchStore(
                networkSelection: networkSelection,
                accountId: accountId
            )
            
            // Load trending tags
            if trendingTags.isEmpty {
                isLoadingTrending = true
                do {
                    trendingTags = try await serviceManager.fetchTrendingTags()
                } catch {
                    DebugLog.verbose("Failed to fetch trending tags: \(error)")
                }
                isLoadingTrending = false
            }
        }
        .onChange(of: serviceManager.accounts.count) {
            let accountId = serviceManager.selectedAccountIds.first ?? "all"
            let networkSelection = searchStore?.networkSelection ?? determineNetworkSelection()
            let oldText = searchStore?.text ?? ""
            let oldScope = searchStore?.scope ?? .posts
            let oldSort = searchStore?.sort ?? .latest
            searchStore = serviceManager.createSearchStore(
                networkSelection: networkSelection,
                accountId: accountId
            )
            if !oldText.isEmpty {
                searchStore?.text = oldText
                searchStore?.scope = oldScope
                searchStore?.sort = oldSort
                searchStore?.performSearch()
            }
        }
        .sheet(item: $replyingToPost) { post in
            ComposeView(replyingTo: post)
                .environmentObject(serviceManager)
        }
        .sheet(item: $quotingToPost) { post in
            ComposeView(quotingTo: post)
                .environmentObject(serviceManager)
        }
        .sheet(isPresented: $showAddAccountView) {
            AddAccountView()
                .environmentObject(serviceManager)
        }
        .refreshable {
            if let store = searchStore {
                await store.refresh()
            }
            HapticEngine.tap.trigger()
        }
    }
    
    // MARK: - Results List
    
    private func resultsList(store: SearchStore) -> some View {
        List {
            ForEach(Array(store.results.enumerated()), id: \.element.id) { index, item in
                switch item {
                case .post(let post):
                    postCardView(for: post)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .onAppear {
                            // Load next page when approaching end
                            if item.id == store.results.suffix(3).first?.id {
                                Task {
                                    await store.loadNextPage()
                                }
                            }
                        }
                case .user(let user):
                    SearchUserRow(user: user) {
                        navigationEnvironment.navigateToUser(from: user)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                case .tag(let tag):
                    SearchTagRow(tag: tag) {
                        // Navigate to tag timeline
                        navigationEnvironment.navigateToTag(tag)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
            }

            // Bottom pagination indicator
            if store.isLoadingNextPage {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading more...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(PlainListStyle())
    }
    
    // MARK: - Post Card View (Reusing PostCardView exactly)
    
    private func postCardView(for post: Post) -> some View {
        // Determine the correct TimelineEntry kind based on post properties
        // CRITICAL: Use same logic as ConsolidatedTimelineView.postCard
        let entryKind: TimelineEntryKind
        if post.originalPost != nil || post.boostedBy != nil {
            let boostedByHandle = post.boostedBy ?? post.authorUsername
            entryKind = .boost(boostedBy: boostedByHandle)
        } else if let parentId = post.inReplyToID {
            entryKind = .reply(parentId: parentId)
        } else {
            entryKind = .normal
        }
        
        let entry = TimelineEntry(
            id: post.id,
            kind: entryKind,
            post: post,
            createdAt: post.createdAt
        )
        
        return PostCardView(
            entry: entry,
            postActionStore: serviceManager.postActionStore,
            postActionCoordinator: serviceManager.postActionCoordinator,
            layoutSnapshot: nil, // No snapshot for search results
            onPostTap: { navigationEnvironment.navigateToPost(post) },
            onParentPostTap: { parentPost in navigationEnvironment.navigateToPost(parentPost) },
            onAuthorTap: { navigationEnvironment.navigateToUser(from: post) },
            onReply: {
                replyingToPost = post.originalPost ?? post
            },
            onRepost: {
                Task {
                    do {
                        _ = try await serviceManager.repostPost(post)
                    } catch {
                        ErrorHandler.shared.handleError(error)
                    }
                }
            },
            onLike: {
                Task {
                    do {
                        _ = try await serviceManager.likePost(post)
                    } catch {
                        ErrorHandler.shared.handleError(error)
                    }
                }
            },
            onShare: { post.presentShareSheet() },
            onOpenInBrowser: { post.openInBrowser() },
            onCopyLink: { post.copyLink() },
            onReport: { report(post) },
            onQuote: {
                quotingToPost = post
            }
        )
    }
    
    // MARK: - Empty State View

    private func emptyStateView(store: SearchStore) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Recent Searches
                if !store.recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recent")
                                .font(.headline)
                            Spacer()
                            Button("Clear") {
                                store.clearRecentSearches()
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(store.recentSearches, id: \.self) { query in
                                    Button(action: {
                                        store.text = query
                                        store.performSearch()
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "magnifyingglass")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Text(query)
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                        .background(.ultraThinMaterial)
                                        .cornerRadius(20)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                // Pinned Searches
                if !store.pinnedSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pinned")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(spacing: 0) {
                            ForEach(Array(store.pinnedSearches.enumerated()), id: \.element.id) { index, savedSearch in
                                Button(action: {
                                    store.text = savedSearch.query
                                    store.scope = savedSearch.scope
                                    store.networkSelection = savedSearch.networkSelection
                                    store.performSearch()
                                }) {
                                    HStack {
                                        Image(systemName: "pin.fill")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                        Text(savedSearch.displayName)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption2)
                                            .foregroundStyle(.quaternary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                                if index < store.pinnedSearches.count - 1 {
                                    Divider().padding(.leading, 40)
                                }
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                }

                // Trending Tags
                if !trendingTags.isEmpty {
                    trendingTagsSection
                } else if isLoadingTrending {
                    trendingTagsPlaceholder
                }

                // No-accounts fallback
                if store.pinnedSearches.isEmpty && store.recentSearches.isEmpty && trendingTags.isEmpty && !isLoadingTrending {
                    noAccountsEmptyState
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Trending Tags Section

    private var trendingTagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trending on Mastodon")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(Array(trendingTags.enumerated()), id: \.element.id) { index, tag in
                    NavigationLink(destination: TagDetailView(tag: tag).environmentObject(serviceManager)) {
                        HStack {
                            Text("#\(tag.name)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            Spacer()
                            if let count = tag.formattedUsageCount {
                                Text(count)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.quaternary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    if index < trendingTags.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    // MARK: - Trending Placeholder (Shimmer)

    private var trendingTagsPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trending on Mastodon")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { index in
                    HStack {
                        Text("#placeholder")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("0.0K")
                            .font(.caption)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    if index < 4 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .redacted(reason: .placeholder)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    // MARK: - No Accounts Empty State

    private var noAccountsEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
                .padding(.top, 40)

            Text("Add an account to discover\ntrending topics")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { showAddAccountView = true }) {
                Text("Add Account")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(20)
            }
        }
    }

    // MARK: - Direct Open Handling
    
    private func handleDirectOpen(_ target: DirectOpenTarget) {
        switch target {
        case .profile(let user):
            navigationEnvironment.navigateToUser(from: user)
        case .post(let post):
            navigationEnvironment.navigateToPost(post)
        case .tag(let tag):
            navigationEnvironment.navigateToTag(tag)
        }
    }
    
    // MARK: - Helper Methods
    
    private func determineNetworkSelection() -> SearchNetworkSelection {
        // Determine based on selected accounts or default to unified
        if serviceManager.mastodonAccounts.isEmpty && !serviceManager.blueskyAccounts.isEmpty {
            return .bluesky
        } else if !serviceManager.mastodonAccounts.isEmpty && serviceManager.blueskyAccounts.isEmpty {
            return .mastodon
        }
        return .unified
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
    
    private func report(_ post: Post) {
        Task {
            do {
                try await serviceManager.reportPost(post)
            } catch {
                ErrorHandler.shared.handleError(error)
            }
        }
    }
    
}

// MARK: - Direct Open Row

struct DirectOpenRow: View {
    let target: DirectOpenTarget
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(.blue)
                Text(displayText)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundColor(.blue)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    private var iconName: String {
        switch target {
        case .profile: return "person.circle"
        case .post: return "doc.text"
        case .tag: return "number"
        }
    }
    
    private var displayText: String {
        switch target {
        case .profile(let user):
            return "Open Profile: @\(user.username)"
        case .post:
            return "Open Post"
        case .tag(let tag):
            return "Search Tag: #\(tag.name)"
        }
    }
}

struct PlatformIndicator: View {
    let platform: SocialPlatform
    
    var body: some View {
        Image(platform.icon)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .padding(4)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(4)
    }
}

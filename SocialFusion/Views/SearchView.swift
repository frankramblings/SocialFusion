import SwiftUI

struct SearchView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @Binding var showAccountDropdown: Bool
    @Binding var showComposeView: Bool
    @Binding var showValidationView: Bool
    @Binding var selectedAccountId: String?
    @Binding var previousAccountId: String?
    
    @StateObject private var navigationEnvironment = PostNavigationEnvironment()
    @State private var searchText = ""
    @State private var searchResult: SearchResult? = nil
    @State private var isSearching = false
    @State private var selectedTab = 0  // 0: Posts, 1: Users, 2: Tags
    @State private var showAddAccountView = false

    @State private var selectedFilterPlatforms: Set<SocialPlatform> = [.mastodon, .bluesky]
    @State private var onlyMedia = false
    @State private var showFilters = false

    @State private var trendingTags: [SearchTag] = []
    @State private var isLoadingTrending = false

    @AppStorage("recentSearches") private var recentSearchesData: Data = Data()
    @State private var recentSearches: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search for people, posts, and hashtags", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onSubmit {
                        performSearch()
                    }
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        searchResult = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }

                Button(action: {
                    showFilters.toggle()
                }) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(
                            showFilters || onlyMedia
                                || selectedFilterPlatforms.count < SocialPlatform.allCases.count
                                ? .blue : .secondary)
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.top, 10)

            if showFilters {
                VStack(spacing: 12) {
                    HStack {
                        Text("Platforms")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        ForEach(SocialPlatform.allCases, id: \.self) { platform in
                            Toggle(
                                platform.rawValue.capitalized,
                                isOn: Binding(
                                    get: { selectedFilterPlatforms.contains(platform) },
                                    set: { isOn in
                                        if isOn {
                                            selectedFilterPlatforms.insert(platform)
                                        } else if selectedFilterPlatforms.count > 1 {
                                            selectedFilterPlatforms.remove(platform)
                                        }
                                    }
                                )
                            )
                            .toggleStyle(.button)
                            .controlSize(.small)
                        }
                    }

                    Toggle("Media Only", isOn: $onlyMedia)
                        .font(.subheadline)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 8)
            }

            if isSearching {
                Spacer()
                ProgressView("Searching...")
                Spacer()
            } else if let result = searchResult {
                Picker("Search Scope", selection: $selectedTab) {
                    Text("Posts").tag(0)
                    Text("Users").tag(1)
                    Text("Tags").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                List {
                    if selectedTab == 0 {
                        ForEach(result.posts) { post in
                            PostCardView(
                                entry: TimelineEntry(
                                    id: post.id,
                                    kind: .normal,
                                    post: post,
                                    createdAt: post.createdAt
                                ),
                                postActionStore: serviceManager.postActionStore,
                                onAuthorTap: { navigationEnvironment.navigateToUser(from: post) },
                                onShare: { post.presentShareSheet() },
                                onOpenInBrowser: { post.openInBrowser() },
                                onCopyLink: { post.copyLink() },
                                onReport: { report(post) }
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                        }
                    } else if selectedTab == 1 {
                        ForEach(result.users) { user in
                            NavigationLink(destination: UserDetailView(user: user)) {
                                HStack {
                                    if let avatarURL = user.avatarURL,
                                        let url = URL(string: avatarURL)
                                    {
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
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())
                                    } else {
                                        Circle().fill(Color.gray.opacity(0.3))
                                            .frame(width: 40, height: 40)
                                    }

                                    VStack(alignment: .leading) {
                                        Text(user.displayName ?? user.username)
                                            .font(.headline)
                                        Text("@\(user.username)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    PlatformIndicator(platform: user.platform)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } else {
                        ForEach(result.tags) { tag in
                            NavigationLink(destination: TagDetailView(tag: tag)) {
                                HStack {
                                    Image(systemName: "number")
                                        .foregroundColor(.secondary)
                                    Text(tag.name)
                                        .font(.headline)
                                    Spacer()
                                    PlatformIndicator(platform: tag.platform)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
            } else {
                VStack(spacing: 0) {
                    if !trendingTags.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Trending")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(trendingTags) { tag in
                                        NavigationLink(destination: TagDetailView(tag: tag)) {
                                            Text("#\(tag.name)")
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(Color.blue.opacity(0.1))
                                                .cornerRadius(20)
                                                .font(.subheadline)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.bottom)
                    }

                    if !recentSearches.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Recent Searches")
                                    .font(.headline)
                                Spacer()
                                Button("Clear") {
                                    recentSearches.removeAll()
                                    saveHistory()
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                            .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(recentSearches, id: \.self) { query in
                                        Button(action: {
                                            searchText = query
                                            performSearch()
                                        }) {
                                            Text(query)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(Color(.systemGray5))
                                                .cornerRadius(20)
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.bottom)
                    }

                    VStack(spacing: 20) {
                        Spacer()
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
                        Spacer()
                    }
                }
            }
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
        .navigationTitle("Search")
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
        .task {
            loadHistory()
            if trendingTags.isEmpty {
                isLoadingTrending = true
                do {
                    trendingTags = try await serviceManager.fetchTrendingTags()
                } catch {
                    print("Failed to fetch trending: \(error)")
                }
                isLoadingTrending = false
            }
        }
        .sheet(isPresented: $showAddAccountView) {
            AddAccountView()
                .environmentObject(serviceManager)
        }
    }

    private func performSearch() {
        guard !searchText.isEmpty else { return }

        // Add to history
        addToHistory(searchText)

        isSearching = true
        Task {
            do {
                searchResult = try await serviceManager.search(
                    query: searchText,
                    platforms: selectedFilterPlatforms,
                    onlyMedia: onlyMedia
                )
            } catch {
                print("Search failed: \(error)")
            }
            isSearching = false
        }
    }

    private func addToHistory(_ query: String) {
        var updated = recentSearches
        updated.removeAll { $0.lowercased() == query.lowercased() }
        updated.insert(query, at: 0)
        if updated.count > 10 {
            updated = Array(updated.prefix(10))
        }
        recentSearches = updated
        saveHistory()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(recentSearches) {
            recentSearchesData = data
        }
    }

    private func loadHistory() {
        if let decoded = try? JSONDecoder().decode([String].self, from: recentSearchesData) {
            recentSearches = decoded
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
                        isVisible: $showAccountDropdown,
                        showAddAccountView: $showAddAccountView
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
    
    private func report(_ post: Post) {
        Task {
            do {
                try await serviceManager.reportPost(post)
            } catch {
                ErrorHandler.shared.handleError(error)
            }
        }
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

import SwiftUI

struct SearchView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @State private var searchText = ""
    @State private var searchResult: SearchResult? = nil
    @State private var isSearching = false
    @State private var selectedTab = 0  // 0: Posts, 1: Users, 2: Tags

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
                                postActionStore: serviceManager.postActionStore
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
                                        AsyncImage(url: url) { image in
                                            image.resizable()
                                        } placeholder: {
                                            Circle().fill(Color.gray.opacity(0.3))
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
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
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

import PhotosUI
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    let account: SocialAccount
    @Binding var showAccountDropdown: Bool
    @Binding var showComposeView: Bool
    @Binding var showValidationView: Bool
    @Binding var selectedAccountId: String?
    @Binding var previousAccountId: String?
    
    @StateObject private var navigationEnvironment = PostNavigationEnvironment()
    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var error: Error? = nil
    @State private var cursor: String? = nil
    @State private var canLoadMore = true
    @State private var showEditProfile = false
    @State private var replyingToPost: Post? = nil
    @State private var showAddAccountView = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Profile Header
                VStack(spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        ProfileImageView(account: account)
                            .frame(width: 80, height: 80)
                            .overlay(
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.displayName ?? account.username)
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("@\(account.username)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            HStack(spacing: 16) {
                                VStack {
                                    Text("\(account.followersCount)")
                                        .fontWeight(.bold)
                                    Text("Followers")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                VStack {
                                    Text("\(account.followingCount)")
                                        .fontWeight(.bold)
                                    Text("Following")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                VStack {
                                    Text("\(account.postsCount)")
                                        .fontWeight(.bold)
                                    Text("Posts")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.top, 4)
                        }

                        Spacer()
                    }
                    .padding(.horizontal)

                    if let bio = account.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }

                    Button(action: { showEditProfile = true }) {
                        Text("Edit Profile")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 20)
                .background(Color(.secondarySystemBackground))

                // Posts Feed
                if isLoading && posts.isEmpty {
                    ProgressView()
                        .padding(.top, 40)
                } else if error != nil {
                    VStack(spacing: 12) {
                        Text("Failed to load posts")
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task {
                                await fetchPosts()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 40)
                } else if posts.isEmpty {
                    Text("No posts yet")
                        .foregroundColor(.secondary)
                        .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(posts) { post in
                            PostCardView(
                                entry: TimelineEntry(
                                    id: post.id,
                                    kind: .normal,
                                    post: post,
                                    createdAt: post.createdAt
                                ),
                                postActionStore: serviceManager.postActionStore,
                                onPostTap: { navigationEnvironment.navigateToPost(post) },
                                onAuthorTap: { navigationEnvironment.navigateToUser(from: post) },
                                onReply: {
                                    // When replying to a boost/repost, reply to the original post instead
                                    replyingToPost = post.isReposted ? (post.originalPost ?? post) : post
                                },
                                onShare: { post.presentShareSheet() },
                                onOpenInBrowser: { post.openInBrowser() },
                                onCopyLink: { post.copyLink() },
                                onReport: { report(post) }
                            )
                            .onAppear {
                                if post.id == posts.last?.id && canLoadMore && !isLoadingMore {
                                    Task {
                                        await fetchMorePosts()
                                    }
                                }
                            }
                            Divider().padding(.horizontal)
                        }

                        if isLoadingMore {
                            ProgressView()
                                .padding()
                        }
                    }
                }
            }
        }
        .navigationTitle(account.displayName ?? account.username)
        .navigationBarTitleDisplayMode(.inline)
        .background(
            NavigationLink(
                destination: navigationEnvironment.selectedUser.map { user in
                    UserDetailView(user: user)
                        .environmentObject(serviceManager)
                },
                isActive: Binding(
                    get: { navigationEnvironment.selectedUser != nil },
                    set: { if !$0 { navigationEnvironment.clearNavigation() } }
                ),
                label: { EmptyView() }
            )
            .hidden()
        )
        .sheet(isPresented: $showEditProfile) {
            EditProfileView(account: account)
        }
        .sheet(item: $replyingToPost) { post in
            ComposeView(replyingTo: post)
                .environmentObject(serviceManager)
        }
        .onAppear {
            if posts.isEmpty {
                Task {
                    await fetchPosts()
                }
            }
        }
        .sheet(isPresented: $showAddAccountView) {
            AddAccountView()
                .environmentObject(serviceManager)
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

    private func fetchPosts() async {
        isLoading = true
        error = nil
        do {
            print("🔍 ProfileView: Fetching posts for account: \(account.username)")
            print("🔍 ProfileView: platformSpecificId: '\(account.platformSpecificId)'")
            print("🔍 ProfileView: platform: \(account.platform)")
            print("🔍 ProfileView: serverURL: \(account.serverURL?.absoluteString ?? "nil")")
            
            let searchUser = SearchUser(
                id: account.platformSpecificId.isEmpty ? "" : account.platformSpecificId,
                username: account.username,
                displayName: account.displayName,
                avatarURL: account.profileImageURL?.absoluteString,
                platform: account.platform
            )
            print("🔍 ProfileView: Created SearchUser with id: '\(searchUser.id)'")
            
            let (newPosts, nextCursor) = try await serviceManager.fetchUserPosts(
                user: searchUser, account: account)
            print("✅ ProfileView: Successfully fetched \(newPosts.count) posts")
            posts = newPosts
            cursor = nextCursor
            canLoadMore = nextCursor != nil && !newPosts.isEmpty
        } catch {
            print("❌ ProfileView: Failed to fetch user posts: \(error)")
            print("❌ ProfileView: Error details: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("❌ ProfileView: Error domain: \(nsError.domain), code: \(nsError.code)")
            }
            self.error = error
        }
        isLoading = false
    }

    private func fetchMorePosts() async {
        guard let currentCursor = cursor, canLoadMore else { return }

        isLoadingMore = true
        do {
            let searchUser = SearchUser(
                id: account.platformSpecificId,
                username: account.username,
                displayName: account.displayName,
                avatarURL: account.profileImageURL?.absoluteString,
                platform: account.platform
            )
            let (newPosts, nextCursor) = try await serviceManager.fetchUserPosts(
                user: searchUser, account: account, cursor: currentCursor)

            if newPosts.isEmpty {
                canLoadMore = false
            } else {
                posts.append(contentsOf: newPosts)
                cursor = nextCursor
                canLoadMore = nextCursor != nil
            }
        } catch {
            print("Failed to fetch more user posts: \(error)")
        }
        isLoadingMore = false
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

struct EditProfileView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var serviceManager: SocialServiceManager
    let account: SocialAccount

    @State private var displayName: String
    @State private var bio: String
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @State private var isLoading = false
    @State private var error: String? = nil

    init(account: SocialAccount) {
        self.account = account
        _displayName = State(initialValue: account.displayName ?? "")
        _bio = State(initialValue: account.bio ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Profile Image")) {
                    HStack {
                        Spacer()
                        VStack {
                            if let selectedImageData, let uiImage = UIImage(data: selectedImageData)
                            {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            } else {
                                ProfileImageView(account: account)
                                    .frame(width: 100, height: 100)
                            }

                            PhotosPicker(selection: $selectedItem, matching: .images) {
                                Text("Change Photo")
                                    .font(.subheadline)
                            }
                            .onChange(of: selectedItem) { newItem in
                                Task {
                                    if let data = try? await newItem?.loadTransferable(
                                        type: Data.self)
                                    {
                                        selectedImageData = data
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical)
                }

                Section(header: Text("Basic Info")) {
                    TextField("Display Name", text: $displayName)
                    ZStack(alignment: .topLeading) {
                        if bio.isEmpty {
                            Text("Bio")
                                .foregroundColor(.gray.opacity(0.5))
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        TextEditor(text: $bio)
                            .frame(minHeight: 100)
                    }
                }

                if let error = error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Save") {
                            saveProfile()
                        }
                        .fontWeight(.bold)
                    }
                }
            }
        }
    }

    private func saveProfile() {
        isLoading = true
        error = nil

        Task {
            do {
                _ = try await serviceManager.updateProfile(
                    account: account,
                    displayName: displayName,
                    bio: bio,
                    avatarData: selectedImageData
                )
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

import PhotosUI
import SwiftUI

/// Unified profile view for both own-account and other-user profiles.
/// Replaces the old ProfileView (own account only) and UserDetailView (other users)
/// with a single component backed by ProfileViewModel.
struct ProfileView: View {
  @EnvironmentObject var serviceManager: SocialServiceManager
  @EnvironmentObject var mergedIdentityStore: MergedIdentityStore
  @EnvironmentObject var fusedMomentStore: FusedMomentStore
  @StateObject private var viewModel: ProfileViewModel
  @StateObject private var navigationEnvironment = PostNavigationEnvironment()
  @State private var relationshipViewModel: RelationshipViewModel?
  @State private var showEditProfile = false
  @State private var replyingToPost: Post? = nil
  @State private var isAvatarDocked = false
  @State private var scrollOffset: CGFloat = 0
  @State private var showMergeChipMenu = false
  @State private var showingManualMergeSheet = false

  // MARK: - Initializers

  /// Initialize for viewing another user's profile.
  init(user: SearchUser, serviceManager: SocialServiceManager) {
    _viewModel = StateObject(wrappedValue: ProfileViewModel(
      user: user, isOwnProfile: false, serviceManager: serviceManager))
  }

  /// Initialize for viewing your own profile.
  init(account: SocialAccount, serviceManager: SocialServiceManager) {
    _viewModel = StateObject(wrappedValue: ProfileViewModel(
      account: account, serviceManager: serviceManager))
  }

  // MARK: - Body

  var body: some View {
    ZStack(alignment: .top) {
      // Layer 0: Sticky banner (pinned behind content)
      // Extends behind nav bar for color wash effect
      if let profile = viewModel.profile {
        StickyProfileBanner(
          headerURL: profile.headerURL,
          platform: profile.platform,
          scrollOffset: scrollOffset
        )
      }

      // Layer 1: Scrollable content
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
          // Transparent spacer so content starts below the banner
          Color.clear.frame(height: StickyProfileBanner.bannerHeight)

          // Profile header content (avatar, bio, stats -- no banner)
          if let profile = viewModel.profile {
            ProfileHeaderView(
              profile: viewModel.activeProfile ?? profile,
              isOwnProfile: viewModel.isOwnProfile,
              onEditProfile: {
                // Tap haptic — opens the Edit Profile sheet via state
                // flip + sheet presentation animation. Same gesture-
                // confirmation pattern as the other CTAs that open
                // sheets (5bb7600 / 687d5a5).
                HapticEngine.tap.trigger()
                showEditProfile = true
              },
              relationshipState: relationshipState,
              onFollow: { Task { await relationshipViewModel?.follow() } },
              onUnfollow: { Task { await relationshipViewModel?.unfollow() } },
              onMute: { Task { await relationshipViewModel?.mute() } },
              onUnmute: { Task { await relationshipViewModel?.unmute() } },
              onBlock: { Task { await relationshipViewModel?.block() } },
              onUnblock: { Task { await relationshipViewModel?.unblock() } },
              isAvatarDocked: $isAvatarDocked,
              scrollOffset: scrollOffset,
              mergedIdentity: viewModel.mergedIdentity,
              mergedTwinProfile: viewModel.mergedTwinProfile,
              selectedSide: $viewModel.selectedSide,
              combinedFollowersCount: viewModel.isMerged ? viewModel.combinedFollowersCount : nil,
              combinedFollowingCount: viewModel.isMerged ? viewModel.combinedFollowingCount : nil,
              combinedStatusesCount: viewModel.isMerged ? viewModel.combinedStatusesCount : nil,
              onUnmerge: { viewModel.unmerge() },
              onTapMergeChip: { showMergeChipMenu = true },
              onMarkAsSamePerson: canPresentManualMerge ? { showingManualMergeSheet = true } : nil
            )
          } else if viewModel.isLoadingProfile {
            profileSkeleton
          } else if viewModel.profileError != nil {
            profileErrorView
          }

          // Tabs (pinned section header) + content
          Section {
            tabContent
          } header: {
            if viewModel.profile != nil {
              ProfileTabBar(selectedTab: $viewModel.selectedTab)
                .padding(.vertical, 4)
                .background(Color(.systemBackground))
            }
          }
        }
        .background {
          // UIKit KVO observer — fires every frame during scrolling.
          // PreferenceKey doesn't propagate through ScrollView during scroll.
          ScrollOffsetTracker { offset in
            scrollOffset = offset
          }
        }
      }
    }
    .ignoresSafeArea(edges: .top)
    .background(profileKeyboardShortcuts)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbarColorScheme(.dark, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .principal) {
        HStack(spacing: 8) {
          if let profile = viewModel.profile {
            navBarAvatar(profile: profile)
              .opacity(isAvatarDocked ? 1 : 0)
              .scaleEffect(isAvatarDocked ? 1 : 0.6, anchor: .leading)
          }
          Text(navigationTitle)
            .font(.subheadline)
            .fontWeight(.semibold)
            .lineLimit(1)
            .opacity(isAvatarDocked ? 1 : 0)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isAvatarDocked)
      }
    }
    .task {
      viewModel.attach(mergedIdentityStore: mergedIdentityStore)
      await viewModel.loadProfile()
      await viewModel.loadPostsForCurrentTab()
      setupRelationshipViewModel()
    }
    .sheet(isPresented: $showingManualMergeSheet) {
      if let profile = viewModel.profile {
        let oppositePlatform: SocialPlatform = profile.platform == .mastodon ? .bluesky : .mastodon
        ManualMergeSheet(
          sourceProfile: profile,
          targetPlatform: oppositePlatform,
          onConfirm: { candidate, twinProfile in
            await viewModel.manualMerge(with: candidate, twinProfile: twinProfile)
          }
        )
        .environmentObject(serviceManager)
      }
    }
    .sheet(item: $viewModel.pendingMatchCandidate) { candidate in
      MergeConfirmationSheet(
        candidate: candidate,
        mastodonAvatarURL: candidate.mastodon.platform == .mastodon
          ? viewModel.profile?.avatarURL
          : viewModel.mergedTwinProfile?.avatarURL,
        blueskyAvatarURL: candidate.bluesky.platform == .bluesky
          ? viewModel.profile?.avatarURL
          : viewModel.mergedTwinProfile?.avatarURL,
        onConfirm: {
          viewModel.confirmPendingMatch()
        },
        onReject: {
          // Treat reject as a tombstone-equivalent: dismiss the candidate
          // and don't re-prompt for the same pair in this session.
          viewModel.dismissPendingMatch()
        },
        onDismiss: {
          viewModel.dismissPendingMatch()
        }
      )
    }
    .confirmationDialog(
      "Merged identity",
      isPresented: $showMergeChipMenu,
      titleVisibility: .visible
    ) {
      if let merge = viewModel.mergedIdentity {
        Button(mergeProvenanceLabel(merge.provenance)) {
          // Information-only row; selecting it just dismisses.
        }
        Button("Unmerge identities", role: .destructive) {
          viewModel.unmerge()
        }
        Button("Cancel", role: .cancel) {}
      }
    } message: {
      if let merge = viewModel.mergedIdentity {
        Text("@\(merge.mastodon.handle) and @\(merge.bluesky.handle) are shown as the same person.")
      }
    }
    .onChange(of: viewModel.selectedTab) { _, _ in
      Task { await viewModel.loadPostsForCurrentTab() }
    }
    .onChange(of: viewModel.selectedSide) { _, _ in
      Task { await viewModel.reloadCurrentTabForSideChange() }
    }
    .sheet(isPresented: $showEditProfile) {
      if let account = ownAccount {
        EditProfileView(account: account)
          .environmentObject(serviceManager)
      }
    }
    .sheet(item: $replyingToPost) { post in
      ComposeView(replyingTo: post)
        .environmentObject(serviceManager)
    }
    .navigationDestination(
      isPresented: Binding(
        get: { navigationEnvironment.selectedUser != nil },
        set: { if !$0 { navigationEnvironment.clearNavigation() } }
      )
    ) {
      if let selectedUser = navigationEnvironment.selectedUser {
        ProfileView(user: selectedUser, serviceManager: serviceManager)
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
          viewModel: PostViewModel(post: post, serviceManager: serviceManager),
          focusReplyComposer: false
        )
        .environmentObject(serviceManager)
        .environmentObject(navigationEnvironment)
      }
    }
  }

  // MARK: - Navigation Title

  private var navigationTitle: String {
    let displayName = viewModel.profile?.displayName
      ?? viewModel.user.displayName
      ?? viewModel.user.username
    var plainText = displayName
    if let emojiMap = viewModel.profile?.displayNameEmojiMap
        ?? viewModel.user.displayNameEmojiMap {
      for shortcode in emojiMap.keys {
        plainText = plainText.replacingOccurrences(of: ":\(shortcode):", with: "")
      }
    }
    return plainText.trimmingCharacters(in: .whitespaces)
  }

  // MARK: - Nav Bar Avatar

  @ViewBuilder
  private func navBarAvatar(profile: UserProfile) -> some View {
    if let avatarURLString = profile.avatarURL,
       let avatarURL = URL(string: avatarURLString) {
      CachedAsyncImage(url: avatarURL, priority: .high) { image in
        image
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: 28, height: 28)
          .clipShape(Circle())
      } placeholder: {
        Circle()
          .fill(profile.platform.swiftUIColor.opacity(0.4))
          .frame(width: 28, height: 28)
      }
    } else {
      Circle()
        .fill(profile.platform.swiftUIColor.opacity(0.4))
        .frame(width: 28, height: 28)
        .overlay {
          Text(String((profile.displayName ?? profile.username).prefix(1)).uppercased())
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
        }
    }
  }

  // MARK: - Relationship State

  private var relationshipState:
    (isFollowing: Bool, isFollowedBy: Bool, isMuting: Bool, isBlocking: Bool)?
  {
    guard !viewModel.isOwnProfile, let vm = relationshipViewModel else { return nil }
    return (
      isFollowing: vm.state.isFollowing,
      isFollowedBy: vm.state.isFollowedBy,
      isMuting: vm.state.isMuting,
      isBlocking: vm.state.isBlocking
    )
  }

  // MARK: - Own Account

  private var ownAccount: SocialAccount? {
    serviceManager.accounts.first(where: { $0.platform == viewModel.user.platform })
  }

  // MARK: - Manual Merge Visibility

  /// "Mark as same person…" only makes sense when (a) the user isn't viewing
  /// their own profile, (b) no merge is currently active, and (c) the user
  /// actually has an account on the opposite network to search against —
  /// otherwise the sheet's search field would return nothing.
  private var canPresentManualMerge: Bool {
    guard !viewModel.isOwnProfile else { return false }
    guard viewModel.mergedIdentity == nil else { return false }
    guard let profile = viewModel.profile else { return false }
    let opposite: SocialPlatform = profile.platform == .mastodon ? .bluesky : .mastodon
    return serviceManager.accounts.contains(where: { $0.platform == opposite })
  }

  // MARK: - Relationship Setup

  private func setupRelationshipViewModel() {
    guard !viewModel.isOwnProfile, relationshipViewModel == nil else { return }
    let actorID = ActorID(from: viewModel.user)
    guard let account = serviceManager.accounts.first(where: {
      $0.platform == viewModel.user.platform
    }) else { return }

    let graphService = serviceManager.graphService(for: viewModel.user.platform)
    let store = serviceManager.relationshipStore
    let vm = RelationshipViewModel(
      actorID: actorID,
      account: account,
      graphService: graphService,
      relationshipStore: store
    )
    relationshipViewModel = vm
    Task { await vm.loadState() }
  }

  // MARK: - Tab Content

  @ViewBuilder
  private var tabContent: some View {
    // Blocked state
    if let rs = relationshipState, rs.isBlocking {
      blockedPlaceholder
    } else if viewModel.selectedTab == .media {
      mediaTabContent
    } else {
      postListContent
    }
  }

  // MARK: - Blocked Placeholder

  private var blockedPlaceholder: some View {
    VStack(spacing: 12) {
      Image(systemName: "hand.raised.fill")
        .font(.system(size: 48))
        .foregroundColor(.secondary)
      Text("You blocked this account")
        .font(.headline)
        .foregroundColor(.secondary)
      Text("You won't see their posts in your timeline.")
        .font(.subheadline)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 60)
  }

  // MARK: - Post List

  @ViewBuilder
  private var postListContent: some View {
    if viewModel.isLoadingPosts && viewModel.currentPosts.isEmpty {
      ProgressView()
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .accessibilityLabel("Loading posts")
    } else if viewModel.currentPosts.isEmpty && !viewModel.isLoadingPosts {
      Text("No posts yet")
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .accessibilityAddTraits(.isHeader)
    } else {
      ForEach(viewModel.currentPosts) { post in
        PostCardView(
          entry: TimelineEntry(
            id: post.id,
            kind: .normal,
            post: post,
            createdAt: post.createdAt
          ),
          postActionStore: serviceManager.postActionStore,
          onPostTap: { navigationEnvironment.navigateToPostFusedAware(post, fusedMomentStore: fusedMomentStore) },
          onAuthorTap: { navigationEnvironment.navigateToUser(from: post) },
          onReply: {
            replyingToPost = post.isReposted ? (post.originalPost ?? post) : post
          },
          onShare: { post.presentShareSheet() },
          onOpenInBrowser: { post.openInBrowser() },
          onCopyLink: { post.copyLink() },
          onReport: { reportPost(post) }
        )
        .onAppear {
          if post.id == viewModel.currentPosts.last?.id
            && viewModel.canLoadMore && !viewModel.isLoadingMore
          {
            Task { await viewModel.loadMorePostsForCurrentTab() }
          }
        }

        Divider().padding(.horizontal)
      }

      if viewModel.isLoadingMore {
        ProgressView()
          .frame(maxWidth: .infinity)
          .padding()
          .accessibilityLabel("Loading more posts")
      }
    }
  }

  // MARK: - Media Tab

  @ViewBuilder
  private var mediaTabContent: some View {
    if viewModel.isLoadingPosts && viewModel.currentPosts.isEmpty {
      ProgressView()
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .accessibilityLabel("Loading media")
    } else if viewModel.currentPosts.isEmpty && !viewModel.isLoadingPosts {
      Text("No media yet")
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .accessibilityAddTraits(.isHeader)
    } else {
      ProfileMediaGridView(posts: viewModel.currentPosts) { post in
        navigationEnvironment.navigateToPostFusedAware(post, fusedMomentStore: fusedMomentStore)
      }
      .padding(.top, 2)

      // Pagination trigger for media
      if viewModel.canLoadMore {
        Color.clear
          .frame(height: 1)
          .onAppear {
            if !viewModel.isLoadingMore {
              Task { await viewModel.loadMorePostsForCurrentTab() }
            }
          }
      }

      if viewModel.isLoadingMore {
        ProgressView()
          .frame(maxWidth: .infinity)
          .padding()
      }
    }
  }

  // MARK: - Profile Skeleton

  private var profileSkeleton: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Banner placeholder
      Rectangle()
        .fill(Color.gray.opacity(0.15))
        .frame(height: 200)

      // Avatar + text placeholders
      HStack(alignment: .bottom, spacing: 12) {
        Circle()
          .fill(Color.gray.opacity(0.2))
          .frame(width: 72, height: 72)
          .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
          .offset(y: -24)
        Spacer()
      }
      .padding(.horizontal, 16)

      VStack(alignment: .leading, spacing: 8) {
        RoundedRectangle(cornerRadius: 4)
          .fill(Color.gray.opacity(0.15))
          .frame(width: 160, height: 20)
        RoundedRectangle(cornerRadius: 4)
          .fill(Color.gray.opacity(0.12))
          .frame(width: 120, height: 14)
        RoundedRectangle(cornerRadius: 4)
          .fill(Color.gray.opacity(0.10))
          .frame(height: 14)
          .frame(maxWidth: .infinity)
        RoundedRectangle(cornerRadius: 4)
          .fill(Color.gray.opacity(0.10))
          .frame(width: 200, height: 14)
      }
      .padding(.horizontal, 16)
      .padding(.top, -12)
      .padding(.bottom, 16)
    }
    .redacted(reason: .placeholder)
    // Same fix as LoadingQuoteView: VoiceOver would announce each
    // placeholder shape's geometry from the redacted skeleton. Hide
    // the structure and announce the load state as one element.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Loading profile")
  }

  // MARK: - Profile Error View

  private var profileErrorView: some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 40))
        .foregroundColor(.secondary)
        // Decorative — the headline reads the state.
        .accessibilityHidden(true)
      Text("Couldn't load this profile")
        .font(.headline)
        .foregroundColor(.secondary)
        .accessibilityAddTraits(.isHeader)
      if let error = viewModel.profileError {
        Text(error.localizedDescription)
          .font(.caption)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 32)
      }
      Button("Retry") {
        HapticEngine.tap.trigger()
        Task {
          viewModel.profileError = nil
          viewModel.profile = nil
          await viewModel.loadProfile()
          await viewModel.loadPostsForCurrentTab()
        }
      }
      .buttonStyle(.bordered)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 60)
  }

  // MARK: - Helpers

  /// ⌘R reloads the profile and its current tab. Profile uses UIKit
  /// scroll-offset tracking for the parallax effect, which makes
  /// .refreshable risky to wire up — so the keyboard shortcut is
  /// actually the *first* refresh affordance on this surface for
  /// hardware-keyboard users.
  private var profileKeyboardShortcuts: some View {
    Button("Reload") {
      Task {
        await viewModel.loadProfile()
        await viewModel.loadPostsForCurrentTab()
      }
    }
    .keyboardShortcut("r", modifiers: .command)
    .frame(width: 0, height: 0)
    .opacity(0)
    .accessibilityHidden(true)
  }

  private func reportPost(_ post: Post) {
    Task {
      do {
        try await serviceManager.reportPost(post)
        HapticEngine.success.trigger()
      } catch {
        HapticEngine.error.trigger()
        ErrorHandler.shared.handleError(error)
      }
    }
  }

  // MARK: - Merge Helpers

  private func mergeProvenanceLabel(_ provenance: MergeProvenance) -> String {
    switch provenance {
    case .userConfirmed: return "Confirmed by you"
    case .verifiedBioCrossLink: return "Verified via bio cross-link"
    case .handleConvention: return "Suggested from matching handles"
    }
  }
}

// MARK: - EditProfileView

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
              .onChange(of: selectedItem) { _, newItem in
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
          // Success haptic — the upload took a beat and the visible
          // signal is the sheet animating away. Confirms the action
          // landed before the dismiss transition takes over.
          HapticEngine.success.trigger()
          isLoading = false
          dismiss()
        }
      } catch {
        await MainActor.run {
          // Error haptic so the user knows the save didn't land; the
          // error string surfaces below the form, but a quiet failure
          // could be missed at a glance.
          HapticEngine.error.trigger()
          self.error = error.localizedDescription
          isLoading = false
        }
      }
    }
  }
}

// MARK: - Scroll Offset Tracker (UIKit KVO)

/// Observes the nearest UIScrollView's contentOffset via KVO.
/// SwiftUI's PreferenceKey system doesn't propagate through ScrollView during
/// scroll events, so we drop to UIKit for reliable per-frame offset tracking.
private struct ScrollOffsetTracker: UIViewRepresentable {
  var onScroll: (CGFloat) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(onScroll: onScroll) }

  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    view.backgroundColor = .clear
    view.isUserInteractionEnabled = false
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    // Defer setup until the view is in the hierarchy with a parent scroll view
    DispatchQueue.main.async {
      context.coordinator.setupIfNeeded(for: uiView)
    }
  }

  class Coordinator {
    let onScroll: (CGFloat) -> Void
    private var observation: NSKeyValueObservation?
    private var isSetUp = false
    private var initialY: CGFloat?

    init(onScroll: @escaping (CGFloat) -> Void) {
      self.onScroll = onScroll
    }

    func setupIfNeeded(for view: UIView) {
      guard !isSetUp else { return }
      // Walk up the view hierarchy to find the enclosing UIScrollView
      var current: UIView? = view
      while let v = current {
        if let scrollView = v as? UIScrollView {
          isSetUp = true
          // Capture initial offset (includes content inset from safe area + nav bar)
          // so we can normalize: 0 = at rest, negative = scrolled up, positive = overscroll
          observation = scrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] _, change in
            guard let y = change.newValue?.y else { return }
            if self?.initialY == nil {
              self?.initialY = y
            }
            let delta = -(y - (self?.initialY ?? 0))
            Task { @MainActor in
              self?.onScroll(delta)
            }
          }
          return
        }
        current = v.superview
      }
    }
  }
}

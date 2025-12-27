import Foundation
import SwiftUI
import UIKit

// MARK: - Main Post Detail View

/// Post detail view with Ivory-inspired visual hierarchy
struct PostDetailView: View {
    @ObservedObject var viewModel: PostViewModel
    let focusReplyComposer: Bool
    @EnvironmentObject var serviceManager: SocialServiceManager
    @EnvironmentObject var navigationEnvironment: PostNavigationEnvironment

    // Thread state management
    @State private var parentPosts: [Post] = []
    @State private var replyPosts: [Post] = []
    @State private var isLoadingThread: Bool = false
    @State private var threadError: Error?
    @State private var hasLoadedInitialThread: Bool = false
    @State private var activeReplyPost: Post?

    // Reply composer state
    @State private var replyText: String = ""
    @State private var isReplying: Bool = false
    @State private var replyError: Error?
    @FocusState private var isReplyFocused: Bool

    // Reply loading state
    @State private var isLoadingReplies: Bool = false
    @State private var repliesError: Error?

    // UI state
    @State private var hasScrolledToSelectedPost: Bool = false
    @State private var didInitialJump: Bool = false
    @State private var showParentIndicator: Bool = false
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollProxy: ScrollViewProxy?
    @State private var measuredTopInset: CGFloat = 0
    @State private var pendingInitialScrollTask: Task<Void, Never>?
    @State private var anchorReady: Bool = false
    @State private var isInitialPositioned: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // Thread scroll position keys
    private let selectedPostScrollID = "selected-post"
    private let topScrollID = "top-anchor"

    // Date formatter for detailed timestamp
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // Platform color for visual consistency
    private var platformColor: Color {
        let displayPost = viewModel.post.originalPost ?? viewModel.post
        switch displayPost.platform {
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
        }
    }

    // Check if reply can be sent
    private var canSendReply: Bool {
        !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && replyText.count <= 500
    }

    init(viewModel: PostViewModel, focusReplyComposer: Bool = false) {
        self.viewModel = viewModel
        self.focusReplyComposer = focusReplyComposer
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Main content with ScrollViewReader for auto-scroll
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            threadContentView(topInset: geometry.safeAreaInsets.top)
                        }
                        .opacity(isInitialPositioned ? 1 : 0)
                    }
                    .background(alignment: .topLeading) {
                        if !parentPosts.isEmpty {
                            // Subtle thread continuation line hints at history above
                            LinearGradient(
                                colors: [
                                    Color.gray.opacity(0.12),
                                    Color.gray.opacity(0.06),
                                    Color.clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(width: 2, height: 80)
                            .clipShape(Capsule())
                            .padding(.leading, 30)  // Perfectly centered in the 60pt column
                            .padding(.top, geometry.safeAreaInsets.top + 10)
                            .allowsHitTesting(false)
                        }
                    }
                    .background(
                        // Scroll offset tracking for the parent posts indicator
                        GeometryReader { geometry in
                            Color.clear
                                .preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: geometry.frame(in: .named("scrollView")).minY)
                        }
                    )
                    .coordinateSpace(name: "scrollView")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_000_000)
                            updateScrollState(offset: offset)
                        }
                    }
                    .onAppear {
                        scrollProxy = proxy
                        loadThreadContext()
                    }
                }

                // Reply composer overlay
                if isReplying {
                    replyComposerView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Parent posts indicator (liquid glass)
                if showParentIndicator && !parentPosts.isEmpty {
                    VStack {
                        HStack {
                            Spacer()
                            parentPostsIndicator()
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(.top, 20)
                    .allowsHitTesting(true)
                }
            }
        }
        .toolbarBackground(.clear, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(
            leading: Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            },
            trailing: Menu {
                postMenuItems
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .menuStyle(.borderlessButton)
        )
        .onAppear {
            if focusReplyComposer && !isReplying {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isReplying = true
                    }
                }
            }

            if FeatureFlagManager.isEnabled(.postActionsV2) {
                serviceManager.postActionStore.ensureState(for: viewModel.post)
                serviceManager.postActionCoordinator.refreshIfStale(for: viewModel.post)
            }
        }
    }

    // MARK: - Thread Content View

    @ViewBuilder
    private func threadContentView(topInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Initial Top Spacer (ensures clearance for transparent header)
            Color.clear
                .frame(height: topInset + 20)
                .id(topScrollID)

            // 2. Parent posts
            if !parentPosts.isEmpty {
                ForEach(Array(parentPosts.enumerated()), id: \.offset) { index, post in
                    NavigationLink(
                        destination:
                            PostDetailView(
                                viewModel: PostViewModel(
                                    post: post, serviceManager: serviceManager),
                                focusReplyComposer: false
                            )
                            .environmentObject(serviceManager)
                            .environmentObject(navigationEnvironment)
                    ) {
                        PostRow(
                            post: post,
                            rowType: .parent,
                            isLastParent: false,
                            showThreadLine: true,
                            onPostTap: { _ in },
                            onReply: { handleAction(.reply, for: post) },
                            onRepost: { handleAction(.repost, for: post) },
                            onLike: { handleAction(.like, for: post) },
                            onShare: { handleAction(.share, for: post) },
                            postActionStore: serviceManager.postActionStore,
                            postActionCoordinator: serviceManager.postActionCoordinator
                        )
                    }
                    .buttonStyle(.plain)

                    // Note: No Dividers between connected thread items for a continuous look
                }
            }

            // 3. Selected post section
            VStack(alignment: .leading, spacing: 0) {
                // Selected post content
                SelectedPostView(
                    post: viewModel.post,
                    showThreadLine: !parentPosts.isEmpty || !replyPosts.isEmpty,
                    dateFormatter: dateFormatter
                )
                .id(selectedPostScrollID)
                .onAppear { anchorReady = true }
                .layoutPriority(1000)

                // Action bar
                PostActionBarWithViewModel(
                    viewModel: viewModel,
                    isReplying: isReplying,
                    onReply: { handleAction(.reply) },
                    onRepost: { handleAction(.repost) },
                    onLike: { handleAction(.like) },
                    onShare: { handleAction(.share) },
                    postActionStore: serviceManager.postActionStore,
                    postActionCoordinator: serviceManager.postActionCoordinator
                )
                .padding(.leading, 60)
                .padding(.trailing, 16)
                .padding(.top, 2)  // Reduced to close gap
                .padding(.bottom, 2)

                // Full timestamp
                HStack {
                    Text(dateFormatter.string(from: viewModel.post.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.leading, 60)
                .padding(.bottom, 12)

                Divider()
            }

            // 4. Replies header
            if !replyPosts.isEmpty {
                HStack {
                    Text("Replies")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                }
                .padding(.leading, 60)
                .padding(.vertical, 14)
                .background(Color.primary.opacity(0.03))

                Divider()
            }

            // 5. Reply posts
            if !replyPosts.isEmpty {
                ForEach(Array(replyPosts.enumerated()), id: \.offset) { index, post in
                    let isLastReply = index == replyPosts.count - 1

                    NavigationLink(
                        destination:
                            PostDetailView(
                                viewModel: PostViewModel(
                                    post: post, serviceManager: serviceManager),
                                focusReplyComposer: false
                            )
                            .environmentObject(serviceManager)
                            .environmentObject(navigationEnvironment)
                    ) {
                        PostRow(
                            post: post,
                            rowType: .reply,
                            isLastParent: false,
                            showThreadLine: true,
                            onPostTap: { _ in },
                            onReply: { handleAction(.reply, for: post) },
                            onRepost: { handleAction(.repost, for: post) },
                            onLike: { handleAction(.like, for: post) },
                            onShare: { handleAction(.share, for: post) },
                            postActionStore: serviceManager.postActionStore,
                            postActionCoordinator: serviceManager.postActionCoordinator
                        )
                    }
                    .buttonStyle(.plain)

                    if !isLastReply {
                        Divider()
                            .padding(.leading, 60)
                            .padding(.trailing, 16)
                    }
                }
            }

            // End of thread spacer
            Color.clear.frame(height: 400)
        }
    }

    // MARK: - Reply Composer View

    @ViewBuilder
    private var replyComposerView: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(.systemGray3))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            HStack {
                Text("Reply to @\((activeReplyPost ?? viewModel.post).authorUsername)")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button("Cancel") {
                    cancelReply()
                }
                .font(.body)
                .foregroundColor(platformColor)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $replyText)
                    .focused($isReplyFocused)
                    .frame(minHeight: 100, maxHeight: 200)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .font(.body)

                HStack {
                    Text("\(replyText.count)/500")
                        .font(.caption)
                        .foregroundColor(replyText.count > 450 ? .orange : .secondary)

                    Spacer()

                    Button("Send") {
                        sendReply()
                    }
                    .disabled(!canSendReply)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(canSendReply ? platformColor : Color(.systemGray4))
                    .foregroundColor(canSendReply ? .white : .secondary)
                    .cornerRadius(20)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
        .cornerRadius(16, corners: [.topLeft, .topRight])
        .shadow(color: .black.opacity(0.1), radius: 10, y: -5)
        .onAppear {
            isReplyFocused = true
        }
    }

    // MARK: - Menu Items

    @ViewBuilder
    private var postMenuItems: some View {
        Button(action: openInBrowser) {
            Label("Open in Browser", systemImage: "safari")
        }

        Button(action: copyLink) {
            Label("Copy Link", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive, action: reportPost) {
            Label("Report Post", systemImage: "exclamationmark.bubble")
        }
    }

    // MARK: - Actions

    private func handleAction(_ action: PostAction, for post: Post? = nil) {
        let targetPost = post ?? viewModel.post

        switch action {
        case .reply:
            activeReplyPost = targetPost
            withAnimation(.easeInOut(duration: 0.3)) {
                isReplying = true
            }
        case .repost:
            if FeatureFlagManager.isEnabled(.postActionsV2) {
                serviceManager.postActionStore.ensureState(for: targetPost)
                serviceManager.postActionCoordinator.toggleRepost(for: targetPost)
            } else {
                if targetPost.id == viewModel.post.id {
                    Task { viewModel.repost() }
                } else {
                    Task {
                        do {
                            _ = try await serviceManager.repost(post: targetPost)
                        } catch {
                            NSLog(
                                "📊 PostDetailView: Failed to repost: %@", error.localizedDescription
                            )
                        }
                    }
                }
            }
        case .like:
            if FeatureFlagManager.isEnabled(.postActionsV2) {
                serviceManager.postActionStore.ensureState(for: targetPost)
                serviceManager.postActionCoordinator.toggleLike(for: targetPost)
            } else {
                if targetPost.id == viewModel.post.id {
                    Task { viewModel.like() }
                } else {
                    Task {
                        do {
                            _ = try await serviceManager.like(post: targetPost)
                        } catch {
                            NSLog(
                                "📊 PostDetailView: Failed to like: %@", error.localizedDescription)
                        }
                    }
                }
            }
        case .share:
            if targetPost.id == viewModel.post.id {
                viewModel.share()
            } else {
                // Generic share for context posts
                let urlString = targetPost.originalURL
                if let url = URL(string: urlString) {
                    let activityVC = UIActivityViewController(
                        activityItems: [url], applicationActivities: nil)
                    if let windowScene = UIApplication.shared.connectedScenes.first
                        as? UIWindowScene,
                        let window = windowScene.windows.first,
                        let rootVC = window.rootViewController
                    {
                        rootVC.present(activityVC, animated: true)
                    }
                }
            }
        case .quote:
            NSLog("📊 PostDetailView: Quote action for post: %@", targetPost.id)
        }
    }

    private func sendReply() {
        let targetPost = activeReplyPost ?? viewModel.post

        Task {
            do {
                let _ = try await serviceManager.replyToPost(targetPost, content: replyText)

                // Update local state if it's the main post
                if targetPost.id == viewModel.post.id {
                    self.viewModel.post.isReplied = true
                }

                if FeatureFlagManager.isEnabled(.postActionsV2) {
                    serviceManager.postActionCoordinator.registerReplySuccess(for: targetPost)
                }

                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.isReplying = false
                        self.replyText = ""
                        self.activeReplyPost = nil
                    }
                }
                loadReplies()
            } catch {
                NSLog("📊 PostDetailView: Failed to send reply: %@", error.localizedDescription)
                await MainActor.run {
                    self.replyError = error
                }
            }
        }
    }

    private func cancelReply() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isReplying = false
            replyText = ""
            activeReplyPost = nil
        }
    }

    private func openInBrowser() {
        guard let url = URL(string: viewModel.post.originalURL) else { return }
        UIApplication.shared.open(url)
    }

    private func copyLink() {
        UIPasteboard.general.string = viewModel.post.originalURL
    }

    private func reportPost() {
        NSLog("Report post: %@", viewModel.post.id)
    }

    // MARK: - Thread Loading

    private func loadThreadContext() {
        guard !hasLoadedInitialThread else { return }
        NSLog("📊 PostDetailView: Loading thread context for post %@", viewModel.post.id)
        isLoadingThread = true
        threadError = nil

        Task {
            do {
                let context = try await serviceManager.fetchThreadContext(for: viewModel.post)
                await MainActor.run {
                    self.parentPosts = context.ancestors
                    self.replyPosts = context.descendants
                    self.isLoadingThread = false
                    self.hasLoadedInitialThread = true
                    NSLog(
                        "📊 PostDetailView: Thread context loaded - %d ancestors, %d descendants",
                        context.ancestors.count, context.descendants.count)
                    finalizeInitialPositioning()
                }
            } catch {
                await MainActor.run {
                    NSLog(
                        "📊 PostDetailView: Failed to load thread context: %@",
                        error.localizedDescription)
                    self.threadError = error
                    self.isLoadingThread = false
                }
            }
        }
    }

    private func finalizeInitialPositioning() {
        if !didInitialJump {
            scheduleInitialScroll(animated: false)
            didInitialJump = true
        }
    }

    private func performScrollToSelected(animated: Bool) {
        guard let proxy = scrollProxy, hasLoadedInitialThread, anchorReady else {
            scheduleInitialScroll(animated: animated, delay: 150_000_000)
            return
        }

        NSLog("📊 PostDetailView: Executing scroll to selected post %@", viewModel.post.id)

        let action = {
            // TRIPLE-TAP SCROLL: We fire the scroll multiple times to "win" against SwiftUI layout updates
            // as parent posts are measured and physical height is calculated.
            proxy.scrollTo(selectedPostScrollID, anchor: .top)

            // Second tap after a tiny layout tick
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                proxy.scrollTo(selectedPostScrollID, anchor: .top)
            }

            // Third tap to be absolutely sure
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                proxy.scrollTo(selectedPostScrollID, anchor: .top)

                // Finally reveal the view
                withAnimation(.easeIn(duration: 0.2)) {
                    isInitialPositioned = true
                }
            }

            hasScrolledToSelectedPost = true
        }

        DispatchQueue.main.async {
            action()
        }
    }

    private func scheduleInitialScroll(animated: Bool, delay: UInt64 = 60_000_000) {
        pendingInitialScrollTask?.cancel()
        pendingInitialScrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            performScrollToSelected(animated: animated)
        }
    }

    private func refreshThreadContext() {
        hasLoadedInitialThread = false
        hasScrolledToSelectedPost = false
        didInitialJump = false
        isInitialPositioned = false
        pendingInitialScrollTask?.cancel()
        parentPosts = []
        replyPosts = []
        loadThreadContext()
    }

    private func loadReplies() {
        guard !isLoadingReplies else { return }
        isLoadingReplies = true
        repliesError = nil
        Task {
            do {
                let context = try await serviceManager.fetchThreadContext(for: viewModel.post)
                self.replyPosts = context.descendants
                self.isLoadingReplies = false
            } catch {
                self.repliesError = error
                self.isLoadingReplies = false
            }
        }
    }

    private func updateScrollState(offset: CGFloat) {
        scrollOffset = offset
        let shouldShow = offset < -120 && !parentPosts.isEmpty
        if showParentIndicator != shouldShow {
            withAnimation(.easeInOut(duration: 0.2)) {
                showParentIndicator = shouldShow
            }
        }
    }

    @ViewBuilder
    private func parentPostsIndicator() -> some View {
        Button(action: {
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.5)) {
                    scrollProxy?.scrollTo(topScrollID, anchor: .top)
                    showParentIndicator = false
                }
            }
        }) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                Image(systemName: "chevron.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Selected Post View (Ivory-style)

struct SelectedPostView: View {
    let post: Post
    let showThreadLine: Bool
    let dateFormatter: DateFormatter

    @Environment(\.colorScheme) private var colorScheme

    // Platform color
    private var platformColor: Color {
        switch post.platform {
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)
        }
    }

    // Thread line color
    private var threadLineColor: Color {
        Color.gray.opacity(0.25)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                // Column 1: Unified Thread/Avatar Column (60pt)
                ZStack(alignment: .top) {
                    if showThreadLine {
                        Rectangle()
                            .fill(threadLineColor)
                            .frame(width: 2)
                            .padding(.top, -40)  // Ensure continuity from parent post
                    }

                    PostAuthorImageView(
                        authorProfilePictureURL: post.authorProfilePictureURL,
                        platform: post.platform,
                        authorName: post.authorName
                    )
                    .frame(width: 48, height: 48)
                    .background(Color(.systemBackground))  // Solid punch-out
                    .clipShape(Circle())
                }
                .frame(width: 60)

                // Column 2: Content Column
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text("@\(post.authorUsername)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 4)

                Spacer()
            }
            .padding(.horizontal, 0)
            .padding(.top, 8)
            .padding(.bottom, 12)

            // Post content section
            VStack(alignment: .leading, spacing: 12) {
                post.contentView(
                    lineLimit: nil,
                    showLinkPreview: true,
                    font: .body,
                    onQuotePostTap: { _ in },
                    allowTruncation: false
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                if !post.attachments.isEmpty {
                    UnifiedMediaGridView(
                        attachments: post.attachments,
                        maxHeight: 350
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.leading, 60)
            .padding(.trailing, 16)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            HStack {
                Rectangle()
                    .fill(platformColor.opacity(0.3))
                    .frame(width: 3)
                Spacer()
            }
        )
        .clipped()
    }
}

// MARK: - Post Row Component

struct PostRow: View {
    let post: Post
    let rowType: PostRowType
    let isLastParent: Bool
    let showThreadLine: Bool
    let onPostTap: (Post) -> Void

    // Action bar support
    var onReply: (() -> Void)? = nil
    var onRepost: (() -> Void)? = nil
    var onLike: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil
    @ObservedObject var postActionStore: PostActionStore
    let postActionCoordinator: PostActionCoordinator?

    @Environment(\.colorScheme) private var colorScheme

    // Thread line color
    private var threadLineColor: Color {
        Color.gray.opacity(0.25)
    }

    // Content styling
    private var contentFont: Font {
        switch rowType {
        case .parent, .reply:
            return .subheadline
        case .selected:
            return .title3
        }
    }

    private var profileImageSize: CGFloat {
        switch rowType {
        case .parent: return 32.0
        case .reply: return 36.0
        case .selected: return 48.0
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Column 1: Unified Thread/Avatar Column (60pt)
            ZStack(alignment: .center) {
                if showThreadLine {
                    Rectangle()
                        .fill(threadLineColor)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }

                PostAuthorImageView(
                    authorProfilePictureURL: post.authorProfilePictureURL,
                    platform: post.platform,
                    authorName: post.authorName
                )
                .frame(width: profileImageSize, height: profileImageSize)
                .background(Color(.systemBackground))  // Punch-out
                .clipShape(Circle())
            }
            .frame(width: 60)

            // Column 2: Content Column
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    HStack(spacing: 4) {
                        Text(post.authorName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text("@\(post.authorUsername)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(post.createdAt.timeAgoDisplay())
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .opacity(0.7)
                }

                post.contentView(
                    lineLimit: rowType == .reply ? 4 : nil,
                    showLinkPreview: true,
                    font: contentFont,
                    onQuotePostTap: { onPostTap($0) },
                    allowTruncation: rowType == .reply
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                if !post.attachments.isEmpty {
                    UnifiedMediaGridView(
                        attachments: post.attachments,
                        maxHeight: 200
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                // Optional action bar for context posts
                if onReply != nil {
                    SmallPostActionBar(
                        post: post,
                        onReply: { onReply?() },
                        onRepost: { onRepost?() },
                        onLike: { onLike?() },
                        onShare: { onShare?() },
                        postActionStore: postActionStore,
                        postActionCoordinator: postActionCoordinator
                    )
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 16)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Post Row Types

enum PostRowType {
    case parent
    case selected
    case reply
}

// MARK: - Supporting Types

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect, byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

// MARK: - Extensions

extension Date {
    func timeAgoDisplay() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Legacy Components (Kept for compatibility)

struct LegacyPostDetailView: View {
    @ObservedObject var viewModel: PostViewModel
    let focusReplyComposer: Bool
    @EnvironmentObject var serviceManager: SocialServiceManager
    @EnvironmentObject var navigationEnvironment: PostNavigationEnvironment
    @State private var replyText: String = ""
    @State private var isReplying: Bool = false
    @Environment(\.dismiss) private var dismiss

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SelectedPostView(
                    post: viewModel.post, showThreadLine: false, dateFormatter: dateFormatter)
                Spacer()
            }
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
    }
}

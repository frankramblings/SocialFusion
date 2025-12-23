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
    @State private var isInitialPositioned: Bool = false
    @State private var showParentIndicator: Bool = false
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollProxy: ScrollViewProxy?
    @State private var measuredTopInset: CGFloat = 0
    @State private var anchorHeight: CGFloat = 150
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // Thread scroll position keys
    private let selectedPostScrollID = "selected-post"
    private let selectedPostAreaID = "selected-post-area"
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
            // Reserve generous space for the transparent nav/gradient + status bar + dynamic island
            let topInset = geometry.safeAreaInsets.top + 90

            ZStack(alignment: .bottom) {
                // Main content with ScrollViewReader for auto-scroll
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            threadContentView(anchorHeight: anchorHeight)
                                .padding(.bottom, 600)  // Significantly increased bottom padding
                        }
                        // Global top inset so the first visible item sits below the nav/gradient
                        .padding(.top, topInset)
                    }
                    .background(alignment: .topLeading) {
                        if !parentPosts.isEmpty {
                            // Polished, subtle thread continuation line to hint there are parents above
                            LinearGradient(
                                colors: [
                                    Color.gray.opacity(0.16),
                                    Color.gray.opacity(0.08),
                                    Color.gray.opacity(0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(width: 2, height: topInset + 20)
                            .clipShape(Capsule())
                            .padding(.leading, 24)  // align with thread line used in PostRow
                            .padding(.top, 6)  // slight inset for a more refined look
                            .allowsHitTesting(false)
                        }
                    }
                    .opacity(isInitialPositioned ? 1 : 0)
                    .allowsHitTesting(isInitialPositioned)
                    .overlay(alignment: .top) {
                        if !isInitialPositioned {
                            ProgressView()
                                .padding(.top, topInset + 16)
                        }
                    }
                    .background(
                        // Allow content to flow behind navigation with scroll offset tracking
                        GeometryReader { geometry in
                            Color.clear
                                .preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: geometry.frame(in: .named("scrollView")).minY)
                        }
                    )
                    .coordinateSpace(name: "scrollView")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                        // Defer state updates to prevent AttributeGraph cycles
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                            updateScrollState(offset: offset)
                        }
                    }
                    .onAppear {
                        measuredTopInset = topInset
                        anchorHeight = max(topInset + 30, 150)

                        // Set the proxy first
                        scrollProxy = proxy

                        // Load thread context which will trigger scroll when finished
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
            },
            trailing: Menu {
                postMenuItems
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .foregroundColor(.primary)
            }
            .menuStyle(.borderlessButton)
        )
        .onAppear {
            // Auto-focus reply if requested
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
    private func threadContentView(anchorHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Anchor for scrolling to top
            Color.clear
                .frame(height: 1)
                .id(topScrollID)

            // 1. Parent posts (above selected post)
            if !parentPosts.isEmpty {
                ForEach(Array(parentPosts.enumerated()), id: \.offset) { index, post in
                    let isLastParent = index == parentPosts.count - 1

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
                            isLastParent: isLastParent,
                            showThreadLine: true,
                            onPostTap: { tappedPost in
                                // Navigation handled by NavigationLink
                            }
                        )
                    }
                    .buttonStyle(.plain)

                    // Divider between parent posts
                    if !isLastParent {
                        Divider()
                            .padding(.horizontal, 16)
                            .padding(.leading, 52)
                    }
                }

                // Divider before anchor post - reduced vertical padding
                Divider()
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }

            // 2. Selected post (anchor) section
            VStack(spacing: 0) {
                // Anchor used for scroll positioning
                Color.clear
                    .frame(height: anchorHeight)  // match/extend topInset to guarantee clearance
                    .id(selectedPostAreaID)

                VStack(spacing: 0) {
                    // Boost banner (if this post was boosted)
                    if let boostInfo = navigationEnvironment.boostInfo {
                        HStack {
                            BoostBanner(
                                handle: boostInfo.boostedBy,
                                platform: viewModel.post.platform
                            )
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }

                    // Selected post content
                    SelectedPostView(
                        post: viewModel.post,
                        showThreadLine: !parentPosts.isEmpty || !replyPosts.isEmpty,
                        dateFormatter: dateFormatter
                    )
                    .id(selectedPostScrollID)
                    .layoutPriority(1000)

                    // Action bar for selected post
                    PostActionBarWithViewModel(
                        viewModel: viewModel,
                        isReplying: isReplying,
                        onReply: { handleAction(.reply) },
                        onRepost: { handleAction(.repost) },
                        onLike: { handleAction(.like) },
                        onShare: { handleAction(.share) },
                        postActionStore: FeatureFlagManager.isEnabled(.postActionsV2)
                            ? serviceManager.postActionStore : nil,
                        postActionCoordinator: FeatureFlagManager.isEnabled(.postActionsV2)
                            ? serviceManager.postActionCoordinator : nil
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    // Full timestamp section for anchor post
                    HStack {
                        Text(dateFormatter.string(from: viewModel.post.createdAt))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // Divider after anchor post
                    Divider()
                        .padding(.horizontal, 16)
                }
            }

            // 3. Replies header (if there are replies)
            if !replyPosts.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Text("REPLIES")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.3)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }
                .background(Color(.systemGroupedBackground))
            }

            // 5. Reply posts (below selected post)
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
                            onPostTap: { tappedPost in
                                // Navigation handled by NavigationLink
                            }
                        )
                    }
                    .buttonStyle(.plain)

                    // Divider between reply posts
                    if !isLastReply {
                        Divider()
                            .padding(.horizontal, 16)
                            .padding(.leading, 52)
                    }
                }
            }

            // Loading indicator
            if isLoadingThread {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading thread...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 20)
            }

            // Thread error state
            if threadError != nil {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title3)
                        .foregroundColor(.orange)
                    Text("Could not load thread")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        refreshThreadContext()
                    }
                    .font(.caption)
                    .foregroundColor(platformColor)
                }
                .padding(.vertical, 20)
            }
        }
    }

    // MARK: - Reply Composer View

    @ViewBuilder
    private var replyComposerView: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(.systemGray3))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            // Reply header
            HStack {
                Text("Reply to @\(viewModel.post.authorUsername)")
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

            // Text editor
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $replyText)
                    .focused($isReplyFocused)
                    .frame(minHeight: 100, maxHeight: 200)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .font(.body)

                // Character count and send button
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
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .onAppear {
            if focusReplyComposer {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isReplyFocused = true
                }
            }
        }
    }

    // MARK: - Menu Items

    @ViewBuilder
    private var postMenuItems: some View {
        Button(action: openInBrowser) {
            Label("Open in Browser", systemImage: "safari")
        }

        Button(action: copyLink) {
            Label("Copy Link", systemImage: "link")
        }

        Button(action: { viewModel.share() }) {
            Label("Share Post", systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive, action: reportPost) {
            Label("Report Post", systemImage: "flag")
        }
    }

    // MARK: - Action Handlers

    private func handleAction(_ action: PostAction) {
        switch action {
        case .reply:
            withAnimation(.easeInOut(duration: 0.3)) {
                isReplying = true
            }
        case .repost:
            if FeatureFlagManager.isEnabled(.postActionsV2) {
                serviceManager.postActionStore.ensureState(for: viewModel.post)
                serviceManager.postActionCoordinator.toggleRepost(for: viewModel.post)
            } else {
                Task { await viewModel.repost() }
            }
        case .like:
            if FeatureFlagManager.isEnabled(.postActionsV2) {
                serviceManager.postActionStore.ensureState(for: viewModel.post)
                serviceManager.postActionCoordinator.toggleLike(for: viewModel.post)
            } else {
                Task { await viewModel.like() }
            }
        case .share:
            viewModel.share()
        case .quote:
            // TODO: Implement quote post functionality
            print("Quote action for post: \(viewModel.post.id)")
        }
    }

    private func sendReply() {
        Task {
            do {
                let _ = try await serviceManager.replyToPost(viewModel.post, content: replyText)

                // Update the post's isReplied state
                self.viewModel.post.isReplied = true
                if FeatureFlagManager.isEnabled(.postActionsV2) {
                    serviceManager.postActionCoordinator.registerReplySuccess(for: viewModel.post)
                }
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.isReplying = false
                    self.replyText = ""
                }

                // Reload replies to show the new reply
                await loadReplies()

            } catch {
                print("📊 PostDetailView: Failed to send reply: \(error)")
                self.replyError = error
            }
        }
    }

    private func cancelReply() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isReplying = false
            replyText = ""
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
        print("Report post: \(viewModel.post.id)")
        // TODO: Implement reporting functionality
    }

    // MARK: - Thread Loading

    private func loadThreadContext() {
        guard !hasLoadedInitialThread else { return }

        print("📊 PostDetailView: Loading thread context for post \(viewModel.post.id)")

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

                    print(
                        "📊 PostDetailView: Thread context loaded - \(context.ancestors.count) ancestors, \(context.descendants.count) descendants"
                    )

                    // Auto-jump to selected post after thread is loaded (no visible animation)
                    if !didInitialJump {
                        scrollToSelectedPost(animated: false)
                        didInitialJump = true
                        hasScrolledToSelectedPost = true
                    } else {
                        isInitialPositioned = true
                    }
                }

            } catch {
                await MainActor.run {
                    print("📊 PostDetailView: Failed to load thread context: \(error)")
                    self.threadError = error
                    self.isLoadingThread = false
                }
            }
        }
    }

    private func scrollToSelectedPost(animated: Bool = true) {
        guard let proxy = scrollProxy else { return }

        // Use a task with a small delay to ensure the layout is ready
        Task { @MainActor in
            // Small delay to allow layout to settle
            try? await Task.sleep(nanoseconds: 120_000_000)

            print("📊 PostDetailView: Executing scroll to selected post \(viewModel.post.id)")

            if animated {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    proxy.scrollTo(selectedPostAreaID, anchor: .top)
                }
            } else {
                proxy.scrollTo(selectedPostAreaID, anchor: .top)
            }

            hasScrolledToSelectedPost = true
            isInitialPositioned = true
        }
    }

    private func refreshThreadContext() {
        hasLoadedInitialThread = false
        hasScrolledToSelectedPost = false
        didInitialJump = false
        isInitialPositioned = false
        parentPosts = []
        replyPosts = []
        loadThreadContext()
    }

    private func loadReplies() {
        guard !isLoadingReplies else { return }

        print("📊 PostDetailView: Loading replies for post \(viewModel.post.id)")

        isLoadingReplies = true
        repliesError = nil

        Task {
            do {
                let context = try await serviceManager.fetchThreadContext(for: viewModel.post)
                let newReplies = context.descendants

                self.replyPosts = newReplies
                self.isLoadingReplies = false

                print("📊 PostDetailView: Loaded \(newReplies.count) replies")

            } catch {
                print("📊 PostDetailView: Failed to load replies: \(error)")
                self.repliesError = error
                self.isLoadingReplies = false
            }
        }
    }

    private func updateScrollState(offset: CGFloat) {
        scrollOffset = offset

        // Show indicator if we've scrolled down past the top margin and there are parent posts
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
                // Liquid glass background
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )

                // Up arrow
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Author header section - moderately prominent
            HStack(spacing: 12) {  // Reasonable spacing
                PostAuthorImageView(
                    authorProfilePictureURL: post.authorProfilePictureURL,
                    platform: post.platform,
                    authorName: post.authorName
                )
                .frame(width: 44, height: 44)  // Standard size, slightly larger than thread posts
                .onTapGesture {
                    // Profile navigation - could be implemented in future
                }

                VStack(alignment: .leading, spacing: 2) {  // Compact spacing
                    Text(post.authorName)
                        .font(.headline)  // Moderately prominent
                        .fontWeight(.semibold)  // Less bold than bold
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text("@\(post.authorUsername)")
                        .font(.subheadline)  // Standard size
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            // Post content section - moderately emphasized
            VStack(alignment: .leading, spacing: 12) {  // Reasonable spacing
                post.contentView(
                    lineLimit: nil,
                    showLinkPreview: true,
                    font: .body,  // Standard body font, just slightly more readable
                    onQuotePostTap: { _ in },
                    allowTruncation: false  // Anchor post never truncated
                )
                .padding(.horizontal, 16)

                // Media attachments
                if !post.attachments.isEmpty {
                    UnifiedMediaGridView(
                        attachments: post.attachments,
                        maxHeight: 350
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 16)
        }
        .overlay(
            // Subtle left border to indicate selected post (no background to allow transparency)
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

// MARK: - Post Row Types

enum PostRowType {
    case parent
    case selected
    case reply
}

// MARK: - Simple Thread Line Component

struct SimpleThreadLine: View {
    let showAbove: Bool
    let showBelow: Bool
    let showConnection: Bool
    let rowType: PostRowType
    let color: Color

    var body: some View {
        HStack(spacing: 0) {
            // Simple vertical line
            VStack(spacing: 0) {
                // Line above
                if showAbove {
                    Rectangle()
                        .fill(color)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }

                // Connection point
                if showConnection {
                    // Simple dot for all connection points
                    Circle()
                        .fill(color)
                        .frame(width: 4, height: 4)
                }

                // Line below
                if showBelow {
                    Rectangle()
                        .fill(color)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 2)

            // No horizontal connection - just vertical line with dots

            Spacer()
        }
    }
}

// MARK: - Post Row Component

struct PostRow: View {
    let post: Post
    let rowType: PostRowType
    let isLastParent: Bool
    let showThreadLine: Bool
    let onPostTap: (Post) -> Void

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
        Color.gray.opacity(0.3)
    }

    // Content styling based on row type - Ivory-inspired hierarchy
    private var contentFont: Font {
        switch rowType {
        case .parent:
            return .subheadline  // Smaller size for parent posts
        case .selected:
            return .title3  // Larger, more prominent for selected post
        case .reply:
            return .subheadline  // Smaller size for reply posts
        }
    }

    private var authorNameFont: Font {
        switch rowType {
        case .parent:
            return .subheadline.weight(.semibold)  // Larger username for parents
        case .selected:
            return .title2.weight(.bold)  // Much more prominent for selected post
        case .reply:
            return .subheadline.weight(.semibold)  // Larger username for replies
        }
    }

    private var authorUsernameColor: Color {
        switch rowType {
        case .parent:
            return .secondary  // De-emphasized for parents
        case .selected:
            return .secondary
        case .reply:
            return .secondary
        }
    }

    private var timestampOpacity: Double {
        switch rowType {
        case .parent:
            return 0.5  // More de-emphasized for parents
        case .selected:
            return 1.0
        case .reply:
            return 0.7  // Slightly more visible than parents
        }
    }

    // Indentation - Ivory-inspired with proper spacing
    private var leftIndentation: CGFloat {
        switch rowType {
        case .parent:
            return 14.0  // Indent parents (~12-16pts as requested)
        case .selected:
            return 0.0  // Selected post flush left
        case .reply:
            return 10.0  // Indent replies (~8-12pts as requested)
        }
    }

    // Profile image size based on row type
    private var profileImageSize: CGFloat {
        switch rowType {
        case .parent:
            return 32.0  // Smaller for de-emphasized parents
        case .selected:
            return 48.0  // Larger for selected post prominence
        case .reply:
            return 36.0  // Medium for replies
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Thread line (if showing thread line)
            if showThreadLine && rowType != .selected {
                VStack(spacing: 0) {
                    // Line above (for replies, connects to selected post)
                    if rowType == .reply {
                        Rectangle()
                            .fill(threadLineColor)
                            .frame(width: 2, height: 20)
                    }

                    // Line continues down through the post but terminates before the separator
                    Rectangle()
                        .fill(threadLineColor)
                        .frame(width: 2)
                        .frame(minHeight: 60)  // Reduced from 80 to 60 to terminate further from separator
                }
                .padding(.leading, 24)  // Align with profile image center
            }

            // Main content with Ivory-inspired indentation
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    // Profile image - size varies by row type
                    PostAuthorImageView(
                        authorProfilePictureURL: post.authorProfilePictureURL,
                        platform: post.platform,
                        authorName: post.authorName
                    )
                    .frame(width: profileImageSize, height: profileImageSize)
                    .onTapGesture {
                        // Profile navigation - could be implemented in future
                    }

                    // Post content
                    VStack(alignment: .leading, spacing: 8) {
                        // Author info and timestamp
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if rowType == .selected {
                                // Stacked layout for selected post (more prominent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(post.authorName)
                                        .font(authorNameFont)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    Text("@\(post.authorUsername)")
                                        .font(.caption)
                                        .foregroundColor(authorUsernameColor)
                                        .lineLimit(1)
                                }
                            } else {
                                // Inline layout for parent/reply posts (more compact)
                                HStack(spacing: 4) {
                                    Text(post.authorName)
                                        .font(authorNameFont)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    Text("@\(post.authorUsername)")
                                        .font(.caption)
                                        .foregroundColor(authorUsernameColor)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            // Show relative time for replies, absolute for others
                            Text(
                                rowType == .reply
                                    ? post.createdAt.timeAgoDisplay()
                                    : post.createdAt.timeAgoDisplay()
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .opacity(timestampOpacity)
                        }

                        // Post content
                        post.contentView(
                            lineLimit: rowType == .reply ? 4 : nil,
                            showLinkPreview: rowType == .selected,
                            font: contentFont,
                            onQuotePostTap: { quotedPost in
                                onPostTap(quotedPost)
                            },
                            allowTruncation: rowType == .reply  // Only replies get truncated
                        )

                        // Media attachments (only for selected post or small media)
                        if !post.attachments.isEmpty
                            && (rowType == .selected || post.attachments.count <= 2)
                        {
                            UnifiedMediaGridView(
                                attachments: post.attachments,
                                maxHeight: rowType == .selected ? 400 : 200
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }

                        // Engagement metrics for selected post
                        if rowType == .selected && (post.likeCount > 0 || post.repostCount > 0) {
                            HStack(spacing: 24) {
                                if post.repostCount > 0 {
                                    HStack(spacing: 4) {
                                        Text("\(post.repostCount)")
                                            .font(.subheadline.weight(.semibold))
                                        Text(post.repostCount == 1 ? "Repost" : "Reposts")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                if post.likeCount > 0 {
                                    HStack(spacing: 4) {
                                        Text("\(post.likeCount)")
                                            .font(.subheadline.weight(.semibold))
                                        Text(post.likeCount == 1 ? "Like" : "Likes")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.leading, leftIndentation)  // Ivory-inspired indentation

            }

            Spacer()
        }
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

// MARK: - Supporting Types

// ScrollOffsetPreferenceKey is defined in ConsolidatedTimelineView.swift

// MARK: - Legacy Components (for backward compatibility)

/// Legacy post detail view following Mail.app's unified layout styling
/// Kept for backward compatibility - consider migrating to PostDetailView
struct LegacyPostDetailView: View {
    @ObservedObject var viewModel: PostViewModel
    let focusReplyComposer: Bool
    @EnvironmentObject var serviceManager: SocialServiceManager
    @EnvironmentObject var navigationEnvironment: PostNavigationEnvironment
    @State private var replyText: String = ""
    @State private var isReplying: Bool = false
    @State private var error: AppError? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // Date formatter for detailed timestamp
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // Platform color for reply context
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

    init(viewModel: PostViewModel, focusReplyComposer: Bool) {
        self.viewModel = viewModel
        self.focusReplyComposer = focusReplyComposer

        // Auto-open reply composer if requested
        if focusReplyComposer {
            _isReplying = State(initialValue: true)
        }
    }

    var body: some View {
        Text("Legacy PostDetailView - Deprecated")
            .foregroundColor(.red)
            .font(.title)
    }
}

/// Enhanced post detail view - superseded by main PostDetailView
/// Kept for reference only
struct EnhancedPostDetailView: View {
    @ObservedObject var viewModel: PostViewModel
    let focusReplyComposer: Bool

    init(viewModel: PostViewModel, focusReplyComposer: Bool) {
        self.viewModel = viewModel
        self.focusReplyComposer = focusReplyComposer
    }

    var body: some View {
        // Redirect to main PostDetailView
        PostDetailView(viewModel: viewModel, focusReplyComposer: focusReplyComposer)
    }
}

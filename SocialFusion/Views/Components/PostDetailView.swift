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
    @FocusState private var isReplyFocused: Bool

    // UI state
    @State private var hasScrolledToSelectedPost: Bool = false
    @State private var showParentIndicator: Bool = false
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollProxy: ScrollViewProxy?
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
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    // Main content with ScrollViewReader for auto-scroll
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                // Top anchor for scroll position
                                Color.clear
                                    .frame(height: 1)
                                    .id(topScrollID)

                                threadContentView
                                    .padding(.bottom, 100)  // Bottom padding for scroll behavior
                            }
                        }
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .preference(
                                        key: ScrollOffsetPreferenceKey.self,
                                        value: geometry.frame(in: .named("scrollView")).minY)
                            }
                        )
                        .coordinateSpace(name: "scrollView")
                        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                            updateScrollState(offset: offset)
                        }
                        .background(Color(.systemGroupedBackground))
                        .onAppear {
                            loadThreadContext()
                            scrollProxy = proxy
                            // Auto-scroll to selected post as visual anchor - immediate positioning
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                scrollToSelectedPost(proxy: proxy)
                            }
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
        }
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.medium))
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    postMenuItems
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                }
                .menuStyle(.borderlessButton)
            }
        }
        .onAppear {
            // Auto-focus reply if requested
            if focusReplyComposer && !isReplying {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isReplying = true
                    }
                }
            }
        }
    }

    // MARK: - Thread Content View

    @ViewBuilder
    private var threadContentView: some View {
        VStack(spacing: 0) {
            // Boost banner (if this post was boosted)
            if let boostInfo = navigationEnvironment.boostInfo {
                HStack(alignment: .top, spacing: 0) {
                    // Align with profile image position
                    Color.clear
                        .frame(width: 52)

                    BoostBanner(
                        handle: boostInfo.boostedBy,
                        platform: viewModel.post.platform
                    )
                    .padding(.trailing, 16)

                    Spacer()
                }
                .padding(.leading, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }

            // Parent posts (above selected post) - MOVED BACK TO TOP
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
            }

            // Divider before anchor post (if there are parent posts)
            if !parentPosts.isEmpty {
                Divider()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)  // Even spacing above and below separator
            }

            // Selected post (anchor) - Ivory-style layout
            VStack(spacing: 0) {
                // Selected post content with top spacing for perfect anchoring
                SelectedPostView(
                    post: viewModel.post,
                    showThreadLine: !parentPosts.isEmpty || !replyPosts.isEmpty,
                    dateFormatter: dateFormatter
                )
                .id(selectedPostScrollID)

                // Action bar for selected post
                PostActionBar(
                    post: viewModel.post,
                    replyCount: viewModel.replyCount,
                    repostCount: viewModel.repostCount,
                    likeCount: viewModel.likeCount,
                    isReplying: isReplying,
                    isReposted: viewModel.isReposted,
                    isLiked: viewModel.isLiked,
                    onReply: { handleAction(.reply) },
                    onRepost: { handleAction(.repost) },
                    onLike: { handleAction(.like) },
                    onShare: { handleAction(.share) }
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
            .background(Color(.systemBackground))

            // Replies header (if there are replies)
            if !replyPosts.isEmpty {
                VStack(spacing: 0) {
                    // Replies header
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

            // Reply posts (below selected post)
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
            if let error = threadError {
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
            Task { await viewModel.repost() }
        case .like:
            Task { await viewModel.like() }
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
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isReplying = false
                        replyText = ""
                    }
                    // Reload replies to show new reply
                    loadReplies()
                }
            } catch {
                print("Error sending reply: \(error)")
                // TODO: Show error to user
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
                        "✅ PostDetailView: Thread loaded - \(context.ancestors.count) parents, \(context.descendants.count) replies"
                    )
                }
            } catch {
                print("❌ PostDetailView: Thread loading failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.threadError = error
                    self.isLoadingThread = false
                    self.hasLoadedInitialThread = true
                }
            }
        }
    }

    private func refreshThreadContext() {
        hasLoadedInitialThread = false
        parentPosts = []
        replyPosts = []
        loadThreadContext()
    }

    private func loadReplies() {
        Task {
            do {
                let context = try await serviceManager.fetchThreadContext(for: viewModel.post)
                await MainActor.run {
                    self.replyPosts = context.descendants
                }
            } catch {
                print("Failed to reload replies: \(error)")
            }
        }
    }

    private func scrollToSelectedPost(proxy: ScrollViewProxy) {
        guard !hasScrolledToSelectedPost else { return }

        // First, immediately jump to the selected post without animation
        proxy.scrollTo(selectedPostScrollID, anchor: .top)

        // Then animate to fine-tune the position
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.4)) {
                proxy.scrollTo(selectedPostScrollID, anchor: .top)
            }
        }

        hasScrolledToSelectedPost = true
    }

    private func updateScrollState(offset: CGFloat) {
        scrollOffset = offset

        // Show indicator if we've scrolled down and there are parent posts
        let shouldShow = offset < -50 && !parentPosts.isEmpty

        withAnimation(.easeInOut(duration: 0.2)) {
            showParentIndicator = shouldShow
        }
    }

    @ViewBuilder
    private func parentPostsIndicator() -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.5)) {
                scrollProxy?.scrollTo(topScrollID, anchor: .top)
                showParentIndicator = false
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
        VStack(spacing: 0) {
            // Author header section - Ivory-inspired prominence
            HStack(spacing: 16) {  // Increased spacing for better hierarchy
                PostAuthorImageView(
                    authorProfilePictureURL: post.authorProfilePictureURL,
                    platform: post.platform,
                    authorName: post.authorName
                )
                .frame(width: 52, height: 52)  // Larger profile image for selected post
                .onTapGesture {
                    // Profile navigation - could be implemented in future
                }

                VStack(alignment: .leading, spacing: 4) {  // More spacing for readability
                    Text(post.authorName)
                        .font(.headline)  // Reduced from .title2 for less overwhelming size
                        .fontWeight(.bold)  // Bold for emphasis
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text("@\(post.authorUsername)")
                        .font(.callout)  // Slightly larger username
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Share/menu button in top right
                Button(action: {}) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)  // Reduced top padding to balance with separator spacing
            .padding(.bottom, 16)  // More spacing before content

            // Post content section with emphasis
            VStack(alignment: .leading, spacing: 20) {  // More generous spacing
                post.contentView(
                    lineLimit: nil,
                    showLinkPreview: true,
                    font: .title3,  // Reduced from .title for better balance
                    onQuotePostTap: { _ in },
                    allowTruncation: false  // Anchor post never truncated
                )
                .padding(.horizontal, 16)

                // Media attachments
                if !post.attachments.isEmpty {
                    UnifiedMediaGridView(
                        attachments: post.attachments,
                        maxHeight: 400
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 20)  // More bottom padding for emphasis
        }
        .background(
            // Soft background color for emphasis (optional)
            RoundedRectangle(cornerRadius: 0)
                .fill(Color(.systemBackground))
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1),
                    radius: 8,
                    x: 0,
                    y: 2
                )
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

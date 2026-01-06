import Foundation
import SwiftUI
import UIKit

// MARK: - Conditional Modifiers

/// Modifier that conditionally applies clipShape
private struct ConditionalClipShapeModifier: ViewModifier {
    let shouldClip: Bool
    
    func body(content: Content) -> some View {
        if shouldClip {
            content.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            content
        }
    }
}

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
    @State private var isReplying: Bool = false
    @State private var isQuickReplyActive: Bool = false
    @State private var replyingToPost: Post? = nil
    @State private var quotingToPost: Post? = nil
    @State private var inlineReplyText: String = ""
    @State private var isSendingQuickReply: Bool = false
    @State private var quickReplyErrorMessage: String?
    @State private var showQuickReplyError: Bool = false
    @State private var selectedReplyAccountId: String?
    @FocusState private var isInlineReplyFocused: Bool

    // Reply loading state
    @State private var isLoadingReplies: Bool = false
    @State private var repliesError: Error?

    // UI state
    @State private var hasScrolledToSelectedPost: Bool = false
    @State private var didInitialJump: Bool = false
    @State private var showParentIndicator: Bool = false
    @State private var scrollOffset: CGFloat = 0
    @State private var measuredTopInset: CGFloat = 0
    @State private var pendingInitialScrollTask: Task<Void, Never>?
    @State private var anchorReady: Bool = false
    @State private var isInitialPositioned: Bool = false
    @State private var scrollTargetID: String? = nil
    @State private var scrollTrigger: Int = 0
    @State private var dragOffset: CGFloat = 0
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

    private func platformTint(for platform: SocialPlatform) -> Color {
        switch platform {
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)
        }
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
                            updateScrollState(offset: offset)
                        }
                    }
                    .onChange(of: scrollTrigger) { _ in
                        if let targetID = scrollTargetID {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                proxy.scrollTo(targetID, anchor: .top)
                            }
                        }
                    }
                    .onAppear {
                        loadThreadContext()
                    }
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
            .offset(x: max(0, dragOffset))
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        // Only activate if starting from the left edge
                        if value.startLocation.x < 20 && value.translation.width > 0 {
                            dragOffset = min(value.translation.width, geometry.size.width * 0.5)
                        }
                    }
                    .onEnded { value in
                        // If dragged far enough, go back
                        if dragOffset > 100 {
                            withAnimation(.easeOut(duration: 0.2)) {
                                dragOffset = geometry.size.width
                            }
                            // Clear navigation after animation
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                navigationEnvironment.clearNavigation()
                                dragOffset = 0
                            }
                        } else {
                            // Spring back if not far enough
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
            .sheet(isPresented: $isReplying) {
                ComposeView(replyingTo: activeReplyPost ?? viewModel.post)
                    .environmentObject(serviceManager)
            }
        }
        .safeAreaInset(edge: .bottom) {
            inlineReplyBar
        }
        .toolbarBackground(.clear, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(
            leading: Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                    .padding(8)
            },
            trailing: Menu {
                postMenuItems
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                    .padding(8)
            }
            .menuStyle(.borderlessButton)
        )
        .alert("Reply failed", isPresented: $showQuickReplyError) {
            Button("OK", role: .cancel) {
                showQuickReplyError = false
            }
        } message: {
            Text(quickReplyErrorMessage ?? "Something went wrong while sending your reply.")
        }
        .sheet(item: $replyingToPost) { post in
            ComposeView(replyingTo: post)
                .environmentObject(serviceManager)
        }
        .sheet(item: $quotingToPost) { post in
            ComposeView(quotingTo: post)
                .environmentObject(serviceManager)
        }
        .onAppear {
            if focusReplyComposer && !isQuickReplyActive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    activateQuickReply(for: viewModel.post, prefill: true)
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
                .onAppear {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 10_000_000)  // 0.01s delay to prevent AttributeGraph cycles
                        anchorReady = true
                    }
                }
                .layoutPriority(1000)

                // Action bar
                PostActionBarWithViewModel(
                    viewModel: viewModel,
                    isReplying: isReplying,
                    onReply: { handleAction(.reply) },
                    onRepost: { handleAction(.repost) },
                    onLike: { handleAction(.like) },
                    onShare: { handleAction(.share) },
                    onQuote: { handleAction(.quote) },
                    postActionStore: serviceManager.postActionStore,
                    postActionCoordinator: serviceManager.postActionCoordinator
                )
                .padding(.leading, 60)
                .padding(.trailing, 16)
                .padding(.top, 2)  // Reduced to close gap
                .padding(.bottom, 2)

                // Full timestamp and client attribution
                HStack(spacing: 8) {
                    Text(dateFormatter.string(from: viewModel.post.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Client/app attribution (e.g., "Ivory for Mac", "IceCubes for iOS")
                    // Only show for Mastodon posts (Bluesky doesn't provide this info in API)
                    // For boosts, show the originalPost's clientName (the actual content)
                    if viewModel.post.platform == .mastodon {
                        // Check originalPost first (for boosts), then fall back to wrapper post
                        let clientName = viewModel.post.originalPost?.clientName ?? viewModel.post.clientName
                        if let clientName = clientName,
                           !clientName.isEmpty,
                           clientName.trimmingCharacters(in: .whitespaces).count > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "globe")
                                    .font(.caption2)
                                    .foregroundColor(.secondary.opacity(0.7))
                                Text(clientName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
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

    // MARK: - Inline Reply Composer

    @ViewBuilder
    private var inlineReplyBar: some View {
        if let replyTarget = activeReplyPost,
            isQuickReplyActive,
            !isReplying
        {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    quickReplyAccountMenu(for: replyTarget.platform)

                    Spacer()

                    Text("\(inlineReplyRemaining)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(
                            inlineReplyRemaining < 0
                                ? .red
                                : (inlineReplyRemaining < 50 ? .orange : .secondary)
                        )

                    Button {
                        openFullComposer(for: replyTarget)
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(UIColor.secondarySystemBackground))
                            )
                    }
                    .accessibilityLabel("Open full composer")

                    Button(action: resetQuickReplyState) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Dismiss quick reply")
                }

                HStack(alignment: .center, spacing: 8) {
                    TextField(
                        "Reply to @\(replyTarget.authorUsername)...",
                        text: $inlineReplyText,
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .focused($isInlineReplyFocused)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .onSubmit {
                        if canSendInlineReply {
                            sendInlineReply()
                        }
                    }

                    if isSendingQuickReply {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(width: 32, height: 32)
                    } else {
                        Button(action: sendInlineReply) {
                            Image(systemName: "paperplane.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(10)
                                .background(
                                    Circle()
                                        .fill(
                                            canSendInlineReply
                                                ? platformTint(for: replyTarget.platform)
                                                : Color.gray.opacity(0.4)
                                        )
                                )
                        }
                        .disabled(!canSendInlineReply)
                        .accessibilityLabel("Send reply")
                    }
                }
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func quickReplyAccountMenu(for platform: SocialPlatform) -> some View {
        let accounts = replyAccounts(for: platform)
        let currentLabel =
            selectedReplyAccount(for: platform)?.displayName
            ?? selectedReplyAccount(for: platform)?.username
            ?? "Select account"

        if accounts.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("Add \(platform.rawValue) account")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.12))
            .clipShape(Capsule())
        } else if accounts.count == 1, let account = accounts.first {
            HStack(spacing: 6) {
                Image(platform.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                Text(account.displayName ?? account.username)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(Capsule())
        } else {
            Menu {
                ForEach(accounts, id: \.id) { account in
                    Button {
                        selectedReplyAccountId = account.id
                    } label: {
                        HStack {
                            Text(account.displayName ?? account.username)
                            if selectedReplyAccountId == account.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(platform.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                    Text(currentLabel)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(Capsule())
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
            activateQuickReply(for: targetPost, prefill: true)
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
            sharePost(targetPost)
        case .quote:
            quotingToPost = targetPost
        case .follow:
            Task {
                await viewModel.followUser()
            }
        case .mute:
            Task {
                await viewModel.muteUser()
            }
        case .block:
            Task {
                await viewModel.blockUser()
            }
        case .addToList:
            // Handled via separate UI path
            break
        @unknown default:
            break
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
    
    private func sharePost(_ post: Post) {
        guard let url = URL(string: post.originalURL) else { return }
        
        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        
        // Exclude some activity types that don't make sense for URLs
        activityVC.excludedActivityTypes = [
            .assignToContact,
            .addToReadingList
        ]
        
        // Find the topmost view controller to present from
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }),
           let rootVC = window.rootViewController {
            
            // Find the topmost presented view controller
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            
            // Configure for iPad
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topVC.view
                popover.sourceRect = CGRect(
                    x: topVC.view.bounds.midX,
                    y: topVC.view.bounds.midY,
                    width: 0,
                    height: 0
                )
                popover.permittedArrowDirections = []
            }
            
            topVC.present(activityVC, animated: true, completion: nil)
        }
    }

    // MARK: - Reply Composer Helpers

    private var inlineReplyRemaining: Int {
        guard let target = activeReplyPost else { return 0 }
        let limit = target.platform == .mastodon ? 500 : 300
        return limit - inlineReplyText.count
    }

    private var canSendInlineReply: Bool {
        guard let target = activeReplyPost else { return false }
        let content = inlineReplyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !content.isEmpty
            && inlineReplyRemaining >= 0
            && !isSendingQuickReply
            && selectedReplyAccount(for: target.platform) != nil
    }

    private func activateQuickReply(for post: Post, prefill: Bool = false) {
        activeReplyPost = post
        hydrateReplyAccountSelection(for: post.platform)
        if prefill && inlineReplyText.isEmpty {
            inlineReplyText = "@\(post.authorUsername) "
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            isQuickReplyActive = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isInlineReplyFocused = true
        }
    }

    private func openFullComposer(for post: Post) {
        activeReplyPost = post
        isQuickReplyActive = false
        isReplying = true
    }

    private func replyAccounts(for platform: SocialPlatform) -> [SocialAccount] {
        switch platform {
        case .mastodon:
            return serviceManager.mastodonAccounts
        case .bluesky:
            return serviceManager.blueskyAccounts
        }
    }

    private func hydrateReplyAccountSelection(for platform: SocialPlatform) {
        let accounts = replyAccounts(for: platform)
        guard !accounts.isEmpty else { return }
        if let selectedReplyAccountId,
            accounts.contains(where: { $0.id == selectedReplyAccountId })
        {
            return
        }
        selectedReplyAccountId = accounts.first?.id
    }

    private func selectedReplyAccount(for platform: SocialPlatform) -> SocialAccount? {
        let accounts = replyAccounts(for: platform)
        if let selectedReplyAccountId,
            let match = accounts.first(where: { $0.id == selectedReplyAccountId })
        {
            return match
        }
        return accounts.first
    }

    private func resetQuickReplyState() {
        inlineReplyText = ""
        isSendingQuickReply = false
        isQuickReplyActive = false
        isInlineReplyFocused = false
        activeReplyPost = nil
    }

    private func sendInlineReply() {
        guard canSendInlineReply, let target = activeReplyPost else { return }
        guard let account = selectedReplyAccount(for: target.platform) else {
            quickReplyErrorMessage = "Add a \(target.platform.rawValue) account to reply."
            showQuickReplyError = true
            return
        }

        let content = inlineReplyText.trimmingCharacters(in: .whitespacesAndNewlines)
        isSendingQuickReply = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                _ = try await serviceManager.replyToPost(
                    target,
                    content: content,
                    accountOverride: account
                )
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    
                    // Register reply success with PostActionCoordinator
                    if FeatureFlagManager.isEnabled(.postActionsV2) {
                        serviceManager.postActionCoordinator.registerReplySuccess(for: target)
                    }
                    
                    resetQuickReplyState()
                    if target.id == viewModel.post.id {
                        viewModel.replyCount += 1
                        viewModel.post.replyCount = viewModel.replyCount
                        viewModel.post.isReplied = true
                    }
                    loadReplies()
                }
            } catch {
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    isSendingQuickReply = false
                    quickReplyErrorMessage = error.localizedDescription
                    showQuickReplyError = true
                }
            }
        }
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
                    // Update the selected post if a more hydrated version is available
                    if let hydratedPost = context.mainPost {
                        self.viewModel.updatePost(hydratedPost)
                    }

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
        guard hasLoadedInitialThread, anchorReady else {
            scheduleInitialScroll(animated: animated, delay: 150_000_000)
            return
        }

        NSLog("📊 PostDetailView: Triggering scroll to selected post %@", viewModel.post.id)

        // Triple-trigger strategy via state changes to avoid direct proxy access
        scrollTargetID = selectedPostScrollID
        scrollTrigger += 1

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            scrollTrigger += 1

            try? await Task.sleep(nanoseconds: 150_000_000)
            scrollTrigger += 1

            // Finally reveal the view
            withAnimation(.easeIn(duration: 0.2)) {
                isInitialPositioned = true
            }
            hasScrolledToSelectedPost = true
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
                await MainActor.run {
                    if let hydratedPost = context.mainPost {
                        self.viewModel.updatePost(hydratedPost)
                    }
                    self.replyPosts = context.descendants
                    self.isLoadingReplies = false
                }
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
            scrollTargetID = topScrollID
            scrollTrigger += 1
            showParentIndicator = false
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

    @EnvironmentObject var serviceManager: SocialServiceManager
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
                    // Check if any attachment is a GIF - if so, use taller maxHeight
                    // Balance: Allow taller GIFs but still maintain reasonable bounds
                    let hasGIF = post.attachments.contains { $0.type == .animatedGIF }
                    // Use 75% of screen height for GIFs in detail view (more space than feed)
                    let mediaMaxHeight = hasGIF ? min(UIScreen.main.bounds.height * 0.75, 900) : 600
                    
                    UnifiedMediaGridView(
                        attachments: post.attachments,
                        maxHeight: mediaMaxHeight
                    )
                    .frame(maxWidth: .infinity)
                    // Apply clipShape but UnifiedMediaGridView/SmartMediaView handle aspect ratio properly
                    // This prevents overflow while allowing GIFs to display at their natural aspect ratio
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Poll section
                if let poll = post.poll {
                    PostPollView(
                        poll: poll,
                        onVote: { optionIndex in
                            Task {
                                do {
                                    try await serviceManager.voteInPoll(
                                        post: post, optionIndex: optionIndex)
                                } catch {
                                    print("❌ Failed to vote: \(error.localizedDescription)")
                                }
                            }
                        }
                    )
                    .padding(.vertical, 8)
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

    @EnvironmentObject var serviceManager: SocialServiceManager

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
                        maxHeight: 300
                    )
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                // Poll section
                if let poll = post.poll {
                    PostPollView(
                        poll: poll,
                        onVote: { optionIndex in
                            Task {
                                do {
                                    try await serviceManager.voteInPoll(
                                        post: post, optionIndex: optionIndex)
                                } catch {
                                    print("❌ Failed to vote: \(error.localizedDescription)")
                                }
                            }
                        }
                    )
                    .padding(.top, 4)
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

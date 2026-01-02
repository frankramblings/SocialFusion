import SwiftUI

/// A view that displays a post card with all its components
struct PostCardView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    let post: Post
    let replyCount: Int
    let repostCount: Int
    let likeCount: Int
    let isReplying: Bool
    let isReposted: Bool
    let isLiked: Bool
    let onAuthorTap: () -> Void
    let onReply: () -> Void
    let onRepost: () -> Void
    let onLike: () -> Void
    let onShare: () -> Void
    let onMediaTap: (Post.Attachment) -> Void
    let onOpenInBrowser: () -> Void
    let onCopyLink: () -> Void
    let onReport: () -> Void
    let onPostTap: () -> Void
    let onParentPostTap: (Post) -> Void
    @ObservedObject var postActionStore: PostActionStore
    let postActionCoordinator: PostActionCoordinator?

    // Optional boost information
    let boostedBy: String?

    // Optional PostViewModel for state updates
    let viewModel: PostViewModel?

    // State for expanding reply banner - properly keyed to prevent view reuse issues
    @State private var isReplyBannerExpanded = false
    @State private var bannerWasTapped = false
    @State private var showListSelection = false

    // Platform color helper
    private var platformColor: Color {
        switch post.platform {
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
        }
    }

    // Determine which post to display: use original for boosts, otherwise self.post
    private var displayPost: Post {
        // For boosts, always use the original post for display content
        // The wrapper post is just a container with empty content
        if let original = post.originalPost {
            // This is a boost/repost - use the original post for display
            return original
        }
        return post
    }

    // Get attachments to display - prioritize originalPost attachments for boosts
    private var displayAttachments: [Post.Attachment] {
        // For boosts, always use originalPost attachments if available
        if let original = post.originalPost {
            // Use originalPost attachments if they exist, otherwise check displayPost as fallback
            if !original.attachments.isEmpty {
                return original.attachments
            }
            // Fallback: check displayPost attachments (should be same as original, but just in case)
            if !displayPost.attachments.isEmpty {
                return displayPost.attachments
            }
            // Return empty array if no attachments found
            return []
        }
        // For regular posts, use displayPost attachments (which equals post for non-boosts)
        return displayPost.attachments
    }

    // Check if this is a boost (either from TimelineEntry or Post structure)
    private var isBoost: Bool {
        return (boostedBy ?? post.boostedBy) != nil || post.originalPost != nil
    }

    // Get the reply info - check displayPost (which is originalPost for boosts)
    private var replyInfo: (username: String, id: String?, platform: SocialPlatform)? {
        // Use displayPost which is the actual post being shown (originalPost for boosts, post for regular posts)
        // This ensures we get reply info from the correct post
        let displayUsername = displayPost.inReplyToUsername
        let displayReplyID = displayPost.inReplyToID

        if let username = displayUsername, !username.isEmpty {
            return (username, displayReplyID, displayPost.platform)
        }
        // Fallback: check wrapper post (in case the boost wrapper itself is a reply, though rare)
        if let username = post.inReplyToUsername, !username.isEmpty {
            return (username, post.inReplyToID, post.platform)
        }
        return nil
    }

    // Helper to log reply info (called from onAppear to avoid ViewBuilder issues)
    private func logReplyInfo() {
        let displayUsername = displayPost.inReplyToUsername
        let displayReplyID = displayPost.inReplyToID
        let logData: [String: Any] = [
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "E",
            "location": "PostCardView.swift:84",
            "message": "replyInfo check",
            "data": [
                "postId": post.id,
                "displayPostId": displayPost.id,
                "displayUsername": displayUsername ?? "nil",
                "displayReplyID": displayReplyID ?? "nil",
                "postUsername": post.inReplyToUsername ?? "nil",
                "postReplyID": post.inReplyToID ?? "nil",
                "hasOriginalPost": post.originalPost != nil,
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
        ]
        let logPath = "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log"
        if let jsonData = try? JSONSerialization.data(withJSONObject: logData),
            let jsonString = String(data: jsonData, encoding: .utf8)
        {
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write((jsonString + "\n").data(using: .utf8)!)
                try? fileHandle.close()
            } else {
                FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.write((jsonString + "\n").data(using: .utf8)!)
                    try? fileHandle.close()
                }
            }
        }
    }

    // Helper to log boost banner info
    private func logBoostBanner(
        boostHandle: String?, postBoostedBy: String?, finalBoostedBy: String?
    ) {
        let logData: [String: Any] = [
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "F",
            "location": "PostCardView.swift:197",
            "message": "boost banner check",
            "data": [
                "postId": post.id,
                "boostedBy": boostedBy ?? "nil",
                "postBoostedBy": postBoostedBy ?? "nil",
                "finalBoostedBy": finalBoostedBy ?? "nil",
                "boostHandle": boostHandle ?? "nil",
                "hasOriginalPost": post.originalPost != nil,
                "authorUsername": post.authorUsername,
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
        ]
        let logPath = "/Users/frankemanuele/Documents/GitHub/SocialFusion/.cursor/debug.log"
        if let jsonData = try? JSONSerialization.data(withJSONObject: logData),
            let jsonString = String(data: jsonData, encoding: .utf8)
        {
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write((jsonString + "\n").data(using: .utf8)!)
                try? fileHandle.close()
            } else {
                FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.write((jsonString + "\n").data(using: .utf8)!)
                    try? fileHandle.close()
                }
            }
        }
    }

    // Convenience initializer for TimelineEntry
    init(
        entry: TimelineEntry,
        viewModel: PostViewModel? = nil,
        postActionStore: PostActionStore,
        postActionCoordinator: PostActionCoordinator? = nil,
        onPostTap: @escaping () -> Void = {},
        onParentPostTap: @escaping (Post) -> Void = { _ in },
        onReply: @escaping () -> Void = {},
        onRepost: @escaping () -> Void = {},
        onLike: @escaping () -> Void = {},
        onShare: @escaping () -> Void = {}
    ) {
        self.post = entry.post
        self.replyCount = 0
        self.repostCount = entry.post.repostCount
        self.likeCount = entry.post.likeCount
        self.isReplying = false
        self.isReposted = entry.post.isReposted
        self.isLiked = entry.post.isLiked
        self.onAuthorTap = {}
        self.onReply = onReply
        self.onRepost = onRepost
        self.onLike = onLike
        self.onShare = onShare
        self.onMediaTap = { _ in }
        self.onOpenInBrowser = {}
        self.onCopyLink = {}
        self.onReport = {}
        self.onPostTap = onPostTap
        self.onParentPostTap = onParentPostTap
        self.viewModel = viewModel
        self.postActionStore = postActionStore
        self.postActionCoordinator = postActionCoordinator

        // Extract boost information from TimelineEntry
        if case .boost(let boostedBy) = entry.kind {
            self.boostedBy = boostedBy
        } else {
            self.boostedBy = nil
        }
    }

    // Original initializer for backward compatibility
    init(
        post: Post,
        replyCount: Int,
        repostCount: Int,
        likeCount: Int,
        isReplying: Bool,
        isReposted: Bool,
        isLiked: Bool,
        onAuthorTap: @escaping () -> Void,
        onReply: @escaping () -> Void,
        onRepost: @escaping () -> Void,
        onLike: @escaping () -> Void,
        onShare: @escaping () -> Void,
        onMediaTap: @escaping (Post.Attachment) -> Void,
        onOpenInBrowser: @escaping () -> Void,
        onCopyLink: @escaping () -> Void,
        onReport: @escaping () -> Void,
        onPostTap: @escaping () -> Void,
        onParentPostTap: @escaping (Post) -> Void = { _ in },
        viewModel: PostViewModel? = nil,
        postActionStore: PostActionStore,
        postActionCoordinator: PostActionCoordinator? = nil
    ) {
        self.post = post
        self.replyCount = replyCount
        self.repostCount = repostCount
        self.likeCount = likeCount
        self.isReplying = isReplying
        self.isReposted = isReposted
        self.isLiked = isLiked
        self.onAuthorTap = onAuthorTap
        self.onReply = onReply
        self.onRepost = onRepost
        self.onLike = onLike
        self.onShare = onShare
        self.onMediaTap = onMediaTap
        self.onOpenInBrowser = onOpenInBrowser
        self.onCopyLink = onCopyLink
        self.onReport = onReport
        self.onPostTap = onPostTap
        self.onParentPostTap = onParentPostTap
        self.viewModel = viewModel
        // Use post.boostedBy if available, otherwise nil
        self.boostedBy = post.boostedBy
        self.postActionStore = postActionStore
        self.postActionCoordinator = postActionCoordinator
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {  // Apple standard: 8pt spacing
            // Boost banner if this post was boosted/reposted
            // Show banner if boostedBy is set (regardless of originalPost existence)
            // Also check for originalPost to catch boosts that might not have boostedBy set
            let postBoostedBy = post.boostedBy
            let finalBoostedBy = boostedBy ?? postBoostedBy
            let boostHandle = finalBoostedBy?.trimmingCharacters(in: .whitespacesAndNewlines)

            // CRITICAL FIX: Show boost banner if we have originalPost OR if boostedBy is set
            // This ensures boosts are always shown with a banner
            if post.originalPost != nil || (boostHandle != nil && !boostHandle!.isEmpty) {
                let handleToShow = boostHandle ?? post.authorUsername
                if !handleToShow.isEmpty {
                    BoostBanner(handle: handleToShow, platform: post.platform)
                        .padding(.horizontal, 12)  // Apple standard: 12pt for content
                        .padding(.vertical, 6)  // Adequate touch target
                        .frame(maxWidth: .infinity, alignment: .leading)  // Ensure full width visibility
                        .onAppear {
                            logBoostBanner(
                                boostHandle: handleToShow, postBoostedBy: postBoostedBy,
                                finalBoostedBy: finalBoostedBy)
                        }
                }
            }

            // Expanding reply banner if this post is a reply
            // Check both wrapper post and original post for reply info
            if let replyInfo = replyInfo {
                ExpandingReplyBanner(
                    username: replyInfo.username,
                    network: replyInfo.platform,
                    parentId: replyInfo.id,
                    initialParent: nil,
                    isExpanded: $isReplyBannerExpanded,
                    onBannerTap: { bannerWasTapped = true },
                    onParentPostTap: { parentPost in
                        onParentPostTap(parentPost)  // Navigate to the parent post
                    }
                )
                .padding(.horizontal, 12)  // Match BoostBanner alignment structure
                .padding(.bottom, 6)  // Apple standard: 6pt related element spacing
                .frame(maxWidth: .infinity, alignment: .leading)  // Ensure full width visibility
                .id(displayPost.id + "_reply_banner")  // Key the banner to the specific post ID
                .onAppear {
                    print(
                        "[PostCardView] 🎯 Rendering ExpandingReplyBanner for post \(post.id) with username: \(replyInfo.username)"
                    )
                    logReplyInfo()
                }
            }

            // Author section
            PostAuthorView(
                post: displayPost,
                onAuthorTap: onAuthorTap
            )
            .padding(.horizontal, 12)  // Apple standard: 12pt content padding

            // Content section - show quote posts always, and show link previews for all posts
            // CRITICAL FIX: Always show contentView - it handles empty content internally
            // For boosts, displayPost is the originalPost which should have content
            displayPost.contentView(
                lineLimit: nil,
                showLinkPreview: true,  // Always show link previews
                font: .body,
                onQuotePostTap: { quotedPost in
                    onParentPostTap(quotedPost)  // Navigate to the quoted post
                },
                allowTruncation: false  // Timeline posts are not truncated
            )
            .padding(.horizontal, 8)  // Reduced from 12 to give more space for text
            .padding(.top, 4)

            // Poll section
            if let poll = displayPost.poll {
                PostPollView(
                    poll: poll,
                    onVote: { optionIndex in
                        Task {
                            do {
                                try await serviceManager.voteInPoll(
                                    post: displayPost, optionIndex: optionIndex)
                            } catch {
                                print("❌ Failed to vote: \(error.localizedDescription)")
                            }
                        }
                    }
                )
                .padding(.horizontal, 12)
            }

            // Media section - show attachments from the displayed post
            // Use displayAttachments which properly handles boosts vs regular posts
            // CRITICAL: Always check displayPost.attachments directly to ensure we show media even for reposts
            let attachmentsToShow =
                displayAttachments.isEmpty ? displayPost.attachments : displayAttachments
            if !attachmentsToShow.isEmpty {
                UnifiedMediaGridView(attachments: attachmentsToShow, maxHeight: 600)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    .clipped()
                    .onAppear {
                        print(
                            "[PostCardView] 📎 Displaying \(attachmentsToShow.count) attachments for post \(post.id)"
                        )
                        for (index, att) in attachmentsToShow.enumerated() {
                            print(
                                "[PostCardView]   Attachment \(index): type=\(att.type), url=\(att.url)"
                            )
                        }
                    }
            }

            actionBarView
                .padding(.horizontal, 12)  // Apple standard: 12pt content padding
                .padding(.top, 2)  // Reduced from 6 to close vertical gap
        }
        .padding(.horizontal, 12)  // Reduced from 16 to give more space for content
        .padding(.vertical, 12)  // Apple standard: 12pt container padding
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .onTapGesture {
            // Only handle tap if banner wasn't tapped
            if !bannerWasTapped {
                onPostTap()
            }
            bannerWasTapped = false
        }
        // MARK: - Accessibility Support
        .accessibilityElement(children: .contain)
        .accessibilityLabel(postAccessibilityLabel)
        .accessibilityHint("Double tap to view full post and replies")
        .accessibilityAction(named: "Reply") {
            onReply()
        }
        .accessibilityAction(named: "Repost") {
            onRepost()
        }
        .accessibilityAction(named: "Like") {
            onLike()
        }
        .accessibilityAction(named: "Share") {
            onShare()
        }
        .sheet(isPresented: $showListSelection) {
            if let account = serviceManager.mastodonAccounts.first {
                ListSelectionView(accountToLink: post.authorId, platformAccount: account)
                    .environmentObject(serviceManager)
            }
        }
    }

    // MARK: - Action Bar View

    @ViewBuilder
    private var actionBarView: some View {
        if FeatureFlagManager.isEnabled(.postActionsV2),
            let coordinator = postActionCoordinator
        {
            ActionBarV2(
                post: post,
                store: postActionStore,
                coordinator: coordinator,
                onAction: { action in
                    switch action {
                    case .reply:
                        onReply()
                    case .repost:
                        onRepost()
                    case .like:
                        onLike()
                    case .share:
                        onShare()
                    case .quote:
                        print("🔗 Quote action triggered for post: \(displayPost.id)")
                    case .follow:
                        if let viewModel = viewModel {
                            Task { await viewModel.followUser() }
                        }
                    case .mute:
                        if let viewModel = viewModel {
                            Task { await viewModel.muteUser() }
                        }
                    case .block:
                        if let viewModel = viewModel {
                            Task { await viewModel.blockUser() }
                        }
                    case .addToList:
                        showListSelection = true
                    @unknown default:
                        break
                    }
                },
                onReply: onReply,
                onShare: onShare,
                onOpenInBrowser: onOpenInBrowser,
                onCopyLink: onCopyLink,
                onReport: onReport
            )
        } else {
            ActionBar(
                post: displayPost,
                onAction: { action in
                    switch action {
                    case .reply:
                        onReply()
                    case .repost:
                        onRepost()
                    case .like:
                        onLike()
                    case .share:
                        onShare()
                    case .quote:
                        print("🔗 Quote action triggered for post: \(displayPost.id)")
                    case .follow:
                        if let viewModel = viewModel {
                            Task { await viewModel.followUser() }
                        }
                    case .mute:
                        if let viewModel = viewModel {
                            Task { await viewModel.muteUser() }
                        }
                    case .block:
                        if let viewModel = viewModel {
                            Task { await viewModel.blockUser() }
                        }
                    case .addToList:
                        showListSelection = true
                    @unknown default:
                        break
                    }
                },
                onOpenInBrowser: onOpenInBrowser,
                onCopyLink: onCopyLink,
                onReport: onReport
            )
        }
    }

    // MARK: - Accessibility Helpers

    /// Creates a comprehensive accessibility label for the post
    private var postAccessibilityLabel: String {
        var components: [String] = []

        // Boost information
        if let boostedBy = boostedBy {
            components.append("Reposted by \(boostedBy)")
        }

        // Author and timestamp
        components.append(
            "Post by \(displayPost.authorName), \(formatAccessibilityTimestamp(displayPost.createdAt))"
        )

        // Content
        let cleanContent = displayPost.content.replacingOccurrences(of: "\n", with: " ")
        if !cleanContent.isEmpty {
            components.append("Content: \(cleanContent)")
        }

        // Media count
        if !displayPost.attachments.isEmpty {
            let mediaCount = displayPost.attachments.count
            let mediaType = displayPost.attachments.first?.type == .image ? "image" : "media"
            components.append("\(mediaCount) \(mediaType)\(mediaCount > 1 ? "s" : "") attached")
        }

        // Interaction counts
        var interactions: [String] = []
        if replyCount > 0 {
            interactions.append("\(replyCount) repl\(replyCount == 1 ? "y" : "ies")")
        }
        if repostCount > 0 {
            interactions.append("\(repostCount) repost\(repostCount == 1 ? "" : "s")")
        }
        if likeCount > 0 {
            interactions.append("\(likeCount) like\(likeCount == 1 ? "" : "s")")
        }

        if !interactions.isEmpty {
            components.append(interactions.joined(separator: ", "))
        }

        // User's interaction state
        var userStates: [String] = []
        if isLiked {
            userStates.append("liked by you")
        }
        if isReposted {
            userStates.append("reposted by you")
        }
        if isReplying {
            userStates.append("reply in progress")
        }

        if !userStates.isEmpty {
            components.append(userStates.joined(separator: ", "))
        }

        return components.joined(separator: ". ")
    }

    /// Formats timestamp for accessibility
    private func formatAccessibilityTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Preview
struct PostCardView_Previews: PreviewProvider {
    static var previews: some View {
        let store = PostActionStore()

        VStack(spacing: 16) {
            // Simple test - basic post using TimelineEntry
            PostCardView(
                entry: TimelineEntry(
                    id: "1",
                    kind: .normal,
                    post: Post.samplePosts[0],
                    createdAt: Date()
                ),
                viewModel: nil,
                postActionStore: store,
                onPostTap: {}
            )
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .previewLayout(.sizeThatFits)
    }
}

struct ListSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var serviceManager: SocialServiceManager
    let accountToLink: String
    let platformAccount: SocialAccount

    @State private var lists: [MastodonList] = []
    @State private var isLoading = true
    @State private var error: String? = nil

    var body: some View {
        NavigationView {
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if let error = error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                } else if lists.isEmpty {
                    Text("No lists found")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(lists) { list in
                        Button(action: { addToList(list) }) {
                            HStack {
                                Text(list.title)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                fetchLists()
            }
        }
    }

    private func fetchLists() {
        isLoading = true
        Task {
            do {
                let fetchedLists = try await serviceManager.fetchMastodonLists(
                    account: platformAccount)
                await MainActor.run {
                    self.lists = fetchedLists
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func addToList(_ list: MastodonList) {
        isLoading = true
        Task {
            do {
                try await serviceManager.addAccountToMastodonList(
                    listId: list.id,
                    accountToLink: accountToLink,
                    account: platformAccount
                )
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

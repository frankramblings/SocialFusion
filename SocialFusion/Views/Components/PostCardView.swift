import SwiftUI

/// A view that displays a post card with all its components
struct PostCardView: View {
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
        // For boosts, use the original post for display content
        if boostedBy != nil, let original = post.originalPost {
            return original
        }
        return post
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
        self.boostedBy = nil
        self.postActionStore = postActionStore
        self.postActionCoordinator = postActionCoordinator
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {  // Apple standard: 8pt spacing
            // Boost banner if this post was boosted/reposted
            if let boostedBy = boostedBy {
                BoostBanner(handle: boostedBy, platform: post.platform)
                    .padding(.horizontal, 12)  // Apple standard: 12pt for content
                    .padding(.vertical, 6)  // Adequate touch target
            }

            // Expanding reply banner if this post is a reply
            if let inReplyToUsername = displayPost.inReplyToUsername {
                ExpandingReplyBanner(
                    username: inReplyToUsername,
                    network: displayPost.platform,
                    parentId: displayPost.inReplyToID,
                    initialParent: nil,
                    isExpanded: $isReplyBannerExpanded,
                    onBannerTap: { bannerWasTapped = true },
                    onParentPostTap: { parentPost in
                        onParentPostTap(parentPost)  // Navigate to the parent post
                    }
                )
                .padding(.horizontal, 12)  // Match BoostBanner alignment structure
                .padding(.bottom, 6)  // Apple standard: 6pt related element spacing
                .id(displayPost.id + "_reply_banner")  // Key the banner to the specific post ID
            }

            // Author section
            PostAuthorView(
                post: displayPost,
                onAuthorTap: onAuthorTap
            )
            .padding(.horizontal, 12)  // Apple standard: 12pt content padding

            // Content section - show quote posts always, and show link previews for all posts
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

            // Media section
            if !displayPost.attachments.isEmpty {
                UnifiedMediaGridView(attachments: displayPost.attachments)
                    .padding(.horizontal, 4)
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

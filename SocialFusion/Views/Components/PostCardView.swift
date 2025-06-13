import SwiftUI

// State manager for post expansion to avoid view reuse issues
@MainActor
class PostExpansionState: ObservableObject {
    @Published var isExpanded = false
}

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

    // Optional boost information
    let boostedBy: String?

    // Optional PostViewModel for state updates
    let viewModel: PostViewModel?

    // State for expanding reply banner - keyed to post ID to prevent view reuse issues
    @StateObject private var expansionState = PostExpansionState()
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
        onPostTap: @escaping () -> Void = {},
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
        self.viewModel = viewModel

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
        viewModel: PostViewModel? = nil
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
        self.viewModel = viewModel
        self.boostedBy = nil
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
                    isExpanded: $expansionState.isExpanded,
                    onBannerTap: { bannerWasTapped = true }
                )
                .padding(.horizontal, 12)  // Apple standard: 12pt for content - match boost banner alignment
                .padding(.bottom, 6)  // Apple standard: 6pt related element spacing
            }

            // Author section
            PostAuthorView(
                post: displayPost,
                onAuthorTap: onAuthorTap
            )
            .padding(.horizontal, 12)  // Apple standard: 12pt content padding

            // Content section - disable link previews when media is present (Ivory style)
            displayPost.contentView(
                lineLimit: nil,
                showLinkPreview: displayPost.attachments.isEmpty,
                font: .body
            )
            .padding(.horizontal, 12)
            .padding(.top, 4)

            // Media section
            if !displayPost.attachments.isEmpty {
                UnifiedMediaGridView(attachments: displayPost.attachments)
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
            }

            // Action bar (using the working ActionBar)
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
                    }
                },
                onOpenInBrowser: onOpenInBrowser,
                onCopyLink: onCopyLink,
                onReport: onReport
            )
            .padding(.horizontal, 12)  // Apple standard: 12pt content padding
            .padding(.top, 6)  // Apple standard: 6pt separation from content
        }
        .padding(.horizontal, 16)  // Apple standard: 16pt container padding
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
    }
}

// MARK: - Preview
struct PostCardView_Previews: PreviewProvider {
    static var previews: some View {
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
                onPostTap: {}
            )
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .previewLayout(.sizeThatFits)
    }
}

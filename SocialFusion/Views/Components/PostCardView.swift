import SwiftUI

/// Modifier that conditionally applies clipping
private struct ConditionalClippedModifier: ViewModifier {
    let shouldClip: Bool

    func body(content: Content) -> some View {
        if shouldClip {
            content.clipped()
        } else {
            content
        }
    }
}

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
    let onQuote: () -> Void
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
        // CRITICAL FIX: For boosts, always use the original post for display content
        // The wrapper post is just a container with empty content
        // Always use originalPost if it exists, even if content appears empty
        // The contentView() method handles empty content display internally
        // This ensures boosts show the original post content, not blank placeholders

        // Check if this is a boost (via originalPost or boostedBy)
        let isBoost = post.originalPost != nil || (boostedBy ?? post.boostedBy) != nil

        if isBoost {
            // This is a boost/repost - use the original post for display
            if let original = post.originalPost {
                // Always return originalPost - don't fall back to wrapper post
                // The wrapper post has empty content by design
                return original
            } else {
                // CRITICAL: If boost has no originalPost, this is an error state
                // Log warning but still return post to prevent crash
                // This shouldn't happen, but handle gracefully
                print("⚠️ [PostCardView] Boost detected but originalPost is nil for post \(post.id)")
                // Return post as fallback - contentView will handle empty content
                return post
            }
        }

        // For regular posts
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
        // CRITICAL FIX: For boosts, prioritize originalPost reply info since that's what's being displayed
        // For regular posts, check the post itself
        // This ensures reply banners show correctly for both regular replies and boosted replies

        // Debug logging
        print("🔍 [PostCardView] replyInfo check for post \(post.id):")
        print("  - post.inReplyToUsername: \(post.inReplyToUsername ?? "nil")")
        print("  - post.inReplyToID: \(post.inReplyToID ?? "nil")")
        print("  - has originalPost: \(post.originalPost != nil)")

        // If this is a boost, check the original post first (since that's what we're displaying)
        if let original = post.originalPost {
            print("  - original.inReplyToUsername: \(original.inReplyToUsername ?? "nil")")
            print("  - original.inReplyToID: \(original.inReplyToID ?? "nil")")
            if let username = original.inReplyToUsername, !username.isEmpty {
                print("🔍 [PostCardView] Reply info found in originalPost: \(username)")
                return (username, original.inReplyToID, original.platform)
            }
        }

        // Then check if the wrapper post itself is a reply (for non-boosted replies)
        if let username = post.inReplyToUsername, !username.isEmpty {
            print("🔍 [PostCardView] Reply info found in wrapper post: \(username)")
            return (username, post.inReplyToID, post.platform)
        }

        // Fallback: check displayPost (should be same as above, but just in case)
        let displayUsername = displayPost.inReplyToUsername
        let displayReplyID = displayPost.inReplyToID
        print("  - displayPost.inReplyToUsername: \(displayUsername ?? "nil")")
        print("  - displayPost.inReplyToID: \(displayReplyID ?? "nil")")
        if let username = displayUsername, !username.isEmpty {
            print("🔍 [PostCardView] Reply info found in displayPost: \(username)")
            return (username, displayReplyID, displayPost.platform)
        }

        print("🔍 [PostCardView] No reply info found for post \(post.id)")
        return nil
    }
    
    // Debug helper to log boost/reply state
    private func logBannerState() {
        let hasOriginalPost = post.originalPost != nil
        let hasBoostedBy = (boostedBy ?? post.boostedBy) != nil
        let hasReplyInfo = replyInfo != nil
        print("🔍 [PostCardView] Banner state for post \(post.id):")
        print("  - hasOriginalPost: \(hasOriginalPost)")
        print("  - hasBoostedBy: \(hasBoostedBy) (boostedBy param: \(boostedBy ?? "nil"), post.boostedBy: \(post.boostedBy ?? "nil"))")
        print("  - hasReplyInfo: \(hasReplyInfo)")
        if hasOriginalPost {
            print("  - originalPost.id: \(post.originalPost?.id ?? "nil")")
            print("  - originalPost.content.isEmpty: \(post.originalPost?.content.isEmpty ?? true)")
        }
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
        onShare: @escaping () -> Void = {},
        onQuote: @escaping () -> Void = {}
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
        self.onQuote = onQuote
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
        // CRITICAL: Always preserve boostedBy from both TimelineEntry and post
        // This ensures boost banners show even if one source is missing
        if case .boost(let entryBoostedBy) = entry.kind {
            // Use TimelineEntry boostedBy first, but fall back to post.boostedBy if entry is empty
            self.boostedBy = entryBoostedBy.isEmpty ? entry.post.boostedBy : entryBoostedBy
        } else {
            // Not a boost in TimelineEntry, but check if post has originalPost (might be a boost)
            // This handles cases where TimelineEntry kind wasn't set correctly
            if entry.post.originalPost != nil {
                self.boostedBy = entry.post.boostedBy ?? entry.post.authorUsername
            } else {
                self.boostedBy = entry.post.boostedBy
            }
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
        onQuote: @escaping () -> Void = {},
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
        self.onQuote = onQuote
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

    // Helper to get boost handle for banner
    private var boostHandleToShow: String? {
        let hasOriginalPost = post.originalPost != nil
        let postBoostedBy = post.boostedBy
        let finalBoostedBy = boostedBy ?? postBoostedBy
        let boostHandle = finalBoostedBy?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasBoostHandle = boostHandle != nil && !boostHandle!.isEmpty

        // Debug logging
        print("🔍 [PostCardView] boostHandleToShow check for post \(post.id):")
        print("  - hasOriginalPost: \(hasOriginalPost)")
        print("  - postBoostedBy: \(postBoostedBy ?? "nil")")
        print("  - boostedBy param: \(boostedBy ?? "nil")")
        print("  - finalBoostedBy: \(finalBoostedBy ?? "nil")")
        print("  - boostHandle: \(boostHandle ?? "nil")")
        print("  - hasBoostHandle: \(hasBoostHandle)")

        // CRITICAL: If there's an originalPost, this is definitely a boost - always show banner
        // Also show banner if boostedBy is set (even without originalPost, though that shouldn't happen)
        if !hasOriginalPost && !hasBoostHandle {
            print("  - Returning nil: no originalPost and no boostHandle")
            return nil
        }

        // If we have originalPost, we MUST return a handle (even if boostedBy is missing)
        // Priority: use the boostedBy parameter, then post.boostedBy, then authorUsername
        if let handle = boostHandle, !handle.isEmpty {
            print("  - Returning boostHandle: \(handle)")
            return handle
        } else if let handle = postBoostedBy, !handle.isEmpty {
            print("  - Returning postBoostedBy: \(handle)")
            return handle
        } else if hasOriginalPost {
            // For boosts with originalPost, always show the booster's username even if boostedBy isn't set
            // This ensures boost banners always appear for posts with originalPost
            // Use authorUsername as fallback - it should always be set for valid posts
            if !post.authorUsername.isEmpty {
                print("ℹ️ [PostCardView] Using post.authorUsername as boost handle fallback: \(post.authorUsername)")
                return post.authorUsername
            }
            // Last resort: try to extract from post ID if it follows the repost-{handle}-{uri} pattern
            if post.id.hasPrefix("repost-") {
                let components = post.id.split(separator: "-", maxSplits: 2)
                if components.count >= 2 {
                    let extractedHandle = String(components[1])
                    print("ℹ️ [PostCardView] Extracted boost handle from post ID: \(extractedHandle)")
                    return extractedHandle
                }
            }
            // If we have originalPost but no handle, use originalPost author as fallback
            if let original = post.originalPost, !original.authorUsername.isEmpty {
                print("ℹ️ [PostCardView] Using originalPost.authorUsername as boost handle fallback: \(original.authorUsername)")
                return original.authorUsername
            }
            // Final fallback: if we have originalPost, show something
            print("⚠️ [PostCardView] Boost detected (has originalPost) but no handle available for post \(post.id)")
            return "Someone"  // Last resort fallback
        }
        return nil
    }

    // Computed property for boost banner to simplify body
    @ViewBuilder
    private var boostBannerView: some View {
        if let handleToShow = boostHandleToShow, !handleToShow.isEmpty {
            BoostBanner(handle: handleToShow, platform: post.platform)
                .padding(.horizontal, 12)  // Apple standard: 12pt for content
                .padding(.vertical, 6)  // Adequate touch target
                .frame(maxWidth: .infinity, alignment: .leading)  // Ensure full width visibility
                .onAppear {
                    let postBoostedBy = post.boostedBy
                    let finalBoostedBy = boostedBy ?? postBoostedBy
                    print("🔍 [PostCardView] Rendering boost banner for post \(post.id) with handle: \(handleToShow)")
                    logBoostBanner(
                        boostHandle: handleToShow, postBoostedBy: postBoostedBy,
                        finalBoostedBy: finalBoostedBy)
                }
        } else {
            EmptyView()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {  // Apple standard: 8pt spacing
            // Boost banner if this post was boosted/reposted
            // CRITICAL FIX: Explicitly check and render boost banner to ensure it always shows
            if let handleToShow = boostHandleToShow, !handleToShow.isEmpty {
                BoostBanner(handle: handleToShow, platform: post.platform)
                    .padding(.horizontal, 12)  // Apple standard: 12pt for content
                    .padding(.vertical, 6)  // Adequate touch target
                    .frame(maxWidth: .infinity, alignment: .leading)  // Ensure full width visibility
                    .onAppear {
                        let postBoostedBy = post.boostedBy
                        let finalBoostedBy = boostedBy ?? postBoostedBy
                        print("🔍 [PostCardView] Rendering boost banner for post \(post.id) with handle: \(handleToShow)")
                        logBoostBanner(
                            boostHandle: handleToShow, postBoostedBy: postBoostedBy,
                            finalBoostedBy: finalBoostedBy)
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
            .onAppear {
                // Debug logging for boost content
                let isBoost = post.originalPost != nil || (boostedBy ?? post.boostedBy) != nil
                if isBoost {
                    let hasOriginalPost = post.originalPost != nil
                    let displayContentEmpty = displayPost.content.isEmpty
                    let displayHasAttachments = !displayPost.attachments.isEmpty
                    let displayHasQuotedPost = displayPost.quotedPost != nil
                    
                    print("🔍 [PostCardView] Boost content state for post \(post.id):")
                    print("  - hasOriginalPost: \(hasOriginalPost)")
                    print("  - displayPost.id: \(displayPost.id)")
                    print("  - displayPost.content.isEmpty: \(displayContentEmpty)")
                    print("  - displayPost.attachments.count: \(displayPost.attachments.count)")
                    print("  - displayPost.quotedPost: \(displayHasQuotedPost ? "exists" : "nil")")
                    print("  - post.boostedBy: \(post.boostedBy ?? "nil")")
                    print("  - boostedBy param: \(boostedBy ?? "nil")")
                    
                    if displayContentEmpty && !displayHasAttachments && !displayHasQuotedPost {
                        print("⚠️ [PostCardView] Boost post \(post.id) appears blank - no content, attachments, or quoted post")
                    }
                }
            }

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
                // Check if any attachment is a GIF - if so, use taller maxHeight
                // Balance: Allow taller GIFs but still maintain reasonable bounds
                let hasGIF = attachmentsToShow.contains { $0.type == .animatedGIF }
                // Use 70% of screen height for GIFs (balanced between full display and feed usability)
                let mediaMaxHeight = hasGIF ? min(UIScreen.main.bounds.height * 0.7, 800) : 600

                UnifiedMediaGridView(attachments: attachmentsToShow, maxHeight: mediaMaxHeight)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    // Apply clipping but UnifiedMediaGridView/SmartMediaView handle aspect ratio properly
                    // This prevents overflow while allowing GIFs to display at their natural aspect ratio
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
                        onQuote()
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
                        onQuote()
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

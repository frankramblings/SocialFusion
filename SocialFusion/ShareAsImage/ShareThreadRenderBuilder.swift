import Foundation

/// Context mode for share image generation
public enum ContextMode: String, CaseIterable {
    case justThis = "Just this"
    case withContext = "With context"
    case withReplies = "With replies"
}

/// Configuration for share image generation (preview-driven model)
public struct ShareImageConfig {
    public let includeEarlier: Bool  // Include ancestors/parents above selected
    public let includeLater: Bool  // Include replies below selected
    public let hideUsernames: Bool
    public let showWatermark: Bool

    /// Checks if two post IDs match, handling different ID formats across platforms
    /// (e.g., Bluesky AT Protocol URIs vs simple IDs, Mastodon numeric IDs)
    public static func idsMatch(_ id1: String?, _ id2: String?, platformSpecificId: String? = nil)
        -> Bool
    {
        guard let id1 = id1, let id2 = id2 else { return false }

        // Direct match
        if id1 == id2 { return true }

        // Check against platform-specific ID
        if let platformId = platformSpecificId {
            if id1 == platformId || id2 == platformId { return true }
        }

        // Bluesky: Compare rkeys (last component of AT Protocol URIs)
        // AT URIs look like: at://did:plc:xxx/app.bsky.feed.post/rkey
        // Also handle cases where one might be a full URI and the other just an rkey
        let id1IsBluesky = id1.contains("at://") || id1.contains("app.bsky.feed.post")
        let id2IsBluesky = id2.contains("at://") || id2.contains("app.bsky.feed.post")

        if id1IsBluesky || id2IsBluesky {
            // Extract rkeys from both IDs
            let rkey1: String = {
                if id1.contains("/") {
                    return id1.split(separator: "/").last.map(String.init) ?? id1
                }
                return id1
            }()
            let rkey2: String = {
                if id2.contains("/") {
                    return id2.split(separator: "/").last.map(String.init) ?? id2
                }
                return id2
            }()

            // Compare rkeys if both are non-empty
            if !rkey1.isEmpty && !rkey2.isEmpty && rkey1 == rkey2 {
                return true
            }

            // Also try comparing full URIs if both are Bluesky URIs
            if id1IsBluesky && id2IsBluesky && id1 == id2 {
                return true
            }
        }

        return false
    }

    /// Checks if a reply's inReplyToID matches a given post
    public static func isReplyTo(_ reply: Post, post: Post) -> Bool {
        guard let replyToID = reply.inReplyToID else { return false }
        return idsMatch(replyToID, post.id, platformSpecificId: post.platformSpecificId)
    }

    // Internal computed properties
    internal var includePostDetails: Bool {
        // Always include post details
        return true
    }

    internal var includeReplies: Bool {
        return includeLater
    }

    internal var includeAncestors: Bool {
        return includeEarlier
    }

    // Heuristic-based values (computed from toggles)
    internal func maxParentComments(selectedPost: Post) -> Int {
        guard includeEarlier else { return 0 }
        // Default: 2 ancestors, but can be 3 for very short replies
        let contentLength = selectedPost.content.count
        return contentLength < 20 ? 3 : 2
    }

    internal var maxRepliesTotal: Int {
        return includeLater ? 6 : 0  // Cap at 6 replies when enabled
    }

    internal var maxReplyDepth: Int {
        return includeLater ? 1 : 0  // Direct replies only by default, depth 2 if sparse
    }

    internal var maxRepliesPerNode: Int {
        return 3  // Never more than 3 replies per parent
    }

    internal var sortOrder: ThreadSlicer.SliceConfig.SortOrder {
        return .top  // Prefer engagement
    }

    public init(
        includeEarlier: Bool = false,
        includeLater: Bool = false,
        hideUsernames: Bool = false,
        showWatermark: Bool = true
    ) {
        self.includeEarlier = includeEarlier
        self.includeLater = includeLater
        self.hideUsernames = hideUsernames
        self.showWatermark = showWatermark
    }
}

/// Builds a ShareImageDocument from a post and its thread context
public struct ShareThreadRenderBuilder {

    // MARK: - Internal Constants

    private static let defaultContextAncestors = 2
    private static let defaultReplies = 6
    private static let maxRepliesPerParent = 3
    private static let maxReplyDepthDefault = 1
    private static let maxReplyDepthSparse = 2

    // MARK: - Public API

    /// Builds a complete share image document from a post (no specific comment selected)
    static func buildDocument(
        from post: Post,
        threadContext: ThreadContext?,
        config: ShareImageConfig,
        userMapping: inout [String: String]
    ) -> ShareImageDocument {
        var mapping = userMapping
        let displayPost = post.originalPost ?? post

        // Convert main post
        let postRenderable = UnifiedAdapter.convertPost(
            post,
            hideUsernames: config.hideUsernames,
            userMapping: &mapping
        )

        // Determine what to include based on toggles
        let ancestorChain: [CommentRenderable] = []
        var replySubtree: [CommentRenderable] = []

        // For "include later" toggle, include top-level replies
        if config.includeLater, let context = threadContext {
            let allReplies = context.descendants
            // Use the main post from context if available, otherwise use the passed post
            // This ensures we match against the correct post ID that descendants reference
            let targetPost = context.mainPost ?? post

            // Filter for top-level replies (replies directly to this post)
            // Use robust ID matching to handle different ID formats across platforms
            let topLevelReplies = allReplies.filter { reply in
                // If inReplyToID is set, use normal matching
                if let replyToID = reply.inReplyToID {
                    return ShareImageConfig.isReplyTo(reply, post: targetPost)
                } else {
                    // If inReplyToID is nil, check if this reply is replying to another reply in the list
                    // If it's replying to another reply (not the main post), it's nested and should be excluded
                    let isReplyingToAnotherReply = allReplies.contains { otherReply in
                        guard let replyToID = reply.inReplyToID,
                            otherReply.id != reply.id
                        else { return false }
                        return ShareImageConfig.idsMatch(
                            replyToID, otherReply.id,
                            platformSpecificId: otherReply.platformSpecificId)
                    }

                    // If inReplyToID is nil and it's not replying to another reply, treat it as top-level
                    // This handles cases where Bluesky thread API doesn't set inReplyToID correctly
                    return !isReplyingToAnotherReply
                }
            }

            // Apply heuristic: direct replies only, cap at 6, prefer engagement
            // Don't pass parentID here - we've already filtered to top-level replies
            // selectReplies will just sort and take the top N
            let selectedReplies = selectReplies(
                from: topLevelReplies,
                allReplies: allReplies,
                parentID: nil,  // Already filtered, just need to sort and limit
                maxTotal: config.maxRepliesTotal,
                maxDepth: config.maxReplyDepth,
                maxPerNode: config.maxRepliesPerNode,
                sortOrder: config.sortOrder
            )

            // Convert to renderables
            replySubtree = selectedReplies.map { replyPost in
                // Get parent author (the post author for top-level replies)
                let (parentName, _) = UnifiedAdapter.anonymizeUser(
                    displayName: displayPost.authorName,
                    handle: displayPost.authorUsername,
                    id: displayPost.authorId,
                    hideUsernames: config.hideUsernames,
                    userMapping: &mapping
                )

                return UnifiedAdapter.convertComment(
                    replyPost,
                    depth: 0,
                    isSelected: false,
                    hideUsernames: config.hideUsernames,
                    userMapping: &mapping,
                    parentAuthorDisplayName: parentName
                )
            }
        }

        userMapping = mapping

        NSLog(
            "[ShareAsImage] Final document - replySubtree count: \(replySubtree.count), includeReplies: \(config.includeReplies)"
        )

        return ShareImageDocument(
            selectedPost: postRenderable,
            selectedCommentID: nil,
            ancestorChain: ancestorChain,
            replySubtree: replySubtree,
            includePostDetails: config.includePostDetails,
            hideUsernames: config.hideUsernames,
            showWatermark: config.showWatermark,
            includeReplies: config.includeReplies
        )
    }

    /// Builds a complete share image document from a selected comment in a thread
    static func buildDocument(
        from selectedPost: Post,
        threadContext: ThreadContext,
        config: ShareImageConfig,
        userMapping: inout [String: String]
    ) -> ShareImageDocument {
        var mapping = userMapping
        let allPosts =
            threadContext.ancestors + [threadContext.mainPost].compactMap { $0 }
            + threadContext.descendants

        // Build ancestor chain ONLY if includeEarlier is true
        let ancestorChain: [CommentRenderable]
        let rootPost: Post

        if config.includeEarlier {
            // Determine ancestor depth based on heuristics
            let ancestorDepth = config.maxParentComments(selectedPost: selectedPost)

            // Build ancestor chain
            let ancestorPosts = ThreadSlicer.buildAncestorChain(
                from: selectedPost,
                in: allPosts,
                maxDepth: ancestorDepth
            )

            // Find the root post (the one with no inReplyToID)
            rootPost =
                ancestorPosts.first { $0.inReplyToID == nil } ?? ancestorPosts.first ?? selectedPost

            // Remove both selected post AND root post from ancestors
            // Root post should only appear as the post header, not as a comment
            let ancestorsWithoutRootAndSelected = ancestorPosts.filter {
                !ShareImageConfig.idsMatch(
                    $0.id, selectedPost.id, platformSpecificId: selectedPost.platformSpecificId)
                    && !ShareImageConfig.idsMatch(
                        $0.id, rootPost.id, platformSpecificId: rootPost.platformSpecificId)
            }

            // Convert ancestors to renderables (these are only intermediate replies, not the root)
            ancestorChain = ancestorsWithoutRootAndSelected.enumerated().map {
                index, ancestorPost in
                // Get parent author for "Replying to..." label
                let parentAuthor: String? = {
                    if index > 0 {
                        let parentPost = ancestorsWithoutRootAndSelected[index - 1]
                        let (parentName, _) = UnifiedAdapter.anonymizeUser(
                            displayName: parentPost.authorName,
                            handle: parentPost.authorUsername,
                            id: parentPost.authorId,
                            hideUsernames: config.hideUsernames,
                            userMapping: &mapping
                        )
                        return parentName
                    } else if index == 0 {
                        // First ancestor replies to root post
                        let (rootName, _) = UnifiedAdapter.anonymizeUser(
                            displayName: rootPost.authorName,
                            handle: rootPost.authorUsername,
                            id: rootPost.authorId,
                            hideUsernames: config.hideUsernames,
                            userMapping: &mapping
                        )
                        return rootName
                    }
                    return nil
                }()

                return UnifiedAdapter.convertComment(
                    ancestorPost,
                    depth: index,
                    isSelected: false,
                    hideUsernames: config.hideUsernames,
                    userMapping: &mapping,
                    parentAuthorDisplayName: parentAuthor
                )
            }
        } else {
            // When includeEarlier is false, ancestor chain is empty
            // Find root post for post header (but don't include in chain)
            rootPost = allPosts.first { $0.inReplyToID == nil } ?? selectedPost
            ancestorChain = []
        }

        // Debug assertion: ensure selected post is not in ancestor chain
        assert(
            !ancestorChain.contains(where: {
                ShareImageConfig.idsMatch(
                    $0.id, selectedPost.id, platformSpecificId: selectedPost.platformSpecificId)
            }),
            "Selected post must not appear in ancestor chain")

        // Build reply subtree if needed
        var replySubtree: [CommentRenderable] = []

        if config.includeReplies {
            // Get all potential replies
            let allReplies = threadContext.descendants

            // Apply heuristic-based selection
            let selectedReplies = selectReplies(
                from: allReplies,
                allReplies: allReplies,
                parentID: selectedPost.id,
                maxTotal: config.maxRepliesTotal,
                maxDepth: config.maxReplyDepth,
                maxPerNode: config.maxRepliesPerNode,
                sortOrder: config.sortOrder
            )

            // Convert selected post to renderable
            // When includeEarlier is false, selected depth is always 0
            let selectedDepth = config.includeEarlier ? ancestorChain.count : 0
            // Get parent author for selected comment
            let selectedParentAuthor: String? = {
                if config.includeEarlier && selectedDepth > 0, let lastAncestor = ancestorChain.last
                {
                    return lastAncestor.authorDisplayName
                } else if config.includeEarlier && selectedDepth == 0 {
                    // Selected is direct reply to root (when earlier is enabled but no ancestors)
                    let (rootName, _) = UnifiedAdapter.anonymizeUser(
                        displayName: rootPost.authorName,
                        handle: rootPost.authorUsername,
                        id: rootPost.authorId,
                        hideUsernames: config.hideUsernames,
                        userMapping: &mapping
                    )
                    return rootName
                }
                // When includeEarlier is false, no parent author label
                return nil
            }()

            let selectedComment = UnifiedAdapter.convertComment(
                selectedPost,
                depth: selectedDepth,
                isSelected: true,
                hideUsernames: config.hideUsernames,
                userMapping: &mapping,
                parentAuthorDisplayName: selectedParentAuthor
            )

            replySubtree.append(selectedComment)

            // Build depth map for replies
            var depthMap: [String: Int] = [:]
            depthMap[selectedPost.id] = selectedDepth

            func assignDepths(_ posts: [Post], parentID: String, baseDepth: Int) {
                let children = posts.filter { reply in
                    guard let replyToID = reply.inReplyToID else { return false }
                    return ShareImageConfig.idsMatch(replyToID, parentID)
                }
                for child in children {
                    let childDepth = baseDepth + 1
                    depthMap[child.id] = childDepth
                    assignDepths(posts, parentID: child.id, baseDepth: childDepth)
                }
            }

            assignDepths(selectedReplies, parentID: selectedPost.id, baseDepth: selectedDepth)

            // Convert replies to renderables
            let replyRenderables = selectedReplies.map { replyPost in
                let depth = depthMap[replyPost.id] ?? (selectedDepth + 1)
                // Get parent author (could be selected comment or another reply)
                let parentAuthor: String? = {
                    if let parentID = replyPost.inReplyToID {
                        if ShareImageConfig.idsMatch(
                            parentID, selectedPost.id,
                            platformSpecificId: selectedPost.platformSpecificId)
                        {
                            // Replying to selected comment
                            return selectedComment.authorDisplayName
                        } else {
                            // Replying to another reply - find it
                            if let parentReply = selectedReplies.first(where: {
                                ShareImageConfig.idsMatch($0.id, parentID)
                            }) {
                                let (parentName, _) = UnifiedAdapter.anonymizeUser(
                                    displayName: parentReply.authorName,
                                    handle: parentReply.authorUsername,
                                    id: parentReply.authorId,
                                    hideUsernames: config.hideUsernames,
                                    userMapping: &mapping
                                )
                                return parentName
                            }
                        }
                    }
                    return nil
                }()

                return UnifiedAdapter.convertComment(
                    replyPost,
                    depth: depth,
                    isSelected: false,
                    hideUsernames: config.hideUsernames,
                    userMapping: &mapping,
                    parentAuthorDisplayName: parentAuthor
                )
            }

            replySubtree.append(contentsOf: replyRenderables)
        } else {
            // Just the selected comment (when includeReplies is false)
            // When includeEarlier is false, selected depth is always 0
            let selectedDepth = config.includeEarlier ? ancestorChain.count : 0
            // Get parent author for selected comment
            let selectedParentAuthor: String? = {
                if config.includeEarlier && selectedDepth > 0, let lastAncestor = ancestorChain.last
                {
                    return lastAncestor.authorDisplayName
                } else if config.includeEarlier && selectedDepth == 0 {
                    // Selected is direct reply to root (when earlier is enabled but no ancestors)
                    let (rootName, _) = UnifiedAdapter.anonymizeUser(
                        displayName: rootPost.authorName,
                        handle: rootPost.authorUsername,
                        id: rootPost.authorId,
                        hideUsernames: config.hideUsernames,
                        userMapping: &mapping
                    )
                    return rootName
                }
                // When includeEarlier is false, no parent author label
                return nil
            }()

            let selectedComment = UnifiedAdapter.convertComment(
                selectedPost,
                depth: selectedDepth,
                isSelected: true,
                hideUsernames: config.hideUsernames,
                userMapping: &mapping,
                parentAuthorDisplayName: selectedParentAuthor
            )
            replySubtree.append(selectedComment)
        }

        // Use the root post for the post renderable (already identified above)
        let postRenderable = UnifiedAdapter.convertPost(
            rootPost,
            hideUsernames: config.hideUsernames,
            userMapping: &mapping
        )

        userMapping = mapping

        return ShareImageDocument(
            selectedPost: postRenderable,
            selectedCommentID: selectedPost.id,
            ancestorChain: ancestorChain,
            replySubtree: replySubtree,
            includePostDetails: config.includePostDetails,
            hideUsernames: config.hideUsernames,
            showWatermark: config.showWatermark,
            includeReplies: config.includeReplies
        )
    }

    // MARK: - Heuristic-Based Reply Selection

    /// Selects replies using heuristics: prefer engagement, freshness bias, author's own replies
    private static func selectReplies(
        from candidates: [Post],
        allReplies: [Post],
        parentID: String? = nil,
        maxTotal: Int,
        maxDepth: Int,
        maxPerNode: Int,
        sortOrder: ThreadSlicer.SliceConfig.SortOrder
    ) -> [Post] {
        // Filter to direct replies if parentID provided
        let directReplies =
            parentID != nil
            ? candidates.filter { reply in
                guard let replyToID = reply.inReplyToID else { return false }
                return ShareImageConfig.idsMatch(replyToID, parentID!)
            }
            : candidates

        // If we have fewer than 3 direct replies, allow depth 2
        let effectiveMaxDepth = directReplies.count < 3 ? maxReplyDepthSparse : maxDepth

        // Build graph and prune
        let sliceConfig = ThreadSlicer.SliceConfig(
            maxParentComments: 0,
            maxRepliesTotal: maxTotal,
            maxReplyDepth: effectiveMaxDepth,
            maxRepliesPerNode: maxPerNode,
            sortOrder: sortOrder
        )

        // If we have a parent, use pruneReplySubtree
        if let parentID = parentID,
            let parent = candidates.first(where: { ShareImageConfig.idsMatch($0.id, parentID) })
                ?? allReplies.first(where: { ShareImageConfig.idsMatch($0.id, parentID) })
        {
            return ThreadSlicer.pruneReplySubtree(
                from: parent,
                in: allReplies,
                config: sliceConfig
            )
        }

        // Otherwise, sort and take top N
        let sorted = sortReplies(directReplies, by: sortOrder)
        return Array(sorted.prefix(maxTotal))
    }

    /// Sorts replies with engagement and freshness bias
    private static func sortReplies(
        _ replies: [Post],
        by order: ThreadSlicer.SliceConfig.SortOrder
    ) -> [Post] {
        switch order {
        case .top:
            // Prefer engagement, but add freshness bias
            return replies.sorted { lhs, rhs in
                let lhsScore = (lhs.likeCount + lhs.repostCount) * 2
                let rhsScore = (rhs.likeCount + rhs.repostCount) * 2

                // Freshness bias: newer posts get +1 to score
                let lhsFresh = lhs.createdAt > Date().addingTimeInterval(-3600) ? 1 : 0
                let rhsFresh = rhs.createdAt > Date().addingTimeInterval(-3600) ? 1 : 0

                let lhsTotal = lhsScore + lhsFresh
                let rhsTotal = rhsScore + rhsFresh

                if lhsTotal != rhsTotal {
                    return lhsTotal > rhsTotal
                }

                // Always prefer author's own replies
                // (This would need author comparison - simplified for now)

                return lhs.createdAt > rhs.createdAt
            }
        case .newest:
            return replies.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return replies.sorted { $0.createdAt < $1.createdAt }
        }
    }
}

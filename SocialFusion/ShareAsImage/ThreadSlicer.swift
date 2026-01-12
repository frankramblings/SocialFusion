import Foundation

/// Builds and prunes thread graphs for share image rendering
public struct ThreadSlicer {

    // MARK: - Configuration

    public struct SliceConfig {
        public let maxParentComments: Int  // 0...12
        public let maxRepliesTotal: Int  // 0...30
        public let maxReplyDepth: Int  // 1...5
        public let maxRepliesPerNode: Int  // 1...6
        public let sortOrder: SortOrder

        public enum SortOrder {
            case top  // By score (likes/reposts), then timestamp
            case newest  // Most recent first
            case oldest  // Oldest first
        }

        public init(
            maxParentComments: Int = 12,
            maxRepliesTotal: Int = 30,
            maxReplyDepth: Int = 5,
            maxRepliesPerNode: Int = 6,
            sortOrder: SortOrder = .top
        ) {
            self.maxParentComments = maxParentComments
            self.maxRepliesTotal = maxRepliesTotal
            self.maxReplyDepth = maxReplyDepth
            self.maxRepliesPerNode = maxRepliesPerNode
            self.sortOrder = sortOrder
        }
    }

    // MARK: - Thread Graph

    /// Represents a comment node in the thread graph
    public struct CommentNode: Identifiable {
        public let id: String
        public let post: Post
        public let parentID: String?
        public var children: [CommentNode] = []

        public init(id: String, post: Post, parentID: String?) {
            self.id = id
            self.post = post
            self.parentID = parentID
        }
    }

    // MARK: - Public API

    /// Builds ancestor chain from selected post up to root
    public static func buildAncestorChain(
        from selectedPost: Post,
        in allPosts: [Post],
        maxDepth: Int
    ) -> [Post] {
        var chain: [Post] = []
        var current: Post? = selectedPost
        var depth = 0

        while let post = current, depth < maxDepth {
            chain.insert(post, at: 0)  // Prepend to maintain chronological order

            // Find parent using robust ID matching
            if let parentID = post.inReplyToID {
                current = allPosts.first { candidate in
                    ShareImageConfig.idsMatch(
                        candidate.id, parentID, platformSpecificId: candidate.platformSpecificId)
                        || ShareImageConfig.idsMatch(candidate.platformSpecificId, parentID)
                }
            } else {
                current = nil
            }
            depth += 1
        }

        return chain
    }

    /// Builds a thread graph from a flat list of posts
    public static func buildThreadGraph(from posts: [Post]) -> [CommentNode] {
        // Create nodes
        var nodes: [String: CommentNode] = [:]
        var rootNodes: [CommentNode] = []

        for post in posts {
            let node = CommentNode(
                id: post.id,
                post: post,
                parentID: post.inReplyToID
            )
            nodes[post.id] = node
        }

        // Build parent-child relationships
        for (nodeKey, node) in nodes {
            if let parentID = node.parentID {
                // Find parent using robust ID matching
                var foundParent: (key: String, node: CommentNode)? = nil
                for (key, candidate) in nodes {
                    if ShareImageConfig.idsMatch(
                        candidate.id, parentID,
                        platformSpecificId: candidate.post.platformSpecificId)
                        || ShareImageConfig.idsMatch(candidate.post.platformSpecificId, parentID)
                    {
                        foundParent = (key, candidate)
                        break
                    }
                }

                if let (parentKey, parent) = foundParent {
                    var updatedParent = parent
                    updatedParent.children.append(node)
                    nodes[parentKey] = updatedParent
                } else {
                    // Parent not in list, treat as root
                    rootNodes.append(node)
                }
            } else {
                // No parent, this is a root
                rootNodes.append(node)
            }
        }

        return rootNodes
    }

    /// Prunes a reply subtree under the selected comment
    public static func pruneReplySubtree(
        from selectedPost: Post,
        in allPosts: [Post],
        config: SliceConfig
    ) -> [Post] {
        // Build graph
        let graph = buildThreadGraph(from: allPosts)

        // Find selected node using robust ID matching
        guard
            let selectedNode = findNode(
                id: selectedPost.id, platformSpecificId: selectedPost.platformSpecificId, in: graph)
        else {
            return []
        }

        // Prune subtree
        var pruned: [Post] = []
        var totalCount = 0

        func traverse(_ node: CommentNode, depth: Int) {
            guard totalCount < config.maxRepliesTotal else { return }
            guard depth <= config.maxReplyDepth else { return }

            // Add this node (if not the selected one, as it's already in ancestor chain)
            if node.id != selectedPost.id {
                pruned.append(node.post)
                totalCount += 1
            }

            // Sort children
            let sortedChildren = sortComments(node.children.map { $0.post }, by: config.sortOrder)

            // Take up to maxRepliesPerNode
            let childrenToInclude = Array(sortedChildren.prefix(config.maxRepliesPerNode))

            // Recursively traverse children
            for childPost in childrenToInclude {
                if let childNode = findNode(
                    id: childPost.id, platformSpecificId: childPost.platformSpecificId, in: graph)
                {
                    traverse(childNode, depth: depth + 1)
                }
            }
        }

        // Start traversal from selected node's children
        for child in selectedNode.children {
            if allPosts.contains(where: { candidate in
                ShareImageConfig.idsMatch(
                    candidate.id, child.id, platformSpecificId: candidate.platformSpecificId)
                    || ShareImageConfig.idsMatch(candidate.platformSpecificId, child.id)
            }) {
                if let childNode = findNode(
                    id: child.id, platformSpecificId: child.post.platformSpecificId, in: graph)
                {
                    traverse(childNode, depth: 1)
                }
            }
        }

        return pruned
    }

    // MARK: - Helper Methods

    private static func findNode(
        id: String, platformSpecificId: String? = nil, in nodes: [CommentNode]
    ) -> CommentNode? {
        for node in nodes {
            if ShareImageConfig.idsMatch(
                node.id, id, platformSpecificId: node.post.platformSpecificId)
                || (platformSpecificId != nil
                    && ShareImageConfig.idsMatch(node.post.platformSpecificId, platformSpecificId!))
            {
                return node
            }
            if let found = findNode(
                id: id, platformSpecificId: platformSpecificId, in: node.children)
            {
                return found
            }
        }
        return nil
    }

    private static func sortComments(_ comments: [Post], by order: SliceConfig.SortOrder) -> [Post]
    {
        switch order {
        case .top:
            return comments.sorted { lhs, rhs in
                let lhsScore = (lhs.likeCount + lhs.repostCount)
                let rhsScore = (rhs.likeCount + rhs.repostCount)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                return lhs.createdAt > rhs.createdAt
            }
        case .newest:
            return comments.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return comments.sorted { $0.createdAt < $1.createdAt }
        }
    }
}

import XCTest
@testable import SocialFusion

/// Tests for ThreadSlicer - the core thread graph building and pruning logic
final class ThreadSlicerTests: XCTestCase {

    // MARK: - Ancestor Chain Tests

    func testBuildAncestorChainReturnsChronologicalOrder() {
        // Given: A linear chain of posts
        let (posts, selected, _) = ShareAsImageTestHelpers.makeLinearChain(length: 5)

        // When: Building ancestor chain from selected post
        let chain = ThreadSlicer.buildAncestorChain(from: selected, in: posts, maxDepth: 10)

        // Then: Chain should be in chronological order (oldest first)
        assertChronologicalOrder(chain)

        // And: Should include selected and all ancestors
        XCTAssertEqual(chain.count, 5)
        XCTAssertEqual(chain.first?.id, "post-0") // Root
        XCTAssertEqual(chain.last?.id, "post-4")  // Selected
    }

    func testBuildAncestorChainRespectsMaxDepth() {
        // Given: A long chain
        let (posts, selected, _) = ShareAsImageTestHelpers.makeLinearChain(length: 10)

        // When: Building with limited depth
        let chain = ThreadSlicer.buildAncestorChain(from: selected, in: posts, maxDepth: 3)

        // Then: Should only include maxDepth posts
        XCTAssertEqual(chain.count, 3)
        // Should be the 3 most recent (including selected)
        XCTAssertEqual(chain.last?.id, selected.id)
    }

    func testBuildAncestorChainHandlesMissingParent() {
        // Given: A post with a parent that doesn't exist in the list
        let orphan = ShareAsImageTestHelpers.makePost(
            id: "orphan",
            inReplyToID: "nonexistent-parent"
        )

        // When: Building ancestor chain
        let chain = ThreadSlicer.buildAncestorChain(from: orphan, in: [orphan], maxDepth: 10)

        // Then: Should only return the orphan post
        XCTAssertEqual(chain.count, 1)
        XCTAssertEqual(chain.first?.id, "orphan")
    }

    func testBuildAncestorChainHandlesRootPost() {
        // Given: A root post with no parent
        let root = ShareAsImageTestHelpers.makePost(id: "root", inReplyToID: nil)

        // When: Building ancestor chain
        let chain = ThreadSlicer.buildAncestorChain(from: root, in: [root], maxDepth: 10)

        // Then: Should only return the root
        XCTAssertEqual(chain.count, 1)
        XCTAssertEqual(chain.first?.id, "root")
    }

    // MARK: - Thread Graph Building Tests

    func testBuildThreadGraphCreatesCorrectStructure() {
        // Given: A branching thread
        let (posts, _, _, _) = ShareAsImageTestHelpers.makeBranchingThread(replyCount: 3)

        // When: Building graph
        let roots = ThreadSlicer.buildThreadGraph(from: posts)

        // Then: Should have one root node
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots.first?.id, "root")
    }

    func testBuildThreadGraphOrphansAreRoots() {
        // Given: Posts with missing parents become roots
        let orphan1 = ShareAsImageTestHelpers.makePost(id: "orphan1", inReplyToID: "missing1")
        let orphan2 = ShareAsImageTestHelpers.makePost(id: "orphan2", inReplyToID: "missing2")
        let root = ShareAsImageTestHelpers.makePost(id: "root", inReplyToID: nil)

        // When: Building graph
        let roots = ThreadSlicer.buildThreadGraph(from: [orphan1, orphan2, root])

        // Then: All three should be roots
        XCTAssertEqual(roots.count, 3)
    }

    // MARK: - Reply Pruning Tests

    func testPruneReplySubtreeRespectsMaxRepliesTotal() {
        // Given: A thread with many replies
        let (posts, selected, _, _) = ShareAsImageTestHelpers.makeBranchingThread(replyCount: 20)

        // When: Pruning with a limit
        let config = ThreadSlicer.SliceConfig(
            maxParentComments: 0,
            maxRepliesTotal: 5,
            maxReplyDepth: 3,
            maxRepliesPerNode: 10,
            sortOrder: .top
        )
        let pruned = ThreadSlicer.pruneReplySubtree(from: selected, in: posts, config: config)

        // Then: Should not exceed maxRepliesTotal
        XCTAssertLessThanOrEqual(pruned.count, 5)
    }

    func testPruneReplySubtreeRespectsMaxRepliesPerNode() {
        // Given: A thread with many direct replies
        let (posts, selected, _, _) = ShareAsImageTestHelpers.makeBranchingThread(replyCount: 10)

        // When: Pruning with per-node limit
        let config = ThreadSlicer.SliceConfig(
            maxParentComments: 0,
            maxRepliesTotal: 100, // High total
            maxReplyDepth: 1,
            maxRepliesPerNode: 3, // But only 3 per node
            sortOrder: .top
        )
        let pruned = ThreadSlicer.pruneReplySubtree(from: selected, in: posts, config: config)

        // Then: Should not exceed maxRepliesPerNode for direct replies
        XCTAssertLessThanOrEqual(pruned.count, 3)
    }

    func testPruneReplySubtreeRespectsMaxReplyDepth() {
        // Given: A deep thread
        let (posts, selected, _) = ShareAsImageTestHelpers.makeDeepThread(depth: 3, repliesPerLevel: 2)

        // When: Pruning with depth limit of 1
        let config = ThreadSlicer.SliceConfig(
            maxParentComments: 0,
            maxRepliesTotal: 100,
            maxReplyDepth: 1,
            maxRepliesPerNode: 10,
            sortOrder: .top
        )
        let pruned = ThreadSlicer.pruneReplySubtree(from: selected, in: posts, config: config)

        // Then: Should only include direct replies (depth 1)
        for reply in pruned {
            XCTAssertEqual(reply.inReplyToID, selected.id, "Reply \(reply.id) should be direct reply to selected")
        }
    }

    func testPruneReplySubtreeSortsByEngagement() {
        // Given: Replies with different engagement
        let (posts, selected, _, replies) = ShareAsImageTestHelpers.makeBranchingThread(replyCount: 5)

        // When: Pruning with top sort
        let config = ThreadSlicer.SliceConfig(
            maxParentComments: 0,
            maxRepliesTotal: 3,
            maxReplyDepth: 1,
            maxRepliesPerNode: 3,
            sortOrder: .top
        )
        let pruned = ThreadSlicer.pruneReplySubtree(from: selected, in: posts, config: config)

        // Then: Higher engagement replies should come first
        if pruned.count >= 2 {
            let firstScore = pruned[0].likeCount + pruned[0].repostCount
            let secondScore = pruned[1].likeCount + pruned[1].repostCount
            XCTAssertGreaterThanOrEqual(firstScore, secondScore, "Replies should be sorted by engagement")
        }
    }

    func testPruneReplySubtreeSortsByNewest() {
        // Given: Replies at different times
        let (posts, selected, _, _) = ShareAsImageTestHelpers.makeBranchingThread(replyCount: 5)

        // When: Pruning with newest sort
        let config = ThreadSlicer.SliceConfig(
            maxParentComments: 0,
            maxRepliesTotal: 3,
            maxReplyDepth: 1,
            maxRepliesPerNode: 3,
            sortOrder: .newest
        )
        let pruned = ThreadSlicer.pruneReplySubtree(from: selected, in: posts, config: config)

        // Then: Newer replies should come first
        if pruned.count >= 2 {
            XCTAssertGreaterThanOrEqual(pruned[0].createdAt, pruned[1].createdAt, "Replies should be sorted by newest first")
        }
    }

    func testPruneReplySubtreeSortsByOldest() {
        // Given: Replies at different times
        let (posts, selected, _, _) = ShareAsImageTestHelpers.makeBranchingThread(replyCount: 5)

        // When: Pruning with oldest sort
        let config = ThreadSlicer.SliceConfig(
            maxParentComments: 0,
            maxRepliesTotal: 3,
            maxReplyDepth: 1,
            maxRepliesPerNode: 3,
            sortOrder: .oldest
        )
        let pruned = ThreadSlicer.pruneReplySubtree(from: selected, in: posts, config: config)

        // Then: Older replies should come first
        if pruned.count >= 2 {
            XCTAssertLessThanOrEqual(pruned[0].createdAt, pruned[1].createdAt, "Replies should be sorted by oldest first")
        }
    }

    func testPruneReplySubtreeExcludesSelectedPost() {
        // Given: A thread
        let (posts, selected, _, _) = ShareAsImageTestHelpers.makeBranchingThread(replyCount: 3)

        // When: Pruning
        let config = ThreadSlicer.SliceConfig(
            maxParentComments: 0,
            maxRepliesTotal: 10,
            maxReplyDepth: 3,
            maxRepliesPerNode: 10,
            sortOrder: .top
        )
        let pruned = ThreadSlicer.pruneReplySubtree(from: selected, in: posts, config: config)

        // Then: Selected should not be in pruned replies
        XCTAssertFalse(pruned.contains { $0.id == selected.id }, "Pruned replies should not include selected post")
    }

    func testPruneReplySubtreeHandlesNoReplies() {
        // Given: A post with no replies
        let selected = ShareAsImageTestHelpers.makePost(id: "lonely")

        // When: Pruning
        let config = ThreadSlicer.SliceConfig(
            maxParentComments: 0,
            maxRepliesTotal: 10,
            maxReplyDepth: 3,
            maxRepliesPerNode: 10,
            sortOrder: .top
        )
        let pruned = ThreadSlicer.pruneReplySubtree(from: selected, in: [selected], config: config)

        // Then: Should return empty
        XCTAssertTrue(pruned.isEmpty)
    }

    // MARK: - Determinism Tests

    func testPruneReplySubtreeIsDeterministic() {
        // Given: A complex thread
        let (posts, selected, _, _) = ShareAsImageTestHelpers.makeBranchingThread(replyCount: 10)

        let config = ThreadSlicer.SliceConfig(
            maxParentComments: 0,
            maxRepliesTotal: 5,
            maxReplyDepth: 2,
            maxRepliesPerNode: 3,
            sortOrder: .top
        )

        // When: Pruning multiple times
        let result1 = ThreadSlicer.pruneReplySubtree(from: selected, in: posts, config: config)
        let result2 = ThreadSlicer.pruneReplySubtree(from: selected, in: posts, config: config)

        // Then: Results should be identical
        XCTAssertEqual(result1.map { $0.id }, result2.map { $0.id }, "Pruning should be deterministic")
    }

    func testBuildAncestorChainIsDeterministic() {
        // Given: A linear chain
        let (posts, selected, _) = ShareAsImageTestHelpers.makeLinearChain(length: 5)

        // When: Building chain multiple times
        let chain1 = ThreadSlicer.buildAncestorChain(from: selected, in: posts, maxDepth: 10)
        let chain2 = ThreadSlicer.buildAncestorChain(from: selected, in: posts, maxDepth: 10)

        // Then: Results should be identical
        XCTAssertEqual(chain1.map { $0.id }, chain2.map { $0.id }, "Ancestor chain should be deterministic")
    }
}

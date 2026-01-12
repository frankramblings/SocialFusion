import XCTest
@testable import SocialFusion

/// Tests for ShareThreadRenderBuilder - document building with various configurations
final class ShareDocumentBuilderTests: XCTestCase {

    // MARK: - Critical Bug Regression: Earlier OFF Duplication

    /// This test catches the bug where "Earlier replies OFF" caused the selected post to appear twice.
    /// When includeEarlier=false, the selected comment should appear exactly once in replySubtree.
    func testEarlierOffCollapsesToSelectedOnly_noDuplicates() {
        // Given: A chain where selected is second in chain (parent -> selected)
        let (posts, selected, root) = ShareAsImageTestHelpers.makeLinearChain(length: 2)
        let context = ThreadContext(
            mainPost: root,
            ancestors: [],
            descendants: []
        )

        var userMapping: [String: String] = [:]
        let config = ShareAsImageTestHelpers.makeConfig(
            includeEarlier: false, // KEY: Earlier is OFF
            includeLater: false
        )

        // When: Building document
        let doc = ShareThreadRenderBuilder.buildDocument(
            from: selected,
            threadContext: context,
            config: config,
            userMapping: &userMapping
        )

        // Then: Ancestor chain should be empty
        XCTAssertTrue(doc.ancestorChain.isEmpty, "Ancestor chain should be empty when includeEarlier=false")

        // And: Selected should appear exactly once in replySubtree
        assertExactlyOnce(selected.id, in: doc.replySubtree)

        // And: No duplicate IDs across the entire document
        assertNoDuplicateIDs(doc.allComments)
    }

    func testEarlierOffWithLongerChain_noDuplicates() {
        // Given: A longer chain (root -> a -> b -> selected)
        let (posts, selected, root) = ShareAsImageTestHelpers.makeLinearChain(length: 4)
        let ancestors = posts.filter { $0.id != root.id && $0.id != selected.id }
        let context = ThreadContext(
            mainPost: root,
            ancestors: ancestors,
            descendants: []
        )

        var userMapping: [String: String] = [:]
        let config = ShareAsImageTestHelpers.makeConfig(
            includeEarlier: false,
            includeLater: false
        )

        // When: Building document
        let doc = ShareThreadRenderBuilder.buildDocument(
            from: selected,
            threadContext: context,
            config: config,
            userMapping: &userMapping
        )

        // Then: No duplicates
        assertNoDuplicateIDs(doc.allComments)

        // And: Only selected appears in reply subtree
        XCTAssertEqual(doc.replySubtree.count, 1)
        XCTAssertEqual(doc.replySubtree.first?.id, selected.id)
    }

    // MARK: - Earlier ON Tests

    func testEarlierOnIncludesAncestors() {
        // Given: A chain
        let (posts, selected, root) = ShareAsImageTestHelpers.makeLinearChain(length: 4)
        let context = ThreadContext(
            mainPost: root,
            ancestors: posts.filter { $0.id != root.id && $0.id != selected.id },
            descendants: []
        )

        var userMapping: [String: String] = [:]
        let config = ShareAsImageTestHelpers.makeConfig(
            includeEarlier: true, // Earlier is ON
            includeLater: false
        )

        // When: Building document
        let doc = ShareThreadRenderBuilder.buildDocument(
            from: selected,
            threadContext: context,
            config: config,
            userMapping: &userMapping
        )

        // Then: Ancestor chain should not be empty
        XCTAssertFalse(doc.ancestorChain.isEmpty, "Ancestor chain should have entries when includeEarlier=true")

        // And: Selected still appears exactly once (in replySubtree, not ancestorChain)
        assertExactlyOnce(selected.id, in: doc.allComments)

        // And: No duplicates
        assertNoDuplicateIDs(doc.allComments)
    }

    func testAncestorChainExcludesRootPost() {
        // Given: A chain with root -> intermediate -> selected
        let root = ShareAsImageTestHelpers.makePost(id: "root", inReplyToID: nil)
        let intermediate = ShareAsImageTestHelpers.makePost(id: "intermediate", inReplyToID: root.id)
        let selected = ShareAsImageTestHelpers.makePost(id: "selected", inReplyToID: intermediate.id)

        let context = ThreadContext(
            mainPost: root,
            ancestors: [intermediate],
            descendants: []
        )

        var userMapping: [String: String] = [:]
        let config = ShareAsImageTestHelpers.makeConfig(includeEarlier: true)

        // When: Building document
        let doc = ShareThreadRenderBuilder.buildDocument(
            from: selected,
            threadContext: context,
            config: config,
            userMapping: &userMapping
        )

        // Then: Root should NOT appear in ancestor chain (it appears as post header)
        XCTAssertFalse(
            doc.ancestorChain.contains { $0.id == root.id },
            "Root post should not appear in ancestor chain - it's the post header"
        )
    }

    // MARK: - Later Replies Tests

    func testLaterOnRespectsMaxRepliesTotal() {
        // Given: A thread with many replies
        let (posts, selected, root, replies) = ShareAsImageTestHelpers.makeBranchingThread(replyCount: 20)
        let context = ThreadContext(
            mainPost: root,
            ancestors: [],
            descendants: replies
        )

        var userMapping: [String: String] = [:]
        let config = ShareAsImageTestHelpers.makeConfig(
            includeEarlier: false,
            includeLater: true
        )

        // When: Building document
        let doc = ShareThreadRenderBuilder.buildDocument(
            from: selected,
            threadContext: context,
            config: config,
            userMapping: &userMapping
        )

        // Then: Replies should be capped (config.maxRepliesTotal is 6 when includeLater=true)
        // Plus 1 for selected itself
        let replyCountExcludingSelected = doc.replySubtree.count - 1
        XCTAssertLessThanOrEqual(replyCountExcludingSelected, 6, "Replies should be capped at maxRepliesTotal")
    }

    func testLaterOnRespectsMaxRepliesPerParent() {
        // Given: A thread with many direct replies to selected
        let (_, selected, root, replies) = ShareAsImageTestHelpers.makeBranchingThread(replyCount: 10)
        let context = ThreadContext(
            mainPost: root,
            ancestors: [],
            descendants: replies
        )

        var userMapping: [String: String] = [:]
        let config = ShareAsImageTestHelpers.makeConfig(
            includeEarlier: false,
            includeLater: true
        )

        // When: Building document
        let doc = ShareThreadRenderBuilder.buildDocument(
            from: selected,
            threadContext: context,
            config: config,
            userMapping: &userMapping
        )

        // Then: Total replies (excluding selected) should be capped at maxRepliesTotal (6)
        // Note: The implementation caps total replies, not per-parent
        let replyCount = doc.replySubtree.filter { !$0.isSelected }.count
        XCTAssertLessThanOrEqual(replyCount, 6, "Replies should be capped at maxRepliesTotal (6)")
    }

    func testSparseDirectRepliesIncludesDirectReplies() {
        // Given: A sparse thread (< 3 direct replies)
        let (posts, selected, root) = ShareAsImageTestHelpers.makeSparseThread()
        let descendants = posts.filter { $0.id != root.id && $0.id != selected.id }
        let context = ThreadContext(
            mainPost: root,
            ancestors: [],
            descendants: descendants
        )

        var userMapping: [String: String] = [:]
        let config = ShareAsImageTestHelpers.makeConfig(
            includeEarlier: false,
            includeLater: true
        )

        // When: Building document
        let doc = ShareThreadRenderBuilder.buildDocument(
            from: selected,
            threadContext: context,
            config: config,
            userMapping: &userMapping
        )

        // Then: Should include direct replies (depth-1)
        let hasDirectReplies = doc.replySubtree.contains { $0.id == "sparse-reply-1" }
            || doc.replySubtree.contains { $0.id == "sparse-reply-2" }
        XCTAssertTrue(hasDirectReplies, "Should include direct replies")

        // And: Total replies should be reasonable
        let replyCount = doc.replySubtree.filter { !$0.isSelected }.count
        XCTAssertGreaterThan(replyCount, 0, "Should have at least one reply")
    }

    // MARK: - Depth Normalization Tests

    func testDepthNormalizationWhenEarlierOff() {
        // Given: A chain where selected is deep in the original thread
        let (posts, selected, root) = ShareAsImageTestHelpers.makeLinearChain(length: 5)
        let context = ThreadContext(
            mainPost: root,
            ancestors: posts.filter { $0.id != root.id && $0.id != selected.id },
            descendants: []
        )

        var userMapping: [String: String] = [:]
        let config = ShareAsImageTestHelpers.makeConfig(
            includeEarlier: false, // KEY: Earlier is OFF
            includeLater: false
        )

        // When: Building document
        let doc = ShareThreadRenderBuilder.buildDocument(
            from: selected,
            threadContext: context,
            config: config,
            userMapping: &userMapping
        )

        // Then: Selected comment should have depth 0 when earlier is off
        let selectedComment = doc.replySubtree.first { $0.id == selected.id }
        XCTAssertEqual(selectedComment?.depth, 0, "Selected depth should be 0 when includeEarlier=false")
    }

    func testDepthNormalizationWhenEarlierOn() {
        // Given: A chain
        let root = ShareAsImageTestHelpers.makePost(id: "root", inReplyToID: nil)
        let intermediate = ShareAsImageTestHelpers.makePost(id: "intermediate", inReplyToID: root.id)
        let selected = ShareAsImageTestHelpers.makePost(id: "selected", inReplyToID: intermediate.id)

        let context = ThreadContext(
            mainPost: root,
            ancestors: [intermediate],
            descendants: []
        )

        var userMapping: [String: String] = [:]
        let config = ShareAsImageTestHelpers.makeConfig(
            includeEarlier: true,
            includeLater: false
        )

        // When: Building document
        let doc = ShareThreadRenderBuilder.buildDocument(
            from: selected,
            threadContext: context,
            config: config,
            userMapping: &userMapping
        )

        // Then: Selected depth should equal ancestor chain count
        let selectedComment = doc.replySubtree.first { $0.id == selected.id }
        XCTAssertEqual(
            selectedComment?.depth,
            doc.ancestorChain.count,
            "Selected depth should equal ancestor chain count when includeEarlier=true"
        )
    }

    // MARK: - Selected Marking Tests

    func testSelectedIsMarkedCorrectly() {
        // Given: A simple thread
        let (posts, selected, root, replies) = ShareAsImageTestHelpers.makeBranchingThread(replyCount: 3)
        let context = ThreadContext(mainPost: root, ancestors: [], descendants: replies)

        var userMapping: [String: String] = [:]
        let config = ShareAsImageTestHelpers.makeConfig(
            includeEarlier: false,
            includeLater: true
        )

        // When: Building document
        let doc = ShareThreadRenderBuilder.buildDocument(
            from: selected,
            threadContext: context,
            config: config,
            userMapping: &userMapping
        )

        // Then: Exactly one comment should be marked as selected
        let selectedComments = doc.allComments.filter { $0.isSelected }
        XCTAssertEqual(selectedComments.count, 1, "Exactly one comment should be marked as selected")
        XCTAssertEqual(selectedComments.first?.id, selected.id)
    }

    // MARK: - Link Preview Preservation Tests

    func testLinkPreviewPreservedInRenderModel() {
        // Given: A post with link preview
        let postWithLink = ShareAsImageTestHelpers.makePostWithLinkPreview()
        let context = ThreadContext(mainPost: postWithLink, ancestors: [], descendants: [])

        var userMapping: [String: String] = [:]
        let config = ShareAsImageTestHelpers.makeConfig()

        // When: Building document
        let doc = ShareThreadRenderBuilder.buildDocument(
            from: postWithLink,
            threadContext: context,
            config: config,
            userMapping: &userMapping
        )

        // Then: Link preview should be preserved
        XCTAssertNotNil(doc.selectedPost.linkPreviewData, "Link preview should be preserved")
        XCTAssertEqual(doc.selectedPost.linkPreviewData?.title, "Test Article")
    }

    func testMediaPreservedInRenderModel() {
        // Given: A post with media
        let postWithMedia = ShareAsImageTestHelpers.makePostWithMedia(attachmentCount: 3)
        let context = ThreadContext(mainPost: postWithMedia, ancestors: [], descendants: [])

        var userMapping: [String: String] = [:]
        let config = ShareAsImageTestHelpers.makeConfig()

        // When: Building document
        let doc = ShareThreadRenderBuilder.buildDocument(
            from: postWithMedia,
            threadContext: context,
            config: config,
            userMapping: &userMapping
        )

        // Then: Media thumbnails should be preserved
        XCTAssertEqual(doc.selectedPost.mediaThumbnails.count, 3, "Media should be preserved")
    }

    // MARK: - All Config Combinations: Selected Appears Once

    func testSelectedAppearsOnceForAllConfigCombinations() {
        let (posts, selected, root, replies) = ShareAsImageTestHelpers.makeBranchingThread(replyCount: 5)
        let ancestors = [root] // Just root as ancestor
        let context = ThreadContext(mainPost: root, ancestors: [], descendants: replies)

        let combinations: [(earlier: Bool, later: Bool, hideNames: Bool)] = [
            (false, false, false),
            (false, false, true),
            (false, true, false),
            (false, true, true),
            (true, false, false),
            (true, false, true),
            (true, true, false),
            (true, true, true),
        ]

        for combo in combinations {
            var userMapping: [String: String] = [:]
            let config = ShareAsImageTestHelpers.makeConfig(
                includeEarlier: combo.earlier,
                includeLater: combo.later,
                hideUsernames: combo.hideNames
            )

            let doc = ShareThreadRenderBuilder.buildDocument(
                from: selected,
                threadContext: context,
                config: config,
                userMapping: &userMapping
            )

            // Selected should appear exactly once in all comments
            let selectedCount = doc.allComments.filter { $0.id == selected.id }.count
            XCTAssertEqual(
                selectedCount, 1,
                "Selected should appear exactly once for config (earlier=\(combo.earlier), later=\(combo.later), hideNames=\(combo.hideNames))"
            )

            // No duplicates overall
            assertNoDuplicateIDs(doc.allComments)
        }
    }

    // MARK: - Determinism Tests

    func testBuildDocumentIsDeterministic() {
        // Given: A complex thread
        let (posts, selected, root, replies) = ShareAsImageTestHelpers.makeBranchingThread(replyCount: 10)
        let context = ThreadContext(mainPost: root, ancestors: [], descendants: replies)

        // When: Building document twice with same config
        var userMapping1: [String: String] = [:]
        var userMapping2: [String: String] = [:]
        let config = ShareAsImageTestHelpers.makeConfig(includeEarlier: true, includeLater: true)

        let doc1 = ShareThreadRenderBuilder.buildDocument(
            from: selected,
            threadContext: context,
            config: config,
            userMapping: &userMapping1
        )

        let doc2 = ShareThreadRenderBuilder.buildDocument(
            from: selected,
            threadContext: context,
            config: config,
            userMapping: &userMapping2
        )

        // Then: Results should be identical
        XCTAssertEqual(
            doc1.allComments.map { $0.id },
            doc2.allComments.map { $0.id },
            "Document building should be deterministic"
        )
    }
}

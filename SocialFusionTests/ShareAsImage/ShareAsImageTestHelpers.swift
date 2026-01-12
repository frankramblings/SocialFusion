import XCTest
@testable import SocialFusion

/// Test fixtures and helpers for Share-as-Image tests
enum ShareAsImageTestHelpers {

    // MARK: - Post Factory

    /// Creates a test post with customizable properties
    static func makePost(
        id: String = UUID().uuidString,
        content: String = "Test content",
        authorName: String = "Test User",
        authorUsername: String = "testuser",
        authorId: String = "author-1",
        platform: SocialPlatform = .mastodon,
        inReplyToID: String? = nil,
        likeCount: Int = 0,
        repostCount: Int = 0,
        replyCount: Int = 0,
        createdAt: Date = Date()
    ) -> Post {
        Post(
            id: id,
            content: content,
            authorName: authorName,
            authorUsername: authorUsername,
            authorId: authorId,
            authorProfilePictureURL: "https://example.com/avatar.png",
            createdAt: createdAt,
            platform: platform,
            originalURL: "https://example.com/post/\(id)",
            attachments: [],
            mentions: [],
            tags: [],
            likeCount: likeCount,
            repostCount: repostCount,
            replyCount: replyCount,
            inReplyToID: inReplyToID
        )
    }

    /// Creates a post with media attachments
    static func makePostWithMedia(
        id: String = UUID().uuidString,
        content: String = "Post with media",
        attachmentCount: Int = 1,
        platform: SocialPlatform = .mastodon
    ) -> Post {
        let attachments = (0..<attachmentCount).map { i in
            Post.Attachment(
                url: "https://example.com/image\(i).jpg",
                type: .image,
                altText: "Image \(i)"
            )
        }

        return Post(
            id: id,
            content: content,
            authorName: "Media User",
            authorUsername: "mediauser",
            authorId: "author-media",
            authorProfilePictureURL: "https://example.com/avatar.png",
            createdAt: Date(),
            platform: platform,
            originalURL: "https://example.com/post/\(id)",
            attachments: attachments
        )
    }

    /// Creates a post with link preview
    static func makePostWithLinkPreview(
        id: String = UUID().uuidString,
        platform: SocialPlatform = .mastodon
    ) -> Post {
        let post = Post(
            id: id,
            content: "Check out this link!",
            authorName: "Link User",
            authorUsername: "linkuser",
            authorId: "author-link",
            authorProfilePictureURL: "https://example.com/avatar.png",
            createdAt: Date(),
            platform: platform,
            originalURL: "https://example.com/post/\(id)",
            attachments: [],
            primaryLinkURL: URL(string: "https://example.com/article")
        )
        post.primaryLinkTitle = "Test Article"
        post.primaryLinkDescription = "This is a test article description"
        post.primaryLinkThumbnailURL = URL(string: "https://example.com/thumbnail.jpg")
        return post
    }

    // MARK: - Thread Graph Builders

    /// Creates a simple linear chain: root -> a -> b -> c (selected)
    /// Returns (allPosts, selectedPost, rootPost)
    static func makeLinearChain(length: Int = 4) -> (posts: [Post], selected: Post, root: Post) {
        var posts: [Post] = []
        var previousID: String? = nil

        for i in 0..<length {
            let post = makePost(
                id: "post-\(i)",
                content: "Message \(i)",
                authorName: "User \(i % 3)",
                authorUsername: "user\(i % 3)",
                authorId: "author-\(i % 3)",
                inReplyToID: previousID,
                createdAt: Date().addingTimeInterval(Double(i * 60))
            )
            posts.append(post)
            previousID = post.id
        }

        return (posts: posts, selected: posts.last!, root: posts.first!)
    }

    /// Creates a branching thread where the selected post has multiple replies
    /// root -> selected -> [reply1, reply2, reply3, reply4, reply5]
    static func makeBranchingThread(replyCount: Int = 5) -> (posts: [Post], selected: Post, root: Post, replies: [Post]) {
        let root = makePost(
            id: "root",
            content: "Root post",
            authorName: "Root Author",
            authorUsername: "rootauthor",
            authorId: "author-root"
        )

        let selected = makePost(
            id: "selected",
            content: "Selected reply",
            authorName: "Selected Author",
            authorUsername: "selectedauthor",
            authorId: "author-selected",
            inReplyToID: root.id,
            createdAt: Date().addingTimeInterval(60)
        )

        var replies: [Post] = []
        for i in 0..<replyCount {
            let reply = makePost(
                id: "reply-\(i)",
                content: "Reply \(i) to selected",
                authorName: "Reply Author \(i)",
                authorUsername: "replyauthor\(i)",
                authorId: "author-reply-\(i)",
                inReplyToID: selected.id,
                likeCount: replyCount - i, // Higher engagement for earlier replies
                repostCount: i % 2,
                createdAt: Date().addingTimeInterval(Double(120 + i * 30))
            )
            replies.append(reply)
        }

        let allPosts = [root, selected] + replies
        return (posts: allPosts, selected: selected, root: root, replies: replies)
    }

    /// Creates a deep thread with multiple levels
    /// root -> a -> b -> c -> d -> e (selected) -> [replies at different depths]
    static func makeDeepThread(depth: Int = 5, repliesPerLevel: Int = 2) -> (posts: [Post], selected: Post, root: Post) {
        var posts: [Post] = []
        var previousID: String? = nil

        // Build main chain
        for i in 0..<depth {
            let post = makePost(
                id: "chain-\(i)",
                content: "Chain message \(i)",
                authorName: "Chain User \(i)",
                authorUsername: "chainuser\(i)",
                authorId: "author-chain-\(i)",
                inReplyToID: previousID,
                createdAt: Date().addingTimeInterval(Double(i * 60))
            )
            posts.append(post)
            previousID = post.id
        }

        let selected = posts.last!

        // Add replies at different depths under selected
        var parentID = selected.id
        for level in 0..<3 {
            for r in 0..<repliesPerLevel {
                let reply = makePost(
                    id: "deep-reply-\(level)-\(r)",
                    content: "Deep reply level \(level) #\(r)",
                    authorName: "Deep Author",
                    authorUsername: "deepauthor",
                    authorId: "author-deep",
                    inReplyToID: parentID,
                    likeCount: 10 - level * 3,
                    createdAt: Date().addingTimeInterval(Double(100 + level * 50 + r * 10))
                )
                posts.append(reply)
                if r == 0 {
                    parentID = reply.id // First reply becomes parent for next level
                }
            }
        }

        return (posts: posts, selected: selected, root: posts.first!)
    }

    /// Creates a sparse thread (selected has fewer than 3 direct replies)
    /// This tests the depth-2 allowance heuristic
    static func makeSparseThread() -> (posts: [Post], selected: Post, root: Post) {
        let root = makePost(
            id: "sparse-root",
            content: "Sparse root",
            authorName: "Root",
            authorUsername: "root",
            authorId: "author-root"
        )

        let selected = makePost(
            id: "sparse-selected",
            content: "Selected with sparse replies",
            authorName: "Selected",
            authorUsername: "selected",
            authorId: "author-selected",
            inReplyToID: root.id
        )

        // Only 2 direct replies (< 3, so depth 2 should be allowed)
        let reply1 = makePost(
            id: "sparse-reply-1",
            content: "Reply 1",
            authorName: "Reply1",
            authorUsername: "reply1",
            authorId: "author-reply1",
            inReplyToID: selected.id,
            likeCount: 5
        )

        let reply2 = makePost(
            id: "sparse-reply-2",
            content: "Reply 2",
            authorName: "Reply2",
            authorUsername: "reply2",
            authorId: "author-reply2",
            inReplyToID: selected.id,
            likeCount: 3
        )

        // Nested reply (depth 2) - should be included due to sparse heuristic
        let nestedReply = makePost(
            id: "sparse-nested",
            content: "Nested reply at depth 2",
            authorName: "Nested",
            authorUsername: "nested",
            authorId: "author-nested",
            inReplyToID: reply1.id,
            likeCount: 2
        )

        let allPosts = [root, selected, reply1, reply2, nestedReply]
        return (posts: allPosts, selected: selected, root: root)
    }

    // MARK: - Thread Context Factory

    /// Creates a ThreadContext from a thread structure
    static func makeThreadContext(
        mainPost: Post?,
        ancestors: [Post],
        descendants: [Post]
    ) -> ThreadContext {
        ThreadContext(mainPost: mainPost, ancestors: ancestors, descendants: descendants)
    }

    /// Creates ThreadContext from the linear chain helper
    static func makeLinearChainContext() -> (context: ThreadContext, selected: Post, root: Post) {
        let (posts, selected, root) = makeLinearChain()

        // Ancestors are posts before selected (in chronological order)
        let ancestors = posts.filter { $0.id != selected.id }

        let context = ThreadContext(
            mainPost: root,
            ancestors: Array(ancestors.dropLast()), // All except root and selected
            descendants: []
        )

        return (context: context, selected: selected, root: root)
    }

    // MARK: - Config Factories

    static func makeConfig(
        includeEarlier: Bool = false,
        includeLater: Bool = false,
        hideUsernames: Bool = false,
        showWatermark: Bool = true
    ) -> ShareImageConfig {
        ShareImageConfig(
            includeEarlier: includeEarlier,
            includeLater: includeLater,
            hideUsernames: hideUsernames,
            showWatermark: showWatermark
        )
    }
}

// MARK: - Test Assertion Helpers

extension XCTestCase {

    /// Asserts that a collection contains no duplicate IDs (for CommentRenderable)
    func assertNoDuplicateIDs(_ items: [CommentRenderable], file: StaticString = #file, line: UInt = #line) {
        let ids = items.map { $0.id }
        let uniqueIDs = Set(ids)
        XCTAssertEqual(ids.count, uniqueIDs.count, "Found duplicate IDs: \(ids.filter { id in ids.filter { $0 == id }.count > 1 })", file: file, line: line)
    }

    /// Asserts that a collection contains no duplicate IDs (for Post)
    func assertNoDuplicateIDs(_ items: [Post], file: StaticString = #file, line: UInt = #line) {
        let ids = items.map { $0.id }
        let uniqueIDs = Set(ids)
        XCTAssertEqual(ids.count, uniqueIDs.count, "Found duplicate IDs: \(ids.filter { id in ids.filter { $0 == id }.count > 1 })", file: file, line: line)
    }

    /// Asserts that a specific ID appears exactly once in a collection of CommentRenderable
    func assertExactlyOnce(_ id: String, in items: [CommentRenderable], file: StaticString = #file, line: UInt = #line) {
        let count = items.filter { $0.id == id }.count
        XCTAssertEqual(count, 1, "Expected ID '\(id)' to appear exactly once, but found \(count) occurrences", file: file, line: line)
    }

    /// Asserts that a specific ID appears exactly once in a collection of Post
    func assertExactlyOnce(_ id: String, in items: [Post], file: StaticString = #file, line: UInt = #line) {
        let count = items.filter { $0.id == id }.count
        XCTAssertEqual(count, 1, "Expected ID '\(id)' to appear exactly once, but found \(count) occurrences", file: file, line: line)
    }

    /// Asserts that a collection is in chronological order (oldest first)
    func assertChronologicalOrder(_ posts: [Post], file: StaticString = #file, line: UInt = #line) {
        for i in 1..<posts.count {
            XCTAssertLessThanOrEqual(
                posts[i-1].createdAt,
                posts[i].createdAt,
                "Posts not in chronological order at index \(i): \(posts[i-1].createdAt) > \(posts[i].createdAt)",
                file: file,
                line: line
            )
        }
    }
}

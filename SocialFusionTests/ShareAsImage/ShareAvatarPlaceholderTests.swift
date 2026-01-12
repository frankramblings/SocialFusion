import XCTest
@testable import SocialFusion

/// Tests for avatar handling and placeholder behavior in Share-as-Image
final class ShareAvatarPlaceholderTests: XCTestCase {

    // MARK: - Avatar URL Handling Tests

    func testPostRenderablePreservesAvatarURL() {
        // Given: A post with a valid avatar URL
        let post = ShareAsImageTestHelpers.makePost(
            authorName: "Test User",
            authorUsername: "testuser"
        )

        var mapping: [String: String] = [:]

        // When: Converting to renderable without anonymization
        let renderable = UnifiedAdapter.convertPost(
            post,
            hideUsernames: false,
            userMapping: &mapping
        )

        // Then: Avatar URL should be preserved
        XCTAssertNotNil(renderable.authorAvatarURL, "Avatar URL should be preserved")
        XCTAssertEqual(renderable.authorAvatarURL?.absoluteString, "https://example.com/avatar.png")
    }

    func testCommentRenderablePreservesAvatarURL() {
        // Given: A post with a valid avatar URL
        let post = ShareAsImageTestHelpers.makePost()

        var mapping: [String: String] = [:]

        // When: Converting to comment renderable without anonymization
        let renderable = UnifiedAdapter.convertComment(
            post,
            depth: 0,
            isSelected: false,
            hideUsernames: false,
            userMapping: &mapping
        )

        // Then: Avatar URL should be preserved
        XCTAssertNotNil(renderable.authorAvatarURL, "Comment avatar URL should be preserved")
    }

    func testAvatarNilWhenAnonymizing() {
        // Given: A post with an avatar
        let post = ShareAsImageTestHelpers.makePost()

        var mapping: [String: String] = [:]

        // When: Converting with anonymization
        let renderable = UnifiedAdapter.convertPost(
            post,
            hideUsernames: true,
            userMapping: &mapping
        )

        // Then: Avatar should be nil for privacy
        XCTAssertNil(renderable.authorAvatarURL, "Avatar should be nil when anonymizing")
    }

    func testCommentAvatarNilWhenAnonymizing() {
        // Given: A post with an avatar
        let post = ShareAsImageTestHelpers.makePost()

        var mapping: [String: String] = [:]

        // When: Converting to comment with anonymization
        let renderable = UnifiedAdapter.convertComment(
            post,
            depth: 0,
            isSelected: false,
            hideUsernames: true,
            userMapping: &mapping
        )

        // Then: Avatar should be nil
        XCTAssertNil(renderable.authorAvatarURL, "Comment avatar should be nil when anonymizing")
    }

    // MARK: - Invalid/Missing Avatar Tests

    func testHandlesMissingAvatarURL() {
        // Given: A post with empty avatar URL string
        let post = Post(
            id: "test-id",
            content: "Test content",
            authorName: "Test User",
            authorUsername: "testuser",
            authorId: "author-1",
            authorProfilePictureURL: "", // Empty URL
            createdAt: Date(),
            platform: .mastodon,
            originalURL: "https://example.com/post/test-id",
            attachments: []
        )

        var mapping: [String: String] = [:]

        // When: Converting to renderable
        let renderable = UnifiedAdapter.convertPost(
            post,
            hideUsernames: false,
            userMapping: &mapping
        )

        // Then: Avatar URL should be nil (empty string doesn't create valid URL)
        XCTAssertNil(renderable.authorAvatarURL, "Empty avatar URL string should result in nil URL")
    }

    func testHandlesURLConversionGracefully() {
        // Given: A post - URL(string:) is very lenient, so this test just ensures
        // the conversion doesn't crash regardless of input
        let post = Post(
            id: "test-id",
            content: "Test content",
            authorName: "Test User",
            authorUsername: "testuser",
            authorId: "author-1",
            authorProfilePictureURL: "https://example.com/valid.png",
            createdAt: Date(),
            platform: .mastodon,
            originalURL: "https://example.com/post/test-id",
            attachments: []
        )

        var mapping: [String: String] = [:]

        // When: Converting to renderable
        let renderable = UnifiedAdapter.convertPost(
            post,
            hideUsernames: false,
            userMapping: &mapping
        )

        // Then: Valid URL should be preserved
        XCTAssertNotNil(renderable.authorAvatarURL, "Valid URL should be preserved")
        XCTAssertEqual(renderable.authorAvatarURL?.absoluteString, "https://example.com/valid.png")
    }

    // MARK: - Document-Level Avatar Tests

    func testDocumentAvatarsWhenNotAnonymizing() {
        // Given: A thread with posts from different authors
        let (posts, selected, root, replies) = ShareAsImageTestHelpers.makeBranchingThread(replyCount: 3)
        let context = ThreadContext(mainPost: root, ancestors: [], descendants: replies)

        var userMapping: [String: String] = [:]
        let config = ShareAsImageTestHelpers.makeConfig(
            includeEarlier: false,
            includeLater: true,
            hideUsernames: false // NOT anonymizing
        )

        // When: Building document
        let doc = ShareThreadRenderBuilder.buildDocument(
            from: selected,
            threadContext: context,
            config: config,
            userMapping: &userMapping
        )

        // Then: All comments should have avatar URLs
        for comment in doc.replySubtree {
            XCTAssertNotNil(comment.authorAvatarURL, "Comment \(comment.id) should have avatar URL when not anonymizing")
        }
    }

    func testDocumentAvatarsWhenAnonymizing() {
        // Given: A thread with posts from different authors
        let (posts, selected, root, replies) = ShareAsImageTestHelpers.makeBranchingThread(replyCount: 3)
        let context = ThreadContext(mainPost: root, ancestors: [], descendants: replies)

        var userMapping: [String: String] = [:]
        let config = ShareAsImageTestHelpers.makeConfig(
            includeEarlier: false,
            includeLater: true,
            hideUsernames: true // Anonymizing
        )

        // When: Building document
        let doc = ShareThreadRenderBuilder.buildDocument(
            from: selected,
            threadContext: context,
            config: config,
            userMapping: &userMapping
        )

        // Then: All comments should have nil avatar URLs
        for comment in doc.replySubtree {
            XCTAssertNil(comment.authorAvatarURL, "Comment \(comment.id) should have nil avatar when anonymizing")
        }

        // And: Post header should also have nil avatar
        XCTAssertNil(doc.selectedPost.authorAvatarURL, "Post header should have nil avatar when anonymizing")
    }

    // MARK: - Quote Post Avatar Tests

    func testQuotePostAvatarHandling() {
        // Given: A post that quotes another post
        let quotedPost = ShareAsImageTestHelpers.makePost(
            id: "quoted",
            authorName: "Quoted Author",
            authorUsername: "quotedauthor"
        )

        let quotingPost = Post(
            id: "quoting",
            content: "Quoting this!",
            authorName: "Quoting Author",
            authorUsername: "quotingauthor",
            authorId: "quoting-author",
            authorProfilePictureURL: "https://example.com/quoting-avatar.png",
            createdAt: Date(),
            platform: .mastodon,
            originalURL: "https://example.com/post/quoting",
            attachments: [],
            quotedPost: quotedPost
        )

        var mapping: [String: String] = [:]

        // When: Converting without anonymization
        let renderable = UnifiedAdapter.convertPost(
            quotingPost,
            hideUsernames: false,
            userMapping: &mapping
        )

        // Then: Main post should have avatar
        XCTAssertNotNil(renderable.authorAvatarURL)

        // And: Quote post data should exist
        XCTAssertNotNil(renderable.quotePostData, "Quote post data should be present")
    }

    // MARK: - Boost Banner Avatar Tests

    func testBoostBannerAnonymization() {
        // Given: A boosted post
        let original = ShareAsImageTestHelpers.makePost(
            id: "original",
            authorName: "Original Author"
        )

        let boost = Post(
            id: "boost",
            content: "",
            authorName: "Booster",
            authorUsername: "booster",
            authorId: "booster-id",
            authorProfilePictureURL: "https://example.com/booster.png",
            createdAt: Date(),
            platform: .mastodon,
            originalURL: "",
            attachments: [],
            originalPost: original,
            isReposted: true,
            boostedBy: "booster"
        )

        var mapping: [String: String] = [:]

        // When: Converting with anonymization
        let renderable = UnifiedAdapter.convertPost(
            boost,
            hideUsernames: true,
            userMapping: &mapping
        )

        // Then: Boost banner should be anonymized
        if let boostBanner = renderable.boostBannerData {
            XCTAssertTrue(
                boostBanner.boosterHandle.starts(with: "User"),
                "Booster handle should be anonymized"
            )
        }
    }
}

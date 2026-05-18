import XCTest
@testable import SocialFusion

final class FusedMomentDetectorTests: XCTestCase {
    fileprivate func makePost(
        id: String,
        platform: SocialPlatform,
        content: String,
        authorId: String,
        createdAt: Date
    ) -> Post {
        // The Post initializer lives at SocialFusion/Models/Post.swift:764+.
        // Argument order must match the declaration: authorId sits between
        // authorUsername and authorProfilePictureURL.
        Post(
            id: id,
            content: content,
            authorName: "Test Author",
            authorUsername: "testuser",
            authorId: authorId,
            authorProfilePictureURL: "",
            createdAt: createdAt,
            platform: platform,
            originalURL: "",
            attachments: [],
            mentions: [],
            tags: []
        )
    }

    func testMatchesPostsWithSameSignatureAndAuthorWithinWindow() {
        let now = Date()
        let mastoPost = makePost(
            id: "m1",
            platform: .mastodon,
            content: "Big news today, this is genuinely excellent!",
            authorId: "author-identity-1",
            createdAt: now
        )
        let bskyPost = makePost(
            id: "b1",
            platform: .bluesky,
            content: "Big news today, this is genuinely excellent! #news",
            authorId: "author-identity-1",
            createdAt: now.addingTimeInterval(120) // 2 min later
        )

        let detector = FusedMomentDetector()
        let result = detector.detect(in: [mastoPost, bskyPost])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.mastodonPostID, "m1")
        XCTAssertEqual(result.first?.blueskyPostID, "b1")
    }

    func testDoesNotMatchDifferentAuthors() {
        let now = Date()
        let posts = [
            makePost(id: "m1", platform: .mastodon, content: "Hello", authorId: "author-1", createdAt: now),
            makePost(id: "b1", platform: .bluesky, content: "Hello", authorId: "author-2", createdAt: now)
        ]
        XCTAssertEqual(FusedMomentDetector().detect(in: posts).count, 0)
    }

    func testDoesNotMatchOutsideTimeWindow() {
        let now = Date()
        let posts = [
            makePost(id: "m1", platform: .mastodon, content: "Hello", authorId: "a", createdAt: now),
            makePost(id: "b1", platform: .bluesky, content: "Hello", authorId: "a",
                     createdAt: now.addingTimeInterval(60 * 60)) // 1 hour later
        ]
        XCTAssertEqual(FusedMomentDetector().detect(in: posts).count, 0)
    }

    func testDoesNotMatchTwoSameNetworkPosts() {
        let now = Date()
        let posts = [
            makePost(id: "m1", platform: .mastodon, content: "Hello", authorId: "a", createdAt: now),
            makePost(id: "m2", platform: .mastodon, content: "Hello", authorId: "a", createdAt: now.addingTimeInterval(60))
        ]
        XCTAssertEqual(FusedMomentDetector().detect(in: posts).count, 0)
    }

    func testEmptyPostsAreNeverMatched() {
        let now = Date()
        let posts = [
            makePost(id: "m1", platform: .mastodon, content: "", authorId: "a", createdAt: now),
            makePost(id: "b1", platform: .bluesky, content: "   ", authorId: "a", createdAt: now)
        ]
        XCTAssertEqual(FusedMomentDetector().detect(in: posts).count, 0,
                       "Empty-content matches are too noisy; never fuse them.")
    }
}

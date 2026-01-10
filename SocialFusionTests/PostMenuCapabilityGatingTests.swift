import XCTest
@testable import SocialFusion

final class PostMenuCapabilityGatingTests: XCTestCase {
    func testMastodonIncludesAddToList() {
        let post = Post(
            id: "1",
            content: "Test",
            authorName: "Test User",
            authorUsername: "testuser",
            authorProfilePictureURL: "",
            createdAt: Date(),
            platform: .mastodon,
            originalURL: "https://mastodon.social/@testuser/12345",
            attachments: []
        )

        let actions = PostAction.platformActions(for: post)
        XCTAssertTrue(actions.contains(.addToList))
    }

    func testBlueskyExcludesAddToList() {
        let post = Post(
            id: "1",
            content: "Test",
            authorName: "Test User",
            authorUsername: "user.bsky.social",
            authorProfilePictureURL: "",
            createdAt: Date(),
            platform: .bluesky,
            originalURL: "https://bsky.app/profile/user.bsky.social/post/abcdef",
            attachments: []
        )

        let actions = PostAction.platformActions(for: post)
        XCTAssertFalse(actions.contains(.addToList))
    }
}

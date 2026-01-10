import XCTest
import SwiftUI
import UIKit
@testable import SocialFusion

final class PostSystemActionsTests: XCTestCase {
    func testAuthorProfileURLForMastodon() {
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

        XCTAssertEqual(
            post.authorProfileURL?.absoluteString,
            "https://mastodon.social/@testuser"
        )
    }

    func testAuthorProfileURLForBluesky() {
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

        XCTAssertEqual(
            post.authorProfileURL?.absoluteString,
            "https://bsky.app/profile/user.bsky.social"
        )
    }

    func testCopyLinkWritesPasteboardURL() {
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

        post.copyLink()

        XCTAssertEqual(
            UIPasteboard.general.url?.absoluteString,
            "https://mastodon.social/@testuser/12345"
        )
    }
}

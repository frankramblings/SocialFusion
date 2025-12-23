import XCTest
@testable import SocialFusion

@MainActor
final class SocialServiceManagerPostActionTests: XCTestCase {

    final class MockMastodonService: MastodonService {
        var likeResponses: [Result<Post, Error>] = []
        var unlikeResponses: [Result<Post, Error>] = []

        override func likePost(_ post: Post, account: SocialAccount) async throws -> Post {
            if likeResponses.isEmpty {
                return post
            }
            let result = likeResponses.removeFirst()
            switch result {
            case .success(let post):
                return post
            case .failure(let error):
                throw error
            }
        }

        override func unlikePost(_ post: Post, account: SocialAccount) async throws -> Post {
            if unlikeResponses.isEmpty {
                return post
            }
            let result = unlikeResponses.removeFirst()
            switch result {
            case .success(let post):
                return post
            case .failure(let error):
                throw error
            }
        }
    }

    private func makeAccount(platform: SocialPlatform = .mastodon) -> SocialAccount {
        SocialAccount(
            id: UUID().uuidString,
            username: "tester",
            displayName: "Tester",
            serverURL: nil,
            platform: platform,
            profileImageURL: nil
        )
    }

    private func makePost(platform: SocialPlatform = .mastodon) -> Post {
        Post(
            id: UUID().uuidString,
            content: "Hello",
            authorName: "Tester",
            authorUsername: "tester",
            authorProfilePictureURL: "",
            createdAt: Date(),
            platform: platform,
            originalURL: "https://example.com",
            attachments: []
        )
    }

    func testLikeUsesBackoffAndUpdatesPost() async throws {
        let mockService = MockMastodonService()
        let updatedPost = makePost()
        updatedPost.isLiked = true
        updatedPost.likeCount = 5

        mockService.likeResponses = [
            .failure(NetworkError.networkUnavailable),
            .success(updatedPost)
        ]

        let serviceManager = SocialServiceManager(
            mastodonService: mockService,
            blueskyService: BlueskyService()
        )

        let account = makeAccount()
        serviceManager.mastodonAccounts = [account]

        let post = makePost()
        let state = try await serviceManager.like(post: post)

        XCTAssertTrue(state.isLiked)
        XCTAssertEqual(state.likeCount, 5)
        XCTAssertTrue(post.isLiked)
        XCTAssertEqual(post.likeCount, 5)
    }

    func testUnlikeReturnsServerState() async throws {
        let mockService = MockMastodonService()
        let updatedPost = makePost()
        updatedPost.isLiked = false
        updatedPost.likeCount = 1

        mockService.unlikeResponses = [
            .success(updatedPost)
        ]

        let serviceManager = SocialServiceManager(
            mastodonService: mockService,
            blueskyService: BlueskyService()
        )

        let account = makeAccount()
        serviceManager.mastodonAccounts = [account]

        let post = makePost()
        post.isLiked = true
        post.likeCount = 3

        let state = try await serviceManager.unlike(post: post)

        XCTAssertFalse(state.isLiked)
        XCTAssertEqual(state.likeCount, 1)
        XCTAssertFalse(post.isLiked)
        XCTAssertEqual(post.likeCount, 1)
    }
}


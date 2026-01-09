import Foundation
import XCTest

@testable import SocialFusion

final class PostFeedFilterTests: XCTestCase {

    var filter: PostFeedFilter!
    var mockMastodonResolver: MockThreadParticipantResolver!
    var mockBlueskyResolver: MockThreadParticipantResolver!

    override func setUp() {
        super.setUp()
        mockMastodonResolver = MockThreadParticipantResolver()
        mockBlueskyResolver = MockThreadParticipantResolver()
        filter = PostFeedFilter(
            mastodonResolver: mockMastodonResolver,
            blueskyResolver: mockBlueskyResolver
        )
    }

    override func tearDown() {
        filter = nil
        mockMastodonResolver = nil
        mockBlueskyResolver = nil
        super.tearDown()
    }

    // MARK: - Top-level posts tests

    func testTopLevelPostFromFollowedUserIsAlwaysIncluded() async {
        // Given
        let user1 = UserID(value: "user1@mastodon.social", platform: SocialPlatform.mastodon)
        let followedAccounts = Set<UserID>([user1])

        let post = createMastodonPost(
            id: "1",
            authorUsername: "user1@mastodon.social",
            inReplyToID: nil  // Top-level post
        )

        // When
        let shouldInclude = await filter.shouldIncludeReply(
            post, followedAccounts: followedAccounts)

        // Then
        XCTAssertTrue(
            shouldInclude, "Top-level posts from followed users should always be included")
    }

    func testTopLevelPostFromUnfollowedUserIsAlwaysIncluded() async {
        // Given
        let user1 = UserID(value: "user1@mastodon.social", platform: SocialPlatform.mastodon)
        let followedAccounts = Set<UserID>([user1])

        let post = createMastodonPost(
            id: "1",
            authorUsername: "user2@mastodon.social",  // Different user
            inReplyToID: nil  // Top-level post
        )

        // When
        let shouldInclude = await filter.shouldIncludeReply(
            post, followedAccounts: followedAccounts)

        // Then
        XCTAssertTrue(
            shouldInclude, "Top-level posts should always be included regardless of follow status")
    }

    // MARK: - Reply filtering tests

    func testReplyFromFollowedUserIsAlwaysIncluded() async {
        // Given
        let user1 = UserID(value: "user1@mastodon.social", platform: SocialPlatform.mastodon)
        let followedAccounts = Set<UserID>([user1])

        let post = createMastodonPost(
            id: "2",
            authorUsername: "user1@mastodon.social",
            inReplyToID: "1"  // This is a reply
        )

        // When
        let shouldInclude = await filter.shouldIncludeReply(
            post, followedAccounts: followedAccounts)

        // Then
        XCTAssertTrue(
            shouldInclude, "Replies from followed users should always be included (self-replies)")
    }

    func testReplyWithTwoFollowedParticipantsIsIncluded() async {
        // Given
        let user1 = UserID(value: "user1@mastodon.social", platform: SocialPlatform.mastodon)
        let user2 = UserID(value: "user2@mastodon.social", platform: SocialPlatform.mastodon)
        let user3 = UserID(value: "user3@mastodon.social", platform: SocialPlatform.mastodon)
        let followedAccounts = Set<UserID>([user1, user2])

        let post = createMastodonPost(
            id: "3",
            authorUsername: "user3@mastodon.social",  // Unfollowed user replying
            inReplyToID: "1"
        )

        // Mock thread participants including 2 followed users
        let threadParticipants = Set([user1, user2, user3])
        mockMastodonResolver.mockParticipants = threadParticipants

        // When
        let shouldInclude = await filter.shouldIncludeReply(
            post, followedAccounts: followedAccounts)

        // Then
        XCTAssertTrue(
            shouldInclude, "Reply should be included when thread has 2+ followed participants")
    }

    func testReplyWithOneFollowedParticipantIsExcluded() async {
        // Given
        let user1 = UserID(value: "user1@mastodon.social", platform: .mastodon)
        let user2 = UserID(value: "user2@mastodon.social", platform: .mastodon)
        let user3 = UserID(value: "user3@mastodon.social", platform: .mastodon)
        let followedAccounts = Set([user1])

        let post = createMastodonPost(
            id: "3",
            authorUsername: "user3@mastodon.social",  // Unfollowed user replying
            inReplyToID: "1"
        )

        // Mock thread participants with only 1 followed user
        let threadParticipants = Set([user1, user2, user3])
        mockMastodonResolver.mockParticipants = threadParticipants

        // When
        let shouldInclude = await filter.shouldIncludeReply(
            post, followedAccounts: followedAccounts)

        // Then
        XCTAssertFalse(
            shouldInclude, "Reply should be excluded when thread has <2 followed participants")
    }

    // MARK: - Self-reply edge cases

    func testSelfReply_Mastodon_CaseInsensitiveAndAtSign() async {
        // Given
        let followed = UserID(value: "user1@mastodon.social", platform: .mastodon)
        let followedAccounts = Set([followed])

        // Author mixed-case; in-reply-to includes leading '@'
        let post = createMastodonPost(
            id: "self1",
            authorUsername: "User1@Mastodon.Social",
            inReplyToID: "orig"
        )
        post.inReplyToUsername = "@user1@mastodon.social"

        // When
        let shouldInclude = await filter.shouldIncludeReply(post, followedAccounts: followedAccounts)

        // Then
        XCTAssertTrue(shouldInclude, "Self-reply should be included regardless of case or '@' prefix when author is followed")
    }

    func testSelfReply_Bluesky_UsingDID() async {
        // Given
        let followed = UserID(value: "user1.bsky.social", platform: .bluesky)
        let followedAccounts = Set([followed])

        // Construct a Bluesky Post where authorId is a DID and inReplyToUsername is that DID
        let post = Post(
            id: "bself1",
            content: "Test",
            authorName: "User One",
            authorUsername: "user1.bsky.social",
            authorId: "did:plc:abc123xyz",
            authorProfilePictureURL: "https://example.com/avatar.jpg",
            createdAt: Date(),
            platform: .bluesky,
            originalURL: "https://bsky.app/profile/user1.bsky.social/post/bself1",
            attachments: [],
            mentions: [],
            tags: [],
            originalPost: nil,
            isReposted: false,
            isLiked: false,
            isReplied: false,
            likeCount: 0,
            repostCount: 0,
            replyCount: 0,
            isFollowingAuthor: false,
            isMutedAuthor: false,
            isBlockedAuthor: false,
            platformSpecificId: "at://did:plc:abc123xyz/app.bsky.feed.post/bself1",
            boostedBy: nil,
            parent: nil,
            inReplyToID: "b1",
            inReplyToUsername: "did:plc:abc123xyz",
            quotedPostUri: nil,
            quotedPostAuthorHandle: nil,
            quotedPost: nil,
            poll: nil,
            cid: nil,
            primaryLinkURL: nil,
            primaryLinkTitle: nil,
            primaryLinkDescription: nil,
            primaryLinkThumbnailURL: nil,
            blueskyLikeRecordURI: nil,
            blueskyRepostRecordURI: nil,
            customEmojiMap: nil,
            clientName: nil
        )

        // When
        let shouldInclude = await filter.shouldIncludeReply(post, followedAccounts: followedAccounts)

        // Then
        XCTAssertTrue(shouldInclude, "Self-reply should be included when inReplyTo is DID and author is followed by handle")
    }

    // MARK: - Cross-platform tests

    func testBlueskyReplyFiltering() async {
        // Given
        let user1 = UserID(value: "user1.bsky.social", platform: .bluesky)
        let user2 = UserID(value: "user2.bsky.social", platform: .bluesky)
        let user3 = UserID(value: "user3.bsky.social", platform: .bluesky)
        let followedAccounts = Set([user1, user2])

        let post = createBlueskyPost(
            id: "bsky3",
            authorUsername: "user3.bsky.social",
            inReplyToID: "bsky1"
        )

        // Mock thread participants including 2 followed users
        let threadParticipants = Set([user1, user2, user3])
        mockBlueskyResolver.mockParticipants = threadParticipants

        // When
        let shouldInclude = await filter.shouldIncludeReply(
            post, followedAccounts: followedAccounts)

        // Then
        XCTAssertTrue(
            shouldInclude,
            "Bluesky reply should be included when thread has 2+ followed participants")
    }

    // MARK: - Feature flag tests

    func testFilteringDisabledIncludesAllReplies() async {
        // Given
        filter.isReplyFilteringEnabled = false

        let user1 = UserID(value: "user1@mastodon.social", platform: .mastodon)
        let followedAccounts = Set([user1])

        let post = createMastodonPost(
            id: "3",
            authorUsername: "user3@mastodon.social",  // Unfollowed user
            inReplyToID: "1"
        )

        // Mock thread with no followed participants
        mockMastodonResolver.mockParticipants = Set([
            UserID(value: "user2@mastodon.social", platform: .mastodon),
            UserID(value: "user3@mastodon.social", platform: .mastodon),
        ])

        // When
        let shouldInclude = await filter.shouldIncludeReply(
            post, followedAccounts: followedAccounts)

        // Then
        XCTAssertTrue(shouldInclude, "All replies should be included when filtering is disabled")
    }

    // MARK: - Error handling tests

    func testThreadResolutionErrorDefaultsToInclude() async {
        // Given
        let user1 = UserID(value: "user1@mastodon.social", platform: .mastodon)
        let followedAccounts = Set([user1])

        let post = createMastodonPost(
            id: "3",
            authorUsername: "user3@mastodon.social",
            inReplyToID: "1"
        )

        // Mock resolver to throw error
        mockMastodonResolver.shouldThrowError = true

        // When
        let shouldInclude = await filter.shouldIncludeReply(
            post, followedAccounts: followedAccounts)

        // Then
        XCTAssertTrue(
            shouldInclude, "Should default to including reply when thread resolution fails")
    }

    // MARK: - Helper methods

    private func createMastodonPost(id: String, authorUsername: String, inReplyToID: String?)
        -> Post
    {
        return Post(
            id: id,
            content: "Test content",
            authorName: "Test User",
            authorUsername: authorUsername,
            authorProfilePictureURL: "https://example.com/avatar.jpg",
            createdAt: Date(),
            platform: .mastodon,
            originalURL: "https://mastodon.social/@test/\(id)",
            attachments: [],
            mentions: [],
            tags: [],
            platformSpecificId: id,
            inReplyToID: inReplyToID
        )
    }

    private func createBlueskyPost(id: String, authorUsername: String, inReplyToID: String?) -> Post
    {
        return Post(
            id: id,
            content: "Test content",
            authorName: "Test User",
            authorUsername: authorUsername,
            authorProfilePictureURL: "https://example.com/avatar.jpg",
            createdAt: Date(),
            platform: .bluesky,
            originalURL: "https://bsky.app/profile/\(authorUsername)/post/\(id)",
            attachments: [],
            mentions: [],
            tags: [],
            platformSpecificId: "at://\(authorUsername)/app.bsky.feed.post/\(id)",
            inReplyToID: inReplyToID
        )
    }
}

// MARK: - Mock Implementation

class MockThreadParticipantResolver: ThreadParticipantResolver {
    var mockParticipants: Set<UserID> = []
    var shouldThrowError = false

    func getThreadParticipants(for post: Post) async throws -> Set<UserID> {
        if shouldThrowError {
            throw NSError(
                domain: "MockError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
        return mockParticipants
    }
}

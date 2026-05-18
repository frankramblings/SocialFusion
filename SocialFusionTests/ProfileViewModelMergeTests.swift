import XCTest
@testable import SocialFusion

@MainActor
final class ProfileViewModelMergeTests: XCTestCase {
    func testSelectedSideDefaultsToProfilePlatform() {
        let user = SearchUser(id: "m1", username: "x@mastodon.social", platform: .mastodon)
        let vm = ProfileViewModel(
            user: user, isOwnProfile: false,
            serviceManager: SocialServiceManager()
        )
        XCTAssertEqual(vm.selectedSide, .mastodon)
    }

    func testMergedProfileBindingReadsMastodonProfileWhenMastodonSelected() {
        let user = SearchUser(id: "m1", username: "x@mastodon.social", platform: .mastodon)
        let vm = ProfileViewModel(
            user: user, isOwnProfile: false,
            serviceManager: SocialServiceManager()
        )
        let mastoProfile = makeProfile(id: "m1", username: "x@mastodon.social", platform: .mastodon)
        let bskyProfile = makeProfile(id: "b1", username: "x.bsky.social", platform: .bluesky)
        vm.profile = mastoProfile
        vm.mergedTwinProfile = bskyProfile
        vm.selectedSide = .mastodon
        XCTAssertEqual(vm.activeProfile?.id, "m1")
        vm.selectedSide = .bluesky
        XCTAssertEqual(vm.activeProfile?.id, "b1")
    }

    func testCombinedFollowerAndFollowingCountsSumWhenMerged() {
        let user = SearchUser(id: "m1", username: "x@mastodon.social", platform: .mastodon)
        let vm = ProfileViewModel(
            user: user, isOwnProfile: false,
            serviceManager: SocialServiceManager()
        )
        vm.profile = makeProfile(
            id: "m1", username: "x@mastodon.social", platform: .mastodon,
            followersCount: 100, followingCount: 50, statusesCount: 200
        )
        vm.mergedTwinProfile = makeProfile(
            id: "b1", username: "x.bsky.social", platform: .bluesky,
            followersCount: 70, followingCount: 30, statusesCount: 150
        )
        XCTAssertEqual(vm.combinedFollowersCount, 170)
        XCTAssertEqual(vm.combinedFollowingCount, 80)
        XCTAssertEqual(vm.combinedStatusesCount, 350)
    }

    func testCombinedCountsFallBackToActiveProfileWhenUnmerged() {
        let user = SearchUser(id: "m1", username: "x@mastodon.social", platform: .mastodon)
        let vm = ProfileViewModel(
            user: user, isOwnProfile: false,
            serviceManager: SocialServiceManager()
        )
        vm.profile = makeProfile(
            id: "m1", username: "x@mastodon.social", platform: .mastodon,
            followersCount: 100, followingCount: 50, statusesCount: 200
        )
        vm.mergedTwinProfile = nil
        XCTAssertEqual(vm.combinedFollowersCount, 100)
        XCTAssertEqual(vm.combinedFollowingCount, 50)
        XCTAssertEqual(vm.combinedStatusesCount, 200)
    }

    private func makeProfile(
        id: String, username: String, platform: SocialPlatform,
        followersCount: Int = 0, followingCount: Int = 0, statusesCount: Int = 0
    ) -> UserProfile {
        UserProfile(
            id: id, username: username, displayName: nil,
            avatarURL: nil, headerURL: nil, bio: nil,
            followersCount: followersCount,
            followingCount: followingCount,
            statusesCount: statusesCount,
            platform: platform
        )
    }
}

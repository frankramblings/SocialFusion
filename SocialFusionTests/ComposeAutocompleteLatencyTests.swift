import XCTest
@testable import SocialFusion

@MainActor
final class ComposeAutocompleteServiceKeyTests: XCTestCase {
    private func makeAccount(id: String, platform: SocialPlatform = .mastodon) -> SocialAccount {
        SocialAccount(
            id: id,
            username: "user_\(id)",
            displayName: "User \(id)",
            serverURL: "https://example.com",
            platform: platform,
            accessToken: nil,
            refreshToken: nil,
            expirationDate: nil,
            accountDetails: nil,
            profileImageURL: nil,
            platformSpecificId: id
        )
    }

    func testServiceKeySortsAccountIDsForStableReuse() {
        let a = makeAccount(id: "a")
        let b = makeAccount(id: "b")

        let key1 = ComposeAutocompleteServiceKey.make(
            accounts: [a, b],
            timelineScope: .unified
        )
        let key2 = ComposeAutocompleteServiceKey.make(
            accounts: [b, a],
            timelineScope: .unified
        )

        XCTAssertEqual(key1, key2)
    }

    func testServiceKeyChangesWhenScopeChanges() {
        let a = makeAccount(id: "a")

        let unified = ComposeAutocompleteServiceKey.make(
            accounts: [a],
            timelineScope: .unified
        )
        let thread = ComposeAutocompleteServiceKey.make(
            accounts: [a],
            timelineScope: .thread("post-123")
        )

        XCTAssertNotEqual(unified, thread)
    }

    func testServiceKeyChangesWhenAccountSetChanges() {
        let a = makeAccount(id: "a")
        let b = makeAccount(id: "b")

        let key1 = ComposeAutocompleteServiceKey.make(
            accounts: [a],
            timelineScope: .unified
        )
        let key2 = ComposeAutocompleteServiceKey.make(
            accounts: [a, b],
            timelineScope: .unified
        )

        XCTAssertNotEqual(key1, key2)
    }
}

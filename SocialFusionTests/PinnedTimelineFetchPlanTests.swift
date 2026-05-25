import XCTest
@testable import SocialFusion

@MainActor
final class PinnedTimelineFetchPlanTests: XCTestCase {
    private func makeAccount(id: String, platform: SocialPlatform) -> SocialAccount {
        SocialAccount(
            id: id,
            username: "user-\(id)",
            displayName: "User \(id)",
            serverURL: URL(string: "https://example.test"),
            platform: platform,
            profileImageURL: nil
        )
    }

    private func makeStore() -> PinnedTimelineStore {
        // Unique key per test so persistence from one test never bleeds into
        // the next (no defaults-removeObject dance needed).
        PinnedTimelineStore(
            userDefaults: .standard,
            defaultsKey: "pin-fetch-plan-test-\(UUID().uuidString)"
        )
    }

    // MARK: - Mastodon list

    func testResolveMastodonListPinReturnsAccount() {
        let manager = SocialServiceManager()
        let pinStore = makeStore()
        manager.pinnedTimelineStore = pinStore
        manager.accounts = [makeAccount(id: "m1", platform: .mastodon)]

        let pin = PinnedTimeline(
            displayName: "Friends",
            kind: .mastodonList(accountId: "m1", listId: "list-7")
        )
        pinStore.add(pin)
        manager.setTimelineFeedSelection(.pinned(id: pin.id))

        guard case .pinned(let resolvedPin, let resolution) = manager.resolveTimelineFetchPlan() else {
            return XCTFail("Expected .pinned plan")
        }
        XCTAssertEqual(resolvedPin.id, pin.id)
        guard case .mastodonList(let account, let listId) = resolution else {
            return XCTFail("Expected .mastodonList resolution, got \(resolution)")
        }
        XCTAssertEqual(account.id, "m1")
        XCTAssertEqual(listId, "list-7")
    }

    // MARK: - Bluesky feed

    func testResolveBlueskyFeedPinReturnsAccount() {
        let manager = SocialServiceManager()
        let pinStore = makeStore()
        manager.pinnedTimelineStore = pinStore
        manager.accounts = [makeAccount(id: "b1", platform: .bluesky)]

        let pin = PinnedTimeline(
            displayName: "What's Hot",
            kind: .blueskyFeed(accountId: "b1", feedUri: "at://did:plc:xxx/app.bsky.feed.generator/abc")
        )
        pinStore.add(pin)
        manager.setTimelineFeedSelection(.pinned(id: pin.id))

        guard case .pinned(_, let resolution) = manager.resolveTimelineFetchPlan(),
              case .blueskyFeed(let account, let feedUri) = resolution else {
            return XCTFail("Expected .blueskyFeed resolution")
        }
        XCTAssertEqual(account.id, "b1")
        XCTAssertEqual(feedUri, "at://did:plc:xxx/app.bsky.feed.generator/abc")
    }

    // MARK: - Account group

    func testResolveAccountGroupWithOneMissingAccountStillReturnsRemaining() {
        let manager = SocialServiceManager()
        let pinStore = makeStore()
        manager.pinnedTimelineStore = pinStore
        manager.accounts = [
            makeAccount(id: "m1", platform: .mastodon),
            makeAccount(id: "b1", platform: .bluesky),
        ]

        let pin = PinnedTimeline(
            displayName: "Work",
            kind: .accountGroup(accountIds: ["m1", "b1", "deleted-account"])
        )
        pinStore.add(pin)
        manager.setTimelineFeedSelection(.pinned(id: pin.id))

        guard case .pinned(_, .accountGroup(let resolved)) = manager.resolveTimelineFetchPlan() else {
            return XCTFail("Expected .pinned/.accountGroup")
        }
        XCTAssertEqual(resolved.map(\.id).sorted(), ["b1", "m1"])
    }

    func testResolveAccountGroupWithZeroRemainingAccountsReturnsNil() {
        let manager = SocialServiceManager()
        let pinStore = makeStore()
        manager.pinnedTimelineStore = pinStore
        manager.accounts = [] // all accounts removed

        let pin = PinnedTimeline(
            displayName: "Ghost",
            kind: .accountGroup(accountIds: ["m1"])
        )
        pinStore.add(pin)
        manager.setTimelineFeedSelection(.pinned(id: pin.id))

        XCTAssertNil(manager.resolveTimelineFetchPlan(),
                     "Pin pointing at no-longer-existing accounts must resolve to nil.")
    }

    // MARK: - Wrong-platform / missing account

    func testResolveMastodonListPinWithMissingAccountReturnsNil() {
        let manager = SocialServiceManager()
        let pinStore = makeStore()
        manager.pinnedTimelineStore = pinStore
        manager.accounts = [makeAccount(id: "other", platform: .mastodon)]

        let pin = PinnedTimeline(
            displayName: "Orphaned",
            kind: .mastodonList(accountId: "m1", listId: "list-7")
        )
        pinStore.add(pin)
        manager.setTimelineFeedSelection(.pinned(id: pin.id))

        XCTAssertNil(manager.resolveTimelineFetchPlan(),
                     "Pin referencing a removed account must resolve to nil.")
    }

    // MARK: - Unknown id

    func testResolveByUnknownIDReturnsNil() {
        let manager = SocialServiceManager()
        manager.pinnedTimelineStore = makeStore()
        manager.accounts = [makeAccount(id: "m1", platform: .mastodon)]
        manager.setTimelineFeedSelection(.pinned(id: "nonexistent-pin-id"))

        XCTAssertNil(manager.resolveTimelineFetchPlan())
    }

    // MARK: - Without store wired

    func testResolveReturnsNilWhenStoreNotWired() {
        let manager = SocialServiceManager()
        manager.pinnedTimelineStore = nil
        manager.accounts = [makeAccount(id: "m1", platform: .mastodon)]
        manager.setTimelineFeedSelection(.pinned(id: "anything"))

        XCTAssertNil(manager.resolveTimelineFetchPlan(),
                     "Without a pinned-timeline store wired, .pinned selections must safely return nil.")
    }
}

import XCTest
@testable import SocialFusion

@MainActor
final class CanonicalPostStoreTests: XCTestCase {
  private func makePost(
    id: String,
    author: String,
    createdAt: Date,
    content: String = "Hello",
    platform: SocialPlatform = .mastodon
  ) -> Post {
    Post(
      id: id,
      content: content,
      authorName: author,
      authorUsername: author,
      authorProfilePictureURL: "",
      createdAt: createdAt,
      platform: platform,
      originalURL: "https://example.com/@\(author)/\(id)",
      attachments: [],
      mentions: [],
      tags: [],
      platformSpecificId: id
    )
  }

  private func makeBoost(
    wrapperID: String,
    booster: String,
    original: Post,
    createdAt: Date
  ) -> Post {
    let boost = Post(
      id: wrapperID,
      content: "",
      authorName: booster,
      authorUsername: booster,
      authorProfilePictureURL: "",
      createdAt: createdAt,
      platform: original.platform,
      originalURL: "https://example.com/@\(booster)/boost/\(wrapperID)",
      attachments: [],
      mentions: [],
      tags: [],
      originalPost: original,
      isReposted: true,
      platformSpecificId: wrapperID,
      boostedBy: booster
    )
    return boost
  }

  func testOriginalThenBoostDedupes() {
    let store = CanonicalPostStore()
    let original = makePost(id: "1", author: "author", createdAt: Date())
    let boost = makeBoost(wrapperID: "b1", booster: "Booster", original: original, createdAt: Date())

    store.replaceTimeline(
      timelineID: CanonicalPostStore.unifiedTimelineID,
      posts: [original],
      sourceContext: TimelineSourceContext(source: .refresh)
    )

    store.processIncomingPosts(
      [boost],
      timelineID: CanonicalPostStore.unifiedTimelineID,
      sourceContext: TimelineSourceContext(source: .pagination)
    )

    XCTAssertEqual(store.timelineEntries(for: CanonicalPostStore.unifiedTimelineID).count, 1)
    let canonicalID = CanonicalPostResolver.resolve(post: original).canonicalPostID
    XCTAssertEqual(store.boostSummaryText(for: canonicalID), "Booster")
  }

  func testBoostThenOriginalDedupes() {
    let store = CanonicalPostStore()
    let original = makePost(id: "2", author: "author", createdAt: Date())
    let boost = makeBoost(wrapperID: "b2", booster: "Booster", original: original, createdAt: Date())

    store.replaceTimeline(
      timelineID: CanonicalPostStore.unifiedTimelineID,
      posts: [boost],
      sourceContext: TimelineSourceContext(source: .refresh)
    )

    store.processIncomingPosts(
      [original],
      timelineID: CanonicalPostStore.unifiedTimelineID,
      sourceContext: TimelineSourceContext(source: .pagination)
    )

    XCTAssertEqual(store.timelineEntries(for: CanonicalPostStore.unifiedTimelineID).count, 1)
    let canonicalPosts = store.timelinePosts(for: CanonicalPostStore.unifiedTimelineID)
    XCTAssertEqual(canonicalPosts.first?.content, original.content)
  }

  func testDuplicateBoostIsIdempotent() {
    let store = CanonicalPostStore()
    let original = makePost(id: "3", author: "author", createdAt: Date())
    let boost = makeBoost(wrapperID: "b3", booster: "Booster", original: original, createdAt: Date())

    store.replaceTimeline(
      timelineID: CanonicalPostStore.unifiedTimelineID,
      posts: [original],
      sourceContext: TimelineSourceContext(source: .refresh)
    )

    store.processIncomingPosts(
      [boost],
      timelineID: CanonicalPostStore.unifiedTimelineID,
      sourceContext: TimelineSourceContext(source: .pagination)
    )

    store.processIncomingPosts(
      [boost],
      timelineID: CanonicalPostStore.unifiedTimelineID,
      sourceContext: TimelineSourceContext(source: .pagination)
    )

    let canonicalID = CanonicalPostResolver.resolve(post: original).canonicalPostID
    XCTAssertEqual(store.socialEvents(for: canonicalID).count, 1)
  }

  func testPostAppearingInMultipleTimelines() {
    let store = CanonicalPostStore()
    let original = makePost(id: "4", author: "author", createdAt: Date())

    store.processIncomingPosts(
      [original],
      timelineID: "home",
      sourceContext: TimelineSourceContext(source: .refresh)
    )

    store.processIncomingPosts(
      [original],
      timelineID: "list-1",
      sourceContext: TimelineSourceContext(source: .refresh)
    )

    XCTAssertEqual(store.timelineEntries(for: "home").count, 1)
    XCTAssertEqual(store.timelineEntries(for: "list-1").count, 1)
    XCTAssertEqual(store.canonicalPostCount, 1)
  }

  func testCrossAccountBoostsAggregate() {
    let store = CanonicalPostStore()
    let original = makePost(id: "5", author: "author", createdAt: Date())
    let boostOne = makeBoost(
      wrapperID: "b5-1",
      booster: "Booster One",
      original: original,
      createdAt: Date().addingTimeInterval(10)
    )
    let boostTwo = makeBoost(
      wrapperID: "b5-2",
      booster: "Booster Two",
      original: original,
      createdAt: Date().addingTimeInterval(20)
    )

    store.replaceTimeline(
      timelineID: CanonicalPostStore.unifiedTimelineID,
      posts: [original],
      sourceContext: TimelineSourceContext(source: .refresh)
    )

    store.processIncomingPosts(
      [boostOne, boostTwo],
      timelineID: CanonicalPostStore.unifiedTimelineID,
      sourceContext: TimelineSourceContext(source: .pagination)
    )

    let canonicalID = CanonicalPostResolver.resolve(post: original).canonicalPostID
    let canonicalPost = store.canonicalPost(for: canonicalID)
    XCTAssertEqual(canonicalPost?.socialContext.repostActorCount, 2)

    let summary = store.boostSummaryText(for: canonicalID) ?? ""
    XCTAssertTrue(summary.contains("Booster One"))
    XCTAssertTrue(summary.contains("Booster Two"))
  }
}

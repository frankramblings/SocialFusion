import XCTest
@testable import SocialFusion

@MainActor
final class PostLayoutSnapshotBuilderTests: XCTestCase {
  var builder: PostLayoutSnapshotBuilder!
  
  override func setUp() {
    super.setUp()
    builder = PostLayoutSnapshotBuilder()
  }
  
  func testSnapshotForPostWithoutMedia() async {
    let post = Post(
      id: "test-1",
      content: "Test post without media",
      authorName: "Test User",
      authorUsername: "testuser",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .bluesky,
      originalURL: "https://example.com/post/1"
    )
    
    let snapshot = await builder.buildSnapshot(for: post)
    
    XCTAssertEqual(snapshot.id, "test-1")
    XCTAssertFalse(snapshot.isBoostBannerVisible)
    XCTAssertFalse(snapshot.isReplyBannerVisible)
    XCTAssertEqual(snapshot.mediaBlocks.count, 0)
    XCTAssertNil(snapshot.quoteSnapshot)
    XCTAssertNil(snapshot.linkPreviewSnapshot)
    XCTAssertFalse(snapshot.hasPoll)
  }
  
  func testSnapshotForBoostedPost() async {
    let originalPost = Post(
      id: "original-1",
      content: "Original content",
      authorName: "Original Author",
      authorUsername: "original",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .mastodon,
      originalURL: "https://example.com/original/1"
    )
    
    let boostPost = Post(
      id: "boost-1",
      content: "",
      authorName: "Booster",
      authorUsername: "booster",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .mastodon,
      originalURL: "https://example.com/boost/1",
      originalPost: originalPost,
      boostedBy: "booster"
    )
    
    let snapshot = await builder.buildSnapshot(for: boostPost)
    
    XCTAssertTrue(snapshot.isBoostBannerVisible)
    XCTAssertEqual(snapshot.id, "boost-1")
  }
  
  func testSnapshotForPostWithMedia() async {
    let attachment = Post.Attachment(
      url: "https://example.com/image.jpg",
      type: .image,
      width: 1920,
      height: 1080
    )
    
    let post = Post(
      id: "test-media",
      content: "Post with image",
      authorName: "Test User",
      authorUsername: "testuser",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .bluesky,
      originalURL: "https://example.com/post/media",
      attachments: [attachment]
    )
    
    let snapshot = await builder.buildSnapshot(for: post)
    
    XCTAssertEqual(snapshot.mediaBlocks.count, 1)
    let mediaBlock = snapshot.mediaBlocks[0]
    XCTAssertNotNil(mediaBlock.aspectRatio)
    XCTAssertEqual(Double(mediaBlock.aspectRatio ?? 0), 1920.0 / 1080.0, accuracy: 0.01)
    XCTAssertTrue(mediaBlock.shouldShow)
  }
  
  func testSnapshotStability() async {
    let post = Post(
      id: "stable-test",
      content: "Test content",
      authorName: "Test User",
      authorUsername: "testuser",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .bluesky,
      originalURL: "https://example.com/stable"
    )
    
    let snapshot1 = await builder.buildSnapshot(for: post)
    let snapshot2 = await builder.buildSnapshot(for: post)
    
    // Snapshots should be equal for same post
    XCTAssertEqual(snapshot1, snapshot2)
  }
  
  func testSyncSnapshot() {
    let post = Post(
      id: "sync-test",
      content: "Test",
      authorName: "Test",
      authorUsername: "test",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .bluesky,
      originalURL: "https://example.com"
    )
    
    let snapshot = builder.buildSnapshotSync(for: post)
    
    XCTAssertEqual(snapshot.id, "sync-test")
    // Sync version should work without async operations
  }
}

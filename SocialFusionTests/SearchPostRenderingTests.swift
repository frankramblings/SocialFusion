import XCTest
@testable import SocialFusion

@MainActor
final class SearchPostRenderingTests: XCTestCase {
  
  // MARK: - Test Post Creation Helpers
  
  func createRegularPost() -> Post {
    Post(
      id: "post-1",
      content: "Regular post content",
      authorName: "Test User",
      authorUsername: "testuser",
      authorProfilePictureURL: "https://example.com/avatar.jpg",
      createdAt: Date(),
      platform: .bluesky,
      originalURL: "https://example.com/post/1"
    )
  }
  
  func createPostWithSingleImage() -> Post {
    let attachment = Post.Attachment(
      url: "https://example.com/image.jpg",
      type: .image,
      width: 1920,
      height: 1080
    )
    return Post(
      id: "post-image",
      content: "Post with single image",
      authorName: "Test User",
      authorUsername: "testuser",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .bluesky,
      originalURL: "https://example.com/post/image",
      attachments: [attachment]
    )
  }
  
  func createPostWithMultiImage() -> Post {
    let attachments = [
      Post.Attachment(url: "https://example.com/img1.jpg", type: .image, width: 800, height: 600),
      Post.Attachment(url: "https://example.com/img2.jpg", type: .image, width: 800, height: 600),
      Post.Attachment(url: "https://example.com/img3.jpg", type: .image, width: 800, height: 600)
    ]
    return Post(
      id: "post-multi",
      content: "Post with multiple images",
      authorName: "Test User",
      authorUsername: "testuser",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .bluesky,
      originalURL: "https://example.com/post/multi",
      attachments: attachments
    )
  }
  
  func createPostWithVideo() -> Post {
    let attachment = Post.Attachment(
      url: "https://example.com/video.mp4",
      type: .video,
      width: 1920,
      height: 1080
    )
    return Post(
      id: "post-video",
      content: "Post with video",
      authorName: "Test User",
      authorUsername: "testuser",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .bluesky,
      originalURL: "https://example.com/post/video",
      attachments: [attachment]
    )
  }
  
  func createPostWithLinkPreview() -> Post {
    let post = Post(
      id: "post-link",
      content: "Post with link preview https://example.com/article",
      authorName: "Test User",
      authorUsername: "testuser",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .bluesky,
      originalURL: "https://example.com/post/link"
    )
    post.primaryLinkURL = URL(string: "https://example.com/article")
    post.primaryLinkTitle = "Example Article"
    post.primaryLinkDescription = "This is an example article"
    post.primaryLinkThumbnailURL = URL(string: "https://example.com/thumb.jpg")
    return post
  }
  
  func createBoostedPost() -> Post {
    let originalPost = Post(
      id: "original-1",
      content: "Original post content",
      authorName: "Original Author",
      authorUsername: "original",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .mastodon,
      originalURL: "https://example.com/original/1"
    )
    
    return Post(
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
  }
  
  func createReplyPost() -> Post {
    Post(
      id: "reply-1",
      content: "This is a reply",
      authorName: "Replier",
      authorUsername: "replier",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .bluesky,
      originalURL: "https://example.com/reply/1",
      inReplyToID: "parent-1",
      inReplyToUsername: "parentuser"
    )
  }
  
  func createPostWithQuote() -> Post {
    let quotedPost = Post(
      id: "quoted-1",
      content: "Quoted post content",
      authorName: "Quoted Author",
      authorUsername: "quoted",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .bluesky,
      originalURL: "https://example.com/quoted/1"
    )
    
    let post = Post(
      id: "quote-1",
      content: "This post quotes another",
      authorName: "Quoter",
      authorUsername: "quoter",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .bluesky,
      originalURL: "https://example.com/quote/1"
    )
    post.quotedPost = quotedPost
    return post
  }
  
  // MARK: - Tests
  
  func testRegularPostProperties() {
    let post = createRegularPost()
    
    XCTAssertEqual(post.id, "post-1")
    XCTAssertEqual(post.content, "Regular post content")
    XCTAssertEqual(post.attachments.count, 0)
    XCTAssertNil(post.originalPost)
    XCTAssertNil(post.boostedBy)
    XCTAssertNil(post.inReplyToID)
    XCTAssertNil(post.quotedPost)
    XCTAssertNil(post.primaryLinkURL)
  }
  
  func testPostWithSingleImageProperties() {
    let post = createPostWithSingleImage()
    
    XCTAssertEqual(post.attachments.count, 1)
    XCTAssertEqual(post.attachments[0].type, .image)
    XCTAssertEqual(post.attachments[0].width, 1920)
    XCTAssertEqual(post.attachments[0].height, 1080)
  }
  
  func testPostWithMultiImageProperties() {
    let post = createPostWithMultiImage()
    
    XCTAssertEqual(post.attachments.count, 3)
    post.attachments.forEach { attachment in
      XCTAssertEqual(attachment.type, .image)
    }
  }
  
  func testPostWithVideoProperties() {
    let post = createPostWithVideo()
    
    XCTAssertEqual(post.attachments.count, 1)
    XCTAssertEqual(post.attachments[0].type, .video)
  }
  
  func testPostWithLinkPreviewProperties() {
    let post = createPostWithLinkPreview()
    
    XCTAssertNotNil(post.primaryLinkURL)
    XCTAssertNotNil(post.primaryLinkTitle)
    XCTAssertNotNil(post.primaryLinkDescription)
    XCTAssertNotNil(post.primaryLinkThumbnailURL)
    XCTAssertEqual(post.primaryLinkTitle, "Example Article")
  }
  
  func testBoostedPostProperties() {
    let post = createBoostedPost()
    
    XCTAssertNotNil(post.originalPost)
    XCTAssertNotNil(post.boostedBy)
    XCTAssertEqual(post.boostedBy, "booster")
    XCTAssertEqual(post.originalPost?.id, "original-1")
    XCTAssertEqual(post.originalPost?.content, "Original post content")
  }
  
  func testReplyPostProperties() {
    let post = createReplyPost()
    
    XCTAssertNotNil(post.inReplyToID)
    XCTAssertNotNil(post.inReplyToUsername)
    XCTAssertEqual(post.inReplyToID, "parent-1")
    XCTAssertEqual(post.inReplyToUsername, "parentuser")
  }
  
  func testPostWithQuoteProperties() {
    let post = createPostWithQuote()
    
    XCTAssertNotNil(post.quotedPost)
    XCTAssertEqual(post.quotedPost?.id, "quoted-1")
    XCTAssertEqual(post.quotedPost?.content, "Quoted post content")
  }
  
  // MARK: - TimelineEntry Creation Tests
  
  func testTimelineEntryFromRegularPost() {
    let post = createRegularPost()
    let entry = TimelineEntry(
      id: post.id,
      kind: .normal,
      post: post,
      createdAt: post.createdAt
    )
    
    XCTAssertEqual(entry.id, post.id)
    XCTAssertEqual(entry.post.id, post.id)
    if case .normal = entry.kind {
      // Correct kind
    } else {
      XCTFail("Expected normal kind")
    }
  }
  
  func testTimelineEntryFromBoostedPost() {
    let post = createBoostedPost()
    let entryKind: TimelineEntryKind
    if post.originalPost != nil || post.boostedBy != nil {
      let boostedByHandle = post.boostedBy ?? post.authorUsername
      entryKind = .boost(boostedBy: boostedByHandle)
    } else {
      entryKind = .normal
    }
    
    let entry = TimelineEntry(
      id: post.id,
      kind: entryKind,
      post: post,
      createdAt: post.createdAt
    )
    
    if case .boost(let boostedBy) = entry.kind {
      XCTAssertEqual(boostedBy, "booster")
    } else {
      XCTFail("Expected boost kind")
    }
  }
  
  func testTimelineEntryFromReplyPost() {
    let post = createReplyPost()
    let entryKind: TimelineEntryKind
    if let parentId = post.inReplyToID {
      entryKind = .reply(parentId: parentId)
    } else {
      entryKind = .normal
    }
    
    let entry = TimelineEntry(
      id: post.id,
      kind: entryKind,
      post: post,
      createdAt: post.createdAt
    )
    
    if case .reply(let parentId) = entry.kind {
      XCTAssertEqual(parentId, "parent-1")
    } else {
      XCTFail("Expected reply kind")
    }
  }
}

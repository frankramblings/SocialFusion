import XCTest
@testable import SocialFusion

@MainActor
final class SearchPostMappingTests: XCTestCase {
  
  // MARK: - Test Post Property Preservation
  
  func testMediaAttachmentsPreserved() {
    let attachments = [
      Post.Attachment(url: "https://example.com/img1.jpg", type: .image, width: 800, height: 600),
      Post.Attachment(url: "https://example.com/img2.jpg", type: .image, width: 800, height: 600)
    ]
    
    let originalPost = Post(
      id: "original",
      content: "Content",
      authorName: "Author",
      authorUsername: "author",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .bluesky,
      originalURL: "https://example.com/post",
      attachments: attachments
    )
    
    // Simulate search result mapping - attachments should be preserved
    let searchResultPost = Post(
      id: originalPost.id,
      content: originalPost.content,
      authorName: originalPost.authorName,
      authorUsername: originalPost.authorUsername,
      authorProfilePictureURL: originalPost.authorProfilePictureURL,
      createdAt: originalPost.createdAt,
      platform: originalPost.platform,
      originalURL: originalPost.originalURL,
      attachments: originalPost.attachments
    )
    
    XCTAssertEqual(searchResultPost.attachments.count, 2)
    XCTAssertEqual(searchResultPost.attachments[0].url, attachments[0].url)
    XCTAssertEqual(searchResultPost.attachments[1].url, attachments[1].url)
  }
  
  func testQuotePostPreserved() {
    let quotedPost = Post(
      id: "quoted",
      content: "Quoted content",
      authorName: "Quoted Author",
      authorUsername: "quoted",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .bluesky,
      originalURL: "https://example.com/quoted"
    )
    
    let originalPost = Post(
      id: "original",
      content: "Content",
      authorName: "Author",
      authorUsername: "author",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .bluesky,
      originalURL: "https://example.com/post"
    )
    originalPost.quotedPost = quotedPost
    
    // Simulate search result mapping - quoted post should be preserved
    let searchResultPost = Post(
      id: originalPost.id,
      content: originalPost.content,
      authorName: originalPost.authorName,
      authorUsername: originalPost.authorUsername,
      authorProfilePictureURL: originalPost.authorProfilePictureURL,
      createdAt: originalPost.createdAt,
      platform: originalPost.platform,
      originalURL: originalPost.originalURL
    )
    searchResultPost.quotedPost = originalPost.quotedPost
    
    XCTAssertNotNil(searchResultPost.quotedPost)
    XCTAssertEqual(searchResultPost.quotedPost?.id, "quoted")
    XCTAssertEqual(searchResultPost.quotedPost?.content, "Quoted content")
  }
  
  func testLinkPreviewPreserved() {
    let originalPost = Post(
      id: "original",
      content: "Content",
      authorName: "Author",
      authorUsername: "author",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .bluesky,
      originalURL: "https://example.com/post"
    )
    originalPost.primaryLinkURL = URL(string: "https://example.com/article")
    originalPost.primaryLinkTitle = "Article Title"
    originalPost.primaryLinkDescription = "Article Description"
    originalPost.primaryLinkThumbnailURL = URL(string: "https://example.com/thumb.jpg")
    
    // Simulate search result mapping - link preview should be preserved
    let searchResultPost = Post(
      id: originalPost.id,
      content: originalPost.content,
      authorName: originalPost.authorName,
      authorUsername: originalPost.authorUsername,
      authorProfilePictureURL: originalPost.authorProfilePictureURL,
      createdAt: originalPost.createdAt,
      platform: originalPost.platform,
      originalURL: originalPost.originalURL
    )
    searchResultPost.primaryLinkURL = originalPost.primaryLinkURL
    searchResultPost.primaryLinkTitle = originalPost.primaryLinkTitle
    searchResultPost.primaryLinkDescription = originalPost.primaryLinkDescription
    searchResultPost.primaryLinkThumbnailURL = originalPost.primaryLinkThumbnailURL
    
    XCTAssertNotNil(searchResultPost.primaryLinkURL)
    XCTAssertNotNil(searchResultPost.primaryLinkTitle)
    XCTAssertNotNil(searchResultPost.primaryLinkDescription)
    XCTAssertNotNil(searchResultPost.primaryLinkThumbnailURL)
    XCTAssertEqual(searchResultPost.primaryLinkTitle, "Article Title")
  }
  
  func testBoostMetadataPreserved() {
    let originalPost = Post(
      id: "original",
      content: "Original content",
      authorName: "Original Author",
      authorUsername: "original",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .mastodon,
      originalURL: "https://example.com/original"
    )
    
    let boostPost = Post(
      id: "boost",
      content: "",
      authorName: "Booster",
      authorUsername: "booster",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .mastodon,
      originalURL: "https://example.com/boost",
      originalPost: originalPost,
      boostedBy: "booster"
    )
    
    // Simulate search result mapping - boost metadata should be preserved
    let searchResultPost = Post(
      id: boostPost.id,
      content: boostPost.content,
      authorName: boostPost.authorName,
      authorUsername: boostPost.authorUsername,
      authorProfilePictureURL: boostPost.authorProfilePictureURL,
      createdAt: boostPost.createdAt,
      platform: boostPost.platform,
      originalURL: boostPost.originalURL,
      originalPost: boostPost.originalPost,
      boostedBy: boostPost.boostedBy
    )
    
    XCTAssertNotNil(searchResultPost.originalPost)
    XCTAssertNotNil(searchResultPost.boostedBy)
    XCTAssertEqual(searchResultPost.boostedBy, "booster")
    XCTAssertEqual(searchResultPost.originalPost?.id, "original")
  }
  
  func testReplyContextPreserved() {
    let originalPost = Post(
      id: "original",
      content: "Content",
      authorName: "Author",
      authorUsername: "author",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .bluesky,
      originalURL: "https://example.com/post",
      inReplyToID: "parent-1",
      inReplyToUsername: "parentuser"
    )
    
    // Simulate search result mapping - reply context should be preserved
    let searchResultPost = Post(
      id: originalPost.id,
      content: originalPost.content,
      authorName: originalPost.authorName,
      authorUsername: originalPost.authorUsername,
      authorProfilePictureURL: originalPost.authorProfilePictureURL,
      createdAt: originalPost.createdAt,
      platform: originalPost.platform,
      originalURL: originalPost.originalURL,
      inReplyToID: originalPost.inReplyToID,
      inReplyToUsername: originalPost.inReplyToUsername
    )
    
    XCTAssertNotNil(searchResultPost.inReplyToID)
    XCTAssertNotNil(searchResultPost.inReplyToUsername)
    XCTAssertEqual(searchResultPost.inReplyToID, "parent-1")
    XCTAssertEqual(searchResultPost.inReplyToUsername, "parentuser")
  }
  
  func testAllPropertiesPreservedTogether() {
    // Create a complex post with all features
    let quotedPost = Post(
      id: "quoted",
      content: "Quoted",
      authorName: "Quoted Author",
      authorUsername: "quoted",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .bluesky,
      originalURL: "https://example.com/quoted"
    )
    
    let originalPost = Post(
      id: "original",
      content: "Original",
      authorName: "Original Author",
      authorUsername: "original",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .mastodon,
      originalURL: "https://example.com/original",
      attachments: [
        Post.Attachment(url: "https://example.com/img.jpg", type: .image, width: 800, height: 600)
      ],
      inReplyToID: "parent-1",
      inReplyToUsername: "parentuser"
    )
    originalPost.quotedPost = quotedPost
    originalPost.primaryLinkURL = URL(string: "https://example.com/article")
    originalPost.primaryLinkTitle = "Article"
    
    let boostPost = Post(
      id: "boost",
      content: "",
      authorName: "Booster",
      authorUsername: "booster",
      authorProfilePictureURL: "",
      createdAt: Date(),
      platform: .mastodon,
      originalURL: "https://example.com/boost",
      originalPost: originalPost,
      boostedBy: "booster"
    )
    
    // Simulate search result mapping - all properties should be preserved
    let searchResultPost = Post(
      id: boostPost.id,
      content: boostPost.content,
      authorName: boostPost.authorName,
      authorUsername: boostPost.authorUsername,
      authorProfilePictureURL: boostPost.authorProfilePictureURL,
      createdAt: boostPost.createdAt,
      platform: boostPost.platform,
      originalURL: boostPost.originalURL,
      originalPost: boostPost.originalPost,
      boostedBy: boostPost.boostedBy
    )
    
    // Verify boost metadata
    XCTAssertNotNil(searchResultPost.originalPost)
    XCTAssertNotNil(searchResultPost.boostedBy)
    
    // Verify original post properties
    let displayPost = searchResultPost.originalPost!
    XCTAssertEqual(displayPost.attachments.count, 1)
    XCTAssertNotNil(displayPost.quotedPost)
    XCTAssertNotNil(displayPost.primaryLinkURL)
    XCTAssertNotNil(displayPost.inReplyToID)
    XCTAssertNotNil(displayPost.inReplyToUsername)
  }
}

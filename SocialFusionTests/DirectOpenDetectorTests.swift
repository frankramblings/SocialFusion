import XCTest
@testable import SocialFusion

final class DirectOpenDetectorTests: XCTestCase {
  
  func testMastodonHandleDetection() {
    let input = "@user@instance.com"
    let detected = DirectOpenDetector.detectDirectOpen(input: input)
    
    if case .mastodonHandle(let username, let instance) = detected {
      XCTAssertEqual(username, "user")
      XCTAssertEqual(instance, "instance.com")
    } else {
      XCTFail("Expected Mastodon handle detection")
    }
  }
  
  func testBlueskyHandleDetection() {
    let input = "@handle.bsky.social"
    let detected = DirectOpenDetector.detectDirectOpen(input: input)
    
    if case .blueskyHandle(let handle) = detected {
      XCTAssertEqual(handle, "handle.bsky.social")
    } else {
      XCTFail("Expected Bluesky handle detection")
    }
  }
  
  func testDIDDetection() {
    let input = "did:plc:abc123"
    let detected = DirectOpenDetector.detectDirectOpen(input: input)
    
    if case .did(let did) = detected {
      XCTAssertEqual(did, "did:plc:abc123")
    } else {
      XCTFail("Expected DID detection")
    }
  }
  
  func testMastodonProfileURL() {
    let input = "https://mastodon.social/@user"
    let detected = DirectOpenDetector.detectDirectOpen(input: input)
    
    if case .mastodonProfileURL(let instance, let username) = detected {
      XCTAssertEqual(instance, "mastodon.social")
      XCTAssertEqual(username, "user")
    } else {
      XCTFail("Expected Mastodon profile URL detection")
    }
  }
  
  func testBlueskyProfileURL() {
    let input = "https://bsky.app/profile/user.bsky.social"
    let detected = DirectOpenDetector.detectDirectOpen(input: input)
    
    if case .blueskyProfileURL(let handle) = detected {
      XCTAssertEqual(handle, "user.bsky.social")
    } else {
      XCTFail("Expected Bluesky profile URL detection")
    }
  }
  
  func testInvalidInput() {
    let input = "just some text"
    let detected = DirectOpenDetector.detectDirectOpen(input: input)
    XCTAssertNil(detected)
  }
}

import Foundation

/// Utility for detecting direct-open targets (URLs, handles, DIDs)
public struct DirectOpenDetector {
  
  /// Detect if input looks like a direct-open target
  public static func detectDirectOpen(input: String) -> DirectOpenType? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Mastodon handle: @user@instance
    if trimmed.hasPrefix("@") && trimmed.contains("@") && !trimmed.hasPrefix("@@") {
      let components = trimmed.dropFirst().split(separator: "@")
      if components.count == 2 {
        return .mastodonHandle(String(components[0]), String(components[1]))
      }
    }
    
    // Bluesky handle: @handle
    let afterAt = trimmed.index(after: trimmed.startIndex)
    if trimmed.hasPrefix("@") && afterAt < trimmed.endIndex && !trimmed[afterAt...].contains("@") {
      let handle = String(trimmed.dropFirst())
      if !handle.isEmpty {
        return .blueskyHandle(handle)
      }
    }
    
    // DID: did:plc:...
    if trimmed.hasPrefix("did:") {
      return .did(trimmed)
    }
    
    // URL
    if let url = URL(string: trimmed) {
      return detectURLType(url)
    }
    
    return nil
  }
  
  private static func detectURLType(_ url: URL) -> DirectOpenType? {
    guard let host = url.host else {
      return nil
    }
    
    let pathComponents = url.pathComponents
    
    // Mastodon profile: https://instance/@user
    if pathComponents.count >= 2 && pathComponents[1].hasPrefix("@") {
      let username = String(pathComponents[1].dropFirst())
      return .mastodonProfileURL(host, username)
    }
    
    // Mastodon status: https://instance/@user/123456
    if pathComponents.count >= 3 {
      let username = pathComponents[1].hasPrefix("@") ? String(pathComponents[1].dropFirst()) : pathComponents[1]
      let statusId = pathComponents.last ?? ""
      if !statusId.isEmpty && statusId.allSatisfy({ $0.isNumber }) {
        return .mastodonStatusURL(host, username, statusId)
      }
    }
    
    // Bluesky profile: https://bsky.app/profile/handle
    if (host == "bsky.app" || host == "bsky.social") && pathComponents.count >= 3 && pathComponents[1] == "profile" {
      let handle = pathComponents[2]
      return .blueskyProfileURL(handle)
    }
    
    // Bluesky post: https://bsky.app/profile/handle/post/...
    if (host == "bsky.app" || host == "bsky.social") && pathComponents.count >= 4 && pathComponents[3] == "post" {
      let handle = pathComponents[2]
      let postId = pathComponents.last ?? ""
      return .blueskyPostURL(handle, postId)
    }
    
    return nil
  }
}

/// Type of direct-open target detected
public enum DirectOpenType {
  case mastodonHandle(String, String) // username, instance
  case blueskyHandle(String) // handle
  case did(String) // DID
  case mastodonProfileURL(String, String) // instance, username
  case mastodonStatusURL(String, String, String) // instance, username, statusId
  case blueskyProfileURL(String) // handle
  case blueskyPostURL(String, String) // handle, postId
  
  public var platform: SocialPlatform {
    switch self {
    case .mastodonHandle, .mastodonProfileURL, .mastodonStatusURL:
      return .mastodon
    case .blueskyHandle, .did, .blueskyProfileURL, .blueskyPostURL:
      return .bluesky
    }
  }
  
  public var displayText: String {
    switch self {
    case .mastodonHandle(let username, let instance):
      return "@\(username)@\(instance)"
    case .blueskyHandle(let handle):
      return "@\(handle)"
    case .did(let did):
      return did
    case .mastodonProfileURL(let instance, let username):
      return "@\(username)@\(instance)"
    case .mastodonStatusURL(let instance, let username, _):
      return "@\(username)@\(instance)"
    case .blueskyProfileURL(let handle):
      return "@\(handle)"
    case .blueskyPostURL(let handle, _):
      return "@\(handle)"
    }
  }
}

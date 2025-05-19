import Foundation
import SwiftUI

/// Wrapper for URL handling service
class URLServiceWrapper {
    static let shared = URLServiceWrapper()

    private init() {}

    /// Check if a URL is a Bluesky post URL
    func isBlueskyPostURL(_ url: URL) -> Bool {
        guard let host = url.host else { return false }

        // Match bsky.app and bsky.social URLs
        let isBlueskyDomain = host.contains("bsky.app") || host.contains("bsky.social")

        // Check if it's a post URL pattern: /profile/{username}/post/{postId}
        let path = url.path
        let isPostURL = path.contains("/profile/") && path.contains("/post/")

        return isBlueskyDomain && isPostURL
    }

    /// Check if a URL is a Mastodon post URL
    func isMastodonPostURL(_ url: URL) -> Bool {
        guard let host = url.host else { return false }

        // Check for common Mastodon instances or pattern
        let isMastodonInstance =
            host.contains("mastodon.social") || host.contains("mastodon.online")
            || host.contains("mas.to") || host.contains("mastodon.world")
            || host.contains(".social")

        // Check if it matches Mastodon post URL pattern: /@username/postID
        let path = url.path
        let isPostURL = path.contains("/@") && path.split(separator: "/").count >= 3

        return isMastodonInstance && isPostURL
    }

    /// Check if a URL is from any social media platform
    func isSocialMediaURL(_ url: URL) -> Bool {
        return isBlueskyPostURL(url) || isMastodonPostURL(url)
    }

    /// Extract post ID from a Bluesky URL
    func extractBlueskyPostID(_ url: URL) -> String? {
        guard isBlueskyPostURL(url) else { return nil }

        // Extract post ID from path components
        let components = url.path.split(separator: "/")
        if components.count >= 4 && components[components.count - 2] == "post" {
            return String(components[components.count - 1])
        }

        return nil
    }

    /// Extract post ID from a Mastodon URL
    func extractMastodonPostID(_ url: URL) -> String? {
        guard isMastodonPostURL(url) else { return nil }

        // Extract post ID from path components
        let components = url.path.split(separator: "/")
        if components.count >= 2 {
            return String(components[components.count - 1])
        }

        return nil
    }

    /// Validate and potentially fix malformed URLs
    func validateURL(_ url: URL) -> URL {
        return URLService.shared.validateURL(url)
    }

    /// Validate and potentially fix malformed URL strings
    func validateURL(_ urlString: String) -> URL? {
        return URLService.shared.validateURL(urlString)
    }
}
